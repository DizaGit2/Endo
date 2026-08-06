namespace Lumen.Api.Time;

/// <summary>
/// Everything the current request needs to reason about the authenticated user's calendar (D-12),
/// resolved once from their <c>users.timezone</c>.
/// </summary>
/// <param name="UserId">The authenticated user (token <c>sub</c>), confirmed to have a live row.</param>
/// <param name="Today">The user's current calendar day. The ceiling for every dated write (D-13).</param>
/// <param name="BackdateFloor">
/// The oldest day a <c>cycle_events</c> row may be dated: the user-local day of their account
/// creation minus two years (D-13). <b>This floor is cycle-events-only (§G8).</b> D-13 permits
/// symptoms, day logs, check-ins, body metrics, activity and lab entries to be logged arbitrarily
/// far back — they are capped by <see cref="Today"/> alone. Applying this floor to them would
/// reject legitimate historical logging.
/// </param>
/// <param name="TimezoneId">The IANA zone the two dates above were computed in.</param>
/// <param name="NowUtc">
/// The single instant captured for this request (plan §2: one <c>now</c> per operation), from which
/// <see cref="Today"/> was derived. Handlers should stamp <c>CreatedAt</c>/<c>UpdatedAt</c> from it
/// rather than re-reading the clock, so a row's timestamps and its day key can never disagree.
/// </param>
public sealed record UserDayInfo(
    Guid UserId,
    DateOnly Today,
    DateOnly BackdateFloor,
    string TimezoneId,
    DateTimeOffset NowUtc);

/// <summary>
/// Request-scoped access to the current user's <see cref="UserDayInfo"/>. Reads the <c>users</c> row
/// at most once per scope and memoises the answer, so the many validators in one request that all
/// need "today" share a single query.
/// </summary>
public interface IUserDayContext
{
    /// <summary>
    /// The current user's day context, or <see langword="null"/> when the token's <c>sub</c> has no
    /// live <c>users</c> row — either it never existed or it was crypto-shredded (the soft-delete
    /// query filter is honoured, never bypassed).
    /// <para>
    /// <b>Every P4a endpoint turns that <see langword="null"/> into 404.</b> This is the contract
    /// that stops an erased user's still-valid JWT from writing new health data: the token remains
    /// cryptographically sound until it expires, and this is what makes it inert.
    /// </para>
    /// </summary>
    Task<UserDayInfo?> GetAsync(CancellationToken ct);
}
