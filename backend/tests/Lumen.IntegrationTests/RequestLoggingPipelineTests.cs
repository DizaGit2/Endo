using System.Net;
using System.Text;
using Lumen.Application.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Pins the middleware ORDER that decides what an operator sees in the log for a failed request
/// (T3 review round 2, finding 1).
///
/// <para>
/// <c>UseSerilogRequestLogging()</c> must sit OUTSIDE <c>UseExceptionHandler()</c>. Nested inside it,
/// the request-logging middleware observed the in-flight exception instead of the response the client
/// actually got, and Serilog's exception path hard-codes status 500 — so every handled failure,
/// including a malformed request body, was written as an Error-level "responded 500" carrying a stack
/// trace, while the client was correctly answered with a 400. That is an operational alarm for what is
/// really user input, and the binding-failure message quotes the value that failed to bind, which in
/// this app is health data (§F forbids that in a response body or a log line).
/// </para>
///
/// <para>
/// The second test is the counterweight: fixing the false alarm must not silence real ones, so a
/// genuinely unhandled exception must still come out at Error with a 500. (Static pipeline — needs no
/// DB/Keycloak; not a [Category=LiveStack] test.)
/// </para>
/// </summary>
public class RequestLoggingPipelineTests
{
    /// <summary>Unterminated JSON object: fails minimal-API body binding before any handler runs.</summary>
    private const string MalformedJsonBody = """{ "email": """;

    /// <summary>Passes every OnboardingService pre-check, so the request reaches the (faked) identity provider.</summary>
    private const string WellFormedOnboardingBody =
        """{"email":"pipeline-probe@example.com","password":"correct-horse-battery-staple"}""";

    // --- harness ----------------------------------------------------------

    private sealed class CapturingSink : ILogEventSink
    {
        private readonly object _gate = new();
        private readonly List<LogEvent> _events = [];

        public void Emit(LogEvent logEvent)
        {
            lock (_gate) _events.Add(logEvent);
        }

        public LogEvent[] Snapshot()
        {
            lock (_gate) return [.. _events];
        }
    }

    /// <summary>
    /// Serilog's request-logging middleware writes through the STATIC <see cref="Log.Logger"/>
    /// (<c>RequestLoggingOptions.Logger</c> is never set by Program.cs), so swapping that for the
    /// duration of one request is what makes the emitted event observable. The client is created
    /// first on purpose: building the host is what assigns <see cref="Log.Logger"/> in the first
    /// place, so swapping earlier would just be overwritten. This assembly disables xUnit
    /// parallelization, so the swap cannot race another test.
    /// </summary>
    private static async Task<LogEvent[]> CaptureAsync(
        WebApplicationFactory<Program> factory, Func<HttpClient, Task> act)
    {
        var client = factory.CreateClient();
        var sink = new CapturingSink();
        using var capture = new LoggerConfiguration().MinimumLevel.Verbose().WriteTo.Sink(sink).CreateLogger();

        var previous = Log.Logger;
        Log.Logger = capture;
        try
        {
            await act(client);
        }
        finally
        {
            Log.Logger = previous;
        }

        return sink.Snapshot();
    }

    /// <summary>The "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed} ms" event.</summary>
    private static LogEvent RequestCompletion(LogEvent[] events) =>
        events.SingleOrDefault(e => e.Properties.ContainsKey("StatusCode") && e.Properties.ContainsKey("Elapsed"))
        ?? throw new InvalidOperationException(
            "No Serilog request-completion event was captured. Captured events: " +
            (events.Length == 0 ? "(none)" : string.Join(" | ", events.Select(e => e.RenderMessage()))));

    private static int StatusCodeOf(LogEvent completion) =>
        (int)((ScalarValue)completion.Properties["StatusCode"]).Value!;

    /// <summary>Fails before any DB/Vault work, giving a deterministic genuinely-unhandled exception.</summary>
    private sealed class ThrowingKeycloakAdmin : IKeycloakAdmin
    {
        public Task<Guid> CreateUserAsync(string email, string password, CancellationToken ct = default) =>
            throw new InvalidOperationException("deliberate unhandled failure");

        public Task DeleteUserAsync(Guid userId, CancellationToken ct = default) => Task.CompletedTask;

        public Task DisableUserAsync(Guid userId, CancellationToken ct = default) => Task.CompletedTask;
    }

    private sealed class ThrowingKeycloakFactory : LumenApiFactory
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IKeycloakAdmin>();
                services.AddScoped<IKeycloakAdmin, ThrowingKeycloakAdmin>();
            });
        }
    }

    // --- the finding: a malformed request is not an unhandled 500 --------

    [Fact]
    public async Task Malformed_request_is_logged_at_information_with_the_400_the_client_received()
    {
        using var factory = new LumenApiFactory();
        HttpResponseMessage? response = null;

        var events = await CaptureAsync(factory, async client =>
            response = await client.PostAsync(
                "/onboarding/start", new StringContent(MalformedJsonBody, Encoding.UTF8, "application/json")));

        response.ShouldNotBeNull().StatusCode.ShouldBe(HttpStatusCode.BadRequest);

        var completion = RequestCompletion(events);
        StatusCodeOf(completion).ShouldBe(
            400, "the request log must report the status the client actually received");
        completion.Level.ShouldBe(
            LogEventLevel.Information, "a malformed body is user input, not an operational alarm");
        completion.Exception.ShouldBeNull(
            "the binding-failure message quotes the value that failed to bind — health data here (§F)");
    }

    // --- T8 review fix: the logging trio nothing referenced -----------------
    //
    // §F's shipped claim is "a request to /cycle/day/2026-08-06 leaves ZERO occurrences of that date
    // in the log". It rests entirely on three lines of Program.cs — the MessageTemplate, the
    // EnrichDiagnosticContext that sets RouteTemplate, and the MinimumLevel override that silences
    // ASP.NET Core's own hosting diagnostics (which log the raw URL three times per request at
    // Information). Before these tests nothing anywhere referenced RouteTemplate, EnrichDiagnosticContext,
    // MinimumLevel or the message template, and T9 ships the real /cycle/day/{date}.

    /// <summary>A date-keyed path of exactly the shape T9 ships. Unrouted in P4a-T8, which is the
    /// harder case: an unmatched request is precisely where a raw path would otherwise be logged.</summary>
    private const string DateKeyedPath = "/cycle/day/2026-08-06";

    /// <summary>The health-adjacent datum: it asserts this user logged something on that day (§F).</summary>
    private const string DateInPath = "2026-08-06";

    [Fact]
    public async Task Date_keyed_request_logs_a_route_template_and_never_the_raw_date()
    {
        using var factory = new LumenApiFactory();
        HttpResponseMessage? response = null;

        var events = await CaptureAsync(factory, async client => response = await client.GetAsync(DateKeyedPath));

        response.ShouldNotBeNull().StatusCode.ShouldBe(HttpStatusCode.NotFound);

        var completion = RequestCompletion(events);
        completion.Properties.ShouldContainKey(
            "RouteTemplate",
            "the completion event must carry the route template EnrichDiagnosticContext sets — the " +
            "message template renders {RouteTemplate}, so losing the property silently degrades every " +
            "request line to a literal '{RouteTemplate}'");
        ((ScalarValue)completion.Properties["RouteTemplate"]).Value.ShouldBe(
            "(unrouted)",
            "an unmatched request has no endpoint and therefore no template; the fallback is a " +
            "CONSTANT on purpose — falling back to the path would reintroduce the raw date");

        // The claim itself, over every event the request produced — not just the one this app writes.
        var leaks = ProductionVisible(factory, events)
            .Where(e => e.RenderMessage().Contains(DateInPath, StringComparison.Ordinal))
            .Select(e => $"[{e.Level}] {SourceContextOf(e)}: {e.RenderMessage()}")
            .ToArray();
        leaks.ShouldBeEmpty(
            $"§F: no log line may contain {DateInPath}. A date-keyed path is a health-adjacent fact — " +
            "it asserts this user logged something on that day.");
    }

    [Fact]
    public async Task A_routed_request_logs_the_route_template_in_the_rendered_message()
    {
        // The counterweight to the test above: "(unrouted)" everywhere would satisfy the no-date
        // assertion while making the log useless. A matched endpoint must render its actual template,
        // which also proves the MessageTemplate and EnrichDiagnosticContext are wired to each other.
        using var factory = new LumenApiFactory();

        var events = await CaptureAsync(factory, async client => await client.GetAsync("/health"));

        var completion = RequestCompletion(events);
        ((ScalarValue)completion.Properties["RouteTemplate"]).Value.ShouldBe("/health");
        completion.RenderMessage().ShouldStartWith("HTTP \"GET\" \"/health\" responded 200 in ");
    }

    [Fact]
    public void The_level_override_silences_hosting_diagnostics_only_not_authentication_failures()
    {
        // T8 first shipped MinimumLevel.Override("Microsoft.AspNetCore", Warning). It closed the raw-URL
        // leak — and also silenced every authentication/authorization diagnostic in the app, including
        // the ONLY output of the P3c token perimeter guard (Program.cs's JwtBearerEvents.OnTokenValidated,
        // which rejects service-account and foreign-client tokens through context.Fail). The narrowed
        // override closes the same leak with none of that collateral: the raw URL is logged by
        // Microsoft.AspNetCore.Hosting.Diagnostics alone.
        //
        // Asked of the REAL host's logger factory, so this reads the shipped configuration rather than
        // a copy of it. Microsoft.IdentityModel already replaces PII in those messages with
        // "[PII of type '…' is hidden…]", so restoring them re-opens no §F hole.
        using var factory = new LumenApiFactory();
        var loggerFactory = factory.Services.GetRequiredService<ILoggerFactory>();

        loggerFactory.CreateLogger("Microsoft.AspNetCore.Hosting.Diagnostics")
            .IsEnabled(LogLevel.Information).ShouldBeFalse(
                "this category logs 'Request starting/finished … http://host/cycle/day/2026-08-06' and " +
                "the unhandled-request line — the raw path, three times per request (§F)");

        loggerFactory.CreateLogger("Microsoft.AspNetCore.Authentication.JwtBearer")
            .IsEnabled(LogLevel.Information).ShouldBeTrue(
                "silencing bearer-token diagnostics blinds the operator to every rejected token, " +
                "including the perimeter guard's own context.Fail — for zero §F benefit");

        loggerFactory.CreateLogger("Microsoft.AspNetCore.Authorization.DefaultAuthorizationService")
            .IsEnabled(LogLevel.Information).ShouldBeTrue(
                "authorization failures are an operational signal, not a request path");
    }

    /// <summary>The Serilog category (MEL logger name) an event was written under, if any.</summary>
    private static string SourceContextOf(LogEvent logEvent) =>
        logEvent.Properties.TryGetValue("SourceContext", out var value) && value is ScalarValue { Value: string s }
            ? s
            : "(no SourceContext)";

    /// <summary>
    /// Narrows captured events to the ones the SHIPPED configuration would actually emit.
    /// <see cref="CaptureAsync"/> has to swap <see cref="Log.Logger"/> for a bare
    /// <c>MinimumLevel.Verbose()</c> sink to observe anything at all, which makes the capture strictly
    /// BROADER than production — it sees Debug chatter such as
    /// <c>Microsoft.AspNetCore.Routing.Matching.DfaMatcher</c>'s "No candidates found for the request
    /// path '…'", which quotes the raw path and which production never emits (§F: "INFO in production,
    /// DEBUG off by default", plus the category override).
    ///
    /// <para>The filter is DERIVED, not a copy of Program.cs: it asks the real host's
    /// <see cref="ILoggerFactory"/> whether that category is enabled at that level, so it tracks the
    /// shipped configuration automatically. Loosening the override in Program.cs widens what this
    /// returns, and the leak assertion then has to survive it.</para>
    /// </summary>
    private static LogEvent[] ProductionVisible(WebApplicationFactory<Program> factory, LogEvent[] events)
    {
        var loggerFactory = factory.Services.GetRequiredService<ILoggerFactory>();
        return [.. events.Where(e => loggerFactory
            .CreateLogger(SourceContextOf(e))
            .IsEnabled(ToLogLevel(e.Level)))];
    }

    private static LogLevel ToLogLevel(LogEventLevel level) => level switch
    {
        LogEventLevel.Verbose => LogLevel.Trace,
        LogEventLevel.Debug => LogLevel.Debug,
        LogEventLevel.Information => LogLevel.Information,
        LogEventLevel.Warning => LogLevel.Warning,
        LogEventLevel.Error => LogLevel.Error,
        _ => LogLevel.Critical,
    };

    // --- the counterweight: real failures are still alarms ----------------

    [Fact]
    public async Task A_genuinely_unhandled_exception_is_still_logged_at_error_with_a_500()
    {
        using var factory = new ThrowingKeycloakFactory();
        HttpResponseMessage? response = null;

        var events = await CaptureAsync(factory, async client =>
            response = await client.PostAsync(
                "/onboarding/start", new StringContent(WellFormedOnboardingBody, Encoding.UTF8, "application/json")));

        response.ShouldNotBeNull().StatusCode.ShouldBe(HttpStatusCode.InternalServerError);

        var completion = RequestCompletion(events);
        StatusCodeOf(completion).ShouldBe(500);
        completion.Level.ShouldBe(LogEventLevel.Error, "a genuine bug must still page someone");
    }
}
