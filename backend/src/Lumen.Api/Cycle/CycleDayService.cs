using Lumen.Api.Persistence;
using Lumen.Api.Symptoms;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Cycle;

/// <summary>
/// The day surface: the D-11 one-row-per-day upsert reached from the day-detail screen
/// (<c>POST /cycle/day/{date}</c>) and from the quick check-in sheet (<c>POST /checkin/quick</c>),
/// plus the single-day read (<c>GET /cycle/day/{date}</c>). Registered scoped, alongside the
/// request-scoped <see cref="IUserDayContext"/> and <see cref="IUserCryptoContext"/> it depends on.
/// </summary>
/// <remarks>
/// <para><b>1. A null day context is a 404, before anything else happens.</b> Erasure has no write
/// fence behind it: a crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires and inserting a child row takes only a share lock on
/// <c>users</c>, which does not conflict with the shred job's UPDATE. A request already in flight
/// during an erasure would otherwise write fresh plaintext health rows for a user who no longer
/// exists. Resolving the day context FIRST and returning "not found" on null is the whole of the
/// defence — which is why it is checked before validation rather than after.</para>
///
/// <para><b>2. Validate then act (T3).</b> Every field error is collected before the first write, so
/// a rejected request has changed nothing.</para>
///
/// <para><b>3. §G9 — <c>cycle_day_logs</c> is under the UNFILTERED unique-index regime</b>
/// (<c>(UserId, Day)</c>). A tombstone still occupies its key, so the upsert looks the row up with
/// <see cref="EntityFrameworkQueryableExtensions.IgnoreQueryFilters{TEntity}"/> and clears
/// <c>DeletedAt</c>. A blind insert is not a duplicate row — it is a unique violation surfacing as a
/// 500.</para>
///
/// <para><b>4. §G8 — these writes are capped by the user's today and have NO backdate floor.</b>
/// D-13 gives a floor to <c>cycle_events</c> alone; a day log five years back is legitimate history
/// (a user transcribing a paper diary) and rejecting it would lose real data. Do not copy
/// <see cref="CycleService"/>'s second date check into this file.</para>
///
/// <para><b>5. D-08 — <c>pain = 0</c> is a datum, not an absence.</b> "No pain today" is the answer
/// a well user taps. Only <see langword="null"/> means "not recorded", so every check below tests
/// <c>is null</c> and never falsiness.</para>
///
/// <para><b>6. Both write paths MERGE, and that is the opposite of T9.</b> <c>cycle_day_logs</c> is a
/// <b>multi-writer row</b>: <see cref="QuickCheckinAsync"/> writes pain and mood, <see cref="UpsertDayAsync"/>
/// writes pain, mood and the note, and D-10's energy/libido scales land on it later. So on both, an
/// absent or <see langword="null"/> field <b>leaves the stored value unchanged</b> and only a supplied
/// value writes. Reading either body as "the row's desired final state" would let whichever screen
/// posted last silently destroy what the other one recorded — an invisible cross-surface wipe, where
/// the cost of merging is only that <b>P4a ships no way to clear an individual field</b>, an explicit
/// and documented limitation matching screens 9 and 11 (neither offers a clear affordance).
/// <see cref="CycleService.LogEventAsync"/> (<c>POST /cycle/events</c>) is the deliberate contrast: a
/// single-writer row whose body genuinely does describe its whole state, so an omitted field there
/// clears. Both rules are stated side by side on their DTOs in <c>CycleContracts.cs</c>. Neither path
/// here writes <c>Energy</c>/<c>Libido</c> — no DTO carries them at all (D-10) — and neither writes a
/// <c>symptoms</c> row (D-11: classified episodes come from the full form, T11).</para>
///
/// <para><b>7. WARNING — both write paths CLEAR THE WHOLE CHANGE TRACKER, so a caller must not stage
/// un-saved work before invoking one.</b> <see cref="ResolveRowAsync"/> calls
/// <c>ChangeTracker.Clear()</c> to make its <see cref="ConcurrencyRetry"/> action re-runnable, and
/// that acts on the request-scoped <c>LumenDbContext</c> rather than on this action's entities:
/// anything a caller added or modified earlier in the same scope is <b>silently discarded</b> — no
/// exception, no failing test. The shape to avoid is a request that composes two writes, which is
/// exactly what T18's <c>POST /onboarding/cycle</c> plans against
/// <see cref="CycleService.LogEventAsync"/>. Save each part before invoking the next, or compose the
/// whole thing into one retried action. See <see cref="ConcurrencyRetry"/>'s remarks.</para>
/// </remarks>
public sealed class CycleDayService(LumenDbContext db, IUserDayContext dayContext, IUserCryptoContext crypto)
{
    /// <summary>
    /// Upserts the whole of one day (screen 11). Always 200: an upsert has no actionable
    /// created/updated distinction, and §C.2 exposes no <c>GET /cycle/day-log/{id}</c> for a
    /// <c>Location</c> header to point at.
    /// </summary>
    public async Task<CycleDayResult> UpsertDayAsync(DateOnly date, LogCycleDayRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleDayResult.UserNotFound();

        var errors = new List<CycleFieldError>();

        // §G8: capped by today and NOTHING ELSE. There is no `< day.BackdateFloor` branch here, and
        // adding one would reject the historical logging D-13 permits.
        if (date > day.Today)
            errors.Add(new CycleFieldError("date", ValidationMessages.FutureDate));

        AddScaleErrors(errors, request.Pain, request.Mood);

        // Trim first: the cap bounds the note, not a trailing newline.
        var notes = request.Notes?.Trim();
        if (notes is { Length: > FieldLimits.MaxNotesLength })
            errors.Add(new CycleFieldError("notes", ValidationMessages.MaxLength(FieldLimits.MaxNotesLength)));

        // At least one of the three. `request.Pain is null` rather than a truthiness test: pain 0 is
        // a real answer and must satisfy this (D-08). Blank notes are absent text, not text.
        if (request.Pain is null && request.Mood is null && notes is not { Length: > 0 })
            errors.Add(new CycleFieldError(ValidationProblemBuilder.RequestKey, CycleValidationMessages.DayLogEmpty));

        if (errors.Count > 0) return new CycleDayResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock
        // Encrypted once, outside the retry: a fresh nonce per attempt would be wasted work, and the
        // blob is immutable so re-using it on a second attempt is safe.
        var notesEnc = notes is { Length: > 0 } ? await crypto.EncryptStringAsync(notes, ct) : null;

        return await ConcurrencyRetry.ExecuteAsync<CycleDayResult>(async token =>
        {
            var row = await ResolveRowAsync(day.UserId, date, now, token);

            row.DeletedAt = null; // revive in place: same Id, original CreatedAt
            // MERGE: only a supplied value writes (see remark 6). A blank or whitespace-only note is
            // absent text, not an instruction to erase — the same rule the at-least-one check applies.
            MergeScales(row, request.Pain, request.Mood);

            string? storedNotes;
            if (notesEnc is not null)
            {
                row.NotesEnc = notesEnc;
                storedNotes = notes;
            }
            else
            {
                // The 200 body is the STORED row, so an unsupplied note is echoed from the column
                // rather than reported as null — reporting null would render the day as note-less on
                // the very screen that wrote the note, which is the read half of the same wipe.
                storedNotes = await DecryptAsync(row.NotesEnc, token);
            }

            row.UpdatedAt = now;
            // Energy/Libido are deliberately absent: no DTO, no writer (D-10).

            await db.SaveChangesAsync(token);

            return new CycleDayResult.Saved(new CycleDayLogResponse(
                row.Day,
                row.Pain,
                row.Mood,
                storedNotes,
                row.CreatedAt,
                row.UpdatedAt));
        }, ct);
    }

    /// <summary>
    /// The quick check-in (screen 9): today's pain and/or mood, upserted onto the same
    /// <c>cycle_day_logs</c> row the full form writes — and <b>no <c>symptoms</c> row</b> (D-11).
    /// </summary>
    /// <remarks>
    /// There is no date in the payload: the row is the user's local today (D-12). Screen 9 asks about
    /// today, D-11 says a repeat check-in updates today's value, and explicit dates already belong to
    /// <see cref="UpsertDayAsync"/>.
    /// </remarks>
    public async Task<QuickCheckinResult> QuickCheckinAsync(QuickCheckinRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        var day = await dayContext.GetAsync(ct);
        if (day is null) return new QuickCheckinResult.UserNotFound();

        var errors = new List<CycleFieldError>();
        AddScaleErrors(errors, request.Pain, request.Mood);

        if (request.Pain is null && request.Mood is null)
            errors.Add(new CycleFieldError(ValidationProblemBuilder.RequestKey, SymptomValidationMessages.QuickCheckinEmpty));

        if (errors.Count > 0) return new QuickCheckinResult.Invalid(errors);

        var now = day.NowUtc;

        return await ConcurrencyRetry.ExecuteAsync<QuickCheckinResult>(async token =>
        {
            var row = await ResolveRowAsync(day.UserId, day.Today, now, token);

            row.DeletedAt = null;
            // MERGE, exactly as on the full form: only the supplied fields move. Tapping the mood chip
            // must not erase this morning's pain score, and nothing here may touch NotesEnc/Energy/
            // Libido — the note on the day-detail screen belongs to a different write and must survive
            // this one. The sheet offers no note field, so this path never has one to merge.
            MergeScales(row, request.Pain, request.Mood);
            row.UpdatedAt = now;

            await db.SaveChangesAsync(token);

            return new QuickCheckinResult.Saved(new QuickCheckinResponse(row.Day, row.Pain, row.Mood, row.UpdatedAt));
        }, ct);
    }

    /// <summary>
    /// Reads one day (screen 11): the day log, that day's cycle events, and the user's live phase
    /// corrections dated on it — every encrypted note decrypted.
    /// </summary>
    /// <remarks>
    /// <b>No range validation</b> and <b>no 404 for an empty day</b>: an unlogged, future or
    /// long-past date is a legitimate question whose answer is empty, and 404 on this route means
    /// "no such user" alone (§G12). Every query is scoped to the caller, which is also this
    /// endpoint's tenant isolation — another user's day is indistinguishable from an empty one.
    /// <b>Nothing here is computed</b> (§G6): no phase, no cycle day, no confidence.
    /// </remarks>
    public async Task<CycleDayReadResult> GetDayAsync(DateOnly date, CancellationToken ct)
    {
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new CycleDayReadResult.UserNotFound();

        // AsNoTracking throughout: this is a read, and tracking these rows would let a later write in
        // the same scope pick them up by accident.
        var log = await db.CycleDayLogs.AsNoTracking()
            .FirstOrDefaultAsync(l => l.UserId == day.UserId && l.Day == date, ct);

        var events = await db.CycleEvents.AsNoTracking()
            .Where(e => e.UserId == day.UserId && e.OccurredOn == date)
            .OrderBy(e => e.Kind)
            .ToListAsync(ct);

        var overrides = await db.CyclePhaseOverrides.AsNoTracking()
            .Where(o => o.UserId == day.UserId && o.OccurredOn == date)
            .OrderBy(o => o.Phase).ThenBy(o => o.Boundary)
            .ToListAsync(ct);

        CycleDayLogResponse? logResponse = null;
        if (log is not null)
        {
            logResponse = new CycleDayLogResponse(
                log.Day,
                log.Pain,
                log.Mood,
                await DecryptAsync(log.NotesEnc, ct),
                log.CreatedAt,
                log.UpdatedAt);
        }

        var eventResponses = new List<CycleEventResponse>(events.Count);
        foreach (var row in events)
        {
            eventResponses.Add(new CycleEventResponse(
                row.Id,
                row.Kind,
                row.OccurredOn,
                row.FlowIntensity,
                await DecryptAsync(row.NotesEnc, ct),
                row.Source,
                row.CreatedAt,
                row.UpdatedAt));
        }

        var boundaries = overrides
            .Select(o => new PhaseOverrideBoundary(o.Phase, o.Boundary, o.OccurredOn))
            .ToList();

        return new CycleDayReadResult.Found(new CycleDayResponse(date, logResponse, eventResponses, boundaries));
    }

    /// <summary>
    /// Finds the user's row for one day under the §G9 UNFILTERED regime, or stages a new one.
    /// </summary>
    /// <remarks>
    /// Two details are load-bearing. <b><c>IgnoreQueryFilters()</c></b>: a tombstone still occupies
    /// <c>(UserId, Day)</c>, so a filtered lookup would miss it and the insert below would violate
    /// the unique index. <b><c>ChangeTracker.Clear()</c></b>: this runs inside
    /// <see cref="ConcurrencyRetry"/>, and a second attempt happens only because the first one's
    /// insert lost a race — that insert is still sitting in the tracker, and re-saving it would fail
    /// identically. Clearing on every attempt makes the operation genuinely re-runnable.
    ///
    /// <para>Deleting that clear breaks recovery and changes <b>nothing else observable</b>, so it is
    /// pinned by <c>ConcurrencyRecoveryTests</c> — which stages a lost race with an EF interceptor and
    /// fails when the line is gone. The ordinary tests in <c>CycleDayServiceTests</c> and
    /// <c>QuickCheckinServiceTests</c> execute it on every first attempt but would not notice its
    /// absence; executing a line is not covering it.</para>
    ///
    /// <para>Because the clear is context-wide, both public write paths inherit the caller
    /// restriction in remark 7 on this class: no un-saved work may be staged before them.</para>
    /// </remarks>
    private async Task<CycleDayLog> ResolveRowAsync(Guid userId, DateOnly date, DateTimeOffset now, CancellationToken ct)
    {
        db.ChangeTracker.Clear();

        var row = await db.CycleDayLogs.IgnoreQueryFilters()
            .FirstOrDefaultAsync(l => l.UserId == userId && l.Day == date, ct);

        if (row is null)
        {
            row = new CycleDayLog
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Day = date,
                CreatedAt = now,
            };
            db.CycleDayLogs.Add(row);
        }

        return row;
    }

    /// <summary>
    /// The pain and mood range checks, shared by both write paths so the two endpoints can never
    /// disagree about a scale. Both use <c>is { } value</c>: absent is not an error here (the
    /// at-least-one rule owns that), and 0 is a legal pain (D-08).
    /// </summary>
    private static void AddScaleErrors(List<CycleFieldError> errors, int? pain, int? mood)
    {
        if (pain is { } painValue &&
            (painValue < CycleDayLog.PainScale.Min || painValue > CycleDayLog.PainScale.Max))
        {
            errors.Add(new CycleFieldError(
                "pain",
                ValidationMessages.Between(CycleDayLog.PainScale.Min, CycleDayLog.PainScale.Max)));
        }

        if (mood is { } moodValue &&
            (moodValue < CycleDayLog.MoodScale.Min || moodValue > CycleDayLog.MoodScale.Max))
        {
            errors.Add(new CycleFieldError(
                "mood",
                ValidationMessages.Between(CycleDayLog.MoodScale.Min, CycleDayLog.MoodScale.Max)));
        }
    }

    /// <summary>
    /// Merges the two scales onto the row: a supplied value writes, an absent one is left alone.
    /// Shared by both write paths so the endpoints cannot drift apart on the rule.
    /// </summary>
    /// <remarks>
    /// <c>is { }</c> and never a falsiness test: <c>pain = 0</c> is a supplied datum (D-08) and must
    /// overwrite a stored 8, while <see langword="null"/> alone means "not recorded". A
    /// <c>?? row.Pain</c> written over a truthiness check would look identical and silently drop every
    /// pain-free day out of the series P6 reads.
    /// </remarks>
    private static void MergeScales(CycleDayLog row, int? pain, int? mood)
    {
        if (pain is { } painValue) row.Pain = (short)painValue;
        if (mood is { } moodValue) row.Mood = (short)moodValue;
    }

    private async Task<string?> DecryptAsync(byte[]? blob, CancellationToken ct) =>
        blob is { Length: > 0 } ? await crypto.DecryptStringAsync(blob, ct) : null;
}
