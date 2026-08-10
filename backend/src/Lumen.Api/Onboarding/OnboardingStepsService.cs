using Lumen.Api.CycleSettings;
using Lumen.Api.Devices;
using Lumen.Api.Persistence;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Onboarding;

/// <summary>
/// The authenticated onboarding <b>step</b> writes — the ones that come after
/// <c>POST /onboarding/start</c>, four of which D-02 makes individually skippable. T16 opens it with the
/// baseline step (screen 4) and its read path; T17 adds the three preference steps (screens 5, 6, 7);
/// T18 closes the D-02 state machine with the <b>mandatory</b> cycle step (screen 3), the completion
/// gate and the resume read — here rather than in a parallel service for the same feature folder.
/// </summary>
/// <remarks>
/// <para><b>Rules 1 and 2 bind every method in this file. Everything after them is SCOPED to the step
/// it names</b> — this file deliberately holds steps with different write semantics and different
/// unit-of-work styles, so reading any of rules 3–8 as a property of the type would be wrong in at
/// least one direction.</para>
///
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
/// <para><b>3. <see cref="SaveBaselineAsync"/> MERGES; it does not replace.</b> <see langword="null"/>
/// means "leave the stored value
/// unchanged", exactly as on <c>PATCH /me</c>. D-02 makes the baseline a step the user revisits, and
/// screen 31 edits one field at a time — a full replace would mean opening screen 31 to change a
/// height silently erased the diagnosis month. There is deliberately <b>no way to clear a field</b> in
/// P4a: <c>int?</c>/<c>string?</c> on a positional record cannot distinguish absent from
/// explicit-null under <c>System.Text.Json</c>, and both meanings need an <c>Optional&lt;T&gt;</c> the
/// generated Dart client cannot express (the same accepted limitation T10 documented for
/// <c>POST /cycle/day/{date}</c>). An <b>entirely</b> empty body is a 400 under <c>request</c>, since
/// "skip" means not calling the endpoint at all. <b>The three preference steps are the opposite</b> —
/// see rule 8.</para>
///
/// <para><b>4. Every column <see cref="SaveBaselineAsync"/> writes is CIPHERTEXT</b>, so every rule about their contents
/// lives here rather than in the DDL — there is no CHECK on <c>rasrm_stage_enc</c>, no
/// <c>NOT NULL</c>-shaped range on <c>height_cm_enc</c>, and no way for the database to notice a
/// <c>"yyyy-MM-dd"</c> in a month column. Each value goes through the <b>one</b> canonical encoder its
/// entity declares (<see cref="UserProfileEnc.RasrmStages.Encode"/>,
/// <see cref="UserProfileEnc.EncodeDiagnosedOn"/>, <see cref="UserProfileEnc.EncodeDob"/>,
/// <see cref="UserProfileEnc.EncodeHeightCm"/>, <see cref="BodyMetric.EncodeValue"/>) — never a bare
/// <c>ToString()</c>, which is culture-sensitive and reads 60.4&#160;kg back as 604&#160;kg under
/// <c>de-DE</c>. The three preference steps write <b>plaintext</b> columns and take no cipher at all: a
/// goal code and a hormone code are vocabulary members the P6 engine has to query in SQL (§D).
/// <b>No decrypted value is ever logged, and nothing in this file logs at all</b> — which is also what
/// keeps the composed push token (rule 7) out of every sink.</para>
///
/// <para><b>5. The baseline's weight is an UPSERT under §G9's FILTERED regime</b> — <c>body_metrics</c>
/// <c>(UserId, Metric, MeasuredOn)</c> is unique only <c>WHERE "DeletedAt" IS NULL</c>, the one
/// deliberate tombstone exception in the phase, and it exists precisely so D-02's step stays
/// re-submittable after a delete. So the lookup below runs <b>WITHOUT</b>
/// <c>IgnoreQueryFilters()</c>: unlike <c>cycle_events</c> and <c>cycle_day_logs</c>, a tombstone here
/// is <b>not</b> revived — it has already released the key, and a new row is inserted alongside it.
/// Reviving it instead would resurrect a row the user deleted. §G9 does not reach the three preference
/// tables at all: none of them has a <c>DeletedAt</c> column, so there is no tombstone to revive and no
/// <c>IgnoreQueryFilters()</c> anywhere on those paths (erasure hard-deletes them, §F/T8).</para>
///
/// <para><b>6. The baseline's bounds are structural only.</b> See
/// <see cref="BaselineStructuralDomain"/>: no age
/// gate, no clinical height/weight range, no floor on <c>dob</c> beyond the type. §G8's backdate floor
/// is <c>cycle_events</c>-only and every real date of birth sits decades below it, so applying it here
/// would reject the very data the field exists for. The preference steps carry no numeric field at
/// all, so §G7 does not reach them.</para>
///
/// <para><b>7. THE TWO UNIT-OF-WORK STYLES IN THIS FILE, and which method is which.</b>
/// <see cref="ConcurrencyRetry"/> recovers by calling <c>ChangeTracker.Clear()</c>, a
/// <b>whole-context</b> operation on the request-scoped <c>LumenDbContext</c> — so anything a caller
/// staged earlier in the same scope is <b>silently discarded</b>, with no exception and no failing
/// test (§G12).
/// <list type="bullet">
///   <item><b><see cref="SaveBaselineAsync"/> OWNS its unit of work and is deliberately NOT
///   composable.</b> A caller must not stage un-saved work before invoking it. That was the right call
///   for T16 — no later task composes the baseline step — and its two <c>23505</c> hazards are real:
///   the <c>user_profile_enc</c> primary key on a first save, and the <c>body_metrics</c> filtered
///   unique key when a client double-taps "Continue". The hazard is pinned by
///   <c>OnboardingBaselineTests.SaveBaselineAsync_is_NOT_composable_because_its_retry_clears_the_whole_change_tracker</c>.
///   A future task that genuinely needs to compose it must first split out a stage-only method, the
///   way T14 split <c>ApplyOnboardingCycleAsync</c> and T15 split
///   <see cref="DeviceRegistrationService.StageRegistrationAsync"/>.</item>
///   <item><b><see cref="SaveNotificationPrefsAsync"/> IS the composer</b>, and it is the one place in
///   the phase where two features write in one request. It opens exactly ONE retried action that
///   clears the tracker, stages the four <c>user_notification_prefs</c> rows, calls
///   <see cref="DeviceRegistrationService.StageRegistrationAsync"/> — the <b>staging</b> half, which
///   T15 split out for precisely this — and saves once. It must <b>never</b> call
///   <see cref="DeviceRegistrationService.RegisterAsync"/>: that method owns its own retry and its own
///   <c>Clear()</c>, which would throw the staged preference rows away without a trace. Pinned by
///   <c>OnboardingPreferenceStepsTests.The_preference_rows_and_the_device_row_land_in_EXACTLY_ONE_save</c>.</item>
///   <item><b><see cref="SaveCycleAsync"/> IS THE OTHER COMPOSER, and the one §G12's unit-of-work rule
///   was actually written for.</b> It opens exactly ONE retried action that clears the tracker, stages
///   the seeded <c>cycle_events.period_start</c> row <i>itself</i>, calls
///   <see cref="CycleSettingsService.ApplyOnboardingCycleAsync"/> — the stage-only method T14 split out
///   for precisely this — and saves once. It must <b>never</b> call
///   <see cref="Cycle.CycleService.LogEventAsync"/> to write that event: every method on that service
///   owns its own retry and its own whole-context <c>Clear()</c>, which would discard the staged
///   settings row with no exception and no failing test. Pinned by
///   <c>OnboardingCompletionTests.The_settings_row_and_the_seeded_period_start_land_in_EXACTLY_ONE_save</c>.</item>
///   <item><b><see cref="CompleteAsync"/> owns an explicit TRANSACTION and deliberately no retry.</b>
///   The stamp is an <c>ExecuteUpdateAsync</c> and the backfill is a <c>SaveChangesAsync</c>; each would
///   otherwise get its own implicit transaction, and a crash between them would leave
///   <c>GET /me.onboardingCompleted</c> reporting <c>true</c> with the default sets missing. There is no
///   <see cref="ConcurrencyRetry"/> and no <c>ChangeTracker.Clear()</c>: the retry's contract is that
///   its action is re-runnable, and re-running a body that has already opened and rolled back a
///   transaction is a different shape from every other retried action in the phase. What makes that
///   safe is the guarded claim — exactly one caller ever reaches the backfill, and the backfill only
///   writes a set whose table is empty. The residual race (a preference step committing between the
///   emptiness probe and the insert) rolls the <i>whole</i> operation back, stamp included, so the
///   client's retry finds a clean slate rather than a half-completed account.</item>
/// </list></para>
///
/// <para><b>8. The three preference steps are FULL REPLACE, and their defaults are SEEDS rather than
/// implicit state.</b> Each writes its <b>complete</b> row set — all 5 goals, all 7 hormones, all 4
/// categories — with the boolean set from the request, so "provided" is never partial and a code the
/// user leaves out is recorded as <i>deselected</i> rather than left standing. That is the rule T11
/// chose for <c>symptoms</c>, decided on §G12's test — <i>how many surfaces write the row</i>, not the
/// verb: exactly one surface writes each of these tables, and <b>clearing is the affordance</b>,
/// because every one of these fields is a toggle chip. A <b>skipped</b> step writes <b>nothing at
/// all</b>: a missing row means "never saw the question" while <c>false</c> means "was asked and said
/// no", and the entities are explicit that those are different facts. The documented default is
/// therefore applied on the READ side, by <see cref="ReadGoalsAsync"/>,
/// <see cref="ReadHormonePrefsAsync"/> and <see cref="ReadNotificationPrefsAsync"/> — the single place
/// that turns "no row" into the seed, which is what stops T18's <c>/onboarding/complete</c> and any
/// later <c>GET</c> from disagreeing about what "skipped" means.</para>
/// </remarks>
public sealed class OnboardingStepsService(
    LumenDbContext db,
    IUserDayContext dayContext,
    IUserCryptoContext crypto,
    DeviceRegistrationService devices,
    CycleSettingsService cycleSettings)
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

    // ================================================================== T17: the preference steps

    /// <summary>
    /// Saves the D-02 goals step (screen 5): <b>all five</b> <c>user_goals</c> rows, with
    /// <c>Selected</c> set from the request. Answers 200 with the complete stored set in frozen order.
    /// </summary>
    /// <remarks>
    /// <b>Full replace and at-least-one</b> — see rules 8 and 3 on the type. This method owns its
    /// single <see cref="ConcurrencyRetry"/> action; nothing composes it.
    /// </remarks>
    public async Task<SaveGoalsResult> SaveGoalsAsync(SaveGoalsRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: the 404 fence comes first, so an erased token can neither learn that its body was
        // understood nor create a single row.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SaveGoalsResult.UserNotFound();

        var errors = new List<OnboardingFieldError>();
        var selected = NormaliseVocabularySet(request.Goals, UserGoal.Codes.All, "goals", errors);

        if (request.Goals is null)
        {
            errors.Add(new OnboardingFieldError("goals", ValidationMessages.Required));
        }
        else if (request.Goals.Count == 0)
        {
            // D-14: unlike hormones and notifications, "none" is not a state screen 5 can produce.
            // Reported with its own message rather than `Required`, because the field WAS supplied and
            // "value is required" would send the user looking for a missing field instead of at the chips.
            errors.Add(new OnboardingFieldError("goals", OnboardingValidationMessages.GoalsEmpty));
        }

        if (errors.Count > 0) return new SaveGoalsResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        return await ConcurrencyRetry.ExecuteAsync<SaveGoalsResult>(async token =>
        {
            // The action must be genuinely re-runnable: a second attempt happens only because the
            // first one's INSERT lost a race against the unique (UserId, GoalCode), and that insert is
            // still sitting in the tracker. Whole-context, hence rule 7.
            db.ChangeTracker.Clear();

            // No IgnoreQueryFilters(): user_goals has no DeletedAt and no query filter (rule 5).
            var existing = await db.UserGoals.Where(g => g.UserId == day.UserId).ToListAsync(token);

            StagePreferenceRows(
                existing,
                UserGoal.Codes.All,
                selected,
                row => row.GoalCode,
                code => new UserGoal { Id = Guid.NewGuid(), UserId = day.UserId, GoalCode = code, CreatedAt = now },
                (row, on) =>
                {
                    row.Selected = on;
                    row.UpdatedAt = now;
                });

            await db.SaveChangesAsync(token);

            // Re-read rather than echo, for the same reason the baseline step does: the 200 states what
            // is STORED, so a lost write fails on the call that caused it instead of at the next read.
            return new SaveGoalsResult.Saved(new GoalsResponse(await ReadGoalsAsync(day.UserId, token)));
        }, ct);
    }

    /// <summary>
    /// Saves the D-02 hormone step (screen 6): <b>all seven</b> <c>user_hormone_prefs</c> rows, with
    /// <c>Charted</c> set from the request. Answers 200 with the complete stored set in frozen order.
    /// </summary>
    /// <remarks>
    /// <b>Charted is a DISPLAY preference and nothing else (D-14, §G6).</b> An empty selection is
    /// valid and destroys nothing: P7b still extracts every one of the seven hormones from every lab,
    /// and no code anywhere may infer a clinical fact from what the user chose to draw. Owns its single
    /// <see cref="ConcurrencyRetry"/> action; nothing composes it.
    /// </remarks>
    public async Task<SaveHormonePrefsResult> SaveHormonePrefsAsync(
        SaveHormonePrefsRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SaveHormonePrefsResult.UserNotFound();

        var errors = new List<OnboardingFieldError>();
        var charted = NormaliseVocabularySet(
            request.ChartedHormones, HormoneCatalog.Codes.All, "chartedHormones", errors);

        // Required, but an EMPTY array is a valid answer: "chart nothing" is a real choice, and it is a
        // different state from having skipped the step (rule 8).
        if (request.ChartedHormones is null)
            errors.Add(new OnboardingFieldError("chartedHormones", ValidationMessages.Required));

        if (errors.Count > 0) return new SaveHormonePrefsResult.Invalid(errors);

        var now = day.NowUtc;

        return await ConcurrencyRetry.ExecuteAsync<SaveHormonePrefsResult>(async token =>
        {
            db.ChangeTracker.Clear();

            var existing = await db.UserHormonePrefs.Where(p => p.UserId == day.UserId).ToListAsync(token);

            StagePreferenceRows(
                existing,
                HormoneCatalog.Codes.All,
                charted,
                row => row.HormoneCode,
                code => new UserHormonePref
                {
                    Id = Guid.NewGuid(),
                    UserId = day.UserId,
                    HormoneCode = code,
                    CreatedAt = now,
                },
                (row, on) =>
                {
                    row.Charted = on;
                    row.UpdatedAt = now;
                });

            await db.SaveChangesAsync(token);

            return new SaveHormonePrefsResult.Saved(
                new HormonePrefsResponse(await ReadHormonePrefsAsync(day.UserId, token)));
        }, ct);
    }

    /// <summary>
    /// Saves the D-02 notification step (screen 7): <b>all four</b> <c>user_notification_prefs</c>
    /// rows, and — when the request carries a token/platform pair — the <c>user_devices</c> row behind
    /// "Allow &amp; finish", <b>in the same save</b>. Answers 200 with the complete stored set plus
    /// <c>deviceRegistered</c>.
    /// </summary>
    /// <remarks>
    /// <para><b>This is the composing method (rule 7).</b> It stages the preference rows and then calls
    /// <see cref="DeviceRegistrationService.StageRegistrationAsync"/> — the staging half T15 split out
    /// for exactly this — inside ONE <see cref="ConcurrencyRetry"/> action, and saves once, so the
    /// preferences and the device row commit or roll back together.
    /// <see cref="DeviceRegistrationService.RegisterAsync"/> must never be called from here: it owns
    /// its own retry, whose <c>ChangeTracker.Clear()</c> is whole-context and would discard the staged
    /// preference rows with no exception and no failing test.</para>
    ///
    /// <para><b>The device half is OPTIONAL, and that is a product requirement rather than leniency.</b>
    /// A user may decline the OS permission prompt, or the client may not have a token yet — and their
    /// category choices must still be recorded, because the preference is what D-19's scheduler reads.
    /// What is refused is a <i>half</i>-supplied pair: a token with no platform is a device P9a could
    /// never dispatch to, and a platform with no token is not a registration at all.</para>
    ///
    /// <para><b>The token never reaches a log line</b> (§F, inherited from T15 along with the path):
    /// nothing in this file logs, no error message quotes it, and it is absent from
    /// <see cref="NotificationPrefsResponse"/> by construction.</para>
    /// </remarks>
    public async Task<SaveNotificationPrefsResult> SaveNotificationPrefsAsync(
        SaveNotificationPrefsRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1 — and here the fence also runs before the cross-user device DETACH inside
        // StageRegistrationAsync, so an erased token can never be used as an unregister lever.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SaveNotificationPrefsResult.UserNotFound();

        var errors = new List<OnboardingFieldError>();
        var enabled = NormaliseVocabularySet(
            request.EnabledCategories,
            HormoneCatalog.NotificationCategories.All,
            "enabledCategories",
            errors);

        // Required, but an EMPTY array is valid: muting everything is a real answer.
        if (request.EnabledCategories is null)
            errors.Add(new OnboardingFieldError("enabledCategories", ValidationMessages.Required));

        // Blank is absent on both, the same rule PATCH /me and POST /me/devices follow — so a client
        // sending "" for a token it does not have gets "no device", not a half-supplied pair.
        var pushToken = Trimmed(request.PushToken);
        var platform = Trimmed(request.Platform);

        // Reported under `request` because the fault belongs to the COMBINATION: neither field is
        // required on its own, and each is individually fine.
        if (pushToken is null != platform is null)
        {
            errors.Add(new OnboardingFieldError(
                ValidationProblemBuilder.RequestKey, OnboardingValidationMessages.DeviceFieldsIncomplete));
        }

        // Both guards below duplicate no logic from T15: StageRegistrationAsync's own checks are
        // PROGRAMMING-ERROR guards that throw, and this endpoint is the caller that owes the 400.
        if (platform is not null && !UserDevice.Platforms.All.Contains(platform, StringComparer.Ordinal))
            errors.Add(new OnboardingFieldError("platform", ValidationMessages.NotAllowedValue));

        // Trim first: the cap bounds the token, not a trailing newline — the same rule `notes` follows.
        if (pushToken is not null && pushToken.Length > UserDevice.PushTokenMaxLength)
        {
            errors.Add(new OnboardingFieldError(
                "pushToken", ValidationMessages.MaxLength(UserDevice.PushTokenMaxLength)));
        }

        if (errors.Count > 0) return new SaveNotificationPrefsResult.Invalid(errors);

        var registersDevice = pushToken is not null && platform is not null;
        var now = day.NowUtc;

        return await ConcurrencyRetry.ExecuteAsync<SaveNotificationPrefsResult>(async token =>
        {
            // Rule 7: THIS is the one retried action for the whole unit of work — the preference rows
            // and the device row alike. Every participant inside it stages only.
            db.ChangeTracker.Clear();

            var existing = await db.UserNotificationPrefs
                .Where(p => p.UserId == day.UserId).ToListAsync(token);

            StagePreferenceRows(
                existing,
                HormoneCatalog.NotificationCategories.All,
                enabled,
                row => row.CategoryCode,
                code => new UserNotificationPref
                {
                    Id = Guid.NewGuid(),
                    UserId = day.UserId,
                    CategoryCode = code,
                    CreatedAt = now,
                },
                (row, on) =>
                {
                    row.Enabled = on;
                    row.UpdatedAt = now;
                });

            // STAGING half only (§G12). RegisterAsync here would silently discard everything above.
            if (registersDevice)
                await devices.StageRegistrationAsync(day.UserId, platform!, pushToken!, now, token);

            await db.SaveChangesAsync(token);

            return new SaveNotificationPrefsResult.Saved(new NotificationPrefsResponse(
                await ReadNotificationPrefsAsync(day.UserId, token), registersDevice));
        }, ct);
    }

    // ------------------------------------------------------------------ the preference read paths

    /// <summary>
    /// The goals projection: <b>every</b> code in <see cref="UserGoal.Codes.All"/> order, each with its
    /// stored flag — or, for a user who has never answered, the D-14 seed.
    /// </summary>
    /// <remarks>
    /// <b>This is the single place "skipped" is given a meaning</b> (rule 8), and the reason it exists
    /// before anything reads it: T18's <c>/onboarding/complete</c> and <c>GET /onboarding/state</c>
    /// call this rather than re-deriving a default, so the two cannot disagree. The fallback is
    /// per-code rather than per-set, which also keeps an append to the frozen vocabulary readable for
    /// users who answered before it existed.
    /// </remarks>
    public async Task<IReadOnlyList<GoalSelection>> ReadGoalsAsync(Guid userId, CancellationToken ct)
    {
        var stored = await db.UserGoals.AsNoTracking()
            .Where(g => g.UserId == userId)
            .ToDictionaryAsync(g => g.GoalCode, g => g.Selected, StringComparer.Ordinal, ct);

        return
        [
            .. UserGoal.Codes.All.Select(code => new GoalSelection(
                code,
                stored.TryGetValue(code, out var selected)
                    ? selected
                    : UserGoal.DefaultSelected.Contains(code, StringComparer.Ordinal))),
        ];
    }

    /// <summary>
    /// The hormone projection: all seven codes in display order, each with its stored charted flag —
    /// or, for a user who has never answered, the D-14 seed, which is <b>all seven ON</b>.
    /// </summary>
    public async Task<IReadOnlyList<HormoneSelection>> ReadHormonePrefsAsync(Guid userId, CancellationToken ct)
    {
        var stored = await db.UserHormonePrefs.AsNoTracking()
            .Where(p => p.UserId == userId)
            .ToDictionaryAsync(p => p.HormoneCode, p => p.Charted, StringComparer.Ordinal, ct);

        return
        [
            .. HormoneCatalog.Codes.All.Select(code => new HormoneSelection(
                code,
                stored.TryGetValue(code, out var charted)
                    ? charted
                    : UserHormonePref.DefaultCharted.Contains(code, StringComparer.Ordinal))),
        ];
    }

    /// <summary>
    /// The notification projection: all four categories in screen-7 order, each with its stored flag —
    /// or, for a user who has never answered, the ON / ON / OFF / OFF seed.
    /// </summary>
    public async Task<IReadOnlyList<NotificationCategorySelection>> ReadNotificationPrefsAsync(
        Guid userId, CancellationToken ct)
    {
        var stored = await db.UserNotificationPrefs.AsNoTracking()
            .Where(p => p.UserId == userId)
            .ToDictionaryAsync(p => p.CategoryCode, p => p.Enabled, StringComparer.Ordinal, ct);

        return
        [
            .. HormoneCatalog.NotificationCategories.All.Select(code => new NotificationCategorySelection(
                code,
                stored.TryGetValue(code, out var isEnabled)
                    ? isEnabled
                    : UserNotificationPref.DefaultEnabled.Contains(code, StringComparer.Ordinal))),
        ];
    }

    // ============================================ T18: the cycle seed, the completion gate, the state

    /// <summary>
    /// Saves the D-02 cycle step (screen 3, B15) — the one <b>mandatory</b> answer in onboarding. Writes
    /// <c>user_cycle_settings</c> through T14's stage-only
    /// <see cref="CycleSettingsService.ApplyOnboardingCycleAsync"/> <b>and</b> upserts the single
    /// onboarding-seeded <c>cycle_events.period_start</c> row, in ONE unit of work. Answers 200 with the
    /// stored values, every omitted field resolved to its default.
    /// </summary>
    /// <remarks>
    /// <para><b>This is the composer §G12's unit-of-work rule exists for</b> — see rule 7 on the type.
    /// The single retried action below is the whole of it; nothing inside it saves or clears.</para>
    ///
    /// <para><b>§G8 — this and <c>POST /cycle/events</c> are the ONLY two floored writes in P4a.</b>
    /// <c>lastPeriodStart</c> is bounded above by the user's local today (D-12) and below by
    /// <see cref="UserDayInfo.BackdateFloor"/> (account creation − 2 y, D-13). Do not copy this pair of
    /// checks anywhere else: a floor on a symptom, a day log or a date of birth rejects the historical
    /// logging D-13 explicitly permits.</para>
    ///
    /// <para><b>§G7 — nothing here is clinically validated.</b> The two typed self-reports get the
    /// structural storage domain and nothing more; a value outside the sanity band is <b>stored</b> and
    /// answered with a non-blocking code computed by the one method that owns that band.</para>
    ///
    /// <para><b>409 rather than 400 after completion, and checked before validation.</b> The step is
    /// closed once the account is stamped, so there is no body that could be accepted — reporting a
    /// field error would invite the client to keep correcting one.</para>
    /// </remarks>
    public async Task<SaveOnboardingCycleResult> SaveCycleAsync(
        SaveOnboardingCycleRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: the 404 fence comes first, so an erased token can neither learn that its body was
        // understood nor create a single row — and cannot learn whether the account was onboarded.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SaveOnboardingCycleResult.UserNotFound();

        var completedAt = await db.Users.AsNoTracking()
            .Where(u => u.Id == day.UserId)
            .Select(u => u.OnboardingCompletedAt)
            .FirstOrDefaultAsync(ct);

        if (completedAt is not null) return new SaveOnboardingCycleResult.AlreadyCompleted();

        var errors = new List<OnboardingFieldError>();

        // --- lastPeriodStart: the phase's SECOND and LAST floored write (§G8) --------------------
        if (request.LastPeriodStart is not { } lastPeriodStart || lastPeriodStart == default)
        {
            // `default(DateOnly)` is 0001-01-01 — what an unset date field binds to. Reported as
            // "required" rather than as a floor violation, because that is what the user did.
            errors.Add(new OnboardingFieldError("lastPeriodStart", ValidationMessages.Required));
        }
        else if (lastPeriodStart > day.Today)
        {
            errors.Add(new OnboardingFieldError("lastPeriodStart", ValidationMessages.FutureDate));
        }
        else if (lastPeriodStart < day.BackdateFloor)
        {
            errors.Add(new OnboardingFieldError("lastPeriodStart", ValidationMessages.BeforeFloor));
        }

        // --- the two typed self-reports: STRUCTURAL ONLY (§G7) -----------------------------------
        // There is deliberately no sanity-band branch and no clinical-band branch here. A bound that
        // refused a save would be the entry blocker rider 7 forbids, and the C-03/C-04 figures that
        // would do the refusing are clinician-UNSIGNED with no home in backend/src this phase.
        if (request.AvgCycleLengthDays is { } avgCycle && !CycleSettingsStructuralDomain.Contains(avgCycle))
        {
            errors.Add(new OnboardingFieldError(
                "avgCycleLengthDays",
                ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max)));
        }

        if (request.AvgPeriodLengthDays is { } avgPeriod && !CycleSettingsStructuralDomain.Contains(avgPeriod))
        {
            errors.Add(new OnboardingFieldError(
                "avgPeriodLengthDays",
                ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max)));
        }

        // --- regularity: the three ratified codes, matched case-sensitively (§G10) ---------------
        var regularity = Trimmed(request.Regularity);
        if (regularity is not null &&
            !UserCycleSettings.RegularityValues.All.Contains(regularity, StringComparer.Ordinal))
        {
            errors.Add(new OnboardingFieldError("regularity", ValidationMessages.NotAllowedValue));
        }

        if (errors.Count > 0) return new SaveOnboardingCycleResult.Invalid(errors);

        var anchor = request.LastPeriodStart!.Value;
        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        return await ConcurrencyRetry.ExecuteAsync<SaveOnboardingCycleResult>(async token =>
        {
            // Rule 7: THIS is the one retried action for the whole unit of work — the anchor event and
            // the settings row alike. Every participant inside it stages only. The clear is what makes
            // it re-runnable: a lost race leaves BOTH failed inserts staged.
            db.ChangeTracker.Clear();

            await StageOnboardingAnchorAsync(day.UserId, anchor, now, token);

            // Staged, not saved (§G12). Its own tests fail the moment it grows a save or a clear.
            // The casts are safe: the structural domain above is the smallint width.
            var settings = await cycleSettings.ApplyOnboardingCycleAsync(
                day.UserId,
                (short?)request.AvgCycleLengthDays,
                (short?)request.AvgPeriodLengthDays,
                regularity,
                now,
                token);

            await db.SaveChangesAsync(token);

            // Answered off the STAGED entity rather than off the request, so the defaults the server
            // applied are what the client is told — and a lost write shows up here, not at the next read.
            return new SaveOnboardingCycleResult.Saved(new OnboardingCycleResponse(
                anchor,
                settings.AvgCycleLengthDays,
                settings.AvgPeriodLengthDays,
                settings.Regularity,
                CycleSettingsService.ComputeWarnings(settings.AvgCycleLengthDays, settings.AvgPeriodLengthDays)));
        }, ct);
    }

    /// <summary>
    /// Stamps <c>users.onboarding_completed_at</c> — <b>exactly once</b>, whatever the client does — and
    /// materialises the four default sets for any of them the user never answered, in the <b>same
    /// transaction</b>. A repeat call answers 200 with the original instant.
    /// </summary>
    /// <remarks>
    /// <para><b>This method is the ONLY writer of <c>users.OnboardingCompletedAt</c> in the backend</b>,
    /// which <c>BackdateFloorAndCompletionStampTests</c> holds to by scanning the source: a second
    /// writer would bypass the guarded claim below and make "onboarded" mean two different things.</para>
    ///
    /// <para><b>The mandatory set is checked on the DATA, not on which endpoint wrote it.</b> A user who
    /// logged their period from the cycle module has answered the mandatory question by any reading that
    /// matters, and D-02's own wording ("account + last-period date") is about the datum.</para>
    ///
    /// <para><b>Why the backfill exists at all, given T17's read projections.</b> Both mechanisms ship,
    /// and they are coherent only because neither restates the other's literals — the rows written here
    /// come from <see cref="UserGoal.DefaultSelected"/>,
    /// <see cref="UserHormonePref.DefaultCharted"/>, <see cref="UserNotificationPref.DefaultEnabled"/>
    /// and the <see cref="UserCycleSettings"/> initializers, exactly as the projections do. The division
    /// of labour: <b>before</b> completion the projections give absence its meaning, so a
    /// partially-onboarded user reads correctly; <b>at</b> completion the seed is materialised so the
    /// database becomes self-describing and no later consumer (P6, P9a) has to remember to apply a
    /// read-side default — a direct <c>SELECT</c> on <c>user_notification_prefs</c> returning zero rows
    /// would otherwise read as "all notifications off" and silently cost a user their daily check-in
    /// reminder. <b>The accepted cost, stated rather than hidden:</b> the never-asked / said-no
    /// distinction does not survive completion, and nothing after this point may rely on it.</para>
    ///
    /// <para><b>§G6: no <c>user_insight_snapshot</c> row is created here or anywhere else in P4a.</b></para>
    /// </remarks>
    public async Task<CompleteOnboardingResult> CompleteAsync(CancellationToken ct)
    {
        // Rule 1: the 404 fence, before the completion probe as well as before any write.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CompleteOnboardingResult.UserNotFound();

        var completedAt = await db.Users.AsNoTracking()
            .Where(u => u.Id == day.UserId)
            .Select(u => u.OnboardingCompletedAt)
            .FirstOrDefaultAsync(ct);

        if (completedAt is null)
        {
            // TODO(C-12): amenorrhea and post-menopausal users need an alternate mandatory set with no
            // last-period gate. That branch is a clinician-UNSIGNED PO-interim concept and is
            // explicitly NOT in P4a — it must not be approximated here.
            //
            // The query filter is load-bearing: a retracted period start is not an answer.
            var hasAnchor = await db.CycleEvents
                .AnyAsync(e => e.UserId == day.UserId && e.Kind == CycleEvent.Kinds.PeriodStart, ct);

            if (!hasAnchor) return new CompleteOnboardingResult.Incomplete(OnboardingSteps.Mandatory);
        }

        var now = day.NowUtc;

        // Rule 7: ONE transaction over the stamp and the backfill. Each would otherwise get its own
        // implicit transaction, and a crash between them leaves GET /me reporting `true` with the
        // defaults missing — a state no later request can detect or repair.
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // The GUARDED CLAIM (the CryptoShredJob idiom). `WHERE OnboardingCompletedAt IS NULL` is what
        // makes two simultaneous "Finish" taps stamp exactly once: the loser updates no rows and reports
        // the winner's instant instead of racing the column forward. The query filter also excludes a
        // soft-deleted user, so an account erased mid-flight is never stamped.
        var stamped = await db.Users
            .Where(u => u.Id == day.UserId && u.OnboardingCompletedAt == null)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(u => u.OnboardingCompletedAt, now)
                    .SetProperty(u => u.UpdatedAt, now),
                ct);

        if (stamped == 0)
        {
            // Either a repeat call or a lost race — the same answer either way, and deliberately a 200:
            // the user's intent is already satisfied, and a 409 would make the online-only client's
            // retry unsafe on the last screen of the flow. Nothing was written, so the transaction is
            // simply abandoned.
            var winner = await db.Users.AsNoTracking()
                .Where(u => u.Id == day.UserId)
                .Select(u => u.OnboardingCompletedAt)
                .FirstOrDefaultAsync(ct);

            return winner is { } original
                ? new CompleteOnboardingResult.Completed(
                    new OnboardingCompleteResponse(original, AlreadyCompleted: true))
                : new CompleteOnboardingResult.UserNotFound();
        }

        await BackfillDefaultsAsync(day.UserId, now, ct);
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return new CompleteOnboardingResult.Completed(
            new OnboardingCompleteResponse(now, AlreadyCompleted: false));
    }

    /// <summary>
    /// The D-02 resume read (OQ-7b): where the user got to, what is still owed, and the current value of
    /// every preference set — so P4b can re-enter a half-finished flow in one call.
    /// </summary>
    /// <remarks>
    /// <para><b>The three preference lists come from T17's projections</b>
    /// (<see cref="ReadGoalsAsync"/>, <see cref="ReadHormonePrefsAsync"/>,
    /// <see cref="ReadNotificationPrefsAsync"/>) and are never re-derived: those are the single place a
    /// skipped step is given a meaning, and a second restatement of the seed is the drift they exist to
    /// prevent (§G12). <b>Nothing is persisted by this read</b> — the seed is applied, not materialised;
    /// only <see cref="CompleteAsync"/> writes it down.</para>
    ///
    /// <para><b>§G6: nothing is computed.</b> No phase, no cycle day, no prediction, no confidence, and
    /// no property on the response for any of them. Every member is a stored value or the presence of a
    /// row.</para>
    /// </remarks>
    public async Task<OnboardingStateResult> ReadStateAsync(CancellationToken ct)
    {
        // Rule 1. The read is fenced exactly like the writes: an erased token learns nothing.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new OnboardingStateResult.UserNotFound();

        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == day.UserId, ct);
        if (user is null) return new OnboardingStateResult.UserNotFound();

        // No IgnoreQueryFilters(): a retracted period start is not this user's last period start, and
        // it does not answer the mandatory question either.
        var lastPeriodStart = await db.CycleEvents.AsNoTracking()
            .Where(e => e.UserId == day.UserId && e.Kind == CycleEvent.Kinds.PeriodStart)
            .OrderByDescending(e => e.OccurredOn)
            .Select(e => (DateOnly?)e.OccurredOn)
            .FirstOrDefaultAsync(ct);

        // Rider 4 puts weight in `body_metrics` rather than on the profile, so "was screen 4 answered"
        // cannot be read off `user_profile_enc` alone — a weight-only baseline is a real answer.
        var profile = await db.UserProfiles.AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == day.UserId, ct);

        var profileAnswered = profile is not null &&
            (profile.DobEnc is not null
             || profile.HeightCmEnc is not null
             || profile.EndoStatusEnc is not null
             || profile.RasrmStageEnc is not null
             || profile.DiagnosedOnEnc is not null);

        var baselineProvided = profileAnswered || await db.BodyMetrics.AsNoTracking()
            .AnyAsync(m => m.UserId == day.UserId && m.Metric == BodyMetric.Metrics.WeightKg, ct);

        // "Any row at all", never "any row with the flag set": the whole point of the T17 tables is that
        // a row with `false` is an ANSWER while no row is "never saw the question".
        var goalsProvided = await db.UserGoals.AnyAsync(g => g.UserId == day.UserId, ct);
        var hormonesProvided = await db.UserHormonePrefs.AnyAsync(p => p.UserId == day.UserId, ct);
        var notificationsProvided = await db.UserNotificationPrefs.AnyAsync(p => p.UserId == day.UserId, ct);

        return new OnboardingStateResult.Found(new OnboardingStateResponse(
            Completed: user.OnboardingCompletedAt is not null,
            CompletedAt: user.OnboardingCompletedAt,
            MissingMandatorySteps: lastPeriodStart is null ? OnboardingSteps.Mandatory : Array.Empty<string>(),
            CycleProvided: lastPeriodStart is not null,
            BaselineProvided: baselineProvided,
            GoalsProvided: goalsProvided,
            HormonesProvided: hormonesProvided,
            NotificationsProvided: notificationsProvided,
            LastPeriodStart: lastPeriodStart,
            Goals: await ReadGoalsAsync(day.UserId, ct),
            Hormones: await ReadHormonePrefsAsync(day.UserId, ct),
            Notifications: await ReadNotificationPrefsAsync(day.UserId, ct)));
    }

    // ------------------------------------------------------------------ the onboarding cycle anchor

    /// <summary>
    /// Stages the single onboarding-seeded <c>cycle_events.period_start</c> row for
    /// <paramref name="anchor"/>, following the merge rule pinned on <see cref="CycleEvent"/> in T5.
    /// <b>Staged, not saved</b> — <see cref="SaveCycleAsync"/> owns the one save for the unit of work.
    /// </summary>
    /// <remarks>
    /// <para><b>§G9 UNFILTERED regime.</b> <c>(UserId, Kind, OccurredOn)</c> is unique across live
    /// <i>and</i> tombstoned rows, so every lookup here bypasses the soft-delete filter. A blind insert
    /// is not a duplicate row — it is a <c>23505</c> surfacing as a 500, and the three cases below are
    /// exactly the three ways a user reaches that key without this rule.</para>
    ///
    /// <list type="number">
    ///   <item><b>The target day is occupied (live or tombstoned) → ADOPT/REVIVE it.</b> Its
    ///   <see cref="CycleEvent.Source"/> and <see cref="CycleEvent.CreatedAt"/> are preserved: they are
    ///   the row's provenance, and relabelling a hand-logged observation as machine seed would be a lie
    ///   about where the datum came from. A stale seed elsewhere is then retired (soft-deleted), so
    ///   exactly one live anchor survives.</item>
    ///   <item><b>No occupant but a seed exists → MOVE the seed.</b> The user corrected the date on
    ///   screen 3; the same row relocates, keeping its identity and its creation instant.</item>
    ///   <item><b>Neither → insert the seed.</b> The only path that creates a row.</item>
    /// </list>
    ///
    /// <para><b>Nothing here touches <see cref="CycleEvent.FlowIntensity"/> or
    /// <see cref="CycleEvent.NotesEnc"/>.</b> Onboarding never asks for either, so a new row leaves them
    /// null and an adopted row keeps whatever the user logged — clearing them would destroy data this
    /// endpoint was never given.</para>
    /// </remarks>
    private async Task StageOnboardingAnchorAsync(
        Guid userId, DateOnly anchor, DateTimeOffset now, CancellationToken ct)
    {
        var occupant = await db.CycleEvents.IgnoreQueryFilters().FirstOrDefaultAsync(
            e => e.UserId == userId && e.Kind == CycleEvent.Kinds.PeriodStart && e.OccurredOn == anchor, ct);

        // The seed is found by its SOURCE, not by its date — that is the whole reason `source` exists
        // (T5). Ordered so the lookup is deterministic even in the state the merge rule makes
        // unreachable (two onboarding rows), rather than relying on it being unreachable.
        var seed = await db.CycleEvents.IgnoreQueryFilters()
            .Where(e => e.UserId == userId
                        && e.Kind == CycleEvent.Kinds.PeriodStart
                        && e.Source == CycleEvent.Sources.Onboarding)
            .OrderBy(e => e.OccurredOn)
            .FirstOrDefaultAsync(ct);

        if (occupant is not null)
        {
            occupant.DeletedAt = null;
            occupant.UpdatedAt = now;

            if (seed is not null && seed.Id != occupant.Id)
            {
                seed.DeletedAt = now;
                seed.UpdatedAt = now;
            }

            return;
        }

        if (seed is not null)
        {
            seed.OccurredOn = anchor;
            seed.DeletedAt = null;
            seed.UpdatedAt = now;
            return;
        }

        db.CycleEvents.Add(new CycleEvent
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Kind = CycleEvent.Kinds.PeriodStart,
            OccurredOn = anchor,
            Source = CycleEvent.Sources.Onboarding,
            CreatedAt = now,
            UpdatedAt = now,
        });
    }

    // ------------------------------------------------------------------ the completion backfill

    /// <summary>
    /// Materialises the documented seed for each of the four sets the user never answered. <b>Staged,
    /// not saved</b> — <see cref="CompleteAsync"/> owns the save, inside its transaction.
    /// </summary>
    /// <remarks>
    /// <para><b>Every value written here comes from the entity's own seed constant.</b> Not one literal
    /// is restated: the goals come from <see cref="UserGoal.DefaultSelected"/>, the hormones from
    /// <see cref="UserHormonePref.DefaultCharted"/>, the categories from
    /// <see cref="UserNotificationPref.DefaultEnabled"/>, and the settings row from
    /// <see cref="CycleSettingsService.ApplyOnboardingCycleAsync"/> with every argument null, which
    /// applies the <see cref="UserCycleSettings"/> initializers. That is what makes this and T17's read
    /// projections structurally unable to disagree — a restated seed here would be a second source of
    /// truth that drifted the first time a vocabulary was appended to.</para>
    ///
    /// <para><b>"Backfill" means "for a table with zero rows", per set.</b> A user who answered screen 6
    /// with nothing charted must not have all seven turned back on by pressing Finish — that would be
    /// the app overruling an explicit answer. The probe is therefore per table and per user.</para>
    ///
    /// <para>The fourth set is <c>user_cycle_settings</c>, and it earns its place: the mandatory check
    /// is on the DATA, so a user who logged their period from the cycle module reaches completion with
    /// no settings row at all, and leaving it absent would make a direct <c>SELECT</c> read as "no
    /// self-report" for the rest of the product's life.</para>
    /// </remarks>
    private async Task BackfillDefaultsAsync(Guid userId, DateTimeOffset now, CancellationToken ct)
    {
        if (!await db.UserGoals.AnyAsync(g => g.UserId == userId, ct))
        {
            foreach (var code in UserGoal.Codes.All)
            {
                db.UserGoals.Add(new UserGoal
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    GoalCode = code,
                    Selected = UserGoal.DefaultSelected.Contains(code, StringComparer.Ordinal),
                    CreatedAt = now,
                    UpdatedAt = now,
                });
            }
        }

        if (!await db.UserHormonePrefs.AnyAsync(p => p.UserId == userId, ct))
        {
            foreach (var code in HormoneCatalog.Codes.All)
            {
                db.UserHormonePrefs.Add(new UserHormonePref
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    HormoneCode = code,
                    Charted = UserHormonePref.DefaultCharted.Contains(code, StringComparer.Ordinal),
                    CreatedAt = now,
                    UpdatedAt = now,
                });
            }
        }

        if (!await db.UserNotificationPrefs.AnyAsync(p => p.UserId == userId, ct))
        {
            foreach (var code in HormoneCatalog.NotificationCategories.All)
            {
                db.UserNotificationPrefs.Add(new UserNotificationPref
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    CategoryCode = code,
                    Enabled = UserNotificationPref.DefaultEnabled.Contains(code, StringComparer.Ordinal),
                    CreatedAt = now,
                    UpdatedAt = now,
                });
            }
        }

        if (!await db.CycleSettings.AnyAsync(s => s.UserId == userId, ct))
        {
            // Every argument null, so the T6 entity initializers supply all three values — the same
            // defaults `POST /onboarding/cycle` would have written. Stage-only, hence composable here.
            await cycleSettings.ApplyOnboardingCycleAsync(userId, null, null, null, now, ct);
        }
    }

    // ------------------------------------------------------------------ the shared preference machinery

    /// <summary>
    /// Validates every member of a vocabulary array and returns the accepted <b>set</b>.
    /// </summary>
    /// <remarks>
    /// Duplicates collapse silently — chip order and repetition are UI noise, not an answer, and the
    /// unique key would reject the second row anyway. Errors are keyed per member
    /// (<c>goals[1]</c>), matching T12's <c>painTypes[1]</c>, because the client renders these as chips
    /// and has to know which one to flag. Matching is <b>Ordinal</b>: the vocabularies are wire codes,
    /// not prose, and a case-insensitive match would quietly accept <c>Manage_Symptoms</c> as data.
    /// </remarks>
    private static HashSet<string> NormaliseVocabularySet(
        IReadOnlyList<string>? supplied,
        IReadOnlyList<string> vocabulary,
        string field,
        List<OnboardingFieldError> errors)
    {
        var accepted = new HashSet<string>(StringComparer.Ordinal);
        if (supplied is null) return accepted;

        for (var i = 0; i < supplied.Count; i++)
        {
            var member = supplied[i]?.Trim();

            if (string.IsNullOrEmpty(member))
                errors.Add(new OnboardingFieldError($"{field}[{i}]", ValidationMessages.Required));
            else if (!vocabulary.Contains(member, StringComparer.Ordinal))
                errors.Add(new OnboardingFieldError($"{field}[{i}]", ValidationMessages.NotAllowedValue));
            else
                accepted.Add(member);
        }

        return accepted;
    }

    /// <summary>
    /// Stages the COMPLETE row set for one preference vocabulary: one row per code, existing rows
    /// updated in place and missing ones inserted, with the flag set from <paramref name="on"/>.
    /// <b>Staged, not saved</b> — the caller owns the single save for the whole unit of work.
    /// </summary>
    /// <remarks>
    /// <para>Writing every code, rather than only the selected ones, is what makes these steps
    /// idempotent and their storage unambiguous: the row count is a constant (5 / 7 / 4), a re-submit
    /// updates in place instead of inserting a duplicate against <c>(UserId, &lt;Code&gt;)</c>, and a
    /// deselection is recorded as an answer instead of vanishing.</para>
    ///
    /// <para>Generic over the three entity types by delegate rather than by a shared interface,
    /// deliberately: an interface would put extra CLR properties on entities EF maps by convention,
    /// which is a model change §G4 does not permit this phase.</para>
    /// </remarks>
    /// <param name="existing">The user's rows for this vocabulary, already loaded and TRACKED.</param>
    /// <param name="vocabulary">The frozen code list (§G10), in canonical order.</param>
    /// <param name="on">The codes whose flag is <see langword="true"/>; every other code gets <see langword="false"/>.</param>
    /// <param name="codeOf">Reads the row's vocabulary code.</param>
    /// <param name="newRow">Builds a row for a code the user has none for (id, user, code, created-at).</param>
    /// <param name="apply">Writes the flag and the updated-at stamp.</param>
    private void StagePreferenceRows<TRow>(
        List<TRow> existing,
        IReadOnlyList<string> vocabulary,
        IReadOnlySet<string> on,
        Func<TRow, string> codeOf,
        Func<string, TRow> newRow,
        Action<TRow, bool> apply)
        where TRow : class
    {
        foreach (var code in vocabulary)
        {
            var row = existing.Find(r => string.Equals(codeOf(r), code, StringComparison.Ordinal));

            if (row is null)
            {
                row = newRow(code);
                db.Add(row);
            }

            apply(row, on.Contains(code));
        }
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
