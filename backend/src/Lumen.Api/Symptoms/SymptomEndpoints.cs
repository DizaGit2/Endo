using System.Diagnostics;
using Lumen.Api.Validation;

namespace Lumen.Api.Symptoms;

/// <summary>
/// Route registrations for the symptoms write surface (§C.3, T11).
/// </summary>
/// <remarks>
/// Same shape as <see cref="Cycle.CycleEndpoints"/> (§G12): no <c>MapGroup</c>, no <c>.WithTags</c>,
/// no <c>.WithName</c> — a tag would split these operations out of the generated Dart client's
/// <c>LumenApiApi</c> class and break <c>client/lib/core/network/api_client.dart</c> plus both
/// repositories. The handler stays thin: every decision lives in <see cref="SymptomService"/>, where
/// it is unit-testable without HTTP, and this file only translates a result into a status, routing
/// the 404 through <see cref="NotFoundProblem"/> and the 400 through
/// <see cref="ValidationProblemBuilder"/> so the phase keeps one error body each.
///
/// <para><c>POST /checkin/quick</c> is a §C.3 route but writes only <c>cycle_day_logs</c>, so it is
/// registered in <see cref="Cycle.CycleEndpoints"/> beside the day upsert it shares a row with,
/// rather than here (T10).</para>
/// </remarks>
public static class SymptomEndpoints
{
    public static IEndpointRouteBuilder MapSymptomEndpoints(this IEndpointRouteBuilder app)
    {
        // The batch create (OQ-6): 1–50 entries, all-or-nothing, one unit of work. See
        // CreateSymptomsRequest for why one save is one request rather than N.
        app.MapPost("/symptoms", async (
            CreateSymptomsRequest request,
            SymptomService symptoms,
            CancellationToken ct) =>
        {
            var result = await symptoms.CreateAsync(request, ct);
            return result switch
            {
                // 201 with NO Location header: a batch creates N resources and Location holds one
                // URI, so there is nothing honest to put in it. The ids are in the body.
                SymptomCreateResult.Saved saved =>
                    Results.Json(saved.Created, statusCode: StatusCodes.Status201Created),
                SymptomCreateResult.Invalid invalid => Problem(invalid.Errors),
                SymptomCreateResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(SymptomCreateResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CreateSymptomsResponse>(StatusCodes.Status201Created)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    /// <summary>
    /// Replays the service's field errors into the phase's one 400 body. Several messages may share a
    /// key (the builder keeps them in order), which is why this loops rather than building a map.
    /// </summary>
    private static IResult Problem(IReadOnlyList<SymptomFieldError> errors)
    {
        var problems = new ValidationProblemBuilder();
        foreach (var error in errors) problems.Add(error.Field, error.Message);
        return problems.Build();
    }
}
