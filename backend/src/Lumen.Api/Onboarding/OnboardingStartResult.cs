namespace Lumen.Api.Onboarding;

/// <summary>Result of <see cref="OnboardingService.StartAsync"/>: either the new user id, or a validation failure.</summary>
public abstract record OnboardingStartResult
{
    public sealed record Success(Guid UserId) : OnboardingStartResult;

    public sealed record Invalid(string Error) : OnboardingStartResult;
}
