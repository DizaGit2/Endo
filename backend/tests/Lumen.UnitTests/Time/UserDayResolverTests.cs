using System.Text.RegularExpressions;
using Lumen.Infrastructure.Time;
using Microsoft.Extensions.Logging;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Time;

/// <summary>
/// D-12: every day boundary in the app comes from the user's IANA <c>users.timezone</c>, never from
/// UTC and never from the server's local zone. These tests pin the pure conversion half of the
/// helper — "today", day→instant, instant→day, the two DST edge cases, and the fallback behaviour
/// when the stored timezone id is unusable.
/// <para>
/// Maintainer note: the DST cases assert against real transitions that come from tzdata's recurring
/// rules (Madrid's last-Sunday-of-March jump; Havana's midnight jump in both directions). If a
/// jurisdiction abolishes DST and a tzdata update drops a rule, the matching test fails on an offset
/// or instant mismatch — that is a fixture that needs a new date, not a defect in UserDayResolver.
/// </para>
/// </summary>
public partial class UserDayResolverTests
{
    private const string Madrid = "Europe/Madrid";           // UTC+1 / +2
    private const string LosAngeles = "America/Los_Angeles"; // UTC-8 / -7
    private const string Kiritimati = "Pacific/Kiritimati";  // UTC+14, the eastmost zone
    private const string Niue = "Pacific/Niue";              // UTC-11, the westmost inhabited zone
    private const string Havana = "America/Havana";          // the rare zone whose DST flips AT midnight

    /// <summary>22:30Z on 2026-08-06 — already the 7th in Madrid, still the 6th in UTC and in LA.</summary>
    private static readonly DateTimeOffset LateUtcEvening = new(2026, 8, 6, 22, 30, 0, TimeSpan.Zero);

    /// <summary>02:30Z on 2026-08-06 — still the 5th in the Americas, already the 6th east of UTC.</summary>
    private static readonly DateTimeOffset EarlyUtcMorning = new(2026, 8, 6, 2, 30, 0, TimeSpan.Zero);

    [GeneratedRegex(@"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")]
    private static partial Regex GuidRegex();

    private static (UserDayResolver Sut, RecordingLogger Logger) CreateSut(DateTimeOffset? now = null)
    {
        var logger = new RecordingLogger();
        return (new UserDayResolver(new FixedTimeProvider(now ?? LateUtcEvening), logger), logger);
    }

    // --- instant -> user-local day ------------------------------------------------

    [Fact]
    public void Instant_late_in_the_UTC_evening_is_already_tomorrow_in_Madrid()
    {
        var (sut, _) = CreateSut();

        sut.ToUserDay(LateUtcEvening, Madrid).ShouldBe(new DateOnly(2026, 8, 7));
    }

    [Fact]
    public void Instant_early_in_the_UTC_morning_is_still_yesterday_in_Los_Angeles()
    {
        var (sut, _) = CreateSut();

        sut.ToUserDay(EarlyUtcMorning, LosAngeles).ShouldBe(new DateOnly(2026, 8, 5));
    }

    [Fact]
    public void Extreme_east_and_west_zones_disagree_on_the_calendar_day_of_one_instant()
    {
        // +14 and -11 are 25 hours apart: for this instant they are not merely different clocks,
        // they are on different dates. Any endpoint that keyed "today" off UTC would corrupt one
        // of these two users' day-keyed rows.
        var (sut, _) = CreateSut();

        sut.ToUserDay(EarlyUtcMorning, Kiritimati).ShouldBe(new DateOnly(2026, 8, 6));
        sut.ToUserDay(EarlyUtcMorning, Niue).ShouldBe(new DateOnly(2026, 8, 5));
        sut.ToUserDay(EarlyUtcMorning, Kiritimati).ShouldNotBe(sut.ToUserDay(EarlyUtcMorning, Niue));
    }

    // --- today --------------------------------------------------------------------

    [Fact]
    public void TodayFor_reads_the_injected_clock_and_the_users_own_zone()
    {
        var (sut, _) = CreateSut();

        sut.TodayFor(Madrid).ShouldBe(new DateOnly(2026, 8, 7));
        sut.TodayFor(LosAngeles).ShouldBe(new DateOnly(2026, 8, 6));
        sut.TodayFor(Kiritimati).ShouldBe(new DateOnly(2026, 8, 7));
        sut.TodayFor(Niue).ShouldBe(new DateOnly(2026, 8, 6));
    }

    // --- day -> instant range ------------------------------------------------------

    [Fact]
    public void End_of_user_day_is_the_exclusive_start_of_the_next_day()
    {
        var (sut, _) = CreateSut();
        var day = new DateOnly(2026, 8, 7);

        sut.EndOfUserDayExclusive(day, Madrid).ShouldBe(sut.StartOfUserDay(day.AddDays(1), Madrid));
        (sut.EndOfUserDayExclusive(day, Madrid) - sut.StartOfUserDay(day, Madrid)).ShouldBe(TimeSpan.FromHours(24));
    }

    [Fact]
    public void Madrid_spring_forward_day_is_still_exactly_one_calendar_day()
    {
        // 2026-03-29: CET -> CEST, 02:00 jumps to 03:00. The day is 23 hours long but it is still
        // ONE day — the half-open [start, end) window must not drop or duplicate a calendar date.
        var (sut, _) = CreateSut();
        var day = new DateOnly(2026, 3, 29);

        var start = sut.StartOfUserDay(day, Madrid);
        var end = sut.EndOfUserDayExclusive(day, Madrid);

        start.ShouldBe(new DateTimeOffset(2026, 3, 28, 23, 0, 0, TimeSpan.Zero)); // 00:00 CET (+1)
        end.ShouldBe(new DateTimeOffset(2026, 3, 29, 22, 0, 0, TimeSpan.Zero));   // 00:00 CEST (+2) next day
        (end - start).ShouldBe(TimeSpan.FromHours(23));

        sut.ToUserDay(start, Madrid).ShouldBe(day);
        sut.ToUserDay(end.AddTicks(-1), Madrid).ShouldBe(day);
        sut.ToUserDay(end, Madrid).ShouldBe(day.AddDays(1));
    }

    [Fact]
    public void StartOfUserDay_never_throws_when_the_users_midnight_does_not_exist()
    {
        // America/Havana starts DST AT midnight: on 2026-03-08 the local clock goes 00:00 -> 01:00,
        // so 00:00 never happens. TimeZoneInfo.ConvertTimeToUtc THROWS on that input; the day must
        // instead begin at the first instant that does exist (the transition itself, 05:00Z).
        var (sut, _) = CreateSut();
        var day = new DateOnly(2026, 3, 8);

        var start = Should.NotThrow(() => sut.StartOfUserDay(day, Havana));

        start.ShouldBe(new DateTimeOffset(2026, 3, 8, 5, 0, 0, TimeSpan.Zero));
        sut.ToUserDay(start, Havana).ShouldBe(day);

        // The UTC instant above would come out right even from a naive
        // `new DateTimeOffset(midnight, GetUtcOffset(midnight))`, because for a spring-forward gap
        // the standard offset is also the pre-transition one. What that naive form gets wrong — and
        // what these two assertions pin — is the RENDERING: it reports a wall clock of 00:00 at an
        // offset (-05:00) that was no longer in force. The value must read as 01:00 CDT (-04:00),
        // the first local time of that day that actually happened.
        start.Offset.ShouldBe(TimeSpan.FromHours(-4));
        start.DateTime.ShouldBe(new DateTime(2026, 3, 8, 1, 0, 0));
    }

    [Fact]
    public void Fall_back_ambiguity_resolves_to_the_earliest_instant()
    {
        // America/Havana ends DST AT 01:00 -> 00:00, so 2026-11-01 00:00 local happens TWICE:
        // once at 04:00Z (-04:00, still DST) and again at 05:00Z (-05:00, standard). The day must
        // start at the first of the two, otherwise the first hour of the day falls outside its own
        // [start, end) window. Note the BCL default (ConvertTimeToUtc / GetUtcOffset) picks the
        // standard offset, i.e. the LATER instant — this is exactly what must be overridden.
        var (sut, _) = CreateSut();

        var start = sut.StartOfUserDay(new DateOnly(2026, 11, 1), Havana);

        start.ShouldBe(new DateTimeOffset(2026, 11, 1, 4, 0, 0, TimeSpan.Zero));
        start.Offset.ShouldBe(TimeSpan.FromHours(-4));
        start.ShouldBeLessThan(new DateTimeOffset(2026, 11, 1, 5, 0, 0, TimeSpan.Zero));
    }

    // --- unusable timezone ids -----------------------------------------------------

    [Fact]
    public void Unknown_timezone_falls_back_to_Europe_Madrid()
    {
        // The clock is 22:30Z on the 6th: Madrid is already on the 7th while UTC is still on the
        // 6th, so this assertion proves the fallback is Madrid specifically and not a quiet slide
        // to UTC or to the machine's local zone.
        var (sut, logger) = CreateSut();

        sut.TodayFor("Mars/Olympus_Mons").ShouldBe(new DateOnly(2026, 8, 7));
        sut.TodayFor("Mars/Olympus_Mons").ShouldBe(sut.TodayFor(Madrid));
        logger.Entries.ShouldContain(e => e.Level == LogLevel.Warning);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Blank_timezone_falls_back_to_Europe_Madrid(string? timezone)
    {
        // A crypto-shredded user's row has Timezone blanked to "" (CryptoShredJob), so a blank id
        // is a real, reachable state — it must never throw and never silently mean UTC.
        var (sut, logger) = CreateSut();

        sut.TodayFor(timezone!).ShouldBe(new DateOnly(2026, 8, 7));
        sut.StartOfUserDay(new DateOnly(2026, 8, 7), timezone!)
            .ShouldBe(new DateTimeOffset(2026, 8, 6, 22, 0, 0, TimeSpan.Zero)); // 00:00 CEST (+2)
        logger.Entries.ShouldContain(e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public void Fallback_warning_leaks_neither_the_offending_timezone_id_nor_any_identifier()
    {
        // PII redaction is enforced repo-wide (PiiRedactionEnricher). A timezone id is a
        // quasi-identifier (it narrows a user to a region), so the warning may say THAT a fallback
        // happened but never WHICH id or WHOSE.
        const string offending = "Mars/Olympus_Mons";
        var (sut, logger) = CreateSut();

        sut.TodayFor(offending);

        var warning = logger.Entries.ShouldHaveSingleItem();
        warning.Level.ShouldBe(LogLevel.Warning);
        // Everything Serilog could render or index: message text, template, and every structured value.
        warning.Everything.ShouldNotContain(offending);
        warning.Everything.ShouldNotContain("Olympus");
        GuidRegex().IsMatch(warning.Everything).ShouldBeFalse(warning.Everything);
    }

    // --- helpers -------------------------------------------------------------------

    private sealed class RecordingLogger : ILogger<UserDayResolver>
    {
        public List<Entry> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            var parts = new List<string> { formatter(state, exception), eventId.Name ?? string.Empty };
            if (state is IEnumerable<KeyValuePair<string, object?>> pairs)
                parts.AddRange(pairs.Select(p => $"{p.Key}={p.Value}"));
            Entries.Add(new Entry(logLevel, string.Join(" | ", parts)));
        }

        internal sealed record Entry(LogLevel Level, string Everything);
    }
}
