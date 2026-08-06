using System.Text;
using System.Text.Json;
using Lumen.Api;
using Lumen.Application.Auth;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Api;

/// <summary>
/// Pins the P4a error contract at its exception boundary (T3). Two things are guarded here:
///
/// <para>
/// 1. <b>A binding failure is a 400, never a 500.</b> With <c>RouteHandlerOptions.ThrowOnBadRequest</c>
/// on, minimal-API parameter binding throws <see cref="BadHttpRequestException"/> instead of quietly
/// short-circuiting, so without a dedicated arm here every malformed body or unparseable route value
/// falls into the generic arm and surfaces to the client as "an unexpected error occurred" — an
/// operational alarm for what is really user input, and a `ServerFailure` in the Dart client where a
/// `ValidationFailure` belongs.
/// </para>
///
/// <para>
/// 2. <b>The response never echoes <c>exception.Message</c>.</b> A binding failure message quotes the
/// value it failed to bind, and in Lumen those values are health data (an intensity, a symptom code,
/// a date) — §F forbids putting them in a response body or a log line.
/// </para>
///
/// The handler is exercised against the real <see cref="IProblemDetailsService"/> so these assertions
/// are about the bytes on the wire, not about an in-memory object the writer might reshape.
/// </summary>
public class ProblemExceptionHandlerTests
{
    /// <summary>
    /// Asserted as a literal rather than via <c>ValidationMessages.MalformedRequest</c> on purpose:
    /// referencing the constant would make this test agree with any future edit to it. The wire
    /// string is the contract (the Dart client and its tests read it), so it is spelled out.
    /// </summary>
    private const string MalformedRequestMessage = "the request body or parameters could not be read";

    /// <summary>
    /// A realistic minimal-API binding failure message: it quotes the request content, which in this
    /// app is health data. Nothing from this string may reach the response body.
    /// </summary>
    private const string LeakyBindingMessage =
        """Failed to bind parameter "int intensity" from "9 lower_abdomen 2028-03-15".""";

    // --- harness ----------------------------------------------------------

    private sealed record LogEntry(LogLevel Level, Exception? Exception, string Message);

    private sealed record Written(
        int StatusCode, string? ContentType, string RawBody, JsonElement Body, IReadOnlyList<LogEntry> Logged);

    private sealed class CapturingLogger : ILogger<ProblemExceptionHandler>
    {
        public List<LogEntry> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter) =>
            Entries.Add(new LogEntry(logLevel, exception, formatter(state, exception)));
    }

    private static async Task<Written> HandleAsync(Exception exception)
    {
        var services = new ServiceCollection();
        services.AddOptions();
        services.AddProblemDetails();
        using var provider = services.BuildServiceProvider();

        var httpContext = new DefaultHttpContext { RequestServices = provider };
        using var responseBody = new MemoryStream();
        httpContext.Response.Body = responseBody;

        var logger = new CapturingLogger();
        var handler = new ProblemExceptionHandler(provider.GetRequiredService<IProblemDetailsService>(), logger);
        var handled = await handler.TryHandleAsync(httpContext, exception, CancellationToken.None);
        handled.ShouldBeTrue("the handler must own every exception it is handed");

        var raw = Encoding.UTF8.GetString(responseBody.ToArray());
        using var document = JsonDocument.Parse(raw);
        return new Written(
            httpContext.Response.StatusCode,
            httpContext.Response.ContentType,
            raw,
            document.RootElement.Clone(), // Clone() survives the JsonDocument's disposal.
            logger.Entries);
    }

    private static string[] ErrorsFor(JsonElement body, string key) =>
        body.GetProperty("errors").GetProperty(key).EnumerateArray().Select(e => e.GetString()!).ToArray();

    private static string? Title(JsonElement body) =>
        body.TryGetProperty("title", out var title) ? title.GetString() : null;

    private static string? Detail(JsonElement body) =>
        body.TryGetProperty("detail", out var detail) ? detail.GetString() : null;

    // --- the new arm: malformed input is a 400 ----------------------------

    [Fact]
    public async Task BadHttpRequestException_is_a_400_problem_json_not_a_500()
    {
        var written = await HandleAsync(new BadHttpRequestException(LeakyBindingMessage));

        written.StatusCode.ShouldBe(StatusCodes.Status400BadRequest);
        written.ContentType.ShouldNotBeNull().ShouldStartWith("application/problem+json");
        written.Body.GetProperty("status").GetInt32().ShouldBe(StatusCodes.Status400BadRequest);
    }

    [Fact]
    public async Task BadHttpRequestException_carries_the_frozen_request_key_error()
    {
        var written = await HandleAsync(new BadHttpRequestException(LeakyBindingMessage));

        Title(written.Body).ShouldBe("Validation failed.");
        // Same detail ValidationProblemBuilder.Build() carries (T3 review fix): the two 400
        // producers keep distinguishable titles for logs, but a user must see the same sentence
        // either way, since error_mapper.dart renders `detail ?? title`.
        Detail(written.Body).ShouldBe("The request contained invalid data.");
        // Same `errors: { field: [messages] }` shape ValidationProblemBuilder emits, under the
        // reserved cross-field key — one 400 body for the whole phase.
        ErrorsFor(written.Body, "request").ShouldBe([MalformedRequestMessage]);
    }

    [Fact]
    public async Task BadHttpRequestException_never_echoes_the_exception_message()
    {
        var written = await HandleAsync(new BadHttpRequestException(LeakyBindingMessage));

        written.RawBody.ShouldNotContain(LeakyBindingMessage);
        // The quoted request content specifically — §F. Checked in fragments so a partially
        // echoed/escaped message cannot slip through a whole-string comparison.
        written.RawBody.ShouldNotContain("lower_abdomen");
        written.RawBody.ShouldNotContain("intensity");
        written.RawBody.ShouldNotContain("Failed to bind");
    }

    [Fact]
    public async Task BadHttpRequestException_with_its_own_status_code_still_produces_the_one_400_body()
    {
        // BadHttpRequestException carries a StatusCode (413 from the request-size limit, 431 from the
        // header-size limit). P4a deliberately collapses all of them onto the single 400 shape rather
        // than forwarding a status the client's error mapper does not handle.
        var written = await HandleAsync(
            new BadHttpRequestException("Request body too large.", StatusCodes.Status413PayloadTooLarge));

        written.StatusCode.ShouldBe(StatusCodes.Status400BadRequest);
        ErrorsFor(written.Body, "request").ShouldBe([MalformedRequestMessage]);
    }

    // --- regression guards: the pre-existing arms are untouched -----------

    [Fact]
    public async Task DuplicateUserException_is_still_409_with_its_message_as_the_title()
    {
        var written = await HandleAsync(new DuplicateUserException("An account with that email already exists."));

        written.StatusCode.ShouldBe(StatusCodes.Status409Conflict);
        Title(written.Body).ShouldBe("An account with that email already exists.");
        written.Body.TryGetProperty("errors", out _).ShouldBeFalse("only the 400 arm carries an errors map");
    }

    [Fact]
    public async Task IdentityProviderException_is_still_502_with_a_generic_title()
    {
        var written = await HandleAsync(new IdentityProviderException("Keycloak returned 503 for POST /users"));

        written.StatusCode.ShouldBe(StatusCodes.Status502BadGateway);
        Title(written.Body).ShouldBe("An upstream identity service error occurred.");
        written.RawBody.ShouldNotContain("Keycloak");
        written.Body.TryGetProperty("errors", out _).ShouldBeFalse("only the 400 arm carries an errors map");
    }

    [Fact]
    public async Task Unrecognised_exception_is_still_a_generic_500()
    {
        // The new 400 arm must not widen into a catch-all: a genuine bug still has to be a 500 so it
        // pages someone, and its message still must not reach the client.
        var written = await HandleAsync(new InvalidOperationException("DEK unwrap failed for user 8f14e45f"));

        written.StatusCode.ShouldBe(StatusCodes.Status500InternalServerError);
        Title(written.Body).ShouldBe("An unexpected error occurred.");
        written.RawBody.ShouldNotContain("8f14e45f");
        written.Body.TryGetProperty("errors", out _).ShouldBeFalse("only the 400 arm carries an errors map");
    }

    // --- who gets to be an operational alarm (T3 review round 2) ----------
    //
    // Request logging now sits OUTSIDE UseExceptionHandler so it reports the status the client
    // received rather than a hard-coded 500 (Program.cs). The cost of that ordering is that the
    // exception object no longer reaches the request logger at all, and .NET's ExceptionHandlerMiddleware
    // emits no diagnostics of its own once an IExceptionHandler claims the exception — verified against
    // the running app, where a handled exception produced exactly one Error line and it came from
    // Serilog. So the stack trace for a genuine failure has to be logged HERE, by the thing that
    // swallows it. The split is by response class, not by exception type: 5xx means "we broke", 4xx
    // means "the caller did".

    [Fact]
    public async Task Unrecognised_exception_is_logged_at_error_with_the_exception_attached()
    {
        var boom = new InvalidOperationException("DEK unwrap failed for user 8f14e45f");

        var written = await HandleAsync(boom);

        var logged = written.Logged.ShouldHaveSingleItem();
        logged.Level.ShouldBe(LogLevel.Error, "a genuine bug must still page someone");
        // The exception OBJECT, not its text: that is what carries the stack trace to the sink.
        logged.Exception.ShouldBeSameAs(boom);
    }

    [Fact]
    public async Task IdentityProviderException_is_still_logged_at_error_with_the_exception_attached()
    {
        // 502 is an upstream outage, not caller error — it keeps its alarm and its stack trace.
        var upstream = new IdentityProviderException("Keycloak returned 503 for POST /users");

        var written = await HandleAsync(upstream);

        var logged = written.Logged.ShouldHaveSingleItem();
        logged.Level.ShouldBe(LogLevel.Error);
        logged.Exception.ShouldBeSameAs(upstream);
    }

    [Fact]
    public async Task BadHttpRequestException_is_not_logged_as_an_error()
    {
        var written = await HandleAsync(new BadHttpRequestException(LeakyBindingMessage));

        written.Logged.ShouldNotContain(
            entry => entry.Level >= LogLevel.Error,
            "a malformed request is user input; alarming on it is the false alarm this fixes");
        // Nor may the quoted request content reach a log line by this route (§F).
        written.Logged.ShouldBeEmpty();
    }

    [Fact]
    public async Task DuplicateUserException_is_not_logged_as_an_error()
    {
        // A 409 is the caller re-using an email — the same class of event as a 400, not an outage.
        var written = await HandleAsync(new DuplicateUserException("An account with that email already exists."));

        written.Logged.ShouldBeEmpty();
    }
}
