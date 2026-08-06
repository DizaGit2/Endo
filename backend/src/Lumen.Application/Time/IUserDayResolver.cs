namespace Lumen.Application.Time;

/// <summary>
/// The single authority on what "today" means for a user (D-12). Every day boundary in the app —
/// "today", the backdate floor, calendar windows, day↔instant conversion — is derived from the
/// user's IANA <c>users.timezone</c> through this helper, never from UTC and never from the
/// server's local zone. A wrong "today" silently corrupts day-keyed rows for any non-CET user, so
/// no endpoint may re-derive a day boundary of its own.
/// </summary>
/// <remarks>
/// Deliberately BCL-only, so the Application module keeps its no-Infrastructure / no-EF dependency
/// guarantee (see <c>ArchitectureTests</c>). An unusable <paramref name="tz"/> — blank, or an id
/// this machine's timezone database does not know — never throws: the implementation falls back to
/// the <c>users.timezone</c> column default and logs a PII-free warning.
/// </remarks>
public interface IUserDayResolver
{
    /// <summary>The user's current calendar day, from the injected clock.</summary>
    DateOnly TodayFor(string tz);

    /// <summary>The calendar day an instant falls on, as the user experiences it.</summary>
    DateOnly ToUserDay(DateTimeOffset instant, string tz);

    /// <summary>
    /// The first instant of a user-local day (inclusive). Never throws on a DST spring-forward gap:
    /// if the user's midnight does not exist, the day begins at the first instant that does.
    /// On a fall-back ambiguity (a midnight that happens twice) it resolves to the EARLIEST of the
    /// two, so the first hour of the day is inside its own window.
    /// </summary>
    DateTimeOffset StartOfUserDay(DateOnly day, string tz);

    /// <summary>
    /// The exclusive upper bound of a user-local day: the start of the next day. Ranges are
    /// half-open <c>[StartOfUserDay, EndOfUserDayExclusive)</c>, which keeps DST-shortened (23 h)
    /// and DST-lengthened (25 h) days as exactly one calendar day each.
    /// </summary>
    DateTimeOffset EndOfUserDayExclusive(DateOnly day, string tz);
}
