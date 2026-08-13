using System.Diagnostics;
using Lumen.Api.Validation;

namespace Lumen.Api.Devices;

/// <summary>
/// Route registration for the §C.9 push-device resource (T15): <c>POST /me/devices</c>, the token
/// upsert the client calls on first launch and on every push-token refresh.
/// </summary>
/// <remarks>
/// Same shape as <see cref="CycleSettings.CycleSettingsEndpoints"/> and
/// <see cref="Cycle.CycleEndpoints"/> (§G12): no <c>MapGroup</c>, no <c>.WithTags</c>, no
/// <c>.WithName</c> — a tag would split this operation out of the generated Dart client's
/// <c>LumenApiApi</c> class and break <c>client/lib/core/network/api_client.dart</c> plus both
/// repositories. The handler stays thin: every decision lives in
/// <see cref="DeviceRegistrationService"/>, where it is unit-testable without HTTP, and this file only
/// translates a result into a status, routing the 404 through <see cref="NotFoundProblem"/> and the
/// 400 through <see cref="ValidationProblemBuilder"/> so the phase keeps one error body each.
/// </remarks>
public static class DeviceEndpoints
{
    public static IEndpointRouteBuilder MapDeviceEndpoints(this IEndpointRouteBuilder app)
    {
        // Answers 200 on both the insert and the update path: an upsert has no actionable
        // created/updated distinction for a client that re-registers on every token refresh, and §C.9
        // exposes no `GET /me/devices/{id}` for a `Location` header to point at. The body carries the
        // stored row MINUS its token (§F).
        app.MapPost("/me/devices", async (
            RegisterDeviceRequest request,
            DeviceRegistrationService devices,
            CancellationToken ct) =>
        {
            var result = await devices.RegisterAsync(request, ct);
            return result switch
            {
                DeviceRegistrationResult.Saved saved => Results.Ok(saved.Device),
                DeviceRegistrationResult.Invalid invalid => Problem(invalid.Errors),
                DeviceRegistrationResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(DeviceRegistrationResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<RegisterDeviceResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    /// <summary>
    /// Replays the service's field errors into the phase's one 400 body. Several messages may share a
    /// key (the builder keeps them in order), which is why this loops rather than building a map.
    /// </summary>
    private static IResult Problem(IReadOnlyList<DeviceFieldError> errors)
    {
        var problems = new ValidationProblemBuilder();
        foreach (var error in errors) problems.Add(error.Field, error.Message);
        return problems.Build();
    }
}
