namespace Lumen.Application.Crypto;

/// <summary>
/// Factory for creating job-scoped <see cref="IJobCryptoContext"/> instances. A factory is required
/// because the user id is a runtime value (known only when the job runs), not a DI-resolvable dependency.
/// Resolved as a scoped service so it shares the job-scoped <c>DbContext</c>.
/// </summary>
public interface IJobCryptoContextFactory
{
    /// <summary>
    /// Creates a new <see cref="IJobCryptoContext"/> bound to the specified <paramref name="userId"/>.
    /// Callers are responsible for disposing the returned context.
    /// </summary>
    IJobCryptoContext Create(Guid userId);
}
