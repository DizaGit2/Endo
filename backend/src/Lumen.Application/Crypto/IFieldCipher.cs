namespace Lumen.Application.Crypto;

/// <summary>
/// Field-level authenticated cipher for envelope-encrypted columns. Callers supply a
/// 256-bit data key (the per-user DEK). Implementations MUST use AES-256-GCM with a fresh
/// random nonce per call; output is self-describing (nonce ‖ ciphertext ‖ tag) so no nonce
/// needs to be stored separately. Decryption fails loudly if the key is wrong or bytes were tampered.
/// </summary>
public interface IFieldCipher
{
    byte[] Encrypt(byte[] plaintext, byte[] key);
    byte[] Decrypt(byte[] blob, byte[] key);
    byte[] EncryptString(string plaintext, byte[] key);
    string DecryptString(byte[] blob, byte[] key);
}
