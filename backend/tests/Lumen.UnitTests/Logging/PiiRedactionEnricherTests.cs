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
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { Note = "contact-me@example.com", Count = 1 });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted-email]"); // Note isn't a sensitive name — old value scrub
        rendered.ShouldNotContain("contact-me@example.com");
        rendered.ShouldContain("1");
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
