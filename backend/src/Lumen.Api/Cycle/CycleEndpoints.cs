using System.Diagnostics;
using Lumen.Api.Validation;

namespace Lumen.Api.Cycle;

/// <summary>
/// Route registrations for the cycle write surface (T9) — the first feature endpoints of P4a, and the
/// shape the eight endpoint tasks after it copy.
/// </summary>
/// <remarks>
/// No <c>MapGroup</c>, no <c>.WithTags</c>, no <c>.WithName</c> (§G12): a tag would split these
/// operations out of the generated Dart client's <c>LumenApiApi</c> class and break
/// <c>client/lib/core/network/api_client.dart</c> plus both repositories. The handlers stay thin —
/// every decision lives in <see cref="CycleService"/>, where it is unit-testable without HTTP — and
/// each one does exactly two things: translate a result into a status, and route every 404 through
/// <see cref="NotFoundProblem"/> and every 400 through <see cref="ValidationProblemBuilder"/> so the
/// phase keeps one error body each (§G12).
/// </remarks>
public static class CycleEndpoints
{
    public static IEndpointRouteBuilder MapCycleEndpoints(this IEndpointRouteBuilder app)
    {
        // Upsert on (user, kind, day) — see CycleService for the §G9 tombstone-revival contract.
        app.MapPost("/cycle/events", async (
            LogCycleEventRequest request,
            CycleService cycle,
            CancellationToken ct) =>
        {
            var result = await cycle.LogEventAsync(request, ct);
            return result switch
            {
                CycleEventResult.Saved saved => Results.Ok(saved.Event),
                CycleEventResult.Invalid invalid => Problem(invalid.Errors),
                CycleEventResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleEventResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleEventResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // Soft delete (D-13). §C.2 had no DELETE; OQ-5 added it and the same branch amends §C.2.
        // The `:guid` constraint keeps a malformed id out of the handler entirely.
        app.MapDelete("/cycle/events/{id:guid}", async (
            Guid id,
            CycleService cycle,
            CancellationToken ct) =>
        {
            var result = await cycle.DeleteEventAsync(id, ct);
            return result switch
            {
                CycleEventDeleteResult.Deleted => Results.NoContent(),
                CycleEventDeleteResult.NotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleEventDeleteResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // Replace-the-set for one cycle; `boundaries: []` is screen 14's "Reset to predicted".
        app.MapPost("/cycle/phase-override", async (
            SavePhaseOverridesRequest request,
            CycleService cycle,
            CancellationToken ct) =>
        {
            var result = await cycle.SavePhaseOverridesAsync(request, ct);
            return result switch
            {
                PhaseOverrideResult.Saved saved => Results.Ok(saved.Overrides),
                PhaseOverrideResult.Invalid invalid => Problem(invalid.Errors),
                PhaseOverrideResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(PhaseOverrideResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<PhaseOverridesResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    /// <summary>
    /// Replays the service's field errors into the phase's one 400 body. Several messages may share a
    /// key (the builder keeps them in order), which is why this loops rather than building a map.
    /// </summary>
    private static IResult Problem(IReadOnlyList<CycleFieldError> errors)
    {
        var problems = new ValidationProblemBuilder();
        foreach (var error in errors) problems.Add(error.Field, error.Message);
        return problems.Build();
    }
}
