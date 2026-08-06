using Lumen.Api.Validation;
using Lumen.Application.Auth;
using Microsoft.AspNetCore.Diagnostics;

namespace Lumen.Api;

/// <summary>
/// Maps known exceptions to clean ProblemDetails responses with no internal detail or stack traces
/// (§F): malformed request → 400, duplicate identity → 409, upstream identity error → 502,
/// everything else → a generic 500.
/// </summary>
/// <remarks>
/// <b>No arm ever echoes <c>exception.Message</c> to a client that did not already own the
/// information.</b> The 409 does — its message is the caller's own email collision, phrased for
/// display. The 400 must not: a binding failure message quotes the value that failed to bind, and in
/// this app that value is health data (an intensity, a symptom code, a date).
/// </remarks>
public sealed class ProblemExceptionHandler(IProblemDetailsService problemDetails) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var (status, title) = exception switch
        {
            // First arm on purpose (T3). RouteHandlerOptions.ThrowOnBadRequest is on, so every
            // minimal-API binding failure — unparseable JSON, a route/query value of the wrong type,
            // a missing required parameter — arrives here rather than short-circuiting. Without this
            // arm it falls through to the generic 500: an operational alarm for what is really user
            // input, and a ServerFailure in the Dart client where a ValidationFailure belongs.
            // BadHttpRequestException.StatusCode (413/431 from the size limits) is deliberately
            // collapsed onto 400 — one 400 body for the phase beats a status the client cannot map.
            BadHttpRequestException => (StatusCodes.Status400BadRequest, "Validation failed."),
            DuplicateUserException => (StatusCodes.Status409Conflict, exception.Message),
            IdentityProviderException => (StatusCodes.Status502BadGateway, "An upstream identity service error occurred."),
            _ => (StatusCodes.Status500InternalServerError, "An unexpected error occurred."),
        };

        httpContext.Response.StatusCode = status;
        var context = new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = { Status = status, Title = title },
        };

        // The same `errors: { field: [messages] }` envelope ValidationProblemBuilder emits, under the
        // reserved cross-field key: a client parsing a 400 never has to care which side produced it.
        // Detail is the same shared sentence too (T3 review fix): the client renders `detail ?? title`
        // (error_mapper.dart), and title deliberately still differs from the builder's so the two 400
        // producers stay distinguishable in logs.
        if (exception is BadHttpRequestException)
        {
            context.ProblemDetails.Detail = ValidationMessages.RequestDetail;
            context.ProblemDetails.Extensions["errors"] = new Dictionary<string, string[]>(StringComparer.Ordinal)
            {
                [ValidationProblemBuilder.RequestKey] = [ValidationMessages.MalformedRequest],
            };
        }

        return await problemDetails.TryWriteAsync(context);
    }
}
