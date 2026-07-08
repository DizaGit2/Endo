using Lumen.Application.Crypto;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Hand-rolled <see cref="IKeyWrapper"/> test double. "Wraps" by prefixing a marker onto the DEK
/// bytes (reversible via <see cref="UnwrapAsync"/>, if a future test needs it) and can be
/// configured to throw so tests can exercise <c>OnboardingService</c>'s compensation path.
/// </summary>
internal sealed class FakeKeyWrapper : IKeyWrapper
{
    private static readonly byte[] Prefix = "wrapped:"u8.ToArray();

    /// <summary>When set, <see cref="WrapAsync"/> throws this instead of returning.</summary>
    public Exception? ThrowOnWrap { get; set; }

    public Task<byte[]> WrapAsync(byte[] dek, CancellationToken ct = default)
    {
        if (ThrowOnWrap is { } ex) throw ex;
        return Task.FromResult(Prefix.Concat(dek).ToArray());
    }

    public Task<byte[]> UnwrapAsync(byte[] wrappedDek, CancellationToken ct = default)
        => Task.FromResult(wrappedDek[Prefix.Length..]);
}
