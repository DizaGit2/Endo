using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Application.Time;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;

namespace Lumen.Api.Symptoms;

/// <summary>
/// The §C.3 symptom write surface: <c>POST /symptoms</c>, the all-or-nothing batch create behind
/// screen 12's "Save symptom" and screen 13's "Save body map". Registered scoped, alongside the
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

            items.Add(new SymptomResponse(
                row.Id,
                row.SymptomCode,
                row.Intensity,
                row.Region,
                row.Side,
                row.PainTypes,
                row.Triggers,
                row.OccurredAt,
                row.OccurredOn,
                entry.Notes, // echoed from the plaintext: the column holds only ciphertext
                row.CreatedAt,
                row.UpdatedAt));
        }

        // Rule 7: one save for the whole batch, so the database enforces all-or-nothing too.
        await db.SaveChangesAsync(ct);

        return new SymptomCreateResult.Saved(new CreateSymptomsResponse(items));
    }

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

        // The one genuinely required datum besides the date. `is not { }` and never a falsiness test:
        // intensity 0 is a real answer (D-08, rule 5).
        short? intensity = null;
        if (entry.Intensity is not { } suppliedIntensity)
        {
            errors.Add(new SymptomFieldError($"{path}.intensity", ValidationMessages.Required));
        }
        else if (suppliedIntensity < Symptom.IntensityScale.Min || suppliedIntensity > Symptom.IntensityScale.Max)
        {
            errors.Add(new SymptomFieldError(
                $"{path}.intensity",
                ValidationMessages.Between(Symptom.IntensityScale.Min, Symptom.IntensityScale.Max)));
        }
        else
        {
            // Narrowed only after the range check, so the `int?` request type is what protects the
            // cast: a client sending 40000 gets a message on this field, not a wrapped-around value.
            intensity = (short)suppliedIntensity;
        }

        var region = entry.Region?.Trim();
        if (string.IsNullOrEmpty(region))
            region = Symptom.Regions.Default;
        else if (!Symptom.Regions.All.Contains(region, StringComparer.Ordinal))
            errors.Add(new SymptomFieldError($"{path}.region", ValidationMessages.NotAllowedValue));

        // Anatomical front/back, NOT laterality. Blank is "not classified", which is a null column
        // rather than an empty string — an empty string would be a third state nothing reads.
        var side = entry.Side?.Trim();
        if (string.IsNullOrEmpty(side))
            side = null;
        else if (!Symptom.Sides.All.Contains(side, StringComparer.Ordinal))
            errors.Add(new SymptomFieldError($"{path}.side", ValidationMessages.NotAllowedValue));

        var painTypes = NormalizeVocabularyList(
            entry.PainTypes, Symptom.PainTypeCodes.All, $"{path}.painTypes", errors);
        var triggers = NormalizeVocabularyList(
            entry.Triggers, Symptom.TriggerCodes.All, $"{path}.triggers", errors);

        // MANDATORY, not cosmetic: Npgsql throws on a non-zero offset for a `timestamptz` parameter,
        // so an unnormalised instant from a client in UTC+2 would be a 500 rather than a saved symptom.
        var occurredAt = (entry.OccurredAt ?? now).ToUniversalTime();
        // D-12: the day key is the USER's day, computed server-side and never client-supplied.
        var occurredOn = dayResolver.ToUserDay(occurredAt, day.TimezoneId);

        // §G8, rule 3: capped by today and NOTHING ELSE. There is deliberately no
        // `occurredOn < day.BackdateFloor` branch here, and adding one would reject the historical
        // logging D-13 permits. The comparison is on the derived DAY, so an instant later today is fine.
        if (occurredOn > day.Today)
            errors.Add(new SymptomFieldError($"{path}.occurredAt", ValidationMessages.FutureDate));

        // Trim first: the cap bounds the note, not a trailing newline.
        var notes = entry.Notes?.Trim();
        if (notes is { Length: > FieldLimits.MaxNotesLength })
            errors.Add(new SymptomFieldError($"{path}.notes", ValidationMessages.MaxLength(FieldLimits.MaxNotesLength)));

        if (intensity is not { } value) return null;

        return new NormalizedEntry(
            code,
            value,
            region,
            side,
            painTypes,
            triggers,
            occurredAt,
            occurredOn,
            notes is { Length: > 0 } ? notes : null);
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
