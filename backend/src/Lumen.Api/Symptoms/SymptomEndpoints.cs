using System.Diagnostics;
using Lumen.Api.Validation;

namespace Lumen.Api.Symptoms;

/// <summary>
/// Route registrations for the whole §C.3 symptoms resource: the batch create (T11) plus the range
/// read, the full replace and the soft delete that complete it (T12).
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

        // The range read. `from`/`to` are required USER-LOCAL days and both inclusive; a future `to`
        // is legitimate here (a month view spans forward) even though every write is capped by today.
        // All four are nullable so an out-of-range value reaches the validator and comes back attached
        // to its own field — an unparseable one still fails at the binder and becomes T3's one 400
        // under `request`, which is the correct answer for a body that could not be read at all.
        app.MapGet("/symptoms", async (
            DateOnly? from,
            DateOnly? to,
            int? limit,
            int? offset,
            SymptomService symptoms,
            CancellationToken ct) =>
        {
            var result = await symptoms.ListAsync(from, to, limit, offset, ct);
            return result switch
            {
                SymptomListResult.Found found => Results.Ok(found.Page),
                SymptomListResult.Invalid invalid => Problem(invalid.Errors),
                SymptomListResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(SymptomListResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<SymptomListResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // PUT, not PATCH (T12). The row is FULL REPLACE — an omitted classification field CLEARS the
        // stored value — and PATCH has a defined meaning that contradicts exactly that, so a client
        // author sending only the changed field would suffer silent data loss. The verb is the
        // safety affordance; §C.3 is amended in the same commit. See ReplaceSymptomRequest.
        // The `:guid` constraint keeps a malformed id out of the handler entirely.
        app.MapPut("/symptoms/{id:guid}", async (
            Guid id,
            ReplaceSymptomRequest request,
            SymptomService symptoms,
            CancellationToken ct) =>
        {
            var result = await symptoms.ReplaceAsync(id, request, ct);
            return result switch
            {
                SymptomReplaceResult.Saved saved => Results.Ok(saved.Symptom),
                SymptomReplaceResult.Invalid invalid => Problem(invalid.Errors),
                SymptomReplaceResult.NotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(SymptomReplaceResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<SymptomResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // Soft delete (D-13): 204, and 404 for an unknown id, an already-deleted one and — the case
        // that matters — another user's, because tenant isolation is 404 and never 403.
        app.MapDelete("/symptoms/{id:guid}", async (
            Guid id,
            SymptomService symptoms,
            CancellationToken ct) =>
        {
            var result = await symptoms.DeleteAsync(id, ct);
            return result switch
            {
                SymptomDeleteResult.Deleted => Results.NoContent(),
                SymptomDeleteResult.NotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(SymptomDeleteResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces(StatusCodes.Status204NoContent)
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
