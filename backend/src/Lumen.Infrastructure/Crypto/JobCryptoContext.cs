using System.Security.Cryptography;
using System.Text;
using Lumen.Application.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Infrastructure.Crypto;

// Intentional mirror of UserCryptoContext (job-scoped instead of request-scoped). Keep the DEK-custody logic in sync.
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
    Guid userId) : IJobCryptoContext
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile byte[]? _dek;

    private async Task<byte[]> GetDekAsync(CancellationToken ct)
    {
        if (_dek is not null) return _dek;
        await _gate.WaitAsync(ct);
        try
        {
            if (_dek is not null) return _dek;
            // Do not embed the user id (PII / cross-system key) in the exception message — see §F.
            var userKey = await db.UserKeys.AsNoTracking().FirstOrDefaultAsync(k => k.UserId == userId, ct)
                ?? throw new InvalidOperationException("No DEK provisioned for the current user.");
            _dek = await keyWrapper.UnwrapAsync(userKey.WrappedDek, ct);
            return _dek;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<byte[]> EncryptAsync(byte[] plaintext, CancellationToken ct = default)
        => fieldCipher.Encrypt(plaintext, await GetDekAsync(ct));

    public async Task<byte[]> DecryptAsync(byte[] blob, CancellationToken ct = default)
        => fieldCipher.Decrypt(blob, await GetDekAsync(ct));

    public async Task<byte[]> EncryptStringAsync(string plaintext, CancellationToken ct = default)
        => fieldCipher.Encrypt(Encoding.UTF8.GetBytes(plaintext), await GetDekAsync(ct));

    public async Task<string> DecryptStringAsync(byte[] blob, CancellationToken ct = default)
        => Encoding.UTF8.GetString(fieldCipher.Decrypt(blob, await GetDekAsync(ct)));

    public ValueTask DisposeAsync()
    {
        if (_dek is not null)
        {
            CryptographicOperations.ZeroMemory(_dek);
            _dek = null;
        }
        _gate.Dispose();
        return ValueTask.CompletedTask;
    }
}
