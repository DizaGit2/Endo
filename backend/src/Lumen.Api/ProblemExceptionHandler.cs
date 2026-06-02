using Lumen.Application.Auth;
using Microsoft.AspNetCore.Diagnostics;

namespace Lumen.Api;

/// <summary>
/// Maps known exceptions to clean ProblemDetails responses with no internal detail or stack traces
/// (§F): duplicate identity → 409, upstream identity error → 502, everything else → a generic 500.
/// </summary>
public sealed class ProblemExceptionHandler(IProblemDetailsService problemDetails) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var (status, title) = exception switch
        {
            DuplicateUserException => (StatusCodes.Status409Conflict, exception.Message),
            IdentityProviderException => (StatusCodes.Status502BadGateway, "An upstream identity service error occurred."),
            _ => (StatusCodes.Status500InternalServerError, "An unexpected error occurred."),
        };

        httpContext.Response.StatusCode = status;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = { Status = status, Title = title },
        });
    }
}
