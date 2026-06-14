using Lumen.Application.Crypto;
using Lumen.Infrastructure.Persistence;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// Scoped factory that creates <see cref="JobCryptoContext"/> instances for background jobs.
/// Resolved as a scoped service so it shares the job-scoped <see cref="LumenDbContext"/>.
/// </summary>
public sealed class JobCryptoContextFactory(
    LumenDbContext db,
    IKeyWrapper keyWrapper,
    IFieldCipher fieldCipher) : IJobCryptoContextFactory
{
    public IJobCryptoContext Create(Guid userId)
        => new JobCryptoContext(db, keyWrapper, fieldCipher, userId);
}
