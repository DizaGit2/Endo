using System.Text;
using Lumen.Api.Symptoms;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Symptoms;

/// <summary>
/// <c>POST /symptoms</c> (screens 12 and 13), exercised through <see cref="SymptomService"/> against
/// the real model on Sqlite with the real <c>AesGcmFieldCipher</c>, the real
/// <c>UserDayResolver</c> and a frozen clock.
///
/// <para><b>This endpoint is a BATCH, and that is a product decision, not an optimisation</b>
/// (OQ-6). D-09 makes one user action inherently multi-row — screen 12's single "Save symptom" writes
/// the pain row <i>plus one row per RELATED chip</i>, and screen 13's "Save body map" writes one row
/// per placed point — and the client is online-only with no write queue. N requests per save would
/// let a dropped connection leave half an episode recorded, which is worse than no record at all
/// because the user believes it saved. So the whole save is one request, <b>all-or-nothing</b>: one
/// invalid entry rejects the batch and writes nothing.</para>
///
/// <para><b>Classification is ALWAYS optional</b> (D-09). Only <c>intensity</c> and the date are
/// required; region, side, pain types and triggers may all be absent, and <c>intensity: 0</c> is a
/// real datum (D-08), never an absence. <b>No clinical rule comes near this write</b> (§G6/§G7):
/// observed data is never clinically validated, and there are no cross-field rules at all — pain
/// types and triggers are accepted on every symptom code.</para>
///
/// <para><b>§G8 — there is NO backdate floor here.</b> The floor belongs to <c>cycle_events</c> and
/// nothing else; a symptom write is capped by the user's local today alone. Transcribing a paper
/// diary from five years ago is the exact use case D-13 permits.</para>
/// </summary>
public sealed class SymptomServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    // --- helpers -----------------------------------------------------------------------------

    private static SymptomEntryInput Entry(
        string? symptomCode = null,
        int? intensity = 5,
        string? region = null,
        string? side = null,
        IReadOnlyList<string>? painTypes = null,
        IReadOnlyList<string>? triggers = null,
        DateTimeOffset? occurredAt = null,
        string? notes = null) =>
        new(symptomCode, intensity, region, side, painTypes, triggers, occurredAt, notes);

    private Task<SymptomCreateResult> CreateAsync(params SymptomEntryInput[] entries) =>
        _harness.NewSymptomService()
            .CreateAsync(new CreateSymptomsRequest(entries), CancellationToken.None);

    private Task<SymptomCreateResult> CreateAsync(CreateSymptomsRequest request, UserDayInfo? info = null) =>
        _harness.NewSymptomService(info ?? _harness.DayInfo())
            .CreateAsync(request, CancellationToken.None);

    private static IReadOnlyList<string> MessagesFor(SymptomCreateResult result, string field) =>
        result.ShouldBeOfType<SymptomCreateResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private static IReadOnlyList<SymptomResponse> Saved(SymptomCreateResult result) =>
        result.ShouldBeOfType<SymptomCreateResult.Saved>().Created.Items;

    /// <summary>Every row of the caller's, tombstones included — the "wrote nothing" assertion.</summary>
    private int AllSymptomCount() =>
        _harness.NewContext().Symptoms.IgnoreQueryFilters().Count(s => s.UserId == _harness.UserId);

    private Symptom StoredRow() =>
        _harness.NewContext().Symptoms.IgnoreQueryFilters().Single(s => s.UserId == _harness.UserId);

    private IReadOnlyList<Symptom> StoredRows() =>
        _harness.NewContext().Symptoms.IgnoreQueryFilters()
            .Where(s => s.UserId == _harness.UserId).ToList();

    // --- the batch envelope (§G11: 1–50 is a P4a INVENTION, not a ratified number) --------------

    [Fact]
    public async Task A_single_entry_batch_is_accepted()
    {
        // The lower boundary of the invented 1–50 cap.
        var result = await CreateAsync(Entry(intensity: 7));

        Saved(result).Count.ShouldBe(1);
        AllSymptomCount().ShouldBe(1);
    }

    [Fact]
    public async Task A_fifty_entry_batch_is_accepted()
    {
        // The upper boundary. 50 is inclusive — the cap rejects 51, not 50.
        var entries = Enumerable.Range(0, SymptomBatch.MaxEntries).Select(_ => Entry()).ToArray();

        var result = await CreateAsync(new CreateSymptomsRequest(entries));

        Saved(result).Count.ShouldBe(SymptomBatch.MaxEntries);
        AllSymptomCount().ShouldBe(SymptomBatch.MaxEntries);
    }

    [Fact]
    public async Task A_fifty_one_entry_batch_is_rejected_and_writes_nothing()
    {
        var entries = Enumerable.Range(0, SymptomBatch.MaxEntries + 1).Select(_ => Entry()).ToArray();

        var result = await CreateAsync(new CreateSymptomsRequest(entries));

        MessagesFor(result, "entries").ShouldBe([SymptomValidationMessages.MaxEntries(SymptomBatch.MaxEntries)]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task An_empty_entries_array_is_rejected()
    {
        // Distinct from an absent array: the client sent a save with nothing in it, which is a bug on
        // its side rather than a malformed body. A 201 with zero items would be a silent no-op.
        var result = await CreateAsync(new CreateSymptomsRequest([]));

        MessagesFor(result, "entries").ShouldBe([SymptomValidationMessages.BatchEmpty]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task An_absent_entries_array_is_rejected()
    {
        var result = await CreateAsync(new CreateSymptomsRequest(null));

        MessagesFor(result, "entries").ShouldBe([ValidationMessages.Required]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_null_entry_element_is_rejected_rather_than_dereferenced()
    {
        // `entries: [null]` is legal JSON. Dereferencing it would be a 500 for malformed input.
        var result = await CreateAsync(Entry(), null!);

        MessagesFor(result, "entries[1]").ShouldBe([ValidationMessages.Required]);
        AllSymptomCount().ShouldBe(0);
    }

    // --- ALL-OR-NOTHING ------------------------------------------------------------------------

    [Fact]
    public async Task One_invalid_entry_rejects_the_whole_batch_and_writes_nothing()
    {
        // The heart of OQ-6. Screen 12 saves pain + two RELATED chips as three rows; if the middle
        // one is bad, the user must get their form back with the error, not a half-recorded episode
        // that reads as a complete one forever after.
        var result = await CreateAsync(
            Entry(symptomCode: Symptom.Codes.Pain, intensity: 6),
            Entry(symptomCode: Symptom.NonPainCodes.Bloating, intensity: 99),
            Entry(symptomCode: Symptom.NonPainCodes.Nausea, intensity: 3));

        MessagesFor(result, "entries[1].intensity").ShouldBe([ValidationMessages.Between(0, 10)]);
        AllSymptomCount().ShouldBe(0, "a rejected batch writes no row at all, not the valid two");
    }

    [Fact]
    public async Task Every_entrys_errors_are_reported_in_one_response()
    {
        // Validate-then-act (T3): the user fixes the whole form in one round trip, and because
        // nothing is written until every entry passes, a late rejection cannot half-save.
        var result = await CreateAsync(
            Entry(intensity: null),
            Entry(intensity: 4, region: "left_knee"),
            Entry(intensity: 4, side: "left"));

        MessagesFor(result, "entries[0].intensity").ShouldBe([ValidationMessages.Required]);
        MessagesFor(result, "entries[1].region").ShouldBe([ValidationMessages.NotAllowedValue]);
        MessagesFor(result, "entries[2].side").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllSymptomCount().ShouldBe(0);
    }

    // --- D-09: RELATED symptoms are their OWN rows ----------------------------------------------

    [Fact]
    public async Task One_save_writes_one_row_per_entry_in_request_order()
    {
        var result = await CreateAsync(
            Entry(symptomCode: Symptom.Codes.Pain, intensity: 8, region: Symptom.Regions.Pelvis),
            Entry(symptomCode: Symptom.NonPainCodes.Bloating, intensity: 4),
            Entry(symptomCode: Symptom.NonPainCodes.Fatigue, intensity: 6));

        var items = Saved(result);
        items.Select(i => i.SymptomCode)
            .ShouldBe([Symptom.Codes.Pain, Symptom.NonPainCodes.Bloating, Symptom.NonPainCodes.Fatigue]);
        items.Select(i => i.Id).Distinct().Count().ShouldBe(3, "each row gets its own id");
        AllSymptomCount().ShouldBe(3);
    }

    // --- intensity: required, 0–10, and 0 IS a datum ---------------------------------------------

    [Fact]
    public async Task Intensity_is_required()
    {
        var result = await CreateAsync(Entry(intensity: null));

        MessagesFor(result, "entries[0].intensity").ShouldBe([ValidationMessages.Required]);
        AllSymptomCount().ShouldBe(0);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(11)]
    public async Task Intensity_outside_the_0_to_10_scale_is_rejected(int intensity)
    {
        var result = await CreateAsync(Entry(intensity: intensity));

        MessagesFor(result, "entries[0].intensity").ShouldBe([ValidationMessages.Between(0, 10)]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task Intensity_zero_is_a_real_datum_and_is_stored_as_zero()
    {
        // D-08/NRS-11. Coalescing 0 into "absent" would reject "it barely registered today" and leave
        // P6 with a series that only ever contains bad days.
        var result = await CreateAsync(Entry(intensity: 0));

        Saved(result).Single().Intensity.ShouldBe(0);
        StoredRow().Intensity.ShouldBe((short)0);
    }

    [Fact]
    public async Task A_value_far_outside_short_range_reaches_the_validator_rather_than_overflowing()
    {
        // The request DTO carries `int?`, not `short?`. With `short?` the binder would reject 40000
        // before the validator ever saw it, and the client would get the framework's unbindable-body
        // 400 under `request` instead of a message attached to the intensity input.
        var result = await CreateAsync(Entry(intensity: 40000));

        MessagesFor(result, "entries[0].intensity").ShouldBe([ValidationMessages.Between(0, 10)]);
        AllSymptomCount().ShouldBe(0);
    }

    // --- symptomCode: 21 members, default `pain`, ordinal ------------------------------------------

    [Fact]
    public async Task An_absent_symptom_code_defaults_to_pain()
    {
        var result = await CreateAsync(Entry(symptomCode: null));

        Saved(result).Single().SymptomCode.ShouldBe(Symptom.Codes.Pain);
        StoredRow().SymptomCode.ShouldBe("pain");
    }

    [Fact]
    public async Task A_blank_symptom_code_defaults_to_pain()
    {
        var result = await CreateAsync(Entry(symptomCode: "   "));

        Saved(result).Single().SymptomCode.ShouldBe(Symptom.Codes.Pain);
    }

    [Fact]
    public async Task Every_ratified_symptom_code_is_accepted()
    {
        // All 21 (§G10: `pain` plus the 20-member non-pain catalogue), in one batch — which also
        // proves the cap accepts a realistic multi-chip save.
        var entries = Symptom.Codes.All.Select(code => Entry(symptomCode: code)).ToArray();

        var result = await CreateAsync(new CreateSymptomsRequest(entries));

        Saved(result).Select(i => i.SymptomCode).ShouldBe(Symptom.Codes.All);
        Symptom.Codes.All.Count.ShouldBe(21);
    }

    [Theory]
    [InlineData("Pain")]
    [InlineData("PAIN")]
    [InlineData("brainFog")]
    public async Task A_wrong_cased_symptom_code_is_rejected_with_no_fixup(string code)
    {
        // StringComparer.Ordinal throughout. Case-insensitive matching or a snake_case fixup would
        // let two spellings of one concept into the column, and the vocabulary is append-only —
        // stored rows carry these strings forever.
        var result = await CreateAsync(Entry(symptomCode: code));

        MessagesFor(result, "entries[0].symptomCode").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task An_unknown_symptom_code_is_rejected()
    {
        var result = await CreateAsync(Entry(symptomCode: "aching"));

        MessagesFor(result, "entries[0].symptomCode").ShouldBe([ValidationMessages.NotAllowedValue]);
    }

    // --- region: 9 members, default `unspecified` ---------------------------------------------------

    [Fact]
    public async Task An_absent_region_defaults_to_unspecified()
    {
        var result = await CreateAsync(Entry(region: null));

        Saved(result).Single().Region.ShouldBe(Symptom.Regions.Unspecified);
        StoredRow().Region.ShouldBe("unspecified");
    }

    [Fact]
    public async Task Every_ratified_region_is_accepted()
    {
        var entries = Symptom.Regions.All.Select(region => Entry(region: region)).ToArray();

        var result = await CreateAsync(new CreateSymptomsRequest(entries));

        Saved(result).Select(i => i.Region).ShouldBe(Symptom.Regions.All);
        Symptom.Regions.All.Count.ShouldBe(9);
    }

    [Fact]
    public async Task An_unknown_region_is_rejected()
    {
        var result = await CreateAsync(Entry(region: "abdomen"));

        MessagesFor(result, "entries[0].region").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllSymptomCount().ShouldBe(0);
    }

    // --- side: front/back, NOT laterality --------------------------------------------------------

    [Theory]
    [InlineData(Symptom.Sides.Front)]
    [InlineData(Symptom.Sides.Back)]
    public async Task Both_ratified_sides_are_accepted(string side)
    {
        var result = await CreateAsync(Entry(side: side));

        Saved(result).Single().Side.ShouldBe(side);
    }

    [Theory]
    [InlineData("left")]
    [InlineData("right")]
    public async Task Laterality_is_not_a_side_and_is_rejected(string side)
    {
        // ARCHITECTURE.md:37,:51,:184 — the body map has a FRONT view and a BACK view. Laterality was
        // never part of the model, and accepting it would silently store an axis nothing can read.
        var result = await CreateAsync(Entry(side: side));

        MessagesFor(result, "entries[0].side").ShouldBe([ValidationMessages.NotAllowedValue]);
        Symptom.Sides.All.Count.ShouldBe(2);
    }

    [Fact]
    public async Task A_blank_side_is_stored_as_null_rather_than_as_an_empty_string()
    {
        var result = await CreateAsync(Entry(side: "  "));

        Saved(result).Single().Side.ShouldBeNull();
        StoredRow().Side.ShouldBeNull();
    }

    // --- painTypes / triggers: dedup, canonical order, never NULL ---------------------------------

    [Fact]
    public async Task Pain_types_are_de_duplicated_and_re_ordered_into_canonical_vocabulary_order()
    {
        // P6 must never have to normalise order or duplicates out of stored data, and two rows that
        // recorded the same qualities must compare equal.
        var result = await CreateAsync(Entry(painTypes:
            [Symptom.PainTypeCodes.Throbbing, Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Throbbing]));

        Saved(result).Single().PainTypes
            .ShouldBe([Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Throbbing]);
        StoredRow().PainTypes.ShouldBe(["cramping", "throbbing"]);
    }

    [Fact]
    public async Task Triggers_are_de_duplicated_and_re_ordered_into_canonical_vocabulary_order()
    {
        var result = await CreateAsync(Entry(triggers:
            [Symptom.TriggerCodes.Weather, Symptom.TriggerCodes.Stress, Symptom.TriggerCodes.Weather]));

        Saved(result).Single().Triggers
            .ShouldBe([Symptom.TriggerCodes.Stress, Symptom.TriggerCodes.Weather]);
        StoredRow().Triggers.ShouldBe(["stress", "weather"]);
    }

    [Fact]
    public async Task Absent_pain_types_and_triggers_are_stored_as_empty_collections_never_null()
    {
        var result = await CreateAsync(Entry(painTypes: null, triggers: null));

        var item = Saved(result).Single();
        item.PainTypes.ShouldBeEmpty();
        item.Triggers.ShouldBeEmpty();

        var row = StoredRow();
        row.PainTypes.ShouldNotBeNull();
        row.PainTypes.ShouldBeEmpty();
        row.Triggers.ShouldNotBeNull();
        row.Triggers.ShouldBeEmpty();
    }

    [Fact]
    public async Task Every_ratified_pain_type_and_trigger_is_accepted()
    {
        var result = await CreateAsync(Entry(
            painTypes: [.. Symptom.PainTypeCodes.All],
            triggers: [.. Symptom.TriggerCodes.All]));

        var item = Saved(result).Single();
        item.PainTypes.ShouldBe(Symptom.PainTypeCodes.All);
        item.Triggers.ShouldBe(Symptom.TriggerCodes.All);
        Symptom.PainTypeCodes.All.Count.ShouldBe(6);
        Symptom.TriggerCodes.All.Count.ShouldBe(7);
    }

    [Fact]
    public async Task An_unknown_pain_type_is_rejected_under_its_own_indexed_key()
    {
        // The client renders these as chips, so the message has to name WHICH chip.
        var result = await CreateAsync(Entry(painTypes: [Symptom.PainTypeCodes.Sharp, "aching"]));

        MessagesFor(result, "entries[0].painTypes[1]").ShouldBe([ValidationMessages.NotAllowedValue]);
        Symptom.PainTypeCodes.All.ShouldNotContain("aching");
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task An_unknown_trigger_is_rejected_under_its_own_indexed_key()
    {
        var result = await CreateAsync(Entry(triggers: [Symptom.TriggerCodes.Food, "caffeine"]));

        MessagesFor(result, "entries[0].triggers[1]").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_blank_pain_type_member_is_reported_as_required()
    {
        var result = await CreateAsync(Entry(painTypes: [" "]));

        MessagesFor(result, "entries[0].painTypes[0]").ShouldBe([ValidationMessages.Required]);
    }

    // --- classification is ALWAYS optional (D-09) ----------------------------------------------------

    [Fact]
    public async Task An_entry_carrying_only_an_intensity_is_accepted()
    {
        // The guardrail. Only intensity and the date are required; a user who taps "5" and saves has
        // recorded a valid symptom, and demanding a region or a pain type would be an entry blocker.
        var result = await CreateAsync(new CreateSymptomsRequest(
            [new SymptomEntryInput(null, 5, null, null, null, null, null, null)]));

        var item = Saved(result).Single();
        item.SymptomCode.ShouldBe(Symptom.Codes.Pain);
        item.Region.ShouldBe(Symptom.Regions.Unspecified);
        item.Side.ShouldBeNull();
        item.PainTypes.ShouldBeEmpty();
        item.Triggers.ShouldBeEmpty();
        item.Notes.ShouldBeNull();
        item.Intensity.ShouldBe(5);
    }

    [Fact]
    public async Task Pain_types_and_triggers_are_accepted_on_a_non_pain_code()
    {
        // §G6/§G7: NO cross-field rules. "Pain types only belong on `pain`" is a clinical judgement,
        // and observed data is never clinically validated — a user who says their bloating is
        // "cramping" has told us something true about their experience.
        var result = await CreateAsync(Entry(
            symptomCode: Symptom.NonPainCodes.Bloating,
            painTypes: [Symptom.PainTypeCodes.Cramping],
            triggers: [Symptom.TriggerCodes.Food]));

        var item = Saved(result).Single();
        item.SymptomCode.ShouldBe(Symptom.NonPainCodes.Bloating);
        item.PainTypes.ShouldBe([Symptom.PainTypeCodes.Cramping]);
    }

    // --- dates: §G8 (today-capped, NO floor) and D-12 (the user's day) --------------------------------

    [Fact]
    public async Task An_absent_occurredAt_defaults_to_the_requests_single_now()
    {
        var result = await CreateAsync(Entry(occurredAt: null));

        var item = Saved(result).Single();
        item.OccurredAt.ShouldBe(CycleTestHarness.Now);
        item.OccurredOn.ShouldBe(CycleTestHarness.Today);
    }

    [Fact]
    public async Task A_supplied_occurredAt_is_normalised_to_offset_zero()
    {
        // MANDATORY, not cosmetic: Npgsql throws on a non-zero offset for a `timestamptz` parameter,
        // so an unnormalised instant from a client in UTC+2 is a 500 rather than a saved symptom.
        var madridEvening = new DateTimeOffset(2026, 8, 5, 22, 15, 0, TimeSpan.FromHours(2));

        var result = await CreateAsync(Entry(occurredAt: madridEvening));

        var item = Saved(result).Single();
        item.OccurredAt.Offset.ShouldBe(TimeSpan.Zero);
        item.OccurredAt.ShouldBe(madridEvening.ToUniversalTime());
        StoredRow().OccurredAt.ShouldBe(madridEvening.ToUniversalTime());
    }

    [Fact]
    public async Task OccurredOn_is_the_users_local_day_not_the_utc_day()
    {
        // 2026-08-06 20:00Z is already the 7th in Auckland (UTC+12). Deriving occurredOn from the UTC
        // date would file every evening entry of every NZ user under the previous day, forever.
        var nowUtc = new DateTimeOffset(2026, 8, 6, 20, 0, 0, TimeSpan.Zero);
        var aucklandToday = new DateOnly(2026, 8, 7);
        var info = new UserDayInfo(_harness.UserId, aucklandToday, CycleTestHarness.Floor, "Pacific/Auckland", nowUtc);

        var result = await CreateAsync(
            new CreateSymptomsRequest([Entry(occurredAt: nowUtc)]), info);

        var item = Saved(result).Single();
        item.OccurredOn.ShouldBe(aucklandToday);
        item.OccurredOn.ShouldNotBe(DateOnly.FromDateTime(nowUtc.UtcDateTime));
        StoredRow().OccurredOn.ShouldBe(aucklandToday);
    }

    [Fact]
    public async Task OccurredOn_is_never_client_supplied_and_is_derived_from_occurredAt()
    {
        var threeDaysBack = CycleTestHarness.Now.AddDays(-3);

        var result = await CreateAsync(Entry(occurredAt: threeDaysBack));

        Saved(result).Single().OccurredOn.ShouldBe(CycleTestHarness.Today.AddDays(-3));
    }

    [Fact]
    public async Task A_future_local_day_is_rejected()
    {
        var result = await CreateAsync(Entry(occurredAt: CycleTestHarness.Now.AddDays(1)));

        MessagesFor(result, "entries[0].occurredAt").ShouldBe([ValidationMessages.FutureDate]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_later_instant_on_the_users_today_is_accepted()
    {
        // The cap is at LOCAL-DAY granularity, not instant granularity. Now is 09:30Z = 11:30 in
        // Madrid; 21:00 local today is "later than now" but still today, and a phone whose clock runs
        // a few minutes fast must not have its user's morning entry rejected.
        var laterToday = new DateTimeOffset(2026, 8, 6, 19, 0, 0, TimeSpan.Zero);

        var result = await CreateAsync(Entry(occurredAt: laterToday));

        Saved(result).Single().OccurredOn.ShouldBe(CycleTestHarness.Today);
    }

    [Fact]
    public async Task A_date_long_before_the_backdate_floor_is_ACCEPTED()
    {
        // §G8, stated as a test because the neighbouring endpoint does the opposite. D-13 gives a
        // floor to `cycle_events` ALONE; a symptom five years back is a user transcribing a paper
        // diary, and rejecting it would lose real history. `BackdateFloor` must not be read here.
        var wellBeforeTheFloor = CycleTestHarness.Now.AddYears(-5);
        CycleTestHarness.Floor.ShouldBeGreaterThan(DateOnly.FromDateTime(wellBeforeTheFloor.UtcDateTime));

        var result = await CreateAsync(Entry(occurredAt: wellBeforeTheFloor));

        Saved(result).Single().OccurredOn.ShouldBe(CycleTestHarness.Today.AddYears(-5));
        AllSymptomCount().ShouldBe(1);
    }

    // --- notes: trimmed, capped at the SHARED limit, encrypted ---------------------------------------

    [Fact]
    public async Task A_note_is_trimmed_stored_as_ciphertext_and_echoed_back_in_plaintext()
    {
        var result = await CreateAsync(Entry(notes: "  dolor punzante al caminar  "));

        Saved(result).Single().Notes.ShouldBe("dolor punzante al caminar");

        var row = StoredRow();
        row.NotesEnc.ShouldNotBeNull();
        row.NotesEnc!.ShouldNotBe(Encoding.UTF8.GetBytes("dolor punzante al caminar"));
        (await _harness.Crypto.DecryptStringAsync(row.NotesEnc!)).ShouldBe("dolor punzante al caminar");
    }

    [Fact]
    public async Task A_blank_note_is_stored_as_null_rather_than_as_ciphertext_of_nothing()
    {
        var result = await CreateAsync(Entry(notes: "   "));

        Saved(result).Single().Notes.ShouldBeNull();
        StoredRow().NotesEnc.ShouldBeNull();
    }

    [Fact]
    public async Task A_note_at_exactly_the_shared_limit_is_accepted_after_trimming()
    {
        // The cap is measured on the TRIMMED plaintext: 2000 characters wrapped in whitespace is a
        // 2000-character note.
        var note = new string('a', FieldLimits.MaxNotesLength);

        var result = await CreateAsync(Entry(notes: $"  {note}  "));

        Saved(result).Single().Notes.ShouldBe(note);
    }

    [Fact]
    public async Task A_note_over_the_shared_limit_is_rejected_and_writes_nothing()
    {
        var result = await CreateAsync(Entry(notes: new string('a', FieldLimits.MaxNotesLength + 1)));

        MessagesFor(result, "entries[0].notes")
            .ShouldBe([ValidationMessages.MaxLength(FieldLimits.MaxNotesLength)]);
        AllSymptomCount().ShouldBe(0);
    }

    [Fact]
    public void The_note_cap_is_the_shared_one_not_a_symptoms_specific_copy()
    {
        // D-13 states ONE cap for every free-text note. `symptoms` is its third caller; a local copy
        // of `2000` could only drift, and because the number reaches the client inside a wire string
        // the drift would be a silent contract change rather than a compile error.
        FieldLimits.MaxNotesLength.ShouldBe(2000);
    }

    // --- timestamps ------------------------------------------------------------------------------------

    [Fact]
    public async Task Every_row_in_a_batch_is_stamped_with_the_requests_single_now()
    {
        var result = await CreateAsync(Entry(), Entry(), Entry());

        Saved(result).Count.ShouldBe(3);
        foreach (var row in StoredRows())
        {
            row.CreatedAt.ShouldBe(CycleTestHarness.Now);
            row.UpdatedAt.ShouldBe(CycleTestHarness.Now);
            row.DeletedAt.ShouldBeNull();
        }
    }

    // --- tenant scoping --------------------------------------------------------------------------------

    [Fact]
    public async Task Rows_are_written_for_the_caller_and_another_users_rows_are_untouched()
    {
        var theirs = _harness.SeedSymptom(
            Symptom.Codes.Pain, 2, CycleTestHarness.Today, userId: _harness.OtherUserId);

        await CreateAsync(Entry(intensity: 9));

        StoredRows().Count.ShouldBe(1);
        StoredRows().Single().UserId.ShouldBe(_harness.UserId);
        _harness.NewContext().Symptoms.Single(s => s.Id == theirs.Id).Intensity.ShouldBe((short)2);
    }

    // --- the erased-user fence (a SECURITY control, not a formality) --------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_create_symptoms()
    {
        // A shredded account's JWT stays cryptographically valid until it expires, and a child INSERT
        // takes only a share lock on `users` — it does not conflict with the shred job's UPDATE. This
        // 404 is the ONLY thing stopping an in-flight request from re-creating plaintext health rows
        // for a user who no longer exists.
        var result = await _harness.NewSymptomService(null)
            .CreateAsync(new CreateSymptomsRequest([Entry(intensity: 5)]), CancellationToken.None);

        result.ShouldBeOfType<SymptomCreateResult.UserNotFound>();
        _harness.NewContext().Symptoms.IgnoreQueryFilters().Count().ShouldBe(0);
    }

    [Fact]
    public async Task A_crypto_shredded_user_is_rejected_BEFORE_validation()
    {
        // Order matters: resolving the day context first is what makes the fence unconditional. If
        // validation ran first, a well-formed request from an erased account would still reach the
        // write path on any code path that skipped the check.
        var result = await _harness.NewSymptomService(null)
            .CreateAsync(new CreateSymptomsRequest(null), CancellationToken.None);

        result.ShouldBeOfType<SymptomCreateResult.UserNotFound>();
    }

    // --- frozen wire strings (§G12) -----------------------------------------------------------------------

    [Fact]
    public void The_symptom_batch_validation_messages_are_frozen()
    {
        // Every test above asserts THROUGH the constant, which pins the service to the constant but
        // pins the constant to nothing — reword the literal and they all stay green. These are wire
        // strings the Flutter client renders verbatim, so they are pinned against their literals
        // here, mirroring `CyclePhaseOverrideServiceTests.Cycle_validation_messages_are_frozen`.
        SymptomValidationMessages.QuickCheckinEmpty.ShouldBe("at least one of pain or mood is required");
        SymptomValidationMessages.BatchEmpty.ShouldBe("at least one entry is required");
        SymptomValidationMessages.MaxEntries(50).ShouldBe("a request may contain at most 50 entries");
    }

    [Fact]
    public void The_batch_size_limits_are_frozen()
    {
        // §G11: 1–50 is a P4a INVENTION, recorded so a later phase does not mistake it for a ratified
        // clinical or product number. It is a structural payload bound and nothing more.
        SymptomBatch.MinEntries.ShouldBe(1);
        SymptomBatch.MaxEntries.ShouldBe(50);
    }
}
