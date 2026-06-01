using System.Security.Cryptography;
using System.Text;
using Lumen.Application.Crypto;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// AES-256-GCM implementation of <see cref="IFieldCipher"/>. Layout per value:
/// <c>nonce(12) ‖ ciphertext(n) ‖ tag(16)</c>. A fresh random nonce is generated for every
/// encryption, so encrypting the same plaintext twice yields different blobs.
/// </summary>
public sealed class AesGcmFieldCipher : IFieldCipher
{
    private const int KeySize = 32;    // 256-bit DEK
    private const int NonceSize = 12;  // 96-bit GCM nonce
    private const int TagSize = 16;    // 128-bit auth tag

    public byte[] Encrypt(byte[] plaintext, byte[] key)
    {
        ArgumentNullException.ThrowIfNull(plaintext);
        ValidateKey(key);

        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagSize];

        using var gcm = new AesGcm(key, TagSize);
        gcm.Encrypt(nonce, plaintext, ciphertext, tag);

        var blob = new byte[NonceSize + ciphertext.Length + TagSize];
        Buffer.BlockCopy(nonce, 0, blob, 0, NonceSize);
        Buffer.BlockCopy(ciphertext, 0, blob, NonceSize, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, blob, NonceSize + ciphertext.Length, TagSize);
        return blob;
    }

    public byte[] Decrypt(byte[] blob, byte[] key)
    {
        ArgumentNullException.ThrowIfNull(blob);
        ValidateKey(key);
        if (blob.Length < NonceSize + TagSize)
            throw new ArgumentException("Ciphertext blob is too short.", nameof(blob));

        var ctLength = blob.Length - NonceSize - TagSize;
        var nonce = new byte[NonceSize];
        var ciphertext = new byte[ctLength];
        var tag = new byte[TagSize];

        Buffer.BlockCopy(blob, 0, nonce, 0, NonceSize);
        Buffer.BlockCopy(blob, NonceSize, ciphertext, 0, ctLength);
        Buffer.BlockCopy(blob, NonceSize + ctLength, tag, 0, TagSize);

        var plaintext = new byte[ctLength];
        using var gcm = new AesGcm(key, TagSize);
        // Throws AuthenticationTagMismatchException if the key is wrong or the blob was tampered.
        gcm.Decrypt(nonce, ciphertext, tag, plaintext);
        return plaintext;
    }

    public byte[] EncryptString(string plaintext, byte[] key)
        => Encrypt(Encoding.UTF8.GetBytes(plaintext), key);

    public string DecryptString(byte[] blob, byte[] key)
        => Encoding.UTF8.GetString(Decrypt(blob, key));

    private static void ValidateKey(byte[] key)
    {
        ArgumentNullException.ThrowIfNull(key);
        if (key.Length != KeySize)
            throw new ArgumentException($"Key must be {KeySize} bytes (256-bit).", nameof(key));
    }
}
