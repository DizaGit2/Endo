using System.Text.Json;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Proof of the two decisions <see cref="TestResidueSweep"/> makes before it deletes anything: may this
/// run sweep at all, and may this account be reclaimed.
///
/// <para><b>Why these are pure and why that matters.</b> The Keycloak half used to have no coverage at
/// all — <c>TestResidueSweepLiveTests</c> exercises only <c>SweepDatabaseAsync</c>, so the riskiest code
/// in the sweep (the half that deletes accounts in bulk) was asserted by nothing. It could not be
/// covered the obvious way either: a live test of "does it delete accounts" has to create the very
/// accounts it deletes, against the realm a developer's own dev account lives in. Extracting the
/// per-account decision into a predicate over (username, createdTimestamp, cutoff) makes it provable
/// with no Keycloak, no network and no deletion — and the perimeter, not the plumbing, is the part that
/// has to be right.</para>
///
/// <para>Static — no stack, no docker; safe in CI's docker-less contract job.</para>
/// </summary>
public class TestResidueSweepRuleTests
{
    /// <summary>An arbitrary fixed cutoff; only the ordering against it matters.</summary>
    private const long Cutoff = 1_786_400_000_000;

    private const long Aged = Cutoff - 1;
    private const long Recent = Cutoff + 1;

    // ---------------------------------------------------------------- the opt-in gate

    [Theory]
    [InlineData("1")]
    [InlineData("true")]
    [InlineData("TRUE")]
    [InlineData("True")]
    [InlineData(" 1 ")]
    public void An_explicit_opt_in_enables_the_sweep(string value) =>
        TestResidueSweep.IsEnabled(value).ShouldBeTrue();

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("0")]
    [InlineData("false")]
    [InlineData("no")]
    [InlineData("yes")]   // deliberately NOT an opt-in: only the documented values enable a delete
    [InlineData("on")]
    [InlineData("2")]
    public void Anything_else_leaves_the_sweep_off(string? value) =>
        TestResidueSweep.IsEnabled(value).ShouldBeFalse(
            $"'{value ?? "<null>"}' is not the documented opt-in, and a sweep nobody asked for is how "
            + "an unattended `dotnet test --filter` deletes accounts it never needed to touch");

    // ---------------------------------------------------------------- the per-account rule

    [Fact]
    public void An_aged_example_com_account_is_reclaimed() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("cyc-400-abc@example.com", Aged, Cutoff)
            .ShouldBeTrue("this is exactly the residue the sweep exists to reclaim");

    [Fact]
    public void The_suffix_check_is_case_insensitive() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("CYC-400-ABC@EXAMPLE.COM", Aged, Cutoff)
            .ShouldBeTrue("Keycloak lowercases usernames, but the rule must not depend on it");

    [Fact]
    public void A_recent_account_survives_the_age_floor() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("cyc-400-abc@example.com", Recent, Cutoff)
            .ShouldBeFalse(
                "an account younger than the cutoff may belong to a run that is still executing — the "
                + "age floor is what makes the sweep safe under concurrency");

    [Fact]
    public void An_account_created_exactly_at_the_cutoff_survives() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("cyc-400-abc@example.com", Cutoff, Cutoff)
            .ShouldBeFalse("the boundary resolves toward keeping, like every other ambiguity here");

    [Fact]
    public void A_lumen_test_account_is_never_touched() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("live-p3c@lumen.test", Aged, Cutoff)
            .ShouldBeFalse(
                "@lumen.test is the domain the hand-made dev and client-E2E accounts use "
                + "(live-p3c@, watch-p3c@, five e2e-*@) — deleting one breaks somebody's dev stack");

    [Fact]
    public void A_domain_that_merely_CONTAINS_the_test_domain_is_never_touched() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("x@example.com.evil.net", Aged, Cutoff)
            .ShouldBeFalse(
                "the rule is a SUFFIX test and must stay one: Keycloak's `search` is a substring match "
                + "over username AND first/last name, so a candidate list is full of things that merely "
                + "contain the domain. Relaxing this to Contains() is the one-character change that "
                + "turns the sweep loose on the whole realm");

    [Fact]
    public void An_account_outside_the_test_domain_is_never_touched() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("dagoberto@gmail.com", Aged, Cutoff).ShouldBeFalse();

    [Fact]
    public void An_account_with_no_username_is_never_touched() =>
        TestResidueSweep.IsReclaimableKeycloakAccount(null, Aged, Cutoff).ShouldBeFalse();

    // -------------------------------------------- the age floor is FAIL-CLOSED (an unknown age = KEEP)

    [Fact]
    public void An_account_whose_age_is_UNKNOWN_is_kept() =>
        TestResidueSweep.IsReclaimableKeycloakAccount("cyc-400-abc@example.com", null, Cutoff)
            .ShouldBeFalse(
                "an absent createdTimestamp means the age floor could not be evaluated, not that the "
                + "account is old. Deleting on an unknown age makes the floor fail-OPEN: one Keycloak "
                + "serialization change and every @example.com account goes at once, including ones a "
                + "concurrent suite is mid-assertion on. Postgres' half is fail-closed by construction "
                + "(`u.CreatedAt < cutoff` in SQL on a NOT NULL column); this half must match it");

    // ------------------------------------- and an age that cannot be READ is an unknown age, not a zero

    [Fact]
    public void A_numeric_created_timestamp_is_read()
    {
        using var doc = JsonDocument.Parse("""{"createdTimestamp": 1786492211434}""");
        TestResidueSweep.ReadCreatedTimestamp(doc.RootElement).ShouldBe(1786492211434);
    }

    [Theory]
    [InlineData("""{}""", "absent — briefRepresentation, or a representation that stops emitting it")]
    [InlineData("""{"createdTimestamp": null}""", "explicit null")]
    [InlineData("""{"createdTimestamp": "1786492211434"}""", "serialized as a string (a JS-safe-integer fix)")]
    [InlineData("""{"createdTimestamp": "2026-08-11T00:00:00Z"}""", "serialized as an ISO instant")]
    [InlineData("""{"createdTimestamp": 1.7864922e12}""", "serialized as a double")]
    [InlineData("""{"createdTimestamp": true}""", "nonsense")]
    public void A_created_timestamp_that_cannot_be_read_as_int64_reads_as_UNKNOWN(string json, string why)
    {
        using var doc = JsonDocument.Parse(json);
        TestResidueSweep.ReadCreatedTimestamp(doc.RootElement).ShouldBeNull(
            $"{why}: the reader must never throw and must never invent an age — an unreadable timestamp "
            + "is an unknown age, which keeps the account");
    }
}
