using System.Security.Cryptography;
using System.Text;
using Lumen.Application.Crypto;
using Lumen.Infrastructure.Crypto;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Crypto;

public class AesGcmFieldCipherTests
{
    private readonly IFieldCipher _cipher = new AesGcmFieldCipher();

    private static byte[] NewKey() => RandomNumberGenerator.GetBytes(32);

    [Fact]
    public void Encrypt_then_Decrypt_roundtrips_bytes()
    {
        var key = NewKey();
        var plaintext = Encoding.UTF8.GetBytes("ovary pain left side");

        var blob = _cipher.Encrypt(plaintext, key);
        var recovered = _cipher.Decrypt(blob, key);

        recovered.ShouldBe(plaintext);
    }

    [Fact]
    public void EncryptString_then_DecryptString_roundtrips()
    {
        var key = NewKey();
        const string secret = "Diagnóstico: estadio II — síntomas"; // unicode survives round-trip

        var blob = _cipher.EncryptString(secret, key);

        _cipher.DecryptString(blob, key).ShouldBe(secret);
    }

    [Fact]
    public void SamePlaintextAndKey_ProducesDifferentBlobs()
    {
        var key = NewKey();
        var plaintext = Encoding.UTF8.GetBytes("same input");

        var a = _cipher.Encrypt(plaintext, key);
        var b = _cipher.Encrypt(plaintext, key);

        a.ShouldNotBe(b); // fresh random nonce each call
    }

    [Fact]
    public void Blob_DoesNotContainPlaintext()
    {
        var key = NewKey();
        var plaintext = Encoding.UTF8.GetBytes("PLAINTEXT_MARKER");

        var blob = _cipher.Encrypt(plaintext, key);

        Encoding.UTF8.GetString(blob).ShouldNotContain("PLAINTEXT_MARKER");
    }

    [Fact]
    public void TamperedBlob_FailsToDecrypt()
    {
        var key = NewKey();
        var blob = _cipher.EncryptString("authentic", key);
        blob[^1] ^= 0xFF; // flip a bit in the tag

        Should.Throw<CryptographicException>(() => _cipher.Decrypt(blob, key));
    }

    [Fact]
    public void WrongKey_FailsToDecrypt()
    {
        var blob = _cipher.EncryptString("authentic", NewKey());

        Should.Throw<CryptographicException>(() => _cipher.Decrypt(blob, NewKey()));
    }

    [Theory]
    [InlineData(16)]
    [InlineData(31)]
    [InlineData(33)]
    public void BadKeyLength_Throws(int keyLength)
    {
        var badKey = RandomNumberGenerator.GetBytes(keyLength);

        Should.Throw<ArgumentException>(() => _cipher.EncryptString("x", badKey));
    }
}
