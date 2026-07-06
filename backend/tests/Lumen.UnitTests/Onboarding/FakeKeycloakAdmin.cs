using Lumen.Application.Auth;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Hand-rolled <see cref="IKeycloakAdmin"/> test double. Records every call so tests can assert
/// exactly what <c>OnboardingService</c> did — or, for validation failures, did NOT do — against
/// Keycloak, and can be configured to fail <see cref="CreateUserAsync"/> to exercise the
/// compensation and duplicate-user paths.
/// </summary>
internal sealed class FakeKeycloakAdmin : IKeycloakAdmin
{
    public List<(string Email, string Password)> CreateCalls { get; } = [];
    public List<Guid> DeleteCalls { get; } = [];
    public List<Guid> DisableCalls { get; } = [];

    /// <summary>The user id <see cref="CreateUserAsync"/> returns on success.</summary>
    public Guid UserIdToReturn { get; set; } = Guid.NewGuid();

    /// <summary>When set, <see cref="CreateUserAsync"/> throws this instead of returning.</summary>
    public Exception? ThrowOnCreate { get; set; }

    public Task<Guid> CreateUserAsync(string email, string password, CancellationToken ct = default)
    {
        CreateCalls.Add((email, password));
        if (ThrowOnCreate is { } ex) throw ex;
        return Task.FromResult(UserIdToReturn);
    }

    public Task DeleteUserAsync(Guid userId, CancellationToken ct = default)
    {
        DeleteCalls.Add(userId);
        return Task.CompletedTask;
    }

    public Task DisableUserAsync(Guid userId, CancellationToken ct = default)
    {
        DisableCalls.Add(userId);
        return Task.CompletedTask;
    }
}
