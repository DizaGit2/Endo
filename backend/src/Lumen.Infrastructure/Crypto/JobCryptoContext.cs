using Lumen.Application.Crypto;
using Lumen.Infrastructure.Persistence;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// Job-scoped implementation of <see cref="IJobCryptoContext"/>. The DEK is unwrapped at most
/// once per instance (guarded for concurrent first-use), held only in this instance, and zeroed on
/// disposal — so it never outlives the job and two jobs never share key material. The user id is
/// supplied explicitly at construction time rather than obtained from an HTTP request context.
/// </summary>
public sealed class JobCryptoContext(
    LumenDbContext db,
    IKeyWrapper keyWrapper,
    IFieldCipher fieldCipher,
    Guid userId)
    : DekCryptoContextBase(db, keyWrapper, fieldCipher), IJobCryptoContext
{
    protected override Guid GetUserId() => userId;
}
