namespace Lumen.Application.Crypto;

/// <summary>
/// Factory for creating job-scoped <see cref="IJobCryptoContext"/> instances. A factory is required
/// because the user id is a runtime value (known only when the job runs), not a DI-resolvable dependency.
/// Resolved as a scoped service so it shares the job-scoped <c>DbContext</c>.
/// Each returned context is single-owner and must be used sequentially — no overlapping/concurrent crypto
/// ops; contexts from this factory share the job-scoped DbContext, which is not thread-safe.
/// </summary>
public interface IJobCryptoContextFactory
{
    /// <summary>
    /// Creates a new <see cref="IJobCryptoContext"/> bound to <paramref name="userId"/>. The caller owns
    /// the returned instance and MUST dispose it (via <c>await using</c>) so the unwrapped DEK is zeroed promptly.
    /// </summary>
    IJobCryptoContext Create(Guid userId);
}
