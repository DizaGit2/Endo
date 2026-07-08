using Lumen.Application.Auth;
using Lumen.Application.Crypto;
using Lumen.Infrastructure.Persistence;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// Request-scoped implementation of <see cref="IUserCryptoContext"/>. The DEK is unwrapped at most
/// once per instance (guarded for concurrent first-use), held only in this instance, and zeroed on
/// disposal — so it never outlives the request and two requests never share key material.
/// </summary>
public sealed class UserCryptoContext(
    LumenDbContext db,
    IKeyWrapper keyWrapper,
    IFieldCipher fieldCipher,
    ICurrentUserAccessor currentUser)
    : DekCryptoContextBase(db, keyWrapper, fieldCipher), IUserCryptoContext
{
    protected override Guid GetUserId() => currentUser.UserId;
}
