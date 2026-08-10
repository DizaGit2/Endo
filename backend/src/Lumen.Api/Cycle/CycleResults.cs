using Lumen.Api.Symptoms;

namespace Lumen.Api.Cycle;

/// <summary>
/// One rejected field, carried out of <see cref="CycleService"/> so the service can stay free of
/// <c>IResult</c> and be unit-tested on its decisions rather than on an HTTP body.
/// <see cref="CycleEndpoints"/> replays these into <see cref="Validation.ValidationProblemBuilder"/>,
/// which is still the only thing that builds the phase's one 400.
/// </summary>
/// <param name="Field">
/// The camelCase JSON field name, exactly as it appears on the wire — <c>occurredOn</c>, or the
/// indexed path <c>boundaries[0].phase</c>. Passed through verbatim; the client matches it against
/// its own field names to attach the message to an input.
/// </param>
public sealed record CycleFieldError(string Field, string Message);

/// <summary>Outcome of <see cref="CycleService.LogEventAsync"/>.</summary>
public abstract record CycleEventResult
{
    /// <summary>The row was inserted, updated, or revived from a tombstone. → 200.</summary>
    public sealed record Saved(CycleEventResponse Event) : CycleEventResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<CycleFieldError> Errors) : CycleEventResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404. See <see cref="CycleService"/>'s remarks for why this is a security
    /// control and not a formality.
    /// </summary>
    public sealed record UserNotFound : CycleEventResult;
}

/// <summary>Outcome of <see cref="CycleService.DeleteEventAsync"/>.</summary>
public abstract record CycleEventDeleteResult
{
    /// <summary>The row was tombstoned. → 204.</summary>
    public sealed record Deleted : CycleEventDeleteResult;

    /// <summary>
    /// No live row of the caller's has that id. → 404. Covers all four cases on purpose: an unknown
    /// id, an already-deleted one, <b>another user's id</b> (tenant isolation is 404, never 403 —
    /// a 403 would itself confirm the id exists), and an erased caller.
    /// </summary>
    public sealed record NotFound : CycleEventDeleteResult;
}

/// <summary>Outcome of <see cref="CycleDayService.UpsertDayAsync"/>.</summary>
public abstract record CycleDayResult
{
    /// <summary>The day's row was inserted, updated, or revived from a tombstone. → 200.</summary>
    public sealed record Saved(CycleDayLogResponse Log) : CycleDayResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<CycleFieldError> Errors) : CycleDayResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404. See <see cref="CycleDayService"/>'s remarks for why this is a security
    /// control and not a formality.
    /// </summary>
    public sealed record UserNotFound : CycleDayResult;
}

/// <summary>Outcome of <see cref="CycleDayService.QuickCheckinAsync"/>.</summary>
public abstract record QuickCheckinResult
{
    /// <summary>Today's row was upserted. → 200.</summary>
    public sealed record Saved(QuickCheckinResponse Checkin) : QuickCheckinResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<CycleFieldError> Errors) : QuickCheckinResult;

    /// <summary>The token's <c>sub</c> has no live <c>users</c> row. → 404.</summary>
    public sealed record UserNotFound : QuickCheckinResult;
}

/// <summary>
/// Outcome of <see cref="CycleDayService.GetDayAsync"/>. There is deliberately no "day not found"
/// case: an unlogged day is a <see cref="Found"/> carrying a null log and empty collections, because
/// 404 on this route means "no such user" and nothing else (§G12).
/// </summary>
public abstract record CycleDayReadResult
{
    /// <summary>The day was read — possibly empty. → 200.</summary>
    public sealed record Found(CycleDayResponse Day) : CycleDayReadResult;

    /// <summary>The token's <c>sub</c> has no live <c>users</c> row. → 404.</summary>
    public sealed record UserNotFound : CycleDayReadResult;
}

/// <summary>
/// Outcome of <see cref="CycleCalendarService.GetCalendarAsync"/>. There is deliberately no "empty
/// window" case: a window with nothing in it is a <see cref="Found"/> carrying an empty day list,
/// because 404 on this route means "no such user" and nothing else (§G12).
/// </summary>
public abstract record CycleCalendarResult
{
    /// <summary>The window was read — possibly empty. → 200.</summary>
    public sealed record Found(CycleCalendarResponse Calendar) : CycleCalendarResult;

    /// <summary>The window was inverted or wider than <see cref="Validation.ReadWindow.MaxDays"/>. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<CycleFieldError> Errors) : CycleCalendarResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404. On a READ this is a security control in its own right: a successful
    /// empty answer would still confirm the account existed, and a successful non-empty one would
    /// hand back health data after erasure.
    /// </summary>
    public sealed record UserNotFound : CycleCalendarResult;
}

/// <summary>Outcome of <see cref="CycleService.SavePhaseOverridesAsync"/>.</summary>
public abstract record PhaseOverrideResult
{
    /// <summary>The cycle's correction set now matches the request. → 200.</summary>
    public sealed record Saved(PhaseOverridesResponse Overrides) : PhaseOverrideResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<CycleFieldError> Errors) : PhaseOverrideResult;

    /// <summary>The token's <c>sub</c> has no live <c>users</c> row. → 404.</summary>
    public sealed record UserNotFound : PhaseOverrideResult;
}
