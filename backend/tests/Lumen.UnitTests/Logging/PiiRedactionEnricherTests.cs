using Lumen.Infrastructure.Logging;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Logging;

public class PiiRedactionEnricherTests
{
    private sealed class CapturingSink : ILogEventSink
    {
        public List<LogEvent> Events { get; } = [];
        public void Emit(LogEvent logEvent) => Events.Add(logEvent);
    }

    private static (ILogger logger, CapturingSink sink) BuildLogger()
    {
        var sink = new CapturingSink();
        var logger = new LoggerConfiguration()
            .Enrich.With(new PiiRedactionEnricher())
            .WriteTo.Sink(sink)
            .CreateLogger();
        return (logger, sink);
    }

    [Fact]
    public void Redacts_email_in_properties()
    {
        // "Email" is now a sensitive property NAME (defense-in-depth, name-based redaction) — the
        // whole property value is replaced, not just the email-shaped substring within it.
        var (logger, sink) = BuildLogger();
        logger.Information("User {Email} signed in", "maria@example.com");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("maria@example.com");
    }

    [Fact]
    public void Rewrites_user_guid_path()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Request to {Path}", "/users/87dd6291-d2cd-49f7-b8ea-a29a0bae4f49");

        sink.Events.Single().RenderMessage().ShouldContain("/users/[id]");
    }

    [Fact]
    public void Leaves_clean_messages_untouched()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Health check {Status}", "ok");

        sink.Events.Single().RenderMessage().ShouldContain("ok");
    }

    [Fact]
    public void Redacts_pii_nested_in_destructured_object()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { Email = "nested@example.com", UserId = Guid.NewGuid() });

        var rendered = sink.Events.Single().RenderMessage();
        // "Email" is a sensitive property NAME (see Redacts_email_in_properties) — whole-value redact.
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("nested@example.com");
        rendered.ShouldContain("[id]"); // UserId isn't a sensitive name — still value-based Guid scrub
    }

    // ── name-based redaction (defense-in-depth) ──────────────────────────────────────────────────

    [Fact]
    public void Redacts_top_level_password_property()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Login attempt {Password}", "hunter2");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("hunter2");
    }

    [Fact]
    public void Redacts_top_level_property_by_sensitive_name_case_insensitively()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Login attempt {PASSWORD}", "hunter2");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("hunter2");
    }

    [Fact]
    public void Redacts_structure_property_by_name_leaves_sibling_properties_untouched()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("profile {@Profile}", new { DisplayName = "Maya", Count = 3 });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("Maya");
        rendered.ShouldContain("3");
    }

    [Fact]
    public void Redacts_dictionary_value_by_sensitive_key_name()
    {
        var (logger, sink) = BuildLogger();
        var device = new Dictionary<string, object> { ["pushToken"] = "abc123token", ["platform"] = "ios" };
        logger.Information("device registered {@Device}", device);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("abc123token");
        rendered.ShouldContain("ios");
    }

    [Fact]
    public void Redacts_sensitive_name_nested_two_levels_deep()
    {
        // A structure (User) nested inside another structure (Payload) — one level deeper than the
        // immediate destructured object — still gets its sensitive-named property fully redacted.
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { User = new { Password = "hunter2", Id = 7 } });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("hunter2");
        rendered.ShouldContain("7");
    }

    // ── negative controls: value-based scrubbing is unchanged for non-sensitive names ───────────

    [Fact]
    public void Non_sensitive_property_name_with_email_shaped_value_still_gets_value_based_scrub()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Preferences {Locale} status {Status}", "someone@example.com", "ok");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted-email]"); // Locale isn't a sensitive name — old value scrub
        rendered.ShouldNotContain("someone@example.com");
        rendered.ShouldContain("ok"); // benign name + benign value passes through untouched
    }

    [Fact]
    public void Non_sensitive_nested_property_with_email_shaped_value_still_gets_value_based_scrub()
    {
        // `Note` USED to be the benign name in this control. P4a makes free-text notes health data
        // (§F), so `note` joined SensitiveNames in T8 and the control moved to `Label`, which is not
        // a P4a field name.
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { Label = "contact-me@example.com", Count = 1 });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted-email]"); // Label isn't a sensitive name — old value scrub
        rendered.ShouldNotContain("contact-me@example.com");
        rendered.ShouldContain("1");
    }

    // ── T8: the P4a health-data field names, plus the P3c-deferred credential names ─────────────

    /// <summary>
    /// Every property name P4a can put a special-category value under (§D's plaintext columns and the
    /// free-text note ciphertext), plus the credential names P3c deferred. One case per name: a
    /// structured log property carrying that name must never reach a sink with its value intact.
    /// </summary>
    public static TheoryData<string> SensitiveP4aNames =>
    [
        // free-text notes (D-13) — the note itself and both column/DTO spellings
        "notes", "note", "notesEnc",
        // symptom classification (§D plaintext)
        "symptomCode", "painTypes", "triggers", "region", "side", "intensity",
        // day log / check-in ordinals
        "pain", "mood", "energy", "libido", "flowIntensity",
        // the POST /symptoms batch envelope
        "entries",
        // rider-4 condition bundle + body metrics
        "endoStatus", "rasrmStage", "diagnosedOn", "heightCm", "weightKg",
        // cycle settings & onboarding
        "pauseReason", "lastPeriodStart", "goals",
        // credentials — deferred in P3c, in scope now
        "token", "refreshToken", "idToken", "authorization", "secret", "dek",
    ];

    [Theory]
    [MemberData(nameof(SensitiveP4aNames))]
    public void Redacts_every_p4a_sensitive_field_name(string name)
    {
        var (logger, sink) = BuildLogger();
        logger.Information("write {" + name + "}", "leaked-health-datum");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.Contains("leaked-health-datum").ShouldBeFalse(
            $"'{name}' must be a redacted property name — P4a stores health data under it");
        rendered.ShouldContain("[redacted]");
    }

    [Theory]
    [MemberData(nameof(SensitiveP4aNames))]
    public void Redacts_every_p4a_sensitive_field_name_nested_in_a_destructured_object(string name)
    {
        // The request-body shapes P4a logs are objects, not top-level scalars, so the nested path is
        // the one that actually matters in production.
        var (logger, sink) = BuildLogger();
        var payload = new Dictionary<string, object> { [name] = "leaked-health-datum", ["ok"] = "benign" };
        logger.Information("write {@Payload}", payload);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.Contains("leaked-health-datum").ShouldBeFalse(
            $"'{name}' must be redacted when nested inside a destructured payload");
        rendered.ShouldContain("benign"); // siblings survive
    }

    [Fact]
    public void Redacts_a_numeric_pain_score_not_just_strings()
    {
        // Intensity/pain/mood are SHORTS, not strings — a value-shape-based scrub would miss them
        // entirely. Name-based redaction is what makes an ordinal health score safe.
        var (logger, sink) = BuildLogger();
        logger.Information("day log {Pain} {Mood}", 9, 1);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldBe("day log \"[redacted]\" \"[redacted]\"");
    }

    [Fact]
    public void RequestPath_with_a_date_keyed_route_is_not_emitted_raw()
    {
        // §F: `/cycle/day/2026-08-06` is a health-adjacent fact — it says this user logged something
        // on that day. Request logging must emit the route TEMPLATE, never the raw path, so the
        // enricher redacts RequestPath outright rather than trying to parse dates out of it.
        var (logger, sink) = BuildLogger();
        logger.Information("HTTP {RequestMethod} {RequestPath} responded {StatusCode}",
            "POST", "/cycle/day/2026-08-06", 200);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldNotContain("2026-08-06");
        rendered.ShouldNotContain("/cycle/day");
        rendered.ShouldContain("[redacted]");
        rendered.ShouldContain("200"); // status code is not PII and must stay legible
    }

    // ── never throws, even on odd shapes ─────────────────────────────────────────────────────────

    [Fact]
    public void Does_not_throw_on_null_or_empty_shapes()
    {
        var (logger, sink) = BuildLogger();

        var act = () =>
        {
            logger.Information("null sensitive value {DisplayName}", (string?)null);
            logger.Information("empty struct {@Empty}", new { });
            logger.Information(
                "nested null under sensitive name {@Payload}",
                new { DisplayName = (string?)null, Nested = new { Password = (string?)null, Count = 0 } });
        };

        Should.NotThrow(act);
        sink.Events.Count.ShouldBe(3);
    }
}
