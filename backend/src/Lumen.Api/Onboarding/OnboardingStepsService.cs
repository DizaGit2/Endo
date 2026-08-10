using Lumen.Api.Persistence;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Onboarding;

/// <summary>
/// The authenticated onboarding <b>step</b> writes — the ones that come after
/// <c>POST /onboarding/start</c> and that D-02 makes individually skippable. T16 opens it with the
/// baseline step (screen 4) and its read path; T17 and T18 add their own methods here rather than
/// standing up parallel services for the same feature folder.
/// </summary>
/// <remarks>
/// <para><b>1. A null day context is a 404, before anything else happens.</b> Erasure has no other
/// write fence behind it: a crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires and inserting a child row takes only a share lock on
/// <c>users</c>, which does not conflict with the shred job's UPDATE. Resolving the day context FIRST
/// and returning "not found" on null is the whole of the defence — which is why it is checked before
/// validation, so a body that would otherwise be a 400 still answers "no such user".</para>
///
/// <para><b>2. Validate then act (T3).</b> Every field error is collected before the first write, so a
/// rejected request has changed nothing and a form with six bad fields takes one round trip to fix,
/// not six.</para>
///
/// <para><b>3. MERGE, not replace.</b> <see langword="null"/> means "leave the stored value
/// unchanged", exactly as on <c>PATCH /me</c>. D-02 makes the baseline a step the user revisits, and
/// screen 31 edits one field at a time — a full replace would mean opening screen 31 to change a
/// height silently erased the diagnosis month. There is deliberately <b>no way to clear a field</b> in
/// P4a: <c>int?</c>/<c>string?</c> on a positional record cannot distinguish absent from
/// explicit-null under <c>System.Text.Json</c>, and both meanings need an <c>Optional&lt;T&gt;</c> the
/// generated Dart client cannot express (the same accepted limitation T10 documented for
/// <c>POST /cycle/day/{date}</c>). An <b>entirely</b> empty body is a 400 under <c>request</c>, since
/// "skip" means not calling the endpoint at all.</para>
///
/// <para><b>4. Every column this service writes is CIPHERTEXT</b>, so every rule about their contents
/// lives here rather than in the DDL — there is no CHECK on <c>rasrm_stage_enc</c>, no
/// <c>NOT NULL</c>-shaped range on <c>height_cm_enc</c>, and no way for the database to notice a
/// <c>"yyyy-MM-dd"</c> in a month column. Each value goes through the <b>one</b> canonical encoder its
/// entity declares (<see cref="UserProfileEnc.RasrmStages.Encode"/>,
/// <see cref="UserProfileEnc.EncodeDiagnosedOn"/>, <see cref="UserProfileEnc.EncodeDob"/>,
/// <see cref="UserProfileEnc.EncodeHeightCm"/>, <see cref="BodyMetric.EncodeValue"/>) — never a bare
/// <c>ToString()</c>, which is culture-sensitive and reads 60.4&#160;kg back as 604&#160;kg under
/// <c>de-DE</c>. <b>No decrypted value is ever logged</b>; nothing in this file logs at all.</para>
///
/// <para><b>5. The weight is an UPSERT under §G9's FILTERED regime</b> — <c>body_metrics</c>
/// <c>(UserId, Metric, MeasuredOn)</c> is unique only <c>WHERE "DeletedAt" IS NULL</c>, the one
/// deliberate tombstone exception in the phase, and it exists precisely so D-02's step stays
/// re-submittable after a delete. So the lookup below runs <b>WITHOUT</b>
/// <c>IgnoreQueryFilters()</c>: unlike <c>cycle_events</c> and <c>cycle_day_logs</c>, a tombstone here
/// is <b>not</b> revived — it has already released the key, and a new row is inserted alongside it.
/// Reviving it instead would resurrect a row the user deleted.</para>
///
/// <para><b>6. Bounds are structural only.</b> See <see cref="BaselineStructuralDomain"/>: no age
/// gate, no clinical height/weight range, no floor on <c>dob</c> beyond the type. §G8's backdate floor
/// is <c>cycle_events</c>-only and every real date of birth sits decades below it, so applying it here
/// would reject the very data the field exists for.</para>
///
/// <para><b>7. WARNING — <see cref="SaveBaselineAsync"/> OWNS ITS UNIT OF WORK AND CLEARS THE WHOLE
/// CHANGE TRACKER, so a caller must not stage un-saved work before invoking it.</b> Its
/// <see cref="ConcurrencyRetry"/> action calls <c>ChangeTracker.Clear()</c> to be re-runnable, and
/// that acts on the request-scoped <c>LumenDbContext</c>: anything staged earlier in the same scope is
/// <b>silently discarded</b>. That is the deliberate choice for T16 — no later task composes this step
/// (T17 owns notifications, T18 owns the cycle step and <c>GET /onboarding/state</c>), and the two
/// <c>23505</c> hazards are real: the <c>user_profile_enc</c> primary key on a first save, and the
/// <c>body_metrics</c> filtered unique key when a client double-taps "Continue". A future task that
/// genuinely needs to compose the baseline must first split out a stage-only method, the way T14 split
/// <c>ApplyOnboardingCycleAsync</c> and T15 split <c>StageRegistrationAsync</c>; the hazard itself is
/// pinned by
/// <c>OnboardingBaselineTests.SaveBaselineAsync_is_NOT_composable_because_its_retry_clears_the_whole_change_tracker</c>.</para>
/// </remarks>
public sealed class OnboardingStepsService(
    LumenDbContext db,
    IUserDayContext dayContext,
    IUserCryptoContext crypto)
{
    /// <summary>
    /// Saves the D-02 baseline step (screen 4): the five encrypted <c>user_profile_enc</c> condition
    /// fields plus, when a weight is supplied, one <c>body_metrics.weight_kg</c> row for the user's
    /// local day. Answers <b>200 with the stored row decrypted back</b> on both the insert and the
    /// update path.
    /// </summary>
    /// <remarks>
    /// <b>Not composable</b> — see rule 7 on the type. This method owns the whole unit of work and
    /// clears the change tracker.
    /// </remarks>
    public async Task<SaveBaselineResult> SaveBaselineAsync(SaveBaselineRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: the 404 fence comes first, so an erased token can neither learn that its body was
        // understood nor create a single row of health data.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SaveBaselineResult.UserNotFound();

        var errors = new List<OnboardingFieldError>();

        // --- dob: capped by the user's local today, and by NOTHING else (§G8) --------------------
        // There is deliberately no `dob < day.BackdateFloor` branch: D-13 gives that floor to
        // `cycle_events` alone, it is account creation − 2 y, and EVERY real date of birth is decades
        // below it — applying it here would reject the field's entire purpose. Nor is there a lower
        // bound of any other kind: a "born before 19xx" floor is an age gate, which C-12 forbids.
        if (request.Dob is { } dob && dob > day.Today)
            errors.Add(new OnboardingFieldError("dob", ValidationMessages.FutureDate));

        // --- heightCm: the structural storage domain (§G7/§G11), never a clinical range ----------
        if (request.HeightCm is { } heightCm && !BaselineStructuralDomain.ContainsHeightCm(heightCm))
        {
            errors.Add(new OnboardingFieldError(
                "heightCm",
                ValidationMessages.Between(
                    BaselineStructuralDomain.MinHeightCm, BaselineStructuralDomain.MaxHeightCm)));
        }

        // --- weightKg: same, plus the precision a scale actually reports -------------------------
        if (request.WeightKg is { } weightKg)
        {
            if (!BaselineStructuralDomain.ContainsWeightKg(weightKg))
            {
                errors.Add(new OnboardingFieldError(
                    "weightKg", OnboardingValidationMessages.WeightOutOfRange(BaselineStructuralDomain.MaxWeightKg)));
            }
            else if (!BaselineStructuralDomain.HasStorableScale(weightKg))
            {
                // Rejected rather than rounded: quietly storing 60.4 for a user who typed 60.44 is
                // inventing a datum, which is worse than making them correct the field.
                errors.Add(new OnboardingFieldError("weightKg", OnboardingValidationMessages.WeightTooPrecise));
            }
        }

        // --- endoStatus: the three ratified codes, matched case-sensitively (§G10) ---------------
        var endoStatus = Trimmed(request.EndoStatus);
        if (endoStatus is not null && !UserProfileEnc.EndoStatuses.All.Contains(endoStatus, StringComparer.Ordinal))
            errors.Add(new OnboardingFieldError("endoStatus", ValidationMessages.NotAllowedValue));

        // --- rasrmStage: THIS is the range check; the ciphertext column cannot carry one ---------
        if (request.RasrmStage is { } rasrmStage && !UserProfileEnc.RasrmStages.Contains(rasrmStage))
        {
            errors.Add(new OnboardingFieldError(
                "rasrmStage",
                ValidationMessages.Between(UserProfileEnc.RasrmStages.Min, UserProfileEnc.RasrmStages.Max)));
        }

        // --- diagnosedOn: "yyyy-MM", never a day, never a future month ---------------------------
        DateOnly? diagnosedMonth = null;
        var diagnosedOn = Trimmed(request.DiagnosedOn);
        if (diagnosedOn is not null)
        {
            if (!UserProfileEnc.TryDecodeDiagnosedOn(diagnosedOn, out var month))
            {
                // Exact-format parsing, so "2023-08-15" lands here rather than being read as a month
                // and silently re-stored without its day.
                errors.Add(new OnboardingFieldError("diagnosedOn", OnboardingValidationMessages.NotAMonth));
            }
            else if (month > FirstOfMonth(day.Today))
            {
                // Compared at MONTH granularity, so the user's current month is accepted even though
                // it has not ended — a diagnosis received this month is not in the future.
                errors.Add(new OnboardingFieldError("diagnosedOn", ValidationMessages.FutureDate));
            }
            else
            {
                diagnosedMonth = month;
            }
        }

        // --- the whole-body rule: an empty POST is a client bug, not a skip ----------------------
        var anySupplied =
            request.Dob is not null ||
            request.HeightCm is not null ||
            request.WeightKg is not null ||
            endoStatus is not null ||
            request.RasrmStage is not null ||
            diagnosedOn is not null;

        if (!anySupplied)
            errors.Add(new OnboardingFieldError(ValidationProblemBuilder.RequestKey, OnboardingValidationMessages.BaselineEmpty));

        if (errors.Count > 0) return new SaveBaselineResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        return await ConcurrencyRetry.ExecuteAsync<SaveBaselineResult>(async token =>
        {
            // The action must be genuinely re-runnable: a second attempt happens only because the
            // first one's INSERT lost a race, and that insert is still sitting in the tracker.
            // Whole-context, hence rule 7's caller restriction.
            db.ChangeTracker.Clear();

            // user_profile_enc is 1:1 with users and `/onboarding/start` normally creates it, but the
            // row is not guaranteed — and a missing profile must never turn a legitimate answer into
            // an error.
            var profile = await db.UserProfiles.FirstOrDefaultAsync(p => p.UserId == day.UserId, token);
            if (profile is null)
            {
                profile = new UserProfileEnc { UserId = day.UserId, CreatedAt = now, UpdatedAt = now };
                db.UserProfiles.Add(profile);
            }

            // Rule 3: only a SUPPLIED field is touched. Rule 4: one canonical encoder each.
            if (request.Dob is { } suppliedDob)
                profile.DobEnc = await crypto.EncryptStringAsync(UserProfileEnc.EncodeDob(suppliedDob), token);

            if (request.HeightCm is { } suppliedHeight)
                profile.HeightCmEnc = await crypto.EncryptStringAsync(UserProfileEnc.EncodeHeightCm(suppliedHeight), token);

            if (endoStatus is not null)
                profile.EndoStatusEnc = await crypto.EncryptStringAsync(endoStatus, token);

            if (request.RasrmStage is { } suppliedStage)
                profile.RasrmStageEnc = await crypto.EncryptStringAsync(UserProfileEnc.RasrmStages.Encode(suppliedStage), token);

            if (diagnosedMonth is { } suppliedMonth)
                profile.DiagnosedOnEnc = await crypto.EncryptStringAsync(UserProfileEnc.EncodeDiagnosedOn(suppliedMonth), token);

            profile.UpdatedAt = now;

            if (request.WeightKg is { } suppliedWeight)
                await StageWeightAsync(day.UserId, suppliedWeight, day.Today, now, token);

            await db.SaveChangesAsync(token);

            // Re-read rather than echo: the 200 states what is STORED, so a lost merge or a bad
            // encoder fails on the call that caused it instead of at the next GET /me.
            return new SaveBaselineResult.Saved(await ReadBaselineAsync(day.UserId, token));
        }, ct);
    }

    /// <summary>
    /// The profile-condition read path — the projection <c>GET /me</c> splices into
    /// <c>MeResponse</c> and the one <see cref="SaveBaselineAsync"/> answers with.
    /// </summary>
    /// <remarks>
    /// <para><b>Rider 4 is why this exists:</b> every column T7 added gets a reader as well as a
    /// writer, so P4a ships no unreachable storage and the already-shipped screen 31 has something to
    /// bind to.</para>
    ///
    /// <para>Takes the user id explicitly rather than resolving it, because both callers have already
    /// established that the user exists — <c>GET /me</c> through its own soft-delete-filtered
    /// <c>users</c> read, and <see cref="SaveBaselineAsync"/> through the day context. There is
    /// therefore no 404 case here and no result type: an unknown id simply reads as all-nulls, which
    /// no caller can reach.</para>
    ///
    /// <para><b>The weight comes from the latest LIVE row.</b> The query filter hides tombstones, so a
    /// deleted entry is never reported as the user's current weight; ordering by
    /// <see cref="BodyMetric.MeasuredOn"/> alone is deterministic because the filtered unique index
    /// permits at most one live row per day.</para>
    /// </remarks>
    public async Task<BaselineResponse> ReadBaselineAsync(Guid userId, CancellationToken ct)
    {
        var profile = await db.UserProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.UserId == userId, ct);

        // No IgnoreQueryFilters(): a tombstoned metric is not this user's weight (§G9 / rule 5).
        var weight = await db.BodyMetrics.AsNoTracking()
            .Where(m => m.UserId == userId && m.Metric == BodyMetric.Metrics.WeightKg)
            .OrderByDescending(m => m.MeasuredOn)
            .FirstOrDefaultAsync(ct);

        return new BaselineResponse(
            profile?.DobEnc is { } dob ? UserProfileEnc.DecodeDob(await crypto.DecryptStringAsync(dob, ct)) : null,
            profile?.HeightCmEnc is { } height
                ? UserProfileEnc.DecodeHeightCm(await crypto.DecryptStringAsync(height, ct))
                : null,
            profile?.EndoStatusEnc is { } status ? await crypto.DecryptStringAsync(status, ct) : null,
            profile?.RasrmStageEnc is { } stage
                ? UserProfileEnc.RasrmStages.Decode(await crypto.DecryptStringAsync(stage, ct))
                : null,
            // Passed through as the canonical "yyyy-MM" string. Decoding it to a DateOnly and
            // re-formatting would be a round trip through a day this field does not have.
            profile?.DiagnosedOnEnc is { } month ? await crypto.DecryptStringAsync(month, ct) : null,
            weight is null ? null : BodyMetric.DecodeValue(await crypto.DecryptStringAsync(weight.ValueEnc, ct)));
    }

    // ------------------------------------------------------------------ the weight seed

    /// <summary>
    /// Stages the <c>body_metrics.weight_kg</c> upsert for the caller's local day. <b>Staged, not
    /// saved</b> — <see cref="SaveBaselineAsync"/> owns the single save for the whole unit of work, so
    /// the profile columns and the metric row commit or roll back together.
    /// </summary>
    /// <remarks>
    /// Rider 4: weight has <b>one</b> source of truth, this row, never a column on
    /// <see cref="UserProfileEnc"/>. The key is <c>(UserId, "weight_kg", user-local day)</c> — the
    /// day-keyed column exists so this is an index lookup rather than a per-row timezone conversion
    /// (D-12), and it is capped by <c>Today</c> with no backdate floor (§G8).
    /// </remarks>
    private async Task StageWeightAsync(
        Guid userId, decimal weightKg, DateOnly measuredOn, DateTimeOffset now, CancellationToken ct)
    {
        // Rule 5 — NO IgnoreQueryFilters(): under the FILTERED unique index a tombstone has already
        // released the key, so this deliberately inserts a NEW row beside it rather than reviving a
        // measurement the user deleted. That is the opposite of the cycle_events/cycle_day_logs rule,
        // and it is the whole reason §G9 grants this table its one exception.
        var row = await db.BodyMetrics.FirstOrDefaultAsync(
            m => m.UserId == userId && m.Metric == BodyMetric.Metrics.WeightKg && m.MeasuredOn == measuredOn, ct);

        if (row is null)
        {
            row = new BodyMetric
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Metric = BodyMetric.Metrics.WeightKg,
                Source = BodyMetric.Sources.Manual, // onboarding is user-entered, never a sync import
                MeasuredOn = measuredOn,
                CreatedAt = now,
            };
            db.BodyMetrics.Add(row);
        }

        row.ValueEnc = await crypto.EncryptStringAsync(
            BodyMetric.EncodeValue(BaselineStructuralDomain.NormaliseWeightKg(weightKg)), ct);
        row.MeasuredAt = now;
        row.UpdatedAt = now;
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>
    /// The first day of <paramref name="day"/>'s month — the granularity <c>diagnosedOn</c> is
    /// compared at, so the user's current month never reads as "in the future".
    /// </summary>
    private static DateOnly FirstOfMonth(DateOnly day) => new(day.Year, day.Month, 1);

    /// <summary>
    /// Blank is absent, matching <c>PATCH /me</c>, <c>PATCH /settings/cycle</c> and
    /// <c>POST /me/devices</c>: a whitespace-only string is not an answer, so it neither stores a value
    /// nor counts towards "at least one field was supplied".
    /// </summary>
    private static string? Trimmed(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
