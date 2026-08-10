using Lumen.Api.Persistence;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.CycleSettings;

/// <summary>
/// The §C.9 cycle-settings resource: <c>GET</c>/<c>PATCH /settings/cycle</c>, the C-12 tracking-pause
/// state machine, and the onboarding entry point T18 shares. Registered scoped, alongside the
/// request-scoped <see cref="IUserDayContext"/> it depends on.
/// </summary>
/// <remarks>
/// <para><b>1. A null day context is a 404, before anything else happens.</b> Erasure has no write
/// fence behind it: a crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires. Resolving the day context FIRST and returning "not found"
/// on null is the whole of the defence — which is why it is checked before validation rather than
/// after, on the read as well as the write.</para>
///
/// <para><b>2. Validate then act (T3).</b> Every field error is collected before the first write, so a
/// rejected request has changed nothing.</para>
///
/// <para><b>3. §G7 — the bounds on the two typed self-reports are SOFT, and this is the phase's proof
/// of it.</b> The only 400 they can produce is structural
/// (<see cref="CycleSettingsStructuralDomain"/>: a positive integer that fits <c>smallint</c>, matching
/// T6's <c>&gt; 0</c> DDL CHECKs). A value outside <see cref="CycleSettingsSanityBand"/> is
/// <b>persisted</b> and answered with a non-blocking <see cref="CycleSettingsWarnings"/> code. The
/// C-03/C-04 clinical bounds are clinician-UNSIGNED and have no home in <c>backend/src</c> this phase
/// — there is no branch here that consults them, and there must never be one.</para>
///
/// <para><b>4. §G6 — this service computes NOTHING clinical.</b>
/// <see cref="CycleSettingsResponse.PhasesUnavailable"/> is a boolean OR of two stored flags and the
/// warnings are a range check on two self-reported integers. No phase, no cycle day, no prediction, no
/// confidence, and no property on the response for any of them.</para>
///
/// <para><b>5. §G9 does not apply here.</b> Neither <c>user_cycle_settings</c> nor
/// <c>cycle_tracking_pause_spans</c> has a <c>DeletedAt</c> column or a soft-delete query filter (T6:
/// D-13's soft delete governs individual <i>entries</i>, and these are a per-user singleton and its
/// history). So there is no tombstone to revive and <b>no <c>IgnoreQueryFilters()</c> anywhere on this
/// path</b>. The one filtered unique index in play — <c>(UserId) WHERE "EndedOn" IS NULL</c> on the
/// spans table — is filtered on a <b>domain lifecycle</b> column, not a tombstone marker, and is
/// outside the §G9 regime entirely.</para>
///
/// <para><b>6. The current state and the history are reconciled on every write, never patched
/// independently.</b> <c>user_cycle_settings.{TrackingPaused, PauseReason, PausedSince}</c> is the
/// CURRENT pause; <c>cycle_tracking_pause_spans</c> is the history §A:59 requires so P6 can exclude
/// paused spans from its estimators. <see cref="ReconcilePauseAsync"/> derives the span state from the
/// target settings state in one place, which is what makes divergence unreachable rather than merely
/// unlikely — and makes the partial unique index a backstop instead of the mechanism.</para>
///
/// <para><b>7. WARNING — <see cref="UpdateAsync"/> CLEARS THE WHOLE CHANGE TRACKER, so a caller must
/// not stage un-saved work before invoking it.</b> Its <see cref="ConcurrencyRetry"/> action calls
/// <c>ChangeTracker.Clear()</c> to be re-runnable, and that acts on the request-scoped
/// <c>LumenDbContext</c>: anything staged earlier in the same scope is <b>silently discarded</b>.
/// <see cref="ApplyOnboardingCycleAsync"/> is the deliberate opposite — it <b>stages only</b>, exactly
/// so T18 can compose it. See its own remarks.</para>
/// </remarks>
public sealed class CycleSettingsService(LumenDbContext db, IUserDayContext dayContext)
{
    /// <summary>
    /// Reads the caller's cycle settings (screen 32). Always 200 for a live user — <b>including one
    /// who has no row</b>, who is answered with the T6 defaults and <b>nothing is persisted</b>.
    /// </summary>
    /// <remarks>
    /// <para><b>Why "no row" is never a 404.</b> 404 means "no such user" on every P4a route (§G12).
    /// A user reaches this endpoint with no row whenever the onboarding cycle step (T18/B15) has not
    /// run — a legitimate, common state that screen 32 must render — and answering it with the same
    /// status an erased account gets would leave the client unable to tell the two apart.</para>
    ///
    /// <para><b>Why the defaults are not written on read.</b> A GET that materialises a row is a write
    /// on a safe method: it takes a lock, races the crypto-shred fence above it, and creates a row for
    /// a user who only opened a screen. The defaults are read straight off a transient
    /// <see cref="UserCycleSettings"/> instance, so what this returns is the <b>same</b> set of
    /// initializers the entity (and therefore the DDL default) carries and the two cannot drift.
    /// <see cref="CycleSettingsResponse.CreatedAt"/>/<see cref="CycleSettingsResponse.UpdatedAt"/> come
    /// back null, which is what tells the client the row is not yet real.</para>
    /// </remarks>
    public async Task<CycleSettingsReadResult> GetAsync(CancellationToken ct)
    {
        // Rule 1: before anything else.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleSettingsReadResult.UserNotFound();

        // No query filter on this table (rule 5), so no IgnoreQueryFilters(). AsNoTracking because
        // this is a read and tracking would let a later write in the same scope pick the row up.
        var row = await db.CycleSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == day.UserId, ct);

        return new CycleSettingsReadResult.Found(row is null
            ? ToResponse(new UserCycleSettings { UserId = day.UserId }, persisted: false)
            : ToResponse(row, persisted: true));
    }

    /// <summary>
    /// Upserts the caller's cycle settings and runs the C-12 pause state machine. Answers <b>200 with
    /// the full resource</b> (see <see cref="CycleSettingsUpdateResult.Saved"/>).
    /// </summary>
    /// <remarks>
    /// MERGE semantics throughout — <see langword="null"/> leaves the stored value unchanged. See
    /// <see cref="UpdateCycleSettingsRequest"/> for why this row merges and what it costs.
    /// </remarks>
    public async Task<CycleSettingsUpdateResult> UpdateAsync(UpdateCycleSettingsRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: the 404 fence comes first, so a body that would be a 400 still answers "no such
        // user" for an erased token.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleSettingsUpdateResult.UserNotFound();

        // Whether a reason is REQUIRED depends on whether the user is already paused, so validation
        // needs the stored state. Read untracked: the retried action below owns the tracked copy and
        // clears the tracker before it reads.
        var stored = await db.CycleSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == day.UserId, ct);

        var errors = Validate(request, stored, day.Today);
        if (errors.Count > 0) return new CycleSettingsUpdateResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        return await ConcurrencyRetry.ExecuteAsync<CycleSettingsUpdateResult>(async token =>
        {
            // The action must be genuinely re-runnable: a second attempt happens only because the
            // first one's INSERT lost a race, and that insert is still sitting in the tracker.
            // Whole-context, hence rule 7's caller restriction.
            db.ChangeTracker.Clear();

            var row = await db.CycleSettings.FirstOrDefaultAsync(s => s.UserId == day.UserId, token);
            if (row is null)
            {
                row = new UserCycleSettings { UserId = day.UserId, CreatedAt = now, UpdatedAt = now };
                db.CycleSettings.Add(row);
            }

            // MERGE: only a supplied value writes. `is { } value` and never a truthiness test — false
            // is a supplied datum on all three booleans.
            if (request.AvgCycleLengthDays is { } avgCycle) row.AvgCycleLengthDays = (short)avgCycle;
            if (request.AvgPeriodLengthDays is { } avgPeriod) row.AvgPeriodLengthDays = (short)avgPeriod;
            if (Trimmed(request.Regularity) is { } regularity) row.Regularity = regularity;
            if (request.PhasePredictionEnabled is { } phase) row.PhasePredictionEnabled = phase;
            if (request.AutoDetectPeriodStartEnabled is { } autoDetect) row.AutoDetectPeriodStartEnabled = autoDetect;
            if (request.ShowFertilityWindowEnabled is { } fertility) row.ShowFertilityWindowEnabled = fertility;

            var targetPaused = request.TrackingPaused ?? row.TrackingPaused;
            var targetReason = Trimmed(request.PauseReason) ?? row.PauseReason;

            // Unreachable in practice: `Validate` already required a reason whenever the request moves
            // an unpaused user to paused, and nothing ever clears PauseReason. Answered as a 400
            // rather than thrown, because a 500 on a write path is the worse way to be wrong.
            if (targetPaused && targetReason is null)
            {
                return new CycleSettingsUpdateResult.Invalid(
                    [new CycleSettingsFieldError("pauseReason", ValidationMessages.Required)]);
            }

            await ReconcilePauseAsync(row, targetPaused, targetReason, request.PausedSince, day.Today, now, token);

            row.UpdatedAt = now;
            await db.SaveChangesAsync(token);

            return new CycleSettingsUpdateResult.Saved(ToResponse(row, persisted: true));
        }, ct);
    }

    /// <summary>
    /// Creates or updates the caller's <c>user_cycle_settings</c> row from the onboarding cycle step
    /// (B15), applying the T6 defaults for every omitted value. <b>Shared with T18's
    /// <c>POST /onboarding/cycle</c>, which must not duplicate it</b> (§G12).
    /// </summary>
    /// <remarks>
    /// <para><b>THIS METHOD STAGES ONLY. It calls no <c>SaveChangesAsync</c>, no
    /// <c>ChangeTracker.Clear()</c> and no <see cref="ConcurrencyRetry"/>, and it must never start
    /// to.</b> That is §G12's unit-of-work rule, and it exists because <see cref="ConcurrencyRetry"/>
    /// recovers via <c>ChangeTracker.Clear()</c> — a <b>whole-context</b> operation on the
    /// request-scoped <c>LumenDbContext</c>. T18 composes two writes in one request: this settings row
    /// AND a <c>cycle_events</c> row for <c>lastPeriodStart</c>. If this method cleared the tracker or
    /// saved on its own, T18's other staged write would be <b>silently discarded</b> — no exception,
    /// no failing test, just a lost onboarding answer.</para>
    ///
    /// <para><b>So the contract for T18 is:</b> resolve the day context, validate the request, then open
    /// exactly ONE <see cref="ConcurrencyRetry"/> action that clears the tracker, stages the
    /// <c>cycle_events</c> row, calls this method, and saves once. That exact shape is pinned by
    /// <c>CycleSettingsServiceTests.ApplyOnboardingCycleAsync_composes_inside_ONE_ConcurrencyRetry_action_the_way_T18_will</c>,
    /// and <c>..._STAGES_ONLY_so_T18_can_compose_it_with_another_write</c> fails the moment a save or a
    /// clear is added here.</para>
    ///
    /// <para><b>No <c>lastPeriodStart</c> parameter.</b> <c>user_cycle_settings</c> has no column for
    /// it — the period start is a <c>cycle_events</c> row, and T9's
    /// <c>CycleService.LogEventAsync</c> owns that table's §G9 upsert contract. Accepting the date here
    /// and ignoring it would be exactly the kind of dead parameter that invites a caller to assume it
    /// was persisted.</para>
    ///
    /// <para><b>No pause side effects</b> (§G12 / the T14 task text): onboarding never opens, closes or
    /// clears a pause. A user who paused before re-running onboarding stays paused.</para>
    ///
    /// <para><b>§G7 applies here too</b>: the value is stored whatever the clinical bounds would say.
    /// The two guards below are <b>programming-error</b> guards on a caller that is expected to have
    /// validated already — storing an out-of-vocabulary regularity or a non-positive length would
    /// corrupt a column P6 reads (and the second would surface as an opaque <c>DbUpdateException</c>
    /// from the caller's own save, against T6's structural CHECK).</para>
    /// </remarks>
    /// <param name="userId">The onboarding user. Taken explicitly because T18 has already resolved it.</param>
    /// <param name="avgCycleLengthDays">The self-report, or null to apply the T6 default.</param>
    /// <param name="avgPeriodLengthDays">The self-report, or null to leave the column null (screen 3 never collects it).</param>
    /// <param name="regularity">One of <see cref="UserCycleSettings.RegularityValues"/>, or null for the default.</param>
    /// <param name="now">The caller's single instant for the whole request (plan §2).</param>
    /// <returns>The staged entity, tracked and <b>unsaved</b>.</returns>
    /// <exception cref="ArgumentException"><paramref name="regularity"/> is outside the ratified vocabulary.</exception>
    /// <exception cref="ArgumentOutOfRangeException">A supplied length is outside the structural domain.</exception>
    public async Task<UserCycleSettings> ApplyOnboardingCycleAsync(
        Guid userId,
        short? avgCycleLengthDays,
        short? avgPeriodLengthDays,
        string? regularity,
        DateTimeOffset now,
        CancellationToken ct)
    {
        var normalisedRegularity = Trimmed(regularity);
        if (normalisedRegularity is not null && !UserCycleSettings.RegularityValues.All.Contains(normalisedRegularity))
        {
            throw new ArgumentException(
                $"'{normalisedRegularity}' is not a ratified regularity code; the caller validates this before staging.",
                nameof(regularity));
        }

        if (avgCycleLengthDays is { } cycle && !CycleSettingsStructuralDomain.Contains(cycle))
            throw new ArgumentOutOfRangeException(nameof(avgCycleLengthDays), cycle, "value must be a positive smallint");

        if (avgPeriodLengthDays is { } period && !CycleSettingsStructuralDomain.Contains(period))
            throw new ArgumentOutOfRangeException(nameof(avgPeriodLengthDays), period, "value must be a positive smallint");

        // NO ChangeTracker.Clear() here: the caller may already have staged its cycle_events row.
        var row = await db.CycleSettings.FirstOrDefaultAsync(s => s.UserId == userId, ct);
        if (row is null)
        {
            row = new UserCycleSettings { UserId = userId, CreatedAt = now, UpdatedAt = now };
            db.CycleSettings.Add(row);
        }

        // The T6 defaults for omitted values come off the entity initializers, which are the same
        // values the DDL defaults carry — never retyped here.
        row.AvgCycleLengthDays = avgCycleLengthDays ?? UserCycleSettings.DefaultAvgCycleLengthDays;
        row.AvgPeriodLengthDays = avgPeriodLengthDays;
        row.Regularity = normalisedRegularity ?? UserCycleSettings.RegularityValues.Default;
        row.UpdatedAt = now;

        // NO SaveChangesAsync: the caller owns the single save for the whole unit of work.
        return row;
    }

    // ------------------------------------------------------------------ validation

    /// <summary>
    /// Collects every field error before the first write (T3). <paramref name="stored"/> is the
    /// caller's current row or <see langword="null"/>; it decides only one thing — whether a pause
    /// needs a reason supplied in this request.
    /// </summary>
    private static List<CycleSettingsFieldError> Validate(
        UpdateCycleSettingsRequest request,
        UserCycleSettings? stored,
        DateOnly today)
    {
        var errors = new List<CycleSettingsFieldError>();

        var regularity = Trimmed(request.Regularity);
        var pauseReason = Trimmed(request.PauseReason);

        if (request.AvgCycleLengthDays is null &&
            request.AvgPeriodLengthDays is null &&
            regularity is null &&
            request.PhasePredictionEnabled is null &&
            request.AutoDetectPeriodStartEnabled is null &&
            request.ShowFertilityWindowEnabled is null &&
            request.TrackingPaused is null &&
            pauseReason is null &&
            request.PausedSince is null)
        {
            errors.Add(new CycleSettingsFieldError(
                ValidationProblemBuilder.RequestKey, CycleSettingsValidationMessages.NoFieldsSupplied));
            return errors;
        }

        // §G7: STRUCTURAL ONLY. There is no sanity-band branch and no clinical-band branch in this
        // method, and adding one would make a bound an entry blocker — the exact thing rider 7 forbids.
        if (request.AvgCycleLengthDays is { } avgCycle && !CycleSettingsStructuralDomain.Contains(avgCycle))
        {
            errors.Add(new CycleSettingsFieldError(
                "avgCycleLengthDays",
                ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max)));
        }

        if (request.AvgPeriodLengthDays is { } avgPeriod && !CycleSettingsStructuralDomain.Contains(avgPeriod))
        {
            errors.Add(new CycleSettingsFieldError(
                "avgPeriodLengthDays",
                ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max)));
        }

        if (regularity is not null && !UserCycleSettings.RegularityValues.All.Contains(regularity))
            errors.Add(new CycleSettingsFieldError("regularity", ValidationMessages.NotAllowedValue));

        // --- the pause state machine's entry conditions ---------------------------------------
        var wasPaused = stored?.TrackingPaused ?? false;
        var targetPaused = request.TrackingPaused ?? wasPaused;

        if (!targetPaused)
        {
            // A reason or a start date only means something for an actual pause. Reported per field so
            // the client can clear the offending input rather than the whole card.
            if (pauseReason is not null)
            {
                errors.Add(new CycleSettingsFieldError(
                    "pauseReason", CycleSettingsValidationMessages.PauseFieldRequiresPause));
            }

            if (request.PausedSince is not null)
            {
                errors.Add(new CycleSettingsFieldError(
                    "pausedSince", CycleSettingsValidationMessages.PauseFieldRequiresPause));
            }

            return errors;
        }

        if (pauseReason is null)
        {
            // Required on the TRANSITION into paused. Already paused and the client omits it: merge
            // keeps the current reason, which is what a re-tap of an already-on switch should do. But
            // an unpaused user is never paused for a reason they did not name in this request — the
            // remembered reason is a screen-32 pre-selection, not consent.
            if (!wasPaused)
                errors.Add(new CycleSettingsFieldError("pauseReason", ValidationMessages.Required));
        }
        else if (!UserCycleSettings.PauseReasons.All.Contains(pauseReason))
        {
            // The FIVE-member C-12 set (ARCHITECTURE.md §A:59). Taken from the entity constants, never
            // retyped — the r15 three-member list is superseded and must not reappear.
            errors.Add(new CycleSettingsFieldError("pauseReason", ValidationMessages.NotAllowedValue));
        }

        // §G8: capped by the user's today and NOTHING ELSE. There is deliberately no
        // `< day.BackdateFloor` branch — D-13 gives that floor to `cycle_events` alone, and a
        // menopause or surgical pause that began years ago is legitimate history.
        if (request.PausedSince is { } pausedSince && pausedSince > today)
            errors.Add(new CycleSettingsFieldError("pausedSince", ValidationMessages.FutureDate));

        return errors;
    }

    // ------------------------------------------------------------------ the state machine

    /// <summary>
    /// Brings <c>cycle_tracking_pause_spans</c> into agreement with the target pause state, and writes
    /// the settings triple. <b>Idempotent and total</b>: it is a reconciliation from the target state
    /// rather than a set of transition branches, which is why the two representations cannot diverge.
    /// </summary>
    /// <remarks>
    /// <para><b>Pausing while already paused updates the OPEN span in place</b> rather than inserting a
    /// second one. The partial unique index <c>(UserId) WHERE "EndedOn" IS NULL</c> would reject the
    /// insert with a 23505 that surfaces as a 500, so a double-tapped pause button would be an error
    /// page; here it is a no-op with the new reason applied. The index stays the backstop.</para>
    ///
    /// <para><b>Resuming closes the open span with <c>max(today, StartedOn)</c></b>. Through this
    /// endpoint a span can only start in the past, but a row arriving from elsewhere must never produce
    /// <c>EndedOn &lt; StartedOn</c> — a negative-length span in the history P6 estimates from.
    /// Resuming when there is no open span (or when the user was never paused) closes nothing and is a
    /// plain idempotent success.</para>
    ///
    /// <para><b>Resume PRESERVES <see cref="UserCycleSettings.PauseReason"/></b> and clears only the
    /// flag and the date. That is ARCHITECTURE.md §D verbatim — "resume clears the flag and the date
    /// but preserves the reason so the next pause can pre-select it" — and is exactly why T6 put no
    /// CHECK tying the two columns together. The invariant this method therefore holds is
    /// <c>TrackingPaused == (PausedSince != null)</c> and <c>TrackingPaused ⇒ PauseReason != null</c>,
    /// NOT that all three are null together. Every consumer of the reason must gate on the flag first
    /// (see <see cref="CycleSettingsResponse.PauseReason"/>).</para>
    ///
    /// <para><b>P4a stores; it does not interpret</b> (§G6). No exclusion logic, no overlap merging and
    /// no "resume = fresh cycle start" rule ships here — those are P6's, and they read these rows.</para>
    /// </remarks>
    private async Task ReconcilePauseAsync(
        UserCycleSettings row,
        bool targetPaused,
        string? targetReason,
        DateOnly? requestedPausedSince,
        DateOnly today,
        DateTimeOffset now,
        CancellationToken ct)
    {
        // No query filter on this table (rule 5) and at most one row can match (the partial unique
        // index), so this is a single-row lookup, not a "first of many".
        var openSpan = await db.CycleTrackingPauseSpans
            .FirstOrDefaultAsync(s => s.UserId == row.UserId && s.EndedOn == null, ct);

        if (!targetPaused)
        {
            row.TrackingPaused = false;
            row.PausedSince = null;
            // row.PauseReason is deliberately left alone — see the remarks.

            if (openSpan is not null)
            {
                openSpan.EndedOn = today > openSpan.StartedOn ? today : openSpan.StartedOn;
                openSpan.UpdatedAt = now;
            }

            return;
        }

        // Merge on the start date too: an already-paused user re-tapping pause keeps the day the pause
        // actually began, and only a fresh pause falls back to today.
        var startedOn = requestedPausedSince ?? (row.TrackingPaused ? row.PausedSince : null) ?? today;

        row.TrackingPaused = true;
        row.PauseReason = targetReason;
        row.PausedSince = startedOn;

        if (openSpan is null)
        {
            db.CycleTrackingPauseSpans.Add(new CycleTrackingPauseSpan
            {
                Id = Guid.NewGuid(),
                UserId = row.UserId,
                // Copied onto the span so the history survives a later change to the settings row.
                Reason = targetReason!,
                StartedOn = startedOn,
                CreatedAt = now,
                UpdatedAt = now,
            });
        }
        else
        {
            openSpan.Reason = targetReason!;
            openSpan.StartedOn = startedOn;
            openSpan.UpdatedAt = now;
        }
    }

    // ------------------------------------------------------------------ projection

    /// <summary>
    /// Projects a row — stored or transient — onto the wire.
    /// </summary>
    /// <param name="persisted">
    /// <see langword="false"/> for the defaults answer of <see cref="GetAsync"/>, which suppresses the
    /// two timestamps: they are the only signal that no row exists yet, and echoing a fabricated
    /// instant would be the one dishonest field in this response.
    /// </param>
    private static CycleSettingsResponse ToResponse(UserCycleSettings row, bool persisted) => new(
        row.AvgCycleLengthDays,
        row.AvgPeriodLengthDays,
        row.Regularity,
        row.PhasePredictionEnabled,
        row.AutoDetectPeriodStartEnabled,
        row.ShowFertilityWindowEnabled,
        row.TrackingPaused,
        row.PauseReason,
        row.PausedSince,
        // §G6: a boolean OR of two stored flags, and the whole of the "phases unavailable" state
        // ARCHITECTURE.md §A:59 requires. Nothing here infers anything.
        row.TrackingPaused || !row.PhasePredictionEnabled,
        ComputeWarnings(row.AvgCycleLengthDays, row.AvgPeriodLengthDays),
        persisted ? row.CreatedAt : null,
        persisted ? row.UpdatedAt : null);

    /// <summary>
    /// The §G7 sanity hints for the two typed self-reports — <b>non-blocking</b>, computed on the
    /// STORED values, and emitted by the read as well as the write because screen 32 shows the hint
    /// when it loads and not only after a save.
    /// </summary>
    /// <remarks>
    /// <para>Order is fixed (cycle length, then period length) so the client can render them predictably
    /// and the tests can assert the list rather than its contents in any order.</para>
    ///
    /// <para><b>Public because T18's <c>POST /onboarding/cycle</c> answers with the same list</b> — the
    /// same rule §G12 applies to <see cref="ApplyOnboardingCycleAsync"/>: the second surface that writes
    /// these two columns calls this rather than restating the band. A second copy of the comparison
    /// could only ever drift, and it would drift into looking like a clinical bound.</para>
    /// </remarks>
    public static IReadOnlyList<string> ComputeWarnings(short avgCycleLengthDays, short? avgPeriodLengthDays)
    {
        var warnings = new List<string>(CycleSettingsWarnings.All.Count);

        if (!CycleSettingsSanityBand.ContainsCycleLength(avgCycleLengthDays))
            warnings.Add(CycleSettingsWarnings.AvgCycleLengthOutOfSanityBand);

        if (avgPeriodLengthDays is { } period && !CycleSettingsSanityBand.ContainsPeriodLength(period))
            warnings.Add(CycleSettingsWarnings.AvgPeriodLengthOutOfSanityBand);

        return warnings;
    }

    /// <summary>
    /// Blank is absent, matching <c>PATCH /me</c>: an empty or whitespace-only string is not a request
    /// to store one, and under merge it is not a request to clear the column either.
    /// </summary>
    private static string? Trimmed(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
