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
/// <c>PUT /symptoms/{id}</c> and <c>DELETE /symptoms/{id}</c> (T12), exercised through
/// <see cref="SymptomService"/> against the real model on Sqlite with the real
/// <c>AesGcmFieldCipher</c>, the real <c>UserDayResolver</c> and a frozen clock.
///
/// <para><b>The verb is <c>PUT</c>, and that is the point.</b> T11 decided a <c>symptoms</c> row is
/// FULL REPLACE — id-addressed, single-writer, and <i>clearing is the affordance</i>, because the
/// classification fields are toggle chips that a user must be able to switch back off. <c>PATCH</c>
/// has a defined meaning that full replace contradicts: a client author who sends only the changed
/// field would silently lose the rest. <c>PUT</c> says what actually happens, so the verb is a safety
/// affordance rather than a naming preference. (§C.3 is amended in this same commit.)</para>
///
/// <para><b>The replace rule has exactly two halves, and every test below is one of them.</b> A field
/// with an <i>unclassified</i> state — <c>region</c> (→ <c>unspecified</c>), <c>side</c> (→ null),
/// <c>painTypes</c>/<c>triggers</c> (→ empty), <c>notes</c> (→ null) — is <b>CLEARED</b> when omitted.
/// A field with <b>no</b> unclassified state — <c>intensity</c> and <c>occurredAt</c> — is
/// <b>REQUIRED</b>, so an omission is a 400 rather than a fabricated value. That second half is what
/// stops an edit from silently re-dating a five-year-old transcribed entry to today: the edit's clock
/// is not the episode's clock, and inventing one would write an observation the user never made.</para>
///
/// <para><b><c>symptomCode</c> is immutable by construction</b> — it is absent from
/// <see cref="ReplaceSymptomRequest"/> entirely, so there is no wire representation of the change.
/// Re-coding a <c>bloating</c> row into <c>pain</c> rewrites the identity of a series P6 will read;
/// the user action for that is delete and re-create.</para>
///
/// <para><b>Tenant isolation is 404, never 403</b> — a 403 would itself confirm the id exists.</para>
/// </summary>
public sealed class SymptomReplaceServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    private static readonly DateTimeOffset Yesterday = CycleTestHarness.Now.AddDays(-1);

    // --- helpers -----------------------------------------------------------------------------

    /// <summary>A fully-classified stored row, so a clear is distinguishable from a no-op.</summary>
    private async Task<Symptom> SeedFullRowAsync(Guid? userId = null, DateTimeOffset? deletedAt = null) =>
        _harness.SeedSymptom(
            Symptom.NonPainCodes.Bloating, 6, CycleTestHarness.Today.AddDays(-1),
            userId: userId,
            occurredAt: Yesterday,
            region: Symptom.Regions.Pelvis,
            side: Symptom.Sides.Back,
            painTypes: [Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Sharp],
            triggers: [Symptom.TriggerCodes.Stress],
            notesEnc: await _harness.Crypto.EncryptStringAsync("nota original"),
            deletedAt: deletedAt);

    private static ReplaceSymptomRequest Replace(
        int? intensity = 6,
        string? region = null,
        string? side = null,
        IReadOnlyList<string>? painTypes = null,
        IReadOnlyList<string>? triggers = null,
        DateTimeOffset? occurredAt = null,
        string? notes = null) =>
        new(intensity, region, side, painTypes, triggers, occurredAt ?? Yesterday, notes);

    private SymptomService Service(UserDayInfo? info = null, bool erased = false) =>
        _harness.NewSymptomService(erased ? null : info ?? _harness.DayInfo());

    private Task<SymptomReplaceResult> ReplaceAsync(Guid id, ReplaceSymptomRequest request, bool erased = false) =>
        Service(erased: erased).ReplaceAsync(id, request, CancellationToken.None);

    private static SymptomResponse Saved(SymptomReplaceResult result) =>
        result.ShouldBeOfType<SymptomReplaceResult.Saved>().Symptom;

    private static IReadOnlyList<string> MessagesFor(SymptomReplaceResult result, string field) =>
        result.ShouldBeOfType<SymptomReplaceResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private Symptom Stored(Guid id) =>
        _harness.NewContext().Symptoms.IgnoreQueryFilters().AsNoTracking().Single(s => s.Id == id);

    // --- the happy path: every mutable field really is replaced ------------------------------------

    [Fact]
    public async Task Every_mutable_field_is_replaced()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(
            intensity: 9,
            region: Symptom.Regions.LowerBack,
            side: Symptom.Sides.Front,
            painTypes: [Symptom.PainTypeCodes.Burning],
            triggers: [Symptom.TriggerCodes.Exercise, Symptom.TriggerCodes.Food],
            occurredAt: CycleTestHarness.Now,
            notes: "  ahora quema  "));

        var item = Saved(result);
        item.Id.ShouldBe(row.Id);
        item.Intensity.ShouldBe(9);
        item.Region.ShouldBe(Symptom.Regions.LowerBack);
        item.Side.ShouldBe(Symptom.Sides.Front);
        item.PainTypes.ShouldBe([Symptom.PainTypeCodes.Burning]);
        item.Triggers.ShouldBe([Symptom.TriggerCodes.Food, Symptom.TriggerCodes.Exercise],
            "arrays come back in canonical vocabulary order, not request order");
        item.OccurredAt.ShouldBe(CycleTestHarness.Now);
        item.OccurredOn.ShouldBe(CycleTestHarness.Today);
        item.Notes.ShouldBe("ahora quema");
    }

    [Fact]
    public async Task The_row_keeps_its_id_and_its_original_created_at_and_bumps_updated_at()
    {
        var row = await SeedFullRowAsync();
        var later = CycleTestHarness.Now.AddHours(5);

        var result = await Service(_harness.DayInfo(now: later))
            .ReplaceAsync(row.Id, Replace(intensity: 2), CancellationToken.None);

        var item = Saved(result);
        item.CreatedAt.ShouldBe(CycleTestHarness.Now, "CreatedAt belongs to the observation, not to this edit");
        item.UpdatedAt.ShouldBe(later);

        var stored = Stored(row.Id);
        stored.CreatedAt.ShouldBe(CycleTestHarness.Now);
        stored.UpdatedAt.ShouldBe(later);
        stored.DeletedAt.ShouldBeNull();
    }

    [Fact]
    public async Task A_replace_writes_no_second_row()
    {
        var row = await SeedFullRowAsync();

        await ReplaceAsync(row.Id, Replace(intensity: 1));

        _harness.NewContext().Symptoms.IgnoreQueryFilters()
            .Count(s => s.UserId == _harness.UserId).ShouldBe(1);
    }

    // --- HALF ONE OF THE RULE: an omitted "unclassified-able" field CLEARS ----------------------------

    [Fact]
    public async Task An_omitted_side_CLEARS_the_stored_side()
    {
        // DELIBERATE, and pinned here so it can never become an accident. `side` has a real
        // unclassified state (a null column), so under full replace an omission means "the user did
        // not classify a side", exactly as it does on create.
        //
        // The COST is a client obligation, and it is stated on ReplaceSymptomRequest: screen 12
        // (symptom_form) has NO front/back control — its only path to `side` is a drill-in to screen 13
        // (body_map) — so a row located on the body map and then edited from screen 12 loses its side
        // unless the client re-hydrates the row and sends it back. That is why the alternative was
        // rejected: exempting `side` from the clear would make ONE field on a full-replace DTO silently
        // merge, with nothing on the wire and nothing in the generated Dart client to say so, and would
        // make `side` settable but never un-settable — the exact one-way ratchet that ruled MERGE out
        // for this row in the first place. The obligation is cheap to meet (GET /symptoms and both
        // write responses all carry `side`) and P4b has not been written yet.
        var row = await SeedFullRowAsync();
        row.Side.ShouldBe(Symptom.Sides.Back);

        var result = await ReplaceAsync(row.Id, Replace(side: null));

        Saved(result).Side.ShouldBeNull();
        Stored(row.Id).Side.ShouldBeNull();
    }

    [Fact]
    public async Task A_re_sent_side_SURVIVES_the_replace()
    {
        // The other half of the same contract: the client obligation is satisfiable, and this is the
        // round trip that proves it. Read the row, send `side` back unchanged, and it is still there.
        var row = await SeedFullRowAsync();

        var read = await Service().ListAsync(
            CycleTestHarness.Today.AddDays(-7), CycleTestHarness.Today, null, null, CancellationToken.None);
        var hydrated = read.ShouldBeOfType<SymptomListResult.Found>().Page.Items.Single();
        hydrated.Side.ShouldBe(Symptom.Sides.Back);

        // Screen 12 changes only the intensity, but echoes the whole row back — as PUT requires.
        var result = await ReplaceAsync(row.Id, Replace(
            intensity: 3,
            region: hydrated.Region,
            side: hydrated.Side,
            painTypes: hydrated.PainTypes,
            triggers: hydrated.Triggers,
            occurredAt: hydrated.OccurredAt,
            notes: hydrated.Notes));

        var item = Saved(result);
        item.Intensity.ShouldBe(3);
        item.Side.ShouldBe(Symptom.Sides.Back, "a re-sent side survives; this is the client's whole duty");
        item.Region.ShouldBe(Symptom.Regions.Pelvis);
        item.PainTypes.ShouldBe([Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Sharp]);
        item.Triggers.ShouldBe([Symptom.TriggerCodes.Stress]);
        item.Notes.ShouldBe("nota original");
        item.OccurredAt.ShouldBe(Yesterday);
        Stored(row.Id).Side.ShouldBe(Symptom.Sides.Back);
    }

    [Fact]
    public async Task A_blank_side_clears_it_exactly_as_an_absent_one_does()
    {
        var row = await SeedFullRowAsync();

        await ReplaceAsync(row.Id, Replace(side: "   "));

        Stored(row.Id).Side.ShouldBeNull();
    }

    [Fact]
    public async Task An_omitted_region_falls_back_to_unspecified()
    {
        var row = await SeedFullRowAsync();

        Saved(await ReplaceAsync(row.Id, Replace(region: null))).Region.ShouldBe(Symptom.Regions.Unspecified);
        Stored(row.Id).Region.ShouldBe(Symptom.Regions.Unspecified);
    }

    [Fact]
    public async Task An_omitted_pain_type_and_trigger_array_CLEARS_the_stored_ones()
    {
        // This is the case that decided the whole rule (T11): these are toggle chips. Under MERGE a
        // user could add "sharp" but never take it back off, and every classification would be one-way.
        var row = await SeedFullRowAsync();

        var item = Saved(await ReplaceAsync(row.Id, Replace(painTypes: null, triggers: null)));

        item.PainTypes.ShouldBeEmpty();
        item.Triggers.ShouldBeEmpty();

        var stored = Stored(row.Id);
        stored.PainTypes.ShouldBeEmpty();
        stored.Triggers.ShouldBeEmpty();
    }

    [Fact]
    public async Task An_empty_array_clears_exactly_as_an_absent_one_does()
    {
        var row = await SeedFullRowAsync();

        var item = Saved(await ReplaceAsync(row.Id, Replace(painTypes: [], triggers: [])));

        item.PainTypes.ShouldBeEmpty();
        item.Triggers.ShouldBeEmpty();
    }

    [Fact]
    public async Task Arrays_REPLACE_and_never_merge()
    {
        var row = await SeedFullRowAsync();
        row.PainTypes.ShouldBe([Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Sharp]);

        var item = Saved(await ReplaceAsync(row.Id, Replace(painTypes: [Symptom.PainTypeCodes.Dull])));

        item.PainTypes.ShouldBe([Symptom.PainTypeCodes.Dull]);
        Stored(row.Id).PainTypes.ShouldBe([Symptom.PainTypeCodes.Dull]);
    }

    [Fact]
    public async Task An_omitted_note_CLEARS_the_ciphertext_rather_than_leaving_it_in_the_column()
    {
        var row = await SeedFullRowAsync();

        Saved(await ReplaceAsync(row.Id, Replace(notes: null))).Notes.ShouldBeNull();
        Stored(row.Id).NotesEnc.ShouldBeNull("a cleared note must not survive as unreferenced ciphertext");
    }

    [Fact]
    public async Task A_blank_note_clears_it_rather_than_storing_ciphertext_of_nothing()
    {
        var row = await SeedFullRowAsync();

        await ReplaceAsync(row.Id, Replace(notes: "   "));

        Stored(row.Id).NotesEnc.ShouldBeNull();
    }

    // --- HALF TWO OF THE RULE: a field with NO unclassified state is REQUIRED ------------------------

    [Fact]
    public async Task Intensity_is_required_on_a_replace()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(intensity: null));

        MessagesFor(result, "intensity").ShouldBe([ValidationMessages.Required]);
        Stored(row.Id).Intensity.ShouldBe((short)6, "a rejected replace changes nothing");
    }

    [Fact]
    public async Task Intensity_zero_is_a_real_datum_on_a_replace_too()
    {
        var row = await SeedFullRowAsync();

        Saved(await ReplaceAsync(row.Id, Replace(intensity: 0))).Intensity.ShouldBe(0);
        Stored(row.Id).Intensity.ShouldBe((short)0);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(11)]
    [InlineData(40000)]
    public async Task Intensity_outside_the_scale_is_rejected(int intensity)
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(intensity: intensity));

        MessagesFor(result, "intensity").ShouldBe([ValidationMessages.Between(0, 10)]);
        Stored(row.Id).Intensity.ShouldBe((short)6);
    }

    [Fact]
    public async Task OccurredAt_is_REQUIRED_on_a_replace_so_an_edit_can_never_silently_re_date_the_episode()
    {
        // The asymmetry with CREATE is deliberate and is the whole reason this test exists. On create,
        // an absent instant defaults to `now` because the user is logging as it happens. On a replace
        // `now` is the time of the EDIT, not of the episode — defaulting to it would quietly move a
        // five-year-old transcribed diary entry to today, fabricating an observation the user never
        // made (§G6 in spirit: nothing clinical, and nothing invented, comes out of this write).
        // `occurredAt` has no "unclassified" state to fall back to, so the honest answer is a 400.
        var row = await SeedFullRowAsync();

        var result = await Service().ReplaceAsync(
            row.Id,
            new ReplaceSymptomRequest(5, null, null, null, null, null, null),
            CancellationToken.None);

        MessagesFor(result, "occurredAt").ShouldBe([ValidationMessages.Required]);

        var stored = Stored(row.Id);
        stored.OccurredAt.ShouldBe(Yesterday, "the stored instant is untouched");
        stored.OccurredOn.ShouldBe(CycleTestHarness.Today.AddDays(-1));
    }

    [Fact]
    public async Task A_future_local_day_is_rejected_on_a_replace()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(occurredAt: CycleTestHarness.Now.AddDays(1)));

        MessagesFor(result, "occurredAt").ShouldBe([ValidationMessages.FutureDate]);
    }

    [Fact]
    public async Task A_date_long_before_the_backdate_floor_is_ACCEPTED_on_a_replace()
    {
        // §G8: the floor is `cycle_events`-ONLY. Re-dating a symptom to five years ago is a user
        // correcting a transcribed paper diary, which is exactly the history D-13 permits.
        var row = await SeedFullRowAsync();
        var wellBeforeTheFloor = CycleTestHarness.Now.AddYears(-5);
        CycleTestHarness.Floor.ShouldBeGreaterThan(DateOnly.FromDateTime(wellBeforeTheFloor.UtcDateTime));

        var item = Saved(await ReplaceAsync(row.Id, Replace(occurredAt: wellBeforeTheFloor)));

        item.OccurredOn.ShouldBe(CycleTestHarness.Today.AddYears(-5));
    }

    [Fact]
    public async Task OccurredOn_is_re_derived_from_the_new_instant_in_the_users_zone()
    {
        // D-12: the day key is never client-supplied, on a replace no less than on a create.
        var row = await SeedFullRowAsync();
        var nowUtc = new DateTimeOffset(2026, 8, 6, 20, 0, 0, TimeSpan.Zero);
        var aucklandToday = new DateOnly(2026, 8, 7);
        var info = new UserDayInfo(_harness.UserId, aucklandToday, CycleTestHarness.Floor, "Pacific/Auckland", nowUtc);

        var result = await Service(info).ReplaceAsync(row.Id, Replace(occurredAt: nowUtc), CancellationToken.None);

        Saved(result).OccurredOn.ShouldBe(aucklandToday);
        Stored(row.Id).OccurredOn.ShouldBe(aucklandToday);
    }

    [Fact]
    public async Task A_supplied_instant_is_normalised_to_offset_zero()
    {
        // MANDATORY: Npgsql throws on a non-zero offset for a `timestamptz` parameter.
        var row = await SeedFullRowAsync();
        var madridEvening = new DateTimeOffset(2026, 8, 5, 22, 15, 0, TimeSpan.FromHours(2));

        var item = Saved(await ReplaceAsync(row.Id, Replace(occurredAt: madridEvening)));

        item.OccurredAt.Offset.ShouldBe(TimeSpan.Zero);
        Stored(row.Id).OccurredAt.ShouldBe(madridEvening.ToUniversalTime());
    }

    // --- symptomCode is immutable BY CONSTRUCTION ------------------------------------------------------

    [Fact]
    public void The_replace_request_carries_no_symptom_code_at_all()
    {
        // Not "the service ignores it" — there is no wire representation of the change, so no client
        // can express it and no future edit to the service can quietly start honouring it. Re-coding a
        // `bloating` row into `pain` rewrites the identity of a series P6 will read; the user action
        // for that is delete and re-create.
        typeof(ReplaceSymptomRequest).GetProperties().Select(p => p.Name)
            .ShouldNotContain(nameof(SymptomResponse.SymptomCode));
    }

    [Fact]
    public async Task A_replace_leaves_the_symptom_code_untouched()
    {
        var row = await SeedFullRowAsync();

        Saved(await ReplaceAsync(row.Id, Replace(intensity: 1))).SymptomCode
            .ShouldBe(Symptom.NonPainCodes.Bloating);
        Stored(row.Id).SymptomCode.ShouldBe(Symptom.NonPainCodes.Bloating);
    }

    // --- vocabularies, keyed FLAT (no `entries[i]` prefix — this is a single-row endpoint) --------------

    [Fact]
    public async Task An_unknown_region_is_rejected_under_a_flat_field_key()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(region: "abdomen"));

        MessagesFor(result, "region").ShouldBe([ValidationMessages.NotAllowedValue]);
        Stored(row.Id).Region.ShouldBe(Symptom.Regions.Pelvis);
    }

    [Theory]
    [InlineData("left")]
    [InlineData("right")]
    public async Task Laterality_is_still_not_a_side(string side)
    {
        var row = await SeedFullRowAsync();

        MessagesFor(await ReplaceAsync(row.Id, Replace(side: side)), "side")
            .ShouldBe([ValidationMessages.NotAllowedValue]);
    }

    [Fact]
    public async Task An_unknown_pain_type_is_rejected_under_its_own_indexed_key()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(painTypes: [Symptom.PainTypeCodes.Sharp, "aching"]));

        MessagesFor(result, "painTypes[1]").ShouldBe([ValidationMessages.NotAllowedValue]);
    }

    [Fact]
    public async Task An_unknown_trigger_is_rejected_under_its_own_indexed_key()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(triggers: [Symptom.TriggerCodes.Food, "caffeine"]));

        MessagesFor(result, "triggers[1]").ShouldBe([ValidationMessages.NotAllowedValue]);
    }

    [Fact]
    public async Task Pain_types_are_de_duplicated_and_re_ordered_on_a_replace_too()
    {
        var row = await SeedFullRowAsync();

        var item = Saved(await ReplaceAsync(row.Id, Replace(painTypes:
            [Symptom.PainTypeCodes.Throbbing, Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Throbbing])));

        item.PainTypes.ShouldBe([Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Throbbing]);
    }

    [Fact]
    public async Task Every_error_across_the_request_is_reported_in_one_response()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(
            intensity: 99, region: "abdomen", side: "left", occurredAt: CycleTestHarness.Now.AddDays(2)));

        MessagesFor(result, "intensity").ShouldBe([ValidationMessages.Between(0, 10)]);
        MessagesFor(result, "region").ShouldBe([ValidationMessages.NotAllowedValue]);
        MessagesFor(result, "side").ShouldBe([ValidationMessages.NotAllowedValue]);
        MessagesFor(result, "occurredAt").ShouldBe([ValidationMessages.FutureDate]);
        Stored(row.Id).Intensity.ShouldBe((short)6, "a rejected replace writes nothing at all");
    }

    // --- notes: re-encrypted with a FRESH nonce ---------------------------------------------------------

    [Fact]
    public async Task A_replaced_note_is_re_encrypted_with_a_fresh_nonce()
    {
        var row = await SeedFullRowAsync();
        var before = Convert.ToBase64String(Stored(row.Id).NotesEnc!);

        // The SAME plaintext: only a fresh nonce can make the stored blob differ.
        await ReplaceAsync(row.Id, Replace(notes: "nota original"));

        var after = Stored(row.Id).NotesEnc!;
        Convert.ToBase64String(after).ShouldNotBe(before);
        Encoding.UTF8.GetString(after).ShouldNotContain("nota");
        (await _harness.Crypto.DecryptStringAsync(after)).ShouldBe("nota original");
    }

    [Fact]
    public async Task A_note_over_the_shared_limit_is_rejected_and_writes_nothing()
    {
        var row = await SeedFullRowAsync();

        var result = await ReplaceAsync(row.Id, Replace(notes: new string('a', FieldLimits.MaxNotesLength + 1)));

        MessagesFor(result, "notes").ShouldBe([ValidationMessages.MaxLength(FieldLimits.MaxNotesLength)]);
        Stored(row.Id).NotesEnc.ShouldNotBeNull();
    }

    // --- 404: unknown, tombstoned, ANOTHER USER'S, and erased ---------------------------------------------

    [Fact]
    public async Task An_unknown_id_is_not_found()
    {
        (await ReplaceAsync(Guid.NewGuid(), Replace())).ShouldBeOfType<SymptomReplaceResult.NotFound>();
    }

    [Fact]
    public async Task A_soft_deleted_row_cannot_be_replaced()
    {
        // The tombstone is hidden by the query filter, so a deleted row is indistinguishable from a
        // typo'd id — and a resurrection through PUT would defeat the delete.
        var row = await SeedFullRowAsync(deletedAt: CycleTestHarness.Now);

        (await ReplaceAsync(row.Id, Replace(intensity: 1))).ShouldBeOfType<SymptomReplaceResult.NotFound>();
        Stored(row.Id).Intensity.ShouldBe((short)6);
    }

    [Fact]
    public async Task Another_users_row_is_404_and_is_left_untouched()
    {
        // THE tenant-isolation test for this verb. 404, never 403: a 403 would itself confirm that the
        // id exists, which is the disclosure the status code is chosen to avoid.
        var theirs = await SeedFullRowAsync(userId: _harness.OtherUserId);

        var result = await ReplaceAsync(theirs.Id, Replace(intensity: 10, notes: "intruso"));

        result.ShouldBeOfType<SymptomReplaceResult.NotFound>();

        var stored = Stored(theirs.Id);
        stored.Intensity.ShouldBe((short)6);
        stored.Side.ShouldBe(Symptom.Sides.Back);
        stored.UserId.ShouldBe(_harness.OtherUserId);
        (await _harness.Crypto.DecryptStringAsync(stored.NotesEnc!)).ShouldBe("nota original");
    }

    [Fact]
    public async Task A_crypto_shredded_user_cannot_replace_and_is_rejected_BEFORE_validation()
    {
        var row = await SeedFullRowAsync();

        // A wholly invalid body: if validation ran first this would be Invalid, not NotFound.
        var result = await ReplaceAsync(
            row.Id, new ReplaceSymptomRequest(999, "abdomen", "left", null, null, null, null), erased: true);

        result.ShouldBeOfType<SymptomReplaceResult.NotFound>();
        Stored(row.Id).Intensity.ShouldBe((short)6);
    }

    // --- DELETE: soft, 204, and 404 for everything else -----------------------------------------------------

    [Fact]
    public async Task Delete_soft_deletes_the_row_and_leaves_it_in_the_table()
    {
        var row = await SeedFullRowAsync();
        var later = CycleTestHarness.Now.AddHours(2);

        var result = await Service(_harness.DayInfo(now: later)).DeleteAsync(row.Id, CancellationToken.None);

        result.ShouldBeOfType<SymptomDeleteResult.Deleted>();

        var stored = Stored(row.Id);
        stored.DeletedAt.ShouldBe(later, "D-13 soft delete: never ExecuteDeleteAsync");
        stored.UpdatedAt.ShouldBe(later);
        stored.Intensity.ShouldBe((short)6, "the data is tombstoned, not erased");
    }

    [Fact]
    public async Task A_second_delete_is_not_found()
    {
        var row = await SeedFullRowAsync();

        (await Service().DeleteAsync(row.Id, CancellationToken.None)).ShouldBeOfType<SymptomDeleteResult.Deleted>();
        (await Service().DeleteAsync(row.Id, CancellationToken.None)).ShouldBeOfType<SymptomDeleteResult.NotFound>();
    }

    [Fact]
    public async Task Deleting_an_unknown_id_is_not_found()
    {
        (await Service().DeleteAsync(Guid.NewGuid(), CancellationToken.None))
            .ShouldBeOfType<SymptomDeleteResult.NotFound>();
    }

    [Fact]
    public async Task One_user_cannot_delete_another_users_row()
    {
        var theirs = await SeedFullRowAsync(userId: _harness.OtherUserId);

        (await Service().DeleteAsync(theirs.Id, CancellationToken.None))
            .ShouldBeOfType<SymptomDeleteResult.NotFound>();

        Stored(theirs.Id).DeletedAt.ShouldBeNull("the owner's row must be untouched");
    }

    [Fact]
    public async Task A_crypto_shredded_user_cannot_delete()
    {
        var row = await SeedFullRowAsync();

        (await Service(erased: true).DeleteAsync(row.Id, CancellationToken.None))
            .ShouldBeOfType<SymptomDeleteResult.NotFound>();

        Stored(row.Id).DeletedAt.ShouldBeNull();
    }

    [Fact]
    public async Task A_deleted_row_can_still_be_re_created_because_symptoms_has_no_natural_key()
    {
        // §G9 does NOT apply to `symptoms`: it is an APPEND table whose only unique key is the primary
        // key, so there is no tombstone to revive and no `IgnoreQueryFilters()` lookup on the write
        // path. Logging the same episode again is simply a new row — which is also why neither the
        // create nor these two operations use `ConcurrencyRetry` (T11's rule 6): with no natural key
        // there is no unique-key race to lose.
        var row = await SeedFullRowAsync();
        await Service().DeleteAsync(row.Id, CancellationToken.None);

        var again = await Service().CreateAsync(
            new CreateSymptomsRequest([new SymptomEntryInput(
                Symptom.NonPainCodes.Bloating, 6, Symptom.Regions.Pelvis, Symptom.Sides.Back,
                null, null, Yesterday, null)]),
            CancellationToken.None);

        again.ShouldBeOfType<SymptomCreateResult.Saved>().Created.Items.Single().Id.ShouldNotBe(row.Id);
        _harness.NewContext().Symptoms.IgnoreQueryFilters()
            .Count(s => s.UserId == _harness.UserId).ShouldBe(2);
    }
}
