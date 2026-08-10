using System.Diagnostics;
using Lumen.Api.Validation;

namespace Lumen.Api.Onboarding;

/// <summary>
/// Route registrations for the onboarding feature. Extracted from <c>Program.cs</c> by T4 as a pure
/// move so the fifteen later P4a tasks that add onboarding endpoints (<c>/onboarding/cycle</c>,
/// <c>/onboarding/baseline</c>, <c>/onboarding/state</c>, …) extend this file instead of growing the
/// startup file further.
/// </summary>
/// <remarks>
/// No <c>MapGroup</c>, no <c>.WithTags</c>, no <c>.WithName</c> (§G12): a tag would split these
/// operations out of the generated Dart client's <c>LumenApiApi</c> class and break
/// <c>client/lib/core/network/api_client.dart</c> plus both repositories.
/// </remarks>
public static class OnboardingEndpoints
{
    public static IEndpointRouteBuilder MapOnboardingEndpoints(this IEndpointRouteBuilder app)
    {
        // Creates the Keycloak user, provisions the Vault-wrapped DEK, writes the encrypted profile + consent.
        app.MapPost("/onboarding/start", async (
            OnboardingStartRequest request,
            OnboardingService onboarding,
            CancellationToken ct) =>
        {
            var result = await onboarding.StartAsync(request, ct);
            return result switch
            {
                OnboardingStartResult.Success success => Results.Ok(new OnboardingStartResponse(success.UserId)),
                // The one P4a 400 body (T3): `errors: { <field>: [message] }` + the shared detail.
                // The service reports a single failure at a time, so exactly one key is ever present.
                OnboardingStartResult.Invalid invalid =>
                    new ValidationProblemBuilder().Add(invalid.Field, invalid.Error).Build(),
                _ => throw new UnreachableException($"Unhandled {nameof(OnboardingStartResult)}: {result.GetType()}"),
            };
        })
        // Sign-up: the caller cannot have a token yet. The per-IP policy is what protects it, since the
        // global limiter partitions on `sub` and there is no `sub` here.
        .AllowAnonymous()
        .RequireRateLimiting("onboarding-start")
        .Produces<OnboardingStartResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem();

        // The D-02 baseline step (screen 4). Unlike /onboarding/start this one is AUTHENTICATED: the
        // account already exists by the time the user answers it, and the data it carries is
        // special-category health data. Answers 200 with the stored row decrypted back on both the
        // insert and the update path — a step the user may revisit has no actionable created/updated
        // distinction, and §C.1 exposes no `GET /onboarding/baseline` for a `Location` to point at
        // (the read path is `GET /me`).
        app.MapPost("/onboarding/baseline", async (
            SaveBaselineRequest request,
            OnboardingStepsService steps,
            CancellationToken ct) =>
        {
            var result = await steps.SaveBaselineAsync(request, ct);
            return result switch
            {
                SaveBaselineResult.Saved saved => Results.Ok(saved.Baseline),
                SaveBaselineResult.Invalid invalid => Problem(invalid.Errors),
                SaveBaselineResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(SaveBaselineResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<BaselineResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    /// <summary>
    /// Replays a step service's field errors into the phase's one 400 body. Several messages may share
    /// a key (the builder keeps them in order), which is why this loops rather than building a map.
    /// </summary>
    private static IResult Problem(IReadOnlyList<OnboardingFieldError> errors)
    {
        var problems = new ValidationProblemBuilder();
        foreach (var error in errors) problems.Add(error.Field, error.Message);
        return problems.Build();
    }
}
