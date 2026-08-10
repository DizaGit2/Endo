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
/// <c>GET /symptoms?from&amp;to&amp;limit&amp;offset</c> (T12), exercised through
/// <see cref="SymptomService"/> against the real model on Sqlite with the real
/// <c>AesGcmFieldCipher</c> and a frozen clock.
///
/// <para><b>The window is expressed in USER-LOCAL DAYS and filtered on <c>OccurredOn</c></b>, the
/// column D-12 exists to provide. <c>from</c> and <c>to</c> are both required and both inclusive; a
/// <c>to</c> in the future is legitimate, because a month view spans forward past today.</para>
///
/// <para><b>Pagination is D-13's, not an invention</b>: default 50, min 1, max 100, offset ≥ 0. Out of
/// range is a <b>400, never a silent clamp</b> — a client asking for 500 rows and receiving 100
/// without being told cannot distinguish "that is all of them" from "you were truncated", and would
/// render a partial symptom history as a complete one.</para>
///
/// <para><b>Soft-deleted rows are absent from <c>items</c> AND from <c>total</c></b> (D-13): a total
/// that counted tombstones would make the client page forever into rows that never arrive.</para>
/// </summary>
public sealed class SymptomListServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    private static readonly DateOnly From = CycleTestHarness.Today.AddDays(-30);
    private static readonly DateOnly To = CycleTestHarness.Today;

    // --- helpers -----------------------------------------------------------------------------

    private SymptomService Service(UserDayInfo? info = null, bool erased = false) =>
        _harness.NewSymptomService(erased ? null : info ?? _harness.DayInfo());

    /// <summary>
    /// A list call over the default 30-day window. <c>from</c>/<c>to</c> default to real values here so
    /// the ordinary cases read cleanly; the two "required" tests call the service directly, because
    /// this helper can no longer express a genuinely absent bound.
    /// </summary>
    private Task<SymptomListResult> ListAsync(
        DateOnly? from = null,
        DateOnly? to = null,
        int? limit = null,
        int? offset = null,
        UserDayInfo? info = null,
        bool erased = false) =>
        Service(info, erased).ListAsync(from ?? From, to ?? To, limit, offset, CancellationToken.None);

    private static SymptomListResponse Found(SymptomListResult result) =>
        result.ShouldBeOfType<SymptomListResult.Found>().Page;

    private static IReadOnlyList<string> MessagesFor(SymptomListResult result, string field) =>
        result.ShouldBeOfType<SymptomListResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    // --- from / to: required, inclusive, forward-looking `to` allowed ----------------------------

    [Fact]
    public async Task From_is_required()
    {
        // The window is not optional: an unbounded read of every symptom a user ever logged is a
        // different endpoint from "show me this month", and defaulting one into the other would make
        // the response size a function of how long the account has existed.
        var result = await Service().ListAsync(null, To, null, null, CancellationToken.None);

        MessagesFor(result, "from").ShouldBe([ValidationMessages.Required]);
    }

    [Fact]
    public async Task To_is_required()
    {
        var result = await Service().ListAsync(From, null, null, null, CancellationToken.None);

        MessagesFor(result, "to").ShouldBe([ValidationMessages.Required]);
    }

    [Fact]
    public async Task Both_bounds_are_reported_together_when_both_are_absent()
    {
        // Validate-then-act (T3): the client fixes the whole request in one round trip.
        var result = await Service().ListAsync(null, null, null, null, CancellationToken.None);

        MessagesFor(result, "from").ShouldBe([ValidationMessages.Required]);
        MessagesFor(result, "to").ShouldBe([ValidationMessages.Required]);
    }

    [Fact]
    public async Task Both_ends_of_the_window_are_inclusive()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, From);
        _harness.SeedSymptom(Symptom.Codes.Pain, 6, To);
        _harness.SeedSymptom(Symptom.Codes.Pain, 7, From.AddDays(-1));
        _harness.SeedSymptom(Symptom.Codes.Pain, 8, To.AddDays(1));

        var page = Found(await ListAsync());

        page.Total.ShouldBe(2, "only the two rows ON the boundaries are in range");
        page.Items.Select(i => i.Intensity).OrderBy(i => i).ShouldBe([5, 6]);
    }

    [Fact]
    public async Task A_future_to_is_accepted_because_a_month_view_spans_forward()
    {
        // Unlike every WRITE in this phase, a read window is not capped by today: the calendar shows
        // the rest of the current month, and rejecting that would make the client clamp the window it
        // just rendered.
        var result = await ListAsync(to: CycleTestHarness.Today.AddDays(20));

        Found(result).Items.ShouldBeEmpty();
    }

    [Fact]
    public async Task A_to_before_from_is_rejected_rather_than_answered_with_an_empty_page()
    {
        // An inverted window is a client bug. Answering it with `[]` is indistinguishable from "you
        // logged nothing that month", which is the reading that hides the bug forever.
        var result = await ListAsync(from: To, to: From);

        MessagesFor(result, "to").ShouldBe([SymptomValidationMessages.RangeEndBeforeStart]);
    }

    [Fact]
    public async Task A_single_day_window_is_accepted()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 4, To);

        var page = Found(await ListAsync(from: To, to: To));

        page.Total.ShouldBe(1);
    }

    // --- pagination: D-13's 50 / 1 / 100, and NEVER a silent clamp --------------------------------

    [Fact]
    public async Task An_absent_limit_and_offset_default_to_fifty_and_zero()
    {
        var page = Found(await ListAsync(limit: null, offset: null));

        page.Limit.ShouldBe(SymptomPaging.DefaultLimit);
        page.Offset.ShouldBe(0);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(101)]
    [InlineData(5000)]
    public async Task A_limit_outside_the_D13_bounds_is_a_400_and_is_never_silently_clamped(int limit)
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);

        var result = await ListAsync(limit: limit);

        MessagesFor(result, "limit")
            .ShouldBe([ValidationMessages.Between(SymptomPaging.MinLimit, SymptomPaging.MaxLimit)]);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(50)]
    [InlineData(100)]
    public async Task The_limit_bounds_are_inclusive(int limit)
    {
        var page = Found(await ListAsync(limit: limit));

        page.Limit.ShouldBe(limit);
    }

    [Fact]
    public async Task A_negative_offset_is_rejected()
    {
        var result = await ListAsync(offset: -1);

        MessagesFor(result, "offset").ShouldBe([ValidationMessages.NotNegative]);
    }

    [Fact]
    public async Task An_offset_of_zero_is_accepted_because_zero_is_the_first_page()
    {
        var page = Found(await ListAsync(offset: 0));

        page.Offset.ShouldBe(0);
    }

    [Fact]
    public async Task An_offset_past_the_end_returns_an_empty_page_with_the_real_total()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);
        _harness.SeedSymptom(Symptom.Codes.Pain, 6, To);

        var page = Found(await ListAsync(offset: 10));

        page.Items.ShouldBeEmpty();
        page.Total.ShouldBe(2, "total is the size of the MATCH, not of the page");
    }

    [Fact]
    public async Task Total_is_the_matching_count_not_the_page_size()
    {
        for (var i = 0; i < 7; i++) _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);

        var page = Found(await ListAsync(limit: 3));

        page.Items.Count.ShouldBe(3);
        page.Total.ShouldBe(7);
    }

    // --- ordering: newest first, with the id tiebreak that makes offset paging stable ---------------

    [Fact]
    public async Task Rows_come_back_newest_first()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 1, To.AddDays(-2), occurredAt: CycleTestHarness.Now.AddDays(-2));
        _harness.SeedSymptom(Symptom.Codes.Pain, 3, To, occurredAt: CycleTestHarness.Now);
        _harness.SeedSymptom(Symptom.Codes.Pain, 2, To.AddDays(-1), occurredAt: CycleTestHarness.Now.AddDays(-1));

        var page = Found(await ListAsync());

        page.Items.Select(i => i.Intensity).ShouldBe([3, 2, 1]);
    }

    [Fact]
    public async Task Offset_paging_is_stable_when_several_rows_share_one_instant()
    {
        // D-09 makes this the NORMAL case, not an edge one: screen 13's "Save body map" writes one row
        // per placed point and every one of them gets the request's single `now`. Without the `Id`
        // tiebreak the database may order the tied rows differently per query, so page 2 could repeat a
        // row from page 1 and drop another entirely — a symptom silently missing from the user's history.
        var instant = CycleTestHarness.Now;
        for (var i = 0; i < 3; i++) _harness.SeedSymptom(Symptom.Codes.Pain, (short)i, To, occurredAt: instant);

        var first = Found(await ListAsync(limit: 2, offset: 0));
        var second = Found(await ListAsync(limit: 2, offset: 2));

        first.Items.Count.ShouldBe(2);
        second.Items.Count.ShouldBe(1);
        first.Total.ShouldBe(3);
        second.Total.ShouldBe(3);

        var seen = first.Items.Concat(second.Items).Select(i => i.Id).ToList();
        seen.Distinct().Count().ShouldBe(3, "no row may appear on two pages");
        seen.Count.ShouldBe(3, "and none may be skipped between them");
    }

    // --- soft-deleted rows are gone from BOTH items and total (D-13) --------------------------------

    [Fact]
    public async Task A_soft_deleted_row_is_absent_from_items_and_from_total()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);
        _harness.SeedSymptom(Symptom.Codes.Pain, 9, To, deletedAt: CycleTestHarness.Now);

        var page = Found(await ListAsync());

        page.Items.Select(i => i.Intensity).ShouldBe([5]);
        page.Total.ShouldBe(1, "a total that counted tombstones would page into rows that never arrive");
    }

    [Fact]
    public async Task A_row_deleted_through_the_service_disappears_from_the_list()
    {
        var row = _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);
        _harness.SeedSymptom(Symptom.NonPainCodes.Nausea, 3, To);

        (await _harness.NewSymptomService().DeleteAsync(row.Id, CancellationToken.None))
            .ShouldBeOfType<SymptomDeleteResult.Deleted>();

        var page = Found(await ListAsync());
        page.Items.Select(i => i.SymptomCode).ShouldBe([Symptom.NonPainCodes.Nausea]);
        page.Total.ShouldBe(1);
    }

    // --- tenant scoping ----------------------------------------------------------------------------

    [Fact]
    public async Task Another_users_rows_are_absent_from_items_and_from_total()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);
        _harness.SeedSymptom(Symptom.Codes.Pain, 9, To, userId: _harness.OtherUserId);

        var page = Found(await ListAsync());

        page.Total.ShouldBe(1);
        page.Items.Single().Intensity.ShouldBe(5);
    }

    // --- projection --------------------------------------------------------------------------------

    [Fact]
    public async Task Notes_are_decrypted_and_every_classification_field_is_projected()
    {
        var notesEnc = await _harness.Crypto.EncryptStringAsync("dolor al caminar");
        _harness.SeedSymptom(
            Symptom.NonPainCodes.Bloating, 7, To,
            occurredAt: CycleTestHarness.Now,
            region: Symptom.Regions.Pelvis,
            side: Symptom.Sides.Back,
            painTypes: [Symptom.PainTypeCodes.Cramping],
            triggers: [Symptom.TriggerCodes.Food],
            notesEnc: notesEnc);

        var item = Found(await ListAsync()).Items.Single();

        item.SymptomCode.ShouldBe(Symptom.NonPainCodes.Bloating);
        item.Intensity.ShouldBe(7);
        item.Region.ShouldBe(Symptom.Regions.Pelvis);
        item.Side.ShouldBe(Symptom.Sides.Back);
        item.PainTypes.ShouldBe([Symptom.PainTypeCodes.Cramping]);
        item.Triggers.ShouldBe([Symptom.TriggerCodes.Food]);
        item.OccurredOn.ShouldBe(To);
        item.Notes.ShouldBe("dolor al caminar");
    }

    [Fact]
    public async Task A_row_with_no_note_is_projected_with_a_null_note_rather_than_failing_to_decrypt()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To, notesEnc: null);

        Found(await ListAsync()).Items.Single().Notes.ShouldBeNull();
    }

    // --- the erased-user fence ---------------------------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_read_symptoms()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);

        var result = await ListAsync(erased: true);

        result.ShouldBeOfType<SymptomListResult.UserNotFound>();
    }

    [Fact]
    public async Task A_crypto_shredded_user_is_rejected_BEFORE_validation()
    {
        // Order matters on the read too: a 400 leaks that the request shape was understood, and any
        // branch that validated first would be one refactor away from also reading.
        var result = await _harness.NewSymptomService(null)
            .ListAsync(null, null, -5, -5, CancellationToken.None);

        result.ShouldBeOfType<SymptomListResult.UserNotFound>();
    }

    [Fact]
    public async Task The_read_tracks_nothing_so_a_later_write_in_the_same_scope_cannot_pick_it_up()
    {
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, To);

        var db = _harness.NewContext();
        var service = new SymptomService(db, new StubUserDayContext(_harness.DayInfo()), _harness.Crypto, _harness.DayResolver);

        Found(await service.ListAsync(From, To, null, null, CancellationToken.None)).Items.Count.ShouldBe(1);

        db.ChangeTracker.Entries<Symptom>().ShouldBeEmpty();
    }

    // --- frozen numbers (§G12) ---------------------------------------------------------------------

    [Fact]
    public void The_pagination_bounds_are_D13s_and_are_frozen()
    {
        // D-13 verbatim: 50 default, 100 max. Not a P4a invention (§G11 lists what is), so these are
        // pinned against their literals rather than only against the service.
        SymptomPaging.DefaultLimit.ShouldBe(50);
        SymptomPaging.MinLimit.ShouldBe(1);
        SymptomPaging.MaxLimit.ShouldBe(100);
    }

    [Fact]
    public void The_range_message_is_frozen()
    {
        // A wire string the Flutter client renders verbatim; asserting it through the constant would
        // pin the service to the constant and the constant to nothing.
        SymptomValidationMessages.RangeEndBeforeStart.ShouldBe("date must not be before the start of the range");
    }
}
