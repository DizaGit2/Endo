using Lumen.Infrastructure.Auth;
using Lumen.Infrastructure.Crypto;

namespace Lumen.Api;

/// <summary>
/// Fail-closed startup checks (P3c-T8). Outside Development, every security-sensitive setting must
/// be explicitly configured: a config that simply OMITS a setting must not silently fall through to
/// a dev default (Program.cs's hardcoded connection-string fallback, or the dev defaults baked into
/// <see cref="VaultOptions"/>/<see cref="KeycloakOptions"/>). The prior guard only ever caught the
/// exact dev-sentinel literals, so an omitted setting sailed straight through. Pure/static so the
/// whole matrix is unit-testable without booting the host (prod hardening beyond this is P11).
/// </summary>
public static class StartupGuards
{
    // Mirrors the dev defaults on VaultOptions/KeycloakOptions and Program.cs's hardcoded
    // connection-string fallback — the exact values a non-Development environment must never carry.
    private const string DevVaultAddress = "http://127.0.0.1:8200";
    private const string DevVaultToken = "root";
    private const string DevKeycloakBaseUrl = "http://localhost:8080";
    private const string DevKeycloakAdminClientSecret = "dev-api-secret";
    private const string DevConnectionStringSentinel = "Password=postgres";

    /// <summary>
    /// Throws <see cref="InvalidOperationException"/> when running outside Development and any
    /// security-sensitive setting is missing (null/whitespace) or still equal to its dev sentinel
    /// value. Always passes in Development, so dev fallbacks keep working there. Exception messages
    /// name only the offending configuration key — never the secret's actual value.
    /// </summary>
    public static void EnsureNonDevelopmentSecrets(
        bool isDevelopment,
        string? connectionString,
        VaultOptions vault,
        KeycloakOptions keycloak)
    {
        if (isDevelopment)
            return;

        if (string.IsNullOrWhiteSpace(connectionString))
            throw Fail("ConnectionStrings:Lumen is not configured");
        if (connectionString.Contains(DevConnectionStringSentinel, StringComparison.Ordinal))
            throw Fail("ConnectionStrings:Lumen is still set to its dev sentinel value");

        if (string.IsNullOrWhiteSpace(vault.Address) || vault.Address == DevVaultAddress)
            throw Fail("Vault:Address is not configured (missing or still the dev sentinel value)");

        if (string.IsNullOrWhiteSpace(vault.Token) || vault.Token == DevVaultToken)
            throw Fail("Vault:Token is not configured (missing or still the dev sentinel value)");

        if (string.IsNullOrWhiteSpace(keycloak.BaseUrl) || keycloak.BaseUrl == DevKeycloakBaseUrl)
            throw Fail("Keycloak:BaseUrl is not configured (missing or still the dev sentinel value)");

        if (string.IsNullOrWhiteSpace(keycloak.AdminClientSecret) || keycloak.AdminClientSecret == DevKeycloakAdminClientSecret)
            throw Fail("Keycloak:AdminClientSecret is not configured (missing or still the dev sentinel value)");
    }

    private static InvalidOperationException Fail(string reason) =>
        new($"Refusing to start outside Development: {reason}. Configure a real value before deploying.");
}
