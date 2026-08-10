using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Cycle;

/// <summary>
/// The windowed calendar read (<c>GET /cycle/calendar?from&amp;to</c>) behind screen 10 and screen 8:
/// a bounded, <b>sparse</b> aggregation over the three observation tables. Registered scoped,
/// alongside the request-scoped <see cref="IUserDayContext"/> it depends on.
/// </summary>
/// <remarks>
/// <para><b>1. A null day context is a 404, before anything else happens</b> — and on a read that is
/// not a formality. A crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires (disabling the Keycloak user does not revoke an
/// already-issued token). Without this fence the token could still read health data back, and even an
/// empty 200 would confirm the account had existed. Checked FIRST, before the window is validated, so
/// no branch can leak "your request shape was understood" to an erased caller.</para>
///
/// <para><b>2. §G6 — this endpoint computes NOTHING.</b> No phase, no cycle day, no ovulation, no
/// fertile window, no confidence, no prediction, no regularity. It counts rows and copies two scales.
/// The single <c>phase: { available: false, unavailableReason: "phase_engine_not_implemented" }</c>
/// envelope on the response is the only phase-shaped thing it emits, and it exists precisely to say
/// the P6 engine does not exist yet — see <see cref="CyclePhaseAvailabilityResponse"/>. <b>No day row
/// carries a <c>phase</c>, <c>cycleDay</c> or <c>confidence</c> key</b>, and
/// <see cref="CycleCalendarDay"/> has no such property to fill.</para>
///
/// <para><b>3. The window is matched on the DAY-KEYED columns, never on a UTC instant.</b>
/// <c>cycle_day_logs.Day</c>, <c>cycle_events.OccurredOn</c> and <c>symptoms.OccurredOn</c> are
/// already the user's own day (D-12) and are what the indexes are built on. Converting the two bounds
/// back into instants here would re-introduce the per-row timezone conversion those columns were added
/// to remove, and would answer differently for a row logged before the user last changed timezone.
/// <b><see cref="Symptoms.SymptomService.ListAsync"/> (T12) follows the same rule</b>, deliberately, so
/// the two windowed reads can never disagree about which rows a month contains.</para>
///
/// <para><b>4. No <c>*_enc</c> column is decrypted here.</b> The day row carries
/// <see cref="CycleCalendarDay.HasNotes"/> — a flag computed in SQL from <c>NotesEnc IS NOT NULL</c> —
/// and never the note. Decrypting a month of notes to answer a boolean the screen draws as a dot would
/// put plaintext health data on the wire for nothing. This service takes no
/// <see cref="Application.Crypto.IUserCryptoContext"/> at all, which is what keeps a later edit from
/// starting to.</para>
///
/// <para><b>5. Soft-deleted rows are invisible, and the global query filter is what does it.</b> All
/// three tables are soft-deletable (D-13). There is <b>no <c>IgnoreQueryFilters()</c> anywhere on this
/// path</b> — a read that bypassed the filter would count tombstones into
/// <see cref="CycleCalendarDay.EventCount"/> and would draw a day the user had already cleared.</para>
///
/// <para><b>6. Tenant isolation is the <c>UserId</c> predicate, and its answer is emptiness.</b> A
/// range read has no id to 404 on, so the isolation is that another tenant's rows are simply not in
/// the query — absent from <see cref="CycleCalendarResponse.Days"/> and from every count alike.</para>
///
/// <para><b>7. <c>AsNoTracking</c> throughout</b>: this is a read, and tracking these rows would let a
/// later write in the same request scope pick them up by accident.</para>
/// </remarks>
public sealed class CycleCalendarService(LumenDbContext db, IUserDayContext dayContext)
{
    /// <summary>
    /// Reads one bounded window of the caller's calendar. Both bounds are optional and default
    /// independently to the corresponding edge of the user's current month. Answered with 200 and a
    /// possibly-empty day list.
    /// </summary>
    /// <remarks>
    /// <b>A <c>to</c> in the future is legitimate</b>, as it is on <c>GET /symptoms</c> and nowhere
    /// else in this phase: every WRITE is capped by today (§G8), but a month view spans forward and
    /// rejecting that would make the client clamp a window it had just rendered.
    /// </remarks>
    public async Task<CycleCalendarResult> GetCalendarAsync(DateOnly? from, DateOnly? to, CancellationToken ct)
    {
        // Rule 1: before the defaults, before validation, before anything.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleCalendarResult.UserNotFound();

        // The default window is the USER's current month (D-12), derived from UserDayInfo.Today rather
        // than from any UTC date — a month taken off the server clock puts a Madrid user on the wrong
        // one for the first and last hours of it.
        var monthStart = new DateOnly(day.Today.Year, day.Today.Month, 1);
        var windowStart = from ?? monthStart;
        var windowEnd = to ?? monthStart.AddMonths(1).AddDays(-1);

        var errors = new List<CycleFieldError>();

        // Both faults are reported on `to` — the far bound, the one the client most likely got wrong
        // and the one it can move to fix either. `else if` on purpose: a negative span is not a
        // 400,000-day one, and reporting both would give the client two messages on one field of which
        // only one is actionable.
        if (windowEnd < windowStart)
        {
            errors.Add(new CycleFieldError("to", ValidationMessages.RangeEndBeforeStart));
        }
        else if (windowEnd.DayNumber - windowStart.DayNumber + 1 > CycleCalendarWindow.MaxDays)
        {
            // §G11 — a P4a INVENTION, and a bounded DATE WINDOW rather than the D-13 50/100 offset
            // page. See CycleCalendarWindow for why this read is not paginated at all.
            errors.Add(new CycleFieldError("to", CycleValidationMessages.MaxWindowDays(CycleCalendarWindow.MaxDays)));
        }

        if (errors.Count > 0) return new CycleCalendarResult.Invalid(errors);

        // Three queries rather than one join: the tables have no relationship to join ON except the
        // day itself, and a join across them would multiply the day-log row by the event and symptom
        // counts — the classic fan-out that turns "2 events, 3 symptoms" into 6 of each.
        //
        // `HasNotes` is computed in SQL as `NotesEnc IS NOT NULL`, so the ciphertext never leaves the
        // database (rule 4). Only the four members the DTO needs are projected.
        var logs = await db.CycleDayLogs.AsNoTracking()
            .Where(l => l.UserId == day.UserId && l.Day >= windowStart && l.Day <= windowEnd)
            .Select(l => new { l.Day, l.Pain, l.Mood, HasNotes = l.NotesEnc != null })
            .ToListAsync(ct);

        var eventCounts = await db.CycleEvents.AsNoTracking()
            .Where(e => e.UserId == day.UserId && e.OccurredOn >= windowStart && e.OccurredOn <= windowEnd)
            .GroupBy(e => e.OccurredOn)
            .Select(g => new { Day = g.Key, Count = g.Count() })
            .ToDictionaryAsync(g => g.Day, g => g.Count, ct);

        var symptomCounts = await db.Symptoms.AsNoTracking()
            .Where(s => s.UserId == day.UserId && s.OccurredOn >= windowStart && s.OccurredOn <= windowEnd)
            .GroupBy(s => s.OccurredOn)
            .Select(g => new { Day = g.Key, Count = g.Count() })
            .ToDictionaryAsync(g => g.Day, g => g.Count, ct);

        // (UserId, Day) is unique on cycle_day_logs (§G9), so there is at most one live row per day.
        var logsByDay = logs.ToDictionary(l => l.Day);

        // SPARSE: the union of the three key sets, and nothing else. A day with no data is absent
        // rather than a zero row — a month view is mostly empty, and 31 empty rows per request is
        // payload the client throws away. Sorted, so `days` is ascending by date.
        var dates = new SortedSet<DateOnly>(logsByDay.Keys);
        dates.UnionWith(eventCounts.Keys);
        dates.UnionWith(symptomCounts.Keys);

        var days = new List<CycleCalendarDay>(dates.Count);
        foreach (var date in dates)
        {
            logsByDay.TryGetValue(date, out var log);
            days.Add(new CycleCalendarDay(
                date,
                // `log?.Pain` and never `?? 0`: pain 0 is a datum and "no day log" is not (D-08).
                log?.Pain,
                log?.Mood,
                log?.HasNotes ?? false,
                eventCounts.GetValueOrDefault(date),
                symptomCounts.GetValueOrDefault(date)));
        }

        return new CycleCalendarResult.Found(new CycleCalendarResponse(
            windowStart,
            windowEnd,
            day.Today,
            day.TimezoneId,
            // Rule 2: the one thing this response says about phases is that P4a has no engine.
            new CyclePhaseAvailabilityResponse(false, CyclePhaseAvailability.PhaseEngineNotImplemented),
            days));
    }
}
