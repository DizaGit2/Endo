using System.Diagnostics;
using Lumen.Api.Validation;

namespace Lumen.Api.CycleSettings;

/// <summary>
/// Route registrations for the §C.9 cycle-settings resource (T14): the read and the merge-patch behind
/// screen 32, including the C-12 tracking-pause card.
/// </summary>
/// <remarks>
/// Same shape as <see cref="Cycle.CycleEndpoints"/> and <see cref="Symptoms.SymptomEndpoints"/> (§G12):
/// no <c>MapGroup</c>, no <c>.WithTags</c>, no <c>.WithName</c> — a tag would split these operations out
/// of the generated Dart client's <c>LumenApiApi</c> class and break
/// <c>client/lib/core/network/api_client.dart</c> plus both repositories. The handlers stay thin: every
/// decision lives in <see cref="CycleSettingsService"/>, where it is unit-testable without HTTP, and
/// this file only translates a result into a status, routing the 404 through
/// <see cref="NotFoundProblem"/> and the 400 through <see cref="ValidationProblemBuilder"/> so the phase
/// keeps one error body each.
/// </remarks>
public static class CycleSettingsEndpoints
{
    public static IEndpointRouteBuilder MapCycleSettingsEndpoints(this IEndpointRouteBuilder app)
    {
        // The read (screen 32 on load). No 400 is documented: the request has no input to reject, so
        // the only failures are an absent token and an unknown user. A user with NO settings row is a
        // 200 carrying the T6 defaults and null timestamps — never a 404, which on this route means
        // "no such user" and nothing else (§G12).
        app.MapGet("/settings/cycle", async (
            CycleSettingsService settings,
            CancellationToken ct) =>
        {
            var result = await settings.GetAsync(ct);
            return result switch
            {
                CycleSettingsReadResult.Found found => Results.Ok(found.Settings),
                CycleSettingsReadResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleSettingsReadResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleSettingsResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // The merge patch, including the pause state machine. Answers 200 with the FULL resource rather
        // than 204 like PATCH /me: the body carries the non-blocking §G7 warnings and the derived
        // `phasesUnavailable` flag, which an online-only client would otherwise have to re-fetch on
        // every save just to render the hint under the field the user has just left.
        app.MapPatch("/settings/cycle", async (
            UpdateCycleSettingsRequest request,
            CycleSettingsService settings,
            CancellationToken ct) =>
        {
            var result = await settings.UpdateAsync(request, ct);
            return result switch
            {
                CycleSettingsUpdateResult.Saved saved => Results.Ok(saved.Settings),
                CycleSettingsUpdateResult.Invalid invalid => Problem(invalid.Errors),
                CycleSettingsUpdateResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleSettingsUpdateResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleSettingsResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    /// <summary>
    /// Replays the service's field errors into the phase's one 400 body. Several messages may share a
    /// key (the builder keeps them in order), which is why this loops rather than building a map.
    /// </summary>
    private static IResult Problem(IReadOnlyList<CycleSettingsFieldError> errors)
    {
        var problems = new ValidationProblemBuilder();
        foreach (var error in errors) problems.Add(error.Field, error.Message);
        return problems.Build();
    }
}
