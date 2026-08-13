namespace Lumen.Api.Onboarding;

/// <summary>Result of <see cref="OnboardingService.StartAsync"/>: either the new user id, or a validation failure.</summary>
public abstract record OnboardingStartResult
{
    public sealed record Success(Guid UserId) : OnboardingStartResult;

    /// <summary>
    /// A rejected request. <paramref name="Field"/> carries the camelCase JSON field name the message
    /// belongs to, or <see cref="Lumen.Api.Validation.ValidationProblemBuilder.RequestKey"/> when no
    /// single input owns the error — the endpoint feeds both straight into the phase's one 400 body,
    /// whose <c>errors</c> map is how the Flutter client attaches a message to an input.
    /// </summary>
    /// <remarks>
    /// One failure at a time, deliberately: unlike the twenty later P4a endpoints, this one is a
    /// sign-up form whose checks are sequential (an email must parse before it can be canonicalised),
    /// and its four messages predate <c>ValidationMessages</c> and are already on the wire.
    /// </remarks>
    public sealed record Invalid(string Field, string Error) : OnboardingStartResult;
}
