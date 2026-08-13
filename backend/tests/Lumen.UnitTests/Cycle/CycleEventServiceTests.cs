using System.Text;
using Lumen.Api.Cycle;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Cycle;

/// <summary>
/// <c>POST /cycle/events</c> and <c>DELETE /cycle/events/{id}</c>, exercised through
/// <see cref="CycleService"/> against the real model on Sqlite with the real
/// <c>AesGcmFieldCipher</c> and a frozen clock.
///
/// <para>Two behaviours here are load-bearing beyond this endpoint. <b>§G9:</b> <c>cycle_events</c>
/// carries an UNFILTERED unique index on <c>(UserId, Kind, OccurredOn)</c>, so the upsert must revive
/// a tombstone rather than insert a second row — a blind insert is a 500 the moment a user re-logs a
/// day they deleted. <b>The 404-on-null day context:</b> a crypto-shredded user's JWT stays
/// cryptographically valid until it expires and there is no write fence behind it, so this is the
/// only thing stopping an in-flight request from re-creating plaintext health rows after erasure.</para>
/// </summary>
public sealed class CycleEventServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    private static LogCycleEventRequest Request(
        string? kind = CycleEvent.Kinds.PeriodStart,
        DateOnly? occurredOn = null,
        int? flowIntensity = null,
        string? notes = null) =>
        new(kind, occurredOn ?? CycleTestHarness.Today, flowIntensity, notes);

    private static IReadOnlyList<string> MessagesFor(CycleEventResult result, string field) =>
        result.ShouldBeOfType<CycleEventResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private int LiveEventCount() => _harness.NewContext().CycleEvents.Count(e => e.UserId == _harness.UserId);

    private int AllEventCount() =>
        _harness.NewContext().CycleEvents.IgnoreQueryFilters().Count(e => e.UserId == _harness.UserId);

    // --- validation: kind ------------------------------------------------------------

    [Theory]
    [InlineData(CycleEvent.Kinds.PeriodStart)]
    [InlineData(CycleEvent.Kinds.PeriodEnd)]
    [InlineData(CycleEvent.Kinds.Spotting)]
    public async Task Every_ratified_kind_is_accepted(string kind)
    {
        var result = await _harness.NewService().LogEventAsync(Request(kind: kind), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Kind.ShouldBe(kind);
    }

    [Fact]
    public async Task Unknown_kind_is_rejected_and_writes_nothing()
    {
        var result = await _harness.NewService().LogEventAsync(Request(kind: "ovulation"), CancellationToken.None);

        MessagesFor(result, "kind").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllEventCount().ShouldBe(0);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Missing_kind_is_rejected(string? kind)
    {
        var result = await _harness.NewService().LogEventAsync(Request(kind: kind), CancellationToken.None);

        MessagesFor(result, "kind").ShouldBe([ValidationMessages.Required]);
    }

    // --- validation: the §G8 date window (cycle_events is the ONLY table with a floor) ---

    [Fact]
    public async Task Future_date_is_rejected()
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(occurredOn: CycleTestHarness.Today.AddDays(1)), CancellationToken.None);

        MessagesFor(result, "occurredOn").ShouldBe([ValidationMessages.FutureDate]);
        AllEventCount().ShouldBe(0);
    }

    [Fact]
    public async Task Today_is_accepted_so_the_ceiling_is_inclusive()
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(occurredOn: CycleTestHarness.Today), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>();
    }

    [Fact]
    public async Task Date_before_the_backdate_floor_is_rejected()
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(occurredOn: CycleTestHarness.Floor.AddDays(-1)), CancellationToken.None);

        MessagesFor(result, "occurredOn").ShouldBe([ValidationMessages.BeforeFloor]);
        AllEventCount().ShouldBe(0);
    }

    [Fact]
    public async Task The_backdate_floor_itself_is_accepted_so_the_floor_is_inclusive()
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(occurredOn: CycleTestHarness.Floor), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>();
    }

    [Fact]
    public async Task Missing_date_is_rejected()
    {
        var result = await _harness.NewService()
            .LogEventAsync(new LogCycleEventRequest(CycleEvent.Kinds.Spotting, null, null, null), CancellationToken.None);

        MessagesFor(result, "occurredOn").ShouldBe([ValidationMessages.Required]);
    }

    // --- validation: flow intensity ---------------------------------------------------

    [Theory]
    [InlineData(0)]
    [InlineData(5)]
    [InlineData(-1)]
    public async Task Flow_intensity_outside_the_1_to_4_scale_is_rejected(int flow)
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(flowIntensity: flow), CancellationToken.None);

        MessagesFor(result, "flowIntensity").ShouldBe([ValidationMessages.Between(1, 4)]);
        AllEventCount().ShouldBe(0);
    }

    [Theory]
    [InlineData(CycleEvent.Kinds.PeriodStart)]
    [InlineData(CycleEvent.Kinds.PeriodEnd)]
    [InlineData(CycleEvent.Kinds.Spotting)]
    public async Task Null_flow_intensity_is_accepted_on_every_kind(string kind)
    {
        // Deliberately no cross-field clinical rule: "flow >= 2 is period-qualifying" is C-04 /
        // clinician-UNSIGNED and belongs to P6's ref_insight_rule, never to an entry validator (§G7).
        var result = await _harness.NewService()
            .LogEventAsync(Request(kind: kind, flowIntensity: null), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.FlowIntensity.ShouldBeNull();
    }

    [Theory]
    [InlineData(CycleEvent.Kinds.PeriodEnd)]
    [InlineData(CycleEvent.Kinds.Spotting)]
    public async Task Flow_intensity_is_accepted_on_every_kind_not_only_period_start(string kind)
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(kind: kind, flowIntensity: 4), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.FlowIntensity.ShouldBe(4);
    }

    // --- validation: notes -------------------------------------------------------------

    [Fact]
    public async Task Notes_of_exactly_2000_characters_are_accepted()
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(notes: new string('a', 2000)), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Notes!.Length.ShouldBe(2000);
    }

    [Fact]
    public async Task Notes_of_2001_characters_are_rejected()
    {
        var result = await _harness.NewService()
            .LogEventAsync(Request(notes: new string('a', 2001)), CancellationToken.None);

        MessagesFor(result, "notes").ShouldBe([ValidationMessages.MaxLength(2000)]);
        AllEventCount().ShouldBe(0);
    }

    [Fact]
    public async Task Notes_are_measured_after_trimming()
    {
        // 2000 characters of content wrapped in whitespace is a 2000-character note, not a 2004 one.
        var result = await _harness.NewService()
            .LogEventAsync(Request(notes: "  " + new string('a', 2000) + "  "), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Notes!.Length.ShouldBe(2000);
    }

    [Fact]
    public async Task Notes_are_stored_as_ciphertext_never_plaintext()
    {
        const string note = "dolor pélvico agudo";

        var result = await _harness.NewService().LogEventAsync(Request(notes: note), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Notes.ShouldBe(note);
        var row = _harness.NewContext().CycleEvents.Single(e => e.UserId == _harness.UserId);
        row.NotesEnc.ShouldNotBeNull();
        Encoding.UTF8.GetString(row.NotesEnc!).ShouldNotContain("dolor");
        row.NotesEnc!.Length.ShouldBeGreaterThanOrEqualTo(28); // 12-byte nonce + ciphertext + 16-byte tag
        (await _harness.Crypto.DecryptStringAsync(row.NotesEnc!)).ShouldBe(note);
    }

    [Fact]
    public async Task Blank_notes_are_stored_as_null()
    {
        var result = await _harness.NewService().LogEventAsync(Request(notes: "   "), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Notes.ShouldBeNull();
        _harness.NewContext().CycleEvents.Single(e => e.UserId == _harness.UserId).NotesEnc.ShouldBeNull();
    }

    // --- validate-then-act --------------------------------------------------------------

    [Fact]
    public async Task Every_field_error_is_collected_before_any_write()
    {
        var result = await _harness.NewService().LogEventAsync(
            Request(kind: "ovulation", occurredOn: CycleTestHarness.Today.AddDays(3), flowIntensity: 9, notes: new string('a', 2001)),
            CancellationToken.None);

        var invalid = result.ShouldBeOfType<CycleEventResult.Invalid>();
        invalid.Errors.Select(e => e.Field).ShouldBe(["kind", "occurredOn", "flowIntensity", "notes"], ignoreOrder: true);
        AllEventCount().ShouldBe(0);
    }

    // --- upsert on (UserId, Kind, OccurredOn) — §G9 UNFILTERED index regime ---------------

    [Fact]
    public async Task Logging_the_same_kind_and_day_twice_updates_one_row_keeping_CreatedAt()
    {
        var later = CycleTestHarness.Now.AddHours(6);

        var first = await _harness.NewService().LogEventAsync(Request(flowIntensity: 2), CancellationToken.None);
        var second = await _harness.NewService(_harness.DayInfo(now: later))
            .LogEventAsync(Request(flowIntensity: 4), CancellationToken.None);

        var firstEvent = first.ShouldBeOfType<CycleEventResult.Saved>().Event;
        var secondEvent = second.ShouldBeOfType<CycleEventResult.Saved>().Event;
        secondEvent.Id.ShouldBe(firstEvent.Id, "the upsert must not mint a second id");
        secondEvent.CreatedAt.ShouldBe(CycleTestHarness.Now, "CreatedAt belongs to the original observation");
        secondEvent.UpdatedAt.ShouldBe(later);
        secondEvent.FlowIntensity.ShouldBe(4);
        AllEventCount().ShouldBe(1);
    }

    [Fact]
    public async Task Re_logging_a_soft_deleted_day_revives_the_tombstone_instead_of_duplicating_it()
    {
        // The whole point of the unfiltered index: the tombstone still occupies (UserId, Kind,
        // OccurredOn), so a blind insert here is a unique-violation 500, not a duplicate row.
        var tombstone = _harness.SeedEvent(
            CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, deletedAt: CycleTestHarness.Now.AddHours(-1));

        var result = await _harness.NewService().LogEventAsync(Request(flowIntensity: 3), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Id.ShouldBe(tombstone.Id);
        AllEventCount().ShouldBe(1);
        LiveEventCount().ShouldBe(1);
        _harness.NewContext().CycleEvents.Single(e => e.Id == tombstone.Id).DeletedAt.ShouldBeNull();
    }

    [Fact]
    public async Task Delete_then_re_post_round_trips_through_the_same_single_row()
    {
        var saved = (await _harness.NewService().LogEventAsync(Request(flowIntensity: 1), CancellationToken.None))
            .ShouldBeOfType<CycleEventResult.Saved>().Event;

        (await _harness.NewService().DeleteEventAsync(saved.Id, CancellationToken.None))
            .ShouldBeOfType<CycleEventDeleteResult.Deleted>();
        LiveEventCount().ShouldBe(0);

        var reposted = (await _harness.NewService().LogEventAsync(Request(flowIntensity: 3), CancellationToken.None))
            .ShouldBeOfType<CycleEventResult.Saved>().Event;

        reposted.Id.ShouldBe(saved.Id);
        reposted.FlowIntensity.ShouldBe(3);
        AllEventCount().ShouldBe(1);
        LiveEventCount().ShouldBe(1);
    }

    [Fact]
    public async Task An_existing_onboarding_row_keeps_its_provenance_on_update()
    {
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, source: CycleEvent.Sources.Onboarding);

        var result = await _harness.NewService().LogEventAsync(Request(flowIntensity: 2), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Source.ShouldBe(CycleEvent.Sources.Onboarding);
    }

    [Fact]
    public async Task A_new_row_is_sourced_user()
    {
        var result = await _harness.NewService().LogEventAsync(Request(), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.Saved>().Event.Source.ShouldBe(CycleEvent.Sources.User);
    }

    [Fact]
    public async Task Different_kinds_on_the_same_day_are_separate_rows()
    {
        await _harness.NewService().LogEventAsync(Request(kind: CycleEvent.Kinds.PeriodStart), CancellationToken.None);
        await _harness.NewService().LogEventAsync(Request(kind: CycleEvent.Kinds.Spotting), CancellationToken.None);

        LiveEventCount().ShouldBe(2);
    }

    [Fact]
    public async Task Another_users_row_on_the_same_key_is_untouched()
    {
        var theirs = _harness.SeedEvent(
            CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, userId: _harness.OtherUserId, flow: 1);

        await _harness.NewService().LogEventAsync(Request(flowIntensity: 4), CancellationToken.None);

        _harness.NewContext().CycleEvents.Single(e => e.Id == theirs.Id).FlowIntensity.ShouldBe((short)1);
        LiveEventCount().ShouldBe(1);
    }

    // --- DELETE /cycle/events/{id} — soft delete (D-13) ----------------------------------

    [Fact]
    public async Task Delete_soft_deletes_the_row_rather_than_removing_it()
    {
        var saved = (await _harness.NewService().LogEventAsync(Request(), CancellationToken.None))
            .ShouldBeOfType<CycleEventResult.Saved>().Event;
        var later = CycleTestHarness.Now.AddHours(2);

        var result = await _harness.NewService(_harness.DayInfo(now: later))
            .DeleteEventAsync(saved.Id, CancellationToken.None);

        result.ShouldBeOfType<CycleEventDeleteResult.Deleted>();
        var row = _harness.NewContext().CycleEvents.IgnoreQueryFilters().Single(e => e.Id == saved.Id);
        row.DeletedAt.ShouldBe(later);
        row.UpdatedAt.ShouldBe(later);
        LiveEventCount().ShouldBe(0);
    }

    [Fact]
    public async Task Deleting_an_unknown_id_is_not_found()
    {
        var result = await _harness.NewService().DeleteEventAsync(Guid.NewGuid(), CancellationToken.None);

        result.ShouldBeOfType<CycleEventDeleteResult.NotFound>();
    }

    [Fact]
    public async Task Deleting_twice_is_not_found_the_second_time()
    {
        var saved = (await _harness.NewService().LogEventAsync(Request(), CancellationToken.None))
            .ShouldBeOfType<CycleEventResult.Saved>().Event;

        (await _harness.NewService().DeleteEventAsync(saved.Id, CancellationToken.None))
            .ShouldBeOfType<CycleEventDeleteResult.Deleted>();
        (await _harness.NewService().DeleteEventAsync(saved.Id, CancellationToken.None))
            .ShouldBeOfType<CycleEventDeleteResult.NotFound>();
    }

    [Fact]
    public async Task Deleting_another_users_row_is_not_found_and_leaves_it_live()
    {
        // 404, never 403 (§G12): a 403 would itself confirm the id exists.
        var theirs = _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, userId: _harness.OtherUserId);

        var result = await _harness.NewService().DeleteEventAsync(theirs.Id, CancellationToken.None);

        result.ShouldBeOfType<CycleEventDeleteResult.NotFound>();
        _harness.NewContext().CycleEvents.IgnoreQueryFilters().Single(e => e.Id == theirs.Id).DeletedAt.ShouldBeNull();
    }

    // --- the erased-user fence -----------------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_log_an_event()
    {
        // UserDayContext honours the users soft-delete filter, so an erased account resolves to null.
        // There is NO write fence behind this: the JWT stays valid until it expires and a child INSERT
        // takes no lock the shred job's UPDATE conflicts with, so this 404 is what stops an in-flight
        // request from re-creating plaintext health rows after erasure.
        var result = await _harness.NewService(null).LogEventAsync(Request(), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.UserNotFound>();
        AllEventCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_crypto_shredded_user_gets_not_found_on_delete()
    {
        var saved = (await _harness.NewService().LogEventAsync(Request(), CancellationToken.None))
            .ShouldBeOfType<CycleEventResult.Saved>().Event;

        var result = await _harness.NewService(null).DeleteEventAsync(saved.Id, CancellationToken.None);

        result.ShouldBeOfType<CycleEventDeleteResult.NotFound>();
    }

    [Fact]
    public async Task A_crypto_shredded_user_is_rejected_before_validation_so_nothing_leaks()
    {
        // The 404 wins over the 400: an erased token learns nothing about its own payload.
        var result = await _harness.NewService(null)
            .LogEventAsync(Request(kind: "ovulation", occurredOn: CycleTestHarness.Today.AddDays(9)), CancellationToken.None);

        result.ShouldBeOfType<CycleEventResult.UserNotFound>();
    }
}
