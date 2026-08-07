using System.Collections.Concurrent;
using Lumen.Application.Time;
using Microsoft.Extensions.Logging;

namespace Lumen.Infrastructure.Time;

/// <summary>
/// <see cref="IUserDayResolver"/> over <see cref="TimeZoneInfo"/> and the injected
/// <see cref="TimeProvider"/> (plan §2: never <c>DateTime.UtcNow</c>). Registered as a singleton —
/// it holds no per-request state, only a lookup cache of resolved zones.
/// </summary>
public sealed class UserDayResolver(TimeProvider clock, ILogger<UserDayResolver> logger) : IUserDayResolver
{
    /// <summary>
    /// The zone used when a user's stored timezone is unusable — the <c>users.timezone</c> column
    /// default, so a fallback user is treated exactly like one who never chose a zone.
    /// </summary>
    public const string FallbackTimezoneId = "Europe/Madrid";

    // Resolution is not free (id mapping + rule load), and this singleton is on the hot path of
    // every day-keyed request. Only successful lookups are cached; see Fallback below.
    private readonly ConcurrentDictionary<string, TimeZoneInfo> _zones = new(StringComparer.Ordinal);

    public DateOnly TodayFor(string tz) => ToUserDay(clock.GetUtcNow(), tz);

    public DateOnly ToUserDay(DateTimeOffset instant, string tz)
        => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(instant, Resolve(tz)).DateTime);

    public DateTimeOffset StartOfUserDay(DateOnly day, string tz)
    {
        var zone = Resolve(tz);
        var local = day.ToDateTime(TimeOnly.MinValue); // DateTimeKind.Unspecified — a wall-clock reading

        // Spring-forward gap: in the handful of zones that start DST at midnight (America/Havana,
        // America/Santiago, …) the user's 00:00 simply never happens, and TimeZoneInfo.ConvertTimeToUtc
        // would throw on it. The day instead begins at the first instant that does exist. Bounded by
        // real tzdata — the largest transition gap ever recorded is 24 h (Pacific/Apia's 2011
        // date-line skip) — and only ever entered on a transition day.
        while (zone.IsInvalidTime(local))
            local = local.AddMinutes(1);

        // Fall-back ambiguity: a midnight that happens twice. UTC = local − offset, so the EARLIEST
        // of the two instants is the one with the LARGEST offset. The BCL default (ConvertTimeToUtc /
        // GetUtcOffset) picks the standard offset, i.e. the later instant, which would push the first
        // hour of the day outside its own [start, end) window — hence the explicit choice here.
        var offset = zone.IsAmbiguousTime(local)
            ? zone.GetAmbiguousTimeOffsets(local).Max()
            : zone.GetUtcOffset(local);

        return new DateTimeOffset(local, offset);
    }

    public DateTimeOffset EndOfUserDayExclusive(DateOnly day, string tz) => StartOfUserDay(day.AddDays(1), tz);

    private TimeZoneInfo Resolve(string tz)
    {
        // Reachable in production: CryptoShredJob blanks Timezone as part of erasure.
        if (string.IsNullOrWhiteSpace(tz))
            return Fallback("blank");

        if (_zones.TryGetValue(tz, out var cached))
            return cached;

        return TimeZoneInfo.TryFindSystemTimeZoneById(tz, out var zone)
            ? _zones.GetOrAdd(tz, zone)
            : Fallback("unknown");
    }

    private TimeZoneInfo Fallback(string reason)
    {
        // PII-free (§F / PiiRedactionEnricher): a timezone id is a quasi-identifier — it narrows a
        // user to a region — so the warning records THAT a fallback happened and why in the abstract,
        // never which id or whose. The bad id is deliberately NOT cached against its key either, so
        // this stays a per-occurrence signal rather than a one-shot startup blip.
        //
        // The property is FallbackCause, not the obvious {Reason}: `reason` is a redacted name from
        // T8 onward (it is the cycle_tracking_pause_spans column that holds 'pregnancy'), so logging
        // this under it would print "[redacted]" and destroy the only diagnostic the line carries.
        logger.LogWarning(
            "User timezone is unusable ({FallbackCause}); falling back to the default zone {FallbackTimezone}",
            reason, FallbackTimezoneId);

        // If the fallback zone itself is missing, the host has no usable timezone database at all —
        // throwing beats silently answering in UTC and corrupting every user's day-keyed data.
        return _zones.GetOrAdd(FallbackTimezoneId, static id => TimeZoneInfo.FindSystemTimeZoneById(id));
    }
}
