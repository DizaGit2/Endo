using System.Net;
using System.Text;
using Lumen.Application.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
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
