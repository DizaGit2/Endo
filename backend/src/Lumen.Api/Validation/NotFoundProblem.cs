namespace Lumen.Api.Validation;

/// <summary>
/// The one 404 body every P4a endpoint returns (T3 review fix, promoting the commit-message
/// convention T3 set into code). Roughly fifteen later tasks each need this shape; before this type
/// existed every one of them hand-wrote the literal, and a single typo in any of them would have
/// quietly broken the "one 404 body" claim with nothing to catch it.
/// </summary>
/// <remarks>
/// <b>Tenant isolation returns this too — never a 403.</b> A 403 on a row that belongs to another
/// user would itself confirm the id exists; a 404 does not.
/// </remarks>
public static class NotFoundProblem
{
    /// <summary>
    /// The frozen 404 title, exposed so callers and tests can assert it verbatim without retyping the
    /// literal.
    /// </summary>
    public const string Title = "The requested resource was not found.";

    /// <summary>Builds the canonical 404 <see cref="IResult"/>.</summary>
    public static IResult Result() =>
        TypedResults.Problem(statusCode: StatusCodes.Status404NotFound, title: Title);
}
