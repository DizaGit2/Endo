using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Cycle;

/// <summary>
/// The cycle write surface: logging and retracting <c>cycle_events</c>, and recording the user's
/// phase corrections in <c>cycle_phase_overrides</c>. Registered scoped, alongside the request-scoped
/// <see cref="IUserDayContext"/> and <see cref="IUserCryptoContext"/> it depends on.
/// </summary>
/// <remarks>
/// <para><b>Three rules bind every method here.</b></para>
///
/// <para><b>1. A null day context is a 404, before anything else happens.</b> Erasure has no write
/// fence behind it: a crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires (disabling the Keycloak user does not revoke an
/// already-issued token), and inserting a child row takes only a share lock on <c>users</c>, which
/// does not conflict with the shred job's UPDATE. So a request already in flight during an erasure
/// would happily write fresh plaintext health rows for a user who no longer exists. Resolving the
/// day context FIRST and returning "not found" on null is the whole of the defence — it is why the
/// 404 is checked before validation rather than after.</para>
///
/// <para><b>2. Validate then act (T3).</b> Every field error is collected before the first write, so
/// a rejected request has changed nothing and the user fixes the whole form in one round trip.</para>
///
/// <para><b>3. §G9 — both tables written here are under the UNFILTERED unique-index regime</b>
/// (<c>cycle_events (UserId, Kind, OccurredOn)</c>, <c>cycle_phase_overrides (UserId, CycleStartOn,
/// Phase, Boundary)</c>). A tombstone still occupies its key, so every upsert looks the row up with
/// <see cref="EntityFrameworkQueryableExtensions.IgnoreQueryFilters{TEntity}"/> and clears
/// <c>DeletedAt</c>. A blind insert is not a duplicate row — it is a unique violation surfacing as a
/// 500 the first time a user re-logs a day they deleted.</para>
/// </remarks>
public sealed class CycleService(LumenDbContext db, IUserDayContext dayContext, IUserCryptoContext crypto)
{
    /// <summary>Plaintext note limit, D-13. Measured after trimming.</summary>
    public const int MaxNotesLength = 2000;

    /// <summary>
    /// Upserts one cycle event on <c>(UserId, Kind, OccurredOn)</c>. Idempotent by construction, which
    /// is what makes the online-only client's retry safe — and what keeps two <c>period_start</c> rows
    /// off the same day, a state the P6 estimator has no sane reading of.
    /// </summary>
    public async Task<CycleEventResult> LogEventAsync(LogCycleEventRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleEventResult.UserNotFound();

        var errors = new List<CycleFieldError>();

        var kind = request.Kind?.Trim();
        if (string.IsNullOrEmpty(kind))
            errors.Add(new CycleFieldError("kind", ValidationMessages.Required));
        else if (!CycleEvent.Kinds.All.Contains(kind, StringComparer.Ordinal))
            errors.Add(new CycleFieldError("kind", ValidationMessages.NotAllowedValue));

        // §G8: cycle_events is the ONE table with a backdate floor. Do not copy this pair of checks
        // to any other write — D-13 lets symptoms, day logs and body metrics be logged arbitrarily
        // far back, and a floor there would reject legitimate history.
        if (request.OccurredOn is not { } occurredOn)
            errors.Add(new CycleFieldError("occurredOn", ValidationMessages.Required));
        else if (occurredOn > day.Today)
            errors.Add(new CycleFieldError("occurredOn", ValidationMessages.FutureDate));
        else if (occurredOn < day.BackdateFloor)
            errors.Add(new CycleFieldError("occurredOn", ValidationMessages.BeforeFloor));

        if (request.FlowIntensity is { } flow &&
            (flow < CycleEvent.FlowIntensityScale.Min || flow > CycleEvent.FlowIntensityScale.Max))
        {
            errors.Add(new CycleFieldError(
                "flowIntensity",
                ValidationMessages.Between(CycleEvent.FlowIntensityScale.Min, CycleEvent.FlowIntensityScale.Max)));
        }

        // Trim first: 2000 characters wrapped in whitespace is a 2000-character note, and the limit
        // exists to bound the column, not to punish a trailing newline.
        var notes = request.Notes?.Trim();
        if (notes is { Length: > MaxNotesLength })
            errors.Add(new CycleFieldError("notes", ValidationMessages.MaxLength(MaxNotesLength)));

        if (errors.Count > 0) return new CycleEventResult.Invalid(errors);

        var kindValue = kind!;
        var occurredOnValue = request.OccurredOn!.Value;
        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        // §G9 UNFILTERED regime: the lookup MUST bypass the soft-delete filter, or a tombstone on this
        // key is invisible here and the insert below violates the unique index.
        var row = await db.CycleEvents.IgnoreQueryFilters().FirstOrDefaultAsync(
            e => e.UserId == day.UserId && e.Kind == kindValue && e.OccurredOn == occurredOnValue, ct);

        if (row is null)
        {
            row = new CycleEvent
            {
                Id = Guid.NewGuid(),
                UserId = day.UserId,
                Kind = kindValue,
                OccurredOn = occurredOnValue,
                Source = CycleEvent.Sources.User,
                CreatedAt = now,
            };
            db.CycleEvents.Add(row);
        }

        // Revive: a re-logged day resurrects its own row rather than creating a second one, and keeps
        // its original CreatedAt — that timestamp belongs to the observation, not to this edit.
        row.DeletedAt = null;
        row.FlowIntensity = request.FlowIntensity is { } value ? (short)value : null;
        row.NotesEnc = notes is { Length: > 0 } ? await crypto.EncryptStringAsync(notes, ct) : null;
        row.UpdatedAt = now;
        // Source is deliberately NOT reassigned on update: an onboarding-seeded row keeps its
        // provenance when the user edits it, which is what T18's merge rule depends on.

        await db.SaveChangesAsync(ct);

        return new CycleEventResult.Saved(new CycleEventResponse(
            row.Id,
            row.Kind,
            row.OccurredOn,
            row.FlowIntensity,
            notes is { Length: > 0 } ? notes : null,
            row.Source,
            row.CreatedAt,
            row.UpdatedAt));
    }

    /// <summary>
    /// Soft-deletes one cycle event (D-13). A second call answers "not found" because the query filter
    /// hides the tombstone — P4b treats that as success, since the user's intent is already satisfied.
    /// </summary>
    public async Task<CycleEventDeleteResult> DeleteEventAsync(Guid id, CancellationToken ct)
    {
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleEventDeleteResult.NotFound();

        // No IgnoreQueryFilters() here, and the UserId predicate is load-bearing: together they make
        // another tenant's row and an already-tombstoned row indistinguishable from a typo'd id.
        var row = await db.CycleEvents.FirstOrDefaultAsync(e => e.Id == id && e.UserId == day.UserId, ct);
        if (row is null) return new CycleEventDeleteResult.NotFound();

        row.DeletedAt = day.NowUtc;
        row.UpdatedAt = day.NowUtc;
        await db.SaveChangesAsync(ct);

        return new CycleEventDeleteResult.Deleted();
    }

    /// <summary>
    /// Replaces the user's phase corrections for one cycle (screen 14). An empty
    /// <see cref="SavePhaseOverridesRequest.Boundaries"/> is "reset to predicted" and retracts them all.
    /// </summary>
    /// <remarks>
    /// The guards are <b>structural only</b> (§G6/§G7): the cycle must exist as a logged
    /// <c>period_start</c>, and each boundary must fall inside that cycle's window. There is no
    /// monotonicity check — menstrual→follicular→ovulatory→luteal is the C-01 band order, which is
    /// clinician-UNSIGNED, so refusing a user's own correction on that basis would be a clinical entry
    /// blocker in a phase that ships none. Nothing is recomputed either: screen 14's "retrains the
    /// prediction model" copy is a P6 promise.
    /// </remarks>
    public async Task<PhaseOverrideResult> SavePhaseOverridesAsync(SavePhaseOverridesRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        var day = await dayContext.GetAsync(ct);
        if (day is null) return new PhaseOverrideResult.UserNotFound();

        var errors = new List<CycleFieldError>();

        if (request.CycleStartOn is null)
            errors.Add(new CycleFieldError("cycleStartOn", ValidationMessages.Required));

        // Absent is NOT an empty set: silently retracting every correction because a field went
        // missing from a payload would destroy user data on a client bug.
        if (request.Boundaries is null)
            errors.Add(new CycleFieldError("boundaries", ValidationMessages.Required));

        var items = request.Boundaries ?? [];
        var seen = new HashSet<(string Phase, string Boundary)>();

        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];

            // `boundaries: [null]` is legal JSON that binds to a null element. Reported as a field
            // error rather than dereferenced — an NRE here would be a 500 for malformed input.
            if (item is null)
            {
                errors.Add(new CycleFieldError($"boundaries[{i}]", ValidationMessages.Required));
                continue;
            }

            var phase = item.Phase?.Trim();
            var boundary = item.Boundary?.Trim();

            if (string.IsNullOrEmpty(phase))
                errors.Add(new CycleFieldError($"boundaries[{i}].phase", ValidationMessages.Required));
            else if (!CyclePhaseOverride.Phases.All.Contains(phase, StringComparer.Ordinal))
                errors.Add(new CycleFieldError($"boundaries[{i}].phase", ValidationMessages.NotAllowedValue));

            if (string.IsNullOrEmpty(boundary))
                errors.Add(new CycleFieldError($"boundaries[{i}].boundary", ValidationMessages.Required));
            else if (!CyclePhaseOverride.Boundaries.All.Contains(boundary, StringComparer.Ordinal))
                errors.Add(new CycleFieldError($"boundaries[{i}].boundary", ValidationMessages.NotAllowedValue));

            if (item.OccurredOn is null)
                errors.Add(new CycleFieldError($"boundaries[{i}].occurredOn", ValidationMessages.Required));

            // Only recognised pairs enter the duplicate set, so a typo'd phase reports one error, not
            // two. The duplicate is flagged on the SECOND occurrence — the one the user should remove.
            if (IsKnownPair(phase, boundary) && !seen.Add((phase!, boundary!)))
                errors.Add(new CycleFieldError($"boundaries[{i}]", CycleValidationMessages.DuplicateBoundary));
        }

        DateOnly? nextPeriodStart = null;

        if (request.CycleStartOn is { } cycleStartOn)
        {
            // A cycle exists only as the user's own live logged period_start. Scoping the query to the
            // caller is also this endpoint's tenant isolation: another user's period start cannot
            // anchor a correction, and the caller learns nothing about whether it exists.
            var anchored = await db.CycleEvents.AnyAsync(
                e => e.UserId == day.UserId
                     && e.Kind == CycleEvent.Kinds.PeriodStart
                     && e.OccurredOn == cycleStartOn, ct);

            if (!anchored)
            {
                errors.Add(new CycleFieldError("cycleStartOn", CycleValidationMessages.NoMatchingPeriodStart));
            }
            else
            {
                // The cycle's far edge: the next period start the user has logged, if any. Take(1) on an
                // ordered query rather than FirstOrDefault on a DateOnly, whose default (0001-01-01) is
                // indistinguishable from a real answer.
                var following = await db.CycleEvents
                    .Where(e => e.UserId == day.UserId
                                && e.Kind == CycleEvent.Kinds.PeriodStart
                                && e.OccurredOn > cycleStartOn)
                    .OrderBy(e => e.OccurredOn)
                    .Select(e => e.OccurredOn)
                    .Take(1)
                    .ToListAsync(ct);
                nextPeriodStart = following.Count > 0 ? following[0] : null;
            }

            for (var i = 0; i < items.Count; i++)
            {
                if (items[i]?.OccurredOn is not { } on) continue;

                if (on < cycleStartOn)
                    errors.Add(new CycleFieldError($"boundaries[{i}].occurredOn", CycleValidationMessages.BeforeCycleStart));
                else if (on > day.Today)
                    errors.Add(new CycleFieldError($"boundaries[{i}].occurredOn", ValidationMessages.FutureDate));
                else if (nextPeriodStart is { } next && on >= next)
                    errors.Add(new CycleFieldError($"boundaries[{i}].occurredOn", CycleValidationMessages.NotBeforeNextPeriodStart));
            }
        }

        if (errors.Count > 0) return new PhaseOverrideResult.Invalid(errors);

        var cycleStart = request.CycleStartOn!.Value;
        var now = day.NowUtc;

        var requested = items
            .Select(item => new PhaseOverrideBoundary(item.Phase!.Trim(), item.Boundary!.Trim(), item.OccurredOn!.Value))
            .ToList();

        // §G9 UNFILTERED regime again — and the reason it matters here is subtler than on cycle_events:
        // the user retracts a correction ("reset to predicted"), then corrects the same boundary again.
        // Without the tombstone in this set, that second correction is a unique violation.
        var existing = await db.CyclePhaseOverrides.IgnoreQueryFilters()
            .Where(o => o.UserId == day.UserId && o.CycleStartOn == cycleStart)
            .ToListAsync(ct);

        foreach (var wanted in requested)
        {
            var row = existing.FirstOrDefault(o =>
                string.Equals(o.Phase, wanted.Phase, StringComparison.Ordinal)
                && string.Equals(o.Boundary, wanted.Boundary, StringComparison.Ordinal));

            if (row is null)
            {
                row = new CyclePhaseOverride
                {
                    Id = Guid.NewGuid(),
                    UserId = day.UserId,
                    CycleStartOn = cycleStart,
                    Phase = wanted.Phase,
                    Boundary = wanted.Boundary,
                    CreatedAt = now,
                };
                db.CyclePhaseOverrides.Add(row);
                existing.Add(row);
            }

            row.DeletedAt = null; // revive in place: same Id, original CreatedAt
            row.OccurredOn = wanted.OccurredOn;
            row.Source = CyclePhaseOverride.Sources.UserCorrection;
            row.UpdatedAt = now;
        }

        // Replace-the-set: anything live that the request omitted is retracted. With an empty
        // `boundaries` this is the whole "reset to predicted" behaviour, and nothing else is needed.
        foreach (var row in existing)
        {
            if (row.DeletedAt is not null) continue;
            if (requested.Any(wanted =>
                    string.Equals(row.Phase, wanted.Phase, StringComparison.Ordinal)
                    && string.Equals(row.Boundary, wanted.Boundary, StringComparison.Ordinal)))
            {
                continue;
            }

            row.DeletedAt = now;
            row.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);

        return new PhaseOverrideResult.Saved(new PhaseOverridesResponse(cycleStart, requested));
    }

    private static bool IsKnownPair(string? phase, string? boundary) =>
        phase is not null
        && boundary is not null
        && CyclePhaseOverride.Phases.All.Contains(phase, StringComparer.Ordinal)
        && CyclePhaseOverride.Boundaries.All.Contains(boundary, StringComparer.Ordinal);
}
