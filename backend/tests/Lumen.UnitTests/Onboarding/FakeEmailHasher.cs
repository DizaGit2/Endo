using Lumen.Application.Crypto;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Hand-rolled <see cref="IEmailHasher"/> test double. Returns a fixed, obviously-fake HMAC token so
/// tests can assert <c>OnboardingService</c> persists exactly what the hasher returns — see the
/// negative control in <c>OnboardingServiceTests</c> proving it is NOT the raw SHA-256 hex the code
/// used before Vault Transit HMAC (P3c-T3).
/// </summary>
internal sealed class FakeEmailHasher : IEmailHasher
{
    public const string FakeHmac = "vault:v1:FAKEHMAC";

    public List<string> HashCalls { get; } = [];

    public Task<string> HashEmailAsync(string email, CancellationToken ct = default)
    {
        HashCalls.Add(email);
        return Task.FromResult(FakeHmac);
    }
}
