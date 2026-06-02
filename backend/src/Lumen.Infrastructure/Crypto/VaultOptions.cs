namespace Lumen.Infrastructure.Crypto;

/// <summary>Vault Transit connection + key settings (bound from config; dev defaults shown).</summary>
public sealed class VaultOptions
{
    public const string SectionName = "Vault";

    public string Address { get; set; } = "http://127.0.0.1:8200";
    public string Token { get; set; } = "root";
    public string TransitMount { get; set; } = "transit";
    public string KeyName { get; set; } = "lumen-dev-kek";
}
