using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Application.Time;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Symptoms;

/// <summary>
/// The whole §C.3 symptoms resource: the all-or-nothing batch create behind screen 12's "Save
/// symptom" and screen 13's "Save body map" (<c>POST /symptoms</c>, T11), plus the range read, the
/// full replace and the soft delete that complete it (<c>GET /symptoms</c>,
/// <c>PUT /symptoms/{id}</c>, <c>DELETE /symptoms/{id}</c>, T12). Registered scoped, alongside the
/// request-scoped <see cref="IUserDayContext"/> and <see cref="IUserCryptoContext"/> it depends on.
/// </summary>
/// <remarks>
/// <para><b>1. A null day context is a 404, before anything else happens.</b> Erasure has no write
/// fence behind it: a crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires (disabling the Keycloak user does not revoke an
/// already-issued token), and inserting a child row takes only a share lock on <c>users</c>, which
/// does not conflict with the shred job's UPDATE. A request already in flight during an erasure would
/// otherwise write fresh plaintext health rows for a user who no longer exists. Resolving the day
/// context FIRST and returning "not found" on null is the whole of the defence — which is why it is
/// checked before validation rather than after.</para>
///
/// <para><b>2. Validate then act, across the WHOLE batch (T3 + OQ-6).</b> Every entry is validated
/// and normalised before the first row is staged, and one bad entry rejects all of them. This is not
/// tidiness: D-09 makes a single user action multi-row, the client is online-only with no write
/// queue, and a half-written episode reads as a complete one forever after — worse than no record,
/// because the user believes it saved. Errors are keyed by the indexed JSON path
/// (<c>entries[3].intensity</c>) so the client can attach each message to the right row of the form.</para>
///
/// <para><b>3. §G8 — this write is capped by the user's local today and has NO backdate floor.</b>
/// D-13 gives a floor to <c>cycle_events</c> alone. A symptom logged five years back is a user
/// transcribing a paper diary, which is exactly the history D-13 permits, so
/// <see cref="UserDayInfo.BackdateFloor"/> is deliberately never read in this file. The cap is at
/// <b>local-day</b> granularity, not instant granularity, so a phone whose clock runs a few minutes
/// fast does not lose its user's entry.</para>
///
/// <para><b>4. §G6/§G7 — nothing clinical comes near this write.</b> Observed data is never
/// clinically validated: there is no severity bucketing, no phase attribution, no correlation, and
/// <b>no cross-field rules at all</b> — pain types and triggers are accepted on every symptom code,
/// because "pain qualities only belong on <c>pain</c>" is a clinical judgement and a user who says
/// their bloating is cramping has told us something true. D-09's guardrail is the shape of the
/// validation here: <b>classification is ALWAYS optional</b>, and only the intensity and the date are
/// required.</para>
///
/// <para><b>5. D-08 — <c>intensity = 0</c> is a datum, not an absence.</b> Only
/// <see langword="null"/> means "not supplied", so the check below tests <c>is not { }</c> and never
/// falsiness. Coalescing 0 into absent would reject "it barely registered today" and leave P6 with a
/// series that only ever contains bad days.</para>
///
/// <para><b>6. §G9 does not apply, and saying so is the point.</b> <c>symptoms</c> is an APPEND
/// table: its only unique key is the primary key, and its <c>(UserId, OccurredOn, OccurredAt)</c>
/// index is not unique — two identical episodes an hour apart are two real observations, and D-09
/// makes one save produce several rows on the same day by design. So there is no tombstone to revive,
/// no <c>IgnoreQueryFilters()</c> lookup, and <b>no <see cref="Persistence.ConcurrencyRetry"/></b>:
/// with no natural key there is no unique-key race to lose, and wrapping the insert anyway would add
/// that helper's <c>ChangeTracker.Clear()</c> hazard for every future composing caller in exchange
/// for nothing. Untested defensive code on a write path is worse than none — it looks like a
/// guarantee.</para>
///
/// <para><b>7. One <c>SaveChangesAsync</c>, and it is the whole unit of work.</b> EF wraps the batch's
/// inserts in one implicit transaction, so all-or-nothing holds at the database as well as at the
/// validator. Because this service both stages and saves, a later task that needs to compose a
/// symptom write with another write must NOT call this method after staging — it must either save
/// first or grow its own composite (§G12's unit-of-work rule).</para>
///
/// <para><b>8. Tenant isolation is a <c>UserId</c> predicate on the lookup, and the answer is 404 —
/// never 403</b> (§G12). <see cref="ReplaceAsync"/> and <see cref="DeleteAsync"/> both find their row
/// with <c>s.Id == id &amp;&amp; s.UserId == day.UserId</c> and <b>without</b>
/// <see cref="EntityFrameworkQueryableExtensions.IgnoreQueryFilters{TEntity}"/>. Those two facts
/// together are the isolation: another tenant's row, an already-tombstoned row and a typo'd id are
/// indistinguishable to the caller, and a 403 would itself have confirmed that the id exists.
/// <see cref="ListAsync"/> is scoped the same way, so another user's rows are absent from
/// <c>items</c> and from <c>total</c> alike.</para>
///
/// <para><b>9. <c>PUT</c> is a FULL REPLACE with two halves</b> (see
/// <see cref="ReplaceSymptomRequest"/> for the reasoning and the client obligation). A field with an
/// unclassified state clears when omitted; <see cref="ReplaceSymptomRequest.Intensity"/> and
/// <see cref="ReplaceSymptomRequest.OccurredAt"/> have none and are therefore required, so an edit can
/// never fabricate an observation time. The verb was renamed from <c>PATCH</c> in T12 and §C.3 amended
/// in the same commit — <c>PATCH</c>'s defined meaning contradicts what this method does.</para>
/// </remarks>
public sealed class SymptomService(
    LumenDbContext db,
    IUserDayContext dayContext,
    IUserCryptoContext crypto,
    IUserDayResolver dayResolver)
{
    /// <summary>
    /// Records a batch of 1–<see cref="SymptomBatch.MaxEntries"/> symptom episodes as one unit of
    /// work. Answered with 201 and every created row, in request order.
    /// </summary>
    public async Task<SymptomCreateResult> CreateAsync(CreateSymptomsRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: before validation, before anything.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SymptomCreateResult.UserNotFound();

        var errors = new List<SymptomFieldError>();
        var entries = request.Entries;

        // The envelope. These three short-circuit rather than falling through to the per-entry loop:
        // with no entries there is nothing to say, and a 5,000-entry payload would otherwise answer
        // with 5,000 messages when the client has exactly one actionable problem. Nothing is written
        // on any of these paths, so validate-then-act still holds.
        if (entries is null)
            errors.Add(new SymptomFieldError("entries", ValidationMessages.Required));
        else if (entries.Count < SymptomBatch.MinEntries)
            errors.Add(new SymptomFieldError("entries", SymptomValidationMessages.BatchEmpty));
        else if (entries.Count > SymptomBatch.MaxEntries)
            errors.Add(new SymptomFieldError("entries", SymptomValidationMessages.MaxEntries(SymptomBatch.MaxEntries)));

        if (errors.Count > 0) return new SymptomCreateResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock
        var normalized = new List<NormalizedEntry>(entries!.Count);

        for (var i = 0; i < entries.Count; i++)
        {
            var errorsBefore = errors.Count;
            var candidate = Normalize(entries[i], $"entries[{i}]", day, now, errors);
            // Only an entry that raised nothing is carried forward. The list is used solely on the
            // success path, where it is guaranteed to hold every entry.
            if (errors.Count == errorsBefore && candidate is not null) normalized.Add(candidate);
        }

        // All-or-nothing (OQ-6): one bad entry and NOTHING is written — not the valid entries, not a
        // partial episode.
        if (errors.Count > 0) return new SymptomCreateResult.Invalid(errors);

        var items = new List<SymptomResponse>(normalized.Count);

        foreach (var entry in normalized)
        {
            var row = new Symptom
            {
                Id = Guid.NewGuid(),
                UserId = day.UserId,
                SymptomCode = entry.SymptomCode,
                Intensity = entry.Intensity,
                Region = entry.Region,
                Side = entry.Side,
                PainTypes = entry.PainTypes,
                Triggers = entry.Triggers,
                OccurredAt = entry.OccurredAt,
                OccurredOn = entry.OccurredOn,
                NotesEnc = entry.Notes is { Length: > 0 } ? await crypto.EncryptStringAsync(entry.Notes, ct) : null,
                CreatedAt = now,
                UpdatedAt = now,
            };
            db.Symptoms.Add(row);

            // Notes echoed from the plaintext: the column holds only ciphertext.
            items.Add(ToResponse(row, entry.Notes));
        }

        // Rule 7: one save for the whole batch, so the database enforces all-or-nothing too.
        await db.SaveChangesAsync(ct);

        return new SymptomCreateResult.Saved(new CreateSymptomsResponse(items));
    }

    /// <summary>
    /// Reads one page of the caller's symptom history inside an inclusive <b>user-local day</b> window
    /// (screens 10, 11 and 12's history), newest first. Answered with 200 and a possibly-empty page.
    /// </summary>
    /// <remarks>
    /// <para><b>The window is matched on <c>OccurredOn</c>, not on the instant.</b> That column exists
    /// precisely so a range read is a day-keyed index scan against
    /// <c>(UserId, OccurredOn, OccurredAt)</c> rather than a per-row timezone conversion, and it is
    /// already the user's own day (D-12) — converting the two bounds back into UTC instants here would
    /// re-introduce the conversion the column was added to remove, and would answer differently for a
    /// row logged before the user last changed timezone.</para>
    ///
    /// <para><b>A <c>to</c> in the future is legitimate</b>, and this is the one place in P4a where a
    /// forward date is: every WRITE is capped by today (§G8), but a month view spans forward and
    /// rejecting that would make the client clamp a window it had just rendered.</para>
    ///
    /// <para><b>Out-of-range paging is a 400, never a clamp.</b> Silently returning 100 rows to a
    /// client that asked for 500 leaves it unable to tell "that is all of them" from "you were
    /// truncated" — it would render a partial symptom history as a complete one.</para>
    ///
    /// <para><b><c>AsNoTracking</c> throughout</b>: this is a read, and tracking these rows would let a
    /// later write in the same request scope pick them up by accident.</para>
    /// </remarks>
    public async Task<SymptomListResult> ListAsync(
        DateOnly? from,
        DateOnly? to,
        int? limit,
        int? offset,
        CancellationToken ct)
    {
        // Rule 1, on the read too: an erased account's token must not read health rows back either.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SymptomListResult.UserNotFound();

        var errors = new List<SymptomFieldError>();

        if (from is null)
            errors.Add(new SymptomFieldError("from", ValidationMessages.Required));

        if (to is null)
            errors.Add(new SymptomFieldError("to", ValidationMessages.Required));
        else if (from is { } start && to is { } end && end < start)
            errors.Add(new SymptomFieldError("to", ValidationMessages.RangeEndBeforeStart));

        var pageSize = limit ?? SymptomPaging.DefaultLimit;
        if (pageSize < SymptomPaging.MinLimit || pageSize > SymptomPaging.MaxLimit)
        {
            errors.Add(new SymptomFieldError(
                "limit",
                ValidationMessages.Between(SymptomPaging.MinLimit, SymptomPaging.MaxLimit)));
        }

        var skip = offset ?? 0;
        if (skip < 0)
            errors.Add(new SymptomFieldError("offset", ValidationMessages.NotNegative));

        if (errors.Count > 0) return new SymptomListResult.Invalid(errors);

        var windowStart = from!.Value;
        var windowEnd = to!.Value;

        // The UserId predicate is this endpoint's tenant isolation, and the query filter keeps
        // tombstoned rows out of BOTH the page and the count — a total that included them would page
        // the client into rows that never arrive.
        var matching = db.Symptoms.AsNoTracking()
            .Where(s => s.UserId == day.UserId && s.OccurredOn >= windowStart && s.OccurredOn <= windowEnd);

        var total = await matching.CountAsync(ct);

        // The `Id` tiebreak is not defensive: D-09 makes several rows share one instant on EVERY
        // body-map save, and without it the database may order the tied rows differently per query —
        // page 2 repeating a row from page 1 and dropping another, silently losing a symptom.
        var rows = await matching
            .OrderByDescending(s => s.OccurredAt)
            .ThenByDescending(s => s.Id)
            .Skip(skip)
            .Take(pageSize)
            .ToListAsync(ct);

        var items = new List<SymptomResponse>(rows.Count);
        foreach (var row in rows) items.Add(ToResponse(row, await DecryptAsync(row.NotesEnc, ct)));

        return new SymptomListResult.Found(new SymptomListResponse(items, total, pageSize, skip));
    }

    /// <summary>
    /// Replaces one symptom row with the state the body describes (screens 12 and 13, re-opened).
    /// Answered with 200 and the stored row.
    /// </summary>
    /// <remarks>
    /// <b>Full replace, both halves</b> — see rule 9 on this class and
    /// <see cref="ReplaceSymptomRequest"/> for why the verb is <c>PUT</c> and what the client owes.
    /// <see cref="Symptom.SymptomCode"/> is never assigned here because the request cannot carry one.
    /// The note is re-encrypted with a fresh nonce on every replace, and a cleared note nulls the
    /// column rather than leaving unreferenced ciphertext behind.
    ///
    /// <para>The row is looked up <b>before</b> validation so a caller who has no such row does the
    /// least possible work and learns the least possible thing, and <b>without</b>
    /// <c>IgnoreQueryFilters()</c> so a <c>PUT</c> can never resurrect a tombstone. There is no
    /// <see cref="Persistence.ConcurrencyRetry"/> here for the same reason there is none on the create
    /// (rule 6): <c>symptoms</c> has no natural key, so this UPDATE touches no unique index and has no
    /// race to lose.</para>
    /// </remarks>
    public async Task<SymptomReplaceResult> ReplaceAsync(Guid id, ReplaceSymptomRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: before the lookup, before validation, before anything.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SymptomReplaceResult.NotFound();

        // Rule 8: no IgnoreQueryFilters(), and the UserId predicate is load-bearing.
        var row = await db.Symptoms.FirstOrDefaultAsync(s => s.Id == id && s.UserId == day.UserId, ct);
        if (row is null) return new SymptomReplaceResult.NotFound();

        var errors = new List<SymptomFieldError>();

        var intensity = NormalizeIntensity(request.Intensity, "intensity", errors);
        var region = NormalizeRegion(request.Region, "region", errors);
        var side = NormalizeSide(request.Side, "side", errors);
        var painTypes = NormalizeVocabularyList(request.PainTypes, Symptom.PainTypeCodes.All, "painTypes", errors);
        var triggers = NormalizeVocabularyList(request.Triggers, Symptom.TriggerCodes.All, "triggers", errors);
        var notes = NormalizeNotes(request.Notes, "notes", errors);

        // REQUIRED, unlike on create. `now` is the time of this EDIT, not of the episode: defaulting to
        // it would silently re-date a transcribed five-year-old entry to today, fabricating an
        // observation the user never made. `occurredAt` has no unclassified state to fall back to, so
        // the honest answer to an omission is a 400.
        (DateTimeOffset At, DateOnly On) occurred = default;
        if (request.OccurredAt is not { } suppliedInstant)
            errors.Add(new SymptomFieldError("occurredAt", ValidationMessages.Required));
        else
            occurred = NormalizeInstant(suppliedInstant, day, "occurredAt", errors);

        // Validate then act: a rejected replace has changed nothing.
        if (errors.Count > 0) return new SymptomReplaceResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        row.Intensity = intensity!.Value;
        row.Region = region;
        row.Side = side;
        row.PainTypes = painTypes;
        row.Triggers = triggers;
        row.OccurredAt = occurred.At;
        row.OccurredOn = occurred.On;
        // Fresh nonce every time; null when cleared, so no unreferenced ciphertext survives the edit.
        row.NotesEnc = notes is { Length: > 0 } ? await crypto.EncryptStringAsync(notes, ct) : null;
        row.UpdatedAt = now;
        // CreatedAt is deliberately NOT reassigned: it belongs to the observation, not to this edit.
        // SymptomCode is not assignable from the request at all (immutable by construction).

        await db.SaveChangesAsync(ct);

        return new SymptomReplaceResult.Saved(ToResponse(row, notes));
    }

    /// <summary>
    /// Soft-deletes one symptom row (D-13): sets <see cref="Symptom.DeletedAt"/> and answers 204. A
    /// second call is a 404, because the query filter hides the tombstone.
    /// </summary>
    /// <remarks>
    /// <b>Never <c>ExecuteDeleteAsync</c>.</b> D-13 makes soft delete universal outside account
    /// erasure: the row stays for the audit trail and for the erasure path that owns removing it (§F,
    /// T8). Same lookup rules as <see cref="ReplaceAsync"/>, so another user's id, an unknown id and an
    /// already-deleted id are one indistinguishable 404.
    /// </remarks>
    public async Task<SymptomDeleteResult> DeleteAsync(Guid id, CancellationToken ct)
    {
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new SymptomDeleteResult.NotFound();

        var row = await db.Symptoms.FirstOrDefaultAsync(s => s.Id == id && s.UserId == day.UserId, ct);
        if (row is null) return new SymptomDeleteResult.NotFound();

        var now = day.NowUtc;
        row.DeletedAt = now;
        row.UpdatedAt = now;

        await db.SaveChangesAsync(ct);

        return new SymptomDeleteResult.Deleted();
    }

    /// <summary>
    /// Projects a stored row onto the wire shape, taking the note as already-decrypted plaintext (the
    /// column holds only ciphertext). One place, so the create, the read and the replace can never
    /// disagree about what a symptom looks like.
    /// </summary>
    private static SymptomResponse ToResponse(Symptom row, string? notes) => new(
        row.Id,
        row.SymptomCode,
        row.Intensity,
        row.Region,
        row.Side,
        row.PainTypes,
        row.Triggers,
        row.OccurredAt,
        row.OccurredOn,
        notes,
        row.CreatedAt,
        row.UpdatedAt);

    private async Task<string?> DecryptAsync(byte[]? blob, CancellationToken ct) =>
        blob is { Length: > 0 } ? await crypto.DecryptStringAsync(blob, ct) : null;

    /// <summary>
    /// Validates and normalises one entry, appending every fault it finds to <paramref name="errors"/>
    /// under <paramref name="path"/>. Returns <see langword="null"/> when the entry cannot be
    /// normalised at all.
    /// </summary>
    /// <remarks>
    /// The normalisation order is the one the task fixes: code defaulted, region defaulted, blank side
    /// nulled, vocabulary lists de-duplicated and re-ordered, instant normalised to UTC, day derived,
    /// note trimmed. Every membership test is <see cref="StringComparer.Ordinal"/> and <b>nothing is
    /// case-fixed</b>: these vocabularies are append-only and stored rows carry the strings forever,
    /// so letting two spellings of one concept in would be permanent.
    /// </remarks>
    private NormalizedEntry? Normalize(
        SymptomEntryInput? entry,
        string path,
        UserDayInfo day,
        DateTimeOffset now,
        List<SymptomFieldError> errors)
    {
        // `entries: [null]` is legal JSON that binds to a null element. Reported as a field error
        // rather than dereferenced — an NRE here would be a 500 for malformed input.
        if (entry is null)
        {
            errors.Add(new SymptomFieldError(path, ValidationMessages.Required));
            return null;
        }

        // Absent or blank defaults to `pain` (D-09: the form's headline row). A supplied value is
        // matched ordinally, so "Pain" is a rejection and never a silent fixup.
        var code = entry.SymptomCode?.Trim();
        if (string.IsNullOrEmpty(code))
            code = Symptom.Codes.Pain;
        else if (!Symptom.Codes.All.Contains(code, StringComparer.Ordinal))
            errors.Add(new SymptomFieldError($"{path}.symptomCode", ValidationMessages.NotAllowedValue));

        var intensity = NormalizeIntensity(entry.Intensity, $"{path}.intensity", errors);
        var region = NormalizeRegion(entry.Region, $"{path}.region", errors);
        var side = NormalizeSide(entry.Side, $"{path}.side", errors);

        var painTypes = NormalizeVocabularyList(
            entry.PainTypes, Symptom.PainTypeCodes.All, $"{path}.painTypes", errors);
        var triggers = NormalizeVocabularyList(
            entry.Triggers, Symptom.TriggerCodes.All, $"{path}.triggers", errors);

        // Absent defaults to the request's single `now` — the user is logging as it happens. (The
        // REPLACE surface deliberately does NOT share this default: there, `now` would be the time of
        // the edit rather than of the episode, so an omission is a 400 instead.)
        var occurred = NormalizeInstant(entry.OccurredAt ?? now, day, $"{path}.occurredAt", errors);

        var notes = NormalizeNotes(entry.Notes, $"{path}.notes", errors);

        if (intensity is not { } value) return null;

        return new NormalizedEntry(
            code,
            value,
            region,
            side,
            painTypes,
            triggers,
            occurred.At,
            occurred.On,
            notes);
    }

    /// <summary>
    /// The 0–10 NRS-11 check (D-08). <c>is not { }</c> and never a falsiness test:
    /// <b>intensity 0 is a real answer</b>, so only <see langword="null"/> is "not supplied".
    /// </summary>
    /// <remarks>
    /// The narrowing to <c>short</c> happens only after the range check, so the <c>int?</c> on both
    /// request DTOs is what protects the cast: a client sending 40000 gets a message on this field
    /// rather than a wrapped-around value.
    /// </remarks>
    private static short? NormalizeIntensity(int? supplied, string field, List<SymptomFieldError> errors)
    {
        if (supplied is not { } value)
        {
            errors.Add(new SymptomFieldError(field, ValidationMessages.Required));
            return null;
        }

        if (value < Symptom.IntensityScale.Min || value > Symptom.IntensityScale.Max)
        {
            errors.Add(new SymptomFieldError(
                field,
                ValidationMessages.Between(Symptom.IntensityScale.Min, Symptom.IntensityScale.Max)));
            return null;
        }

        return (short)value;
    }

    /// <summary>One of the 9 ratified regions; absent or blank is <c>unspecified</c> (§G10).</summary>
    private static string NormalizeRegion(string? supplied, string field, List<SymptomFieldError> errors)
    {
        var region = supplied?.Trim();
        if (string.IsNullOrEmpty(region)) return Symptom.Regions.Default;

        if (!Symptom.Regions.All.Contains(region, StringComparer.Ordinal))
            errors.Add(new SymptomFieldError(field, ValidationMessages.NotAllowedValue));

        return region;
    }

    /// <summary>
    /// Anatomical <c>front</c>/<c>back</c>, <b>NOT</b> laterality. Blank is "not classified", which is
    /// a null column rather than an empty string — an empty string would be a third state nothing reads.
    /// </summary>
    private static string? NormalizeSide(string? supplied, string field, List<SymptomFieldError> errors)
    {
        var side = supplied?.Trim();
        if (string.IsNullOrEmpty(side)) return null;

        if (!Symptom.Sides.All.Contains(side, StringComparer.Ordinal))
            errors.Add(new SymptomFieldError(field, ValidationMessages.NotAllowedValue));

        return side;
    }

    /// <summary>
    /// Normalises the episode instant to UTC and derives the user's day from it (D-12), rejecting a
    /// day after the user's today.
    /// </summary>
    /// <remarks>
    /// The <c>ToUniversalTime()</c> is <b>mandatory, not cosmetic</b>: Npgsql throws on a non-zero
    /// offset for a <c>timestamptz</c> parameter, so an unnormalised instant from a client in UTC+2
    /// would be a 500 rather than a saved symptom.
    ///
    /// <para><b>§G8: capped by today and NOTHING ELSE.</b> There is deliberately no
    /// <c>occurredOn &lt; day.BackdateFloor</c> branch — D-13 gives a floor to <c>cycle_events</c>
    /// alone, and adding one here would reject the historical logging it explicitly permits. The
    /// comparison is on the derived DAY, so an instant later today is fine and a phone whose clock runs
    /// fast does not lose its user's entry.</para>
    /// </remarks>
    private (DateTimeOffset At, DateOnly On) NormalizeInstant(
        DateTimeOffset supplied,
        UserDayInfo day,
        string field,
        List<SymptomFieldError> errors)
    {
        var occurredAt = supplied.ToUniversalTime();
        var occurredOn = dayResolver.ToUserDay(occurredAt, day.TimezoneId);

        if (occurredOn > day.Today)
            errors.Add(new SymptomFieldError(field, ValidationMessages.FutureDate));

        return (occurredAt, occurredOn);
    }

    /// <summary>
    /// Trims the note and bounds it by the shared D-13 cap, returning <see langword="null"/> for absent
    /// or blank text. Trim first: the cap bounds the note, not a trailing newline.
    /// </summary>
    private static string? NormalizeNotes(string? supplied, string field, List<SymptomFieldError> errors)
    {
        var notes = supplied?.Trim();

        if (notes is { Length: > FieldLimits.MaxNotesLength })
            errors.Add(new SymptomFieldError(field, ValidationMessages.MaxLength(FieldLimits.MaxNotesLength)));

        return notes is { Length: > 0 } ? notes : null;
    }

    /// <summary>
    /// Validates each member of a vocabulary array against <paramref name="vocabulary"/>, then returns
    /// the accepted set <b>de-duplicated and in canonical vocabulary order</b>.
    /// </summary>
    /// <remarks>
    /// Two properties matter downstream. <b>Canonical order</b> means the stored array is a
    /// deterministic function of the SET the user chose, so P6 never has to normalise order or
    /// duplicates out of stored data and two rows recording the same qualities compare equal — chip
    /// order is UI noise, not an observation. <b>Empty, never NULL</b>: an absent array is <c>{}</c>,
    /// matching the entity's <c>= []</c> and keeping "the user classified nothing" a single state.
    /// Errors are keyed per member (<c>painTypes[1]</c>) because the client renders these as chips and
    /// has to know which one to flag.
    /// </remarks>
    private static List<string> NormalizeVocabularyList(
        IReadOnlyList<string>? supplied,
        IReadOnlyList<string> vocabulary,
        string path,
        List<SymptomFieldError> errors)
    {
        if (supplied is null or { Count: 0 }) return [];

        var accepted = new HashSet<string>(StringComparer.Ordinal);

        for (var j = 0; j < supplied.Count; j++)
        {
            var member = supplied[j]?.Trim();

            if (string.IsNullOrEmpty(member))
                errors.Add(new SymptomFieldError($"{path}[{j}]", ValidationMessages.Required));
            else if (!vocabulary.Contains(member, StringComparer.Ordinal))
                errors.Add(new SymptomFieldError($"{path}[{j}]", ValidationMessages.NotAllowedValue));
            else
                accepted.Add(member);
        }

        return [.. vocabulary.Where(accepted.Contains)];
    }

    /// <summary>
    /// One entry after validation and normalisation: every field is already in the shape the column
    /// takes, so the staging loop above is a straight copy and cannot re-introduce a rule.
    /// </summary>
    private sealed record NormalizedEntry(
        string SymptomCode,
        short Intensity,
        string Region,
        string? Side,
        List<string> PainTypes,
        List<string> Triggers,
        DateTimeOffset OccurredAt,
        DateOnly OccurredOn,
        string? Notes);
}
