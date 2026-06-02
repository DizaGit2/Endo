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
        var (logger, sink) = BuildLogger();
        logger.Information("User {Email} signed in", "maria@example.com");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted-email]");
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
}
