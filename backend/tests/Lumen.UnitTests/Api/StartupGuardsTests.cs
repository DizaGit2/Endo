using Lumen.Api;
using Lumen.Infrastructure.Auth;
using Lumen.Infrastructure.Crypto;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Api;

/// <summary>
/// Unit tests for <see cref="StartupGuards.EnsureNonDevelopmentSecrets"/> (P3c-T8). Outside
/// Development, every security-sensitive setting must be explicitly configured — a config that
/// simply OMITS a setting must fail closed rather than silently falling back to a dev default
/// (the old guard only ever caught the exact dev-sentinel literals, so an omitted setting sailed
/// through to Program.cs's hardcoded connection-string fallback).
/// </summary>
public class StartupGuardsTests
{
    // A fully explicit, non-sentinel configuration — the "everything is fine" baseline the
    // individual failure tests mutate one field away from.
    private const string RealConnectionString =
        "Host=prod-db.internal;Port=5432;Database=lumen;Username=lumen_app;Password=Tr0ub4dor&3-Correct-Horse";

    private static VaultOptions RealVault() => new()
    {
        Address = "https://vault.prod.example",
        Token = "s.9f8e7d6c5b4a3210-real-vault-token",
    };

    private static KeycloakOptions RealKeycloak() => new()
    {
        BaseUrl = "https://auth.prod.example",
        AdminClientSecret = "8f14e45f-real-keycloak-secret",
    };

    // --- connection string ----------------------------------------------------------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void NonDevelopment_missing_connection_string_throws_naming_it(string? connectionString)
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: connectionString,
            vault: RealVault(),
            keycloak: RealKeycloak());

        Should.Throw<InvalidOperationException>(act).Message.ShouldContain("ConnectionStrings:Lumen");
    }

    [Fact]
    public void NonDevelopment_connection_string_with_dev_sentinel_throws_naming_it_without_leaking_the_value()
    {
        const string sentinelConnectionString =
            "Host=localhost;Port=55432;Database=lumen;Username=postgres;Password=postgres";

        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: sentinelConnectionString,
            vault: RealVault(),
            keycloak: RealKeycloak());

        var ex = Should.Throw<InvalidOperationException>(act);
        ex.Message.ShouldContain("ConnectionStrings:Lumen");
        ex.Message.ShouldNotContain("Password=postgres"); // names the key, never the value
    }

    // --- Vault address ----------------------------------------------------------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("http://127.0.0.1:8200")]
    public void NonDevelopment_missing_or_sentinel_vault_address_throws_naming_it(string? address)
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: new VaultOptions { Address = address!, Token = RealVault().Token },
            keycloak: RealKeycloak());

        Should.Throw<InvalidOperationException>(act).Message.ShouldContain("Vault:Address");
    }

    // --- Vault token ----------------------------------------------------------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("root")]
    public void NonDevelopment_missing_or_sentinel_vault_token_throws_naming_it(string? token)
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: new VaultOptions { Address = RealVault().Address, Token = token! },
            keycloak: RealKeycloak());

        Should.Throw<InvalidOperationException>(act).Message.ShouldContain("Vault:Token");
    }

    [Fact]
    public void NonDevelopment_vault_token_sentinel_does_not_leak_the_value()
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: new VaultOptions { Address = RealVault().Address, Token = "root" },
            keycloak: RealKeycloak());

        Should.Throw<InvalidOperationException>(act).Message.ShouldNotContain("root");
    }

    // --- Keycloak base URL ----------------------------------------------------------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("http://localhost:8080")]
    public void NonDevelopment_missing_or_sentinel_keycloak_base_url_throws_naming_it(string? baseUrl)
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: RealVault(),
            keycloak: new KeycloakOptions { BaseUrl = baseUrl!, AdminClientSecret = RealKeycloak().AdminClientSecret });

        Should.Throw<InvalidOperationException>(act).Message.ShouldContain("Keycloak:BaseUrl");
    }

    // --- Keycloak admin client secret ----------------------------------------------------------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("dev-api-secret")]
    public void NonDevelopment_missing_or_sentinel_keycloak_secret_throws_naming_it(string? secret)
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: RealVault(),
            keycloak: new KeycloakOptions { BaseUrl = RealKeycloak().BaseUrl, AdminClientSecret = secret! });

        Should.Throw<InvalidOperationException>(act).Message.ShouldContain("Keycloak:AdminClientSecret");
    }

    [Fact]
    public void NonDevelopment_keycloak_secret_sentinel_does_not_leak_the_value()
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: RealVault(),
            keycloak: new KeycloakOptions { BaseUrl = RealKeycloak().BaseUrl, AdminClientSecret = "dev-api-secret" });

        Should.Throw<InvalidOperationException>(act).Message.ShouldNotContain("dev-api-secret");
    }

    // --- happy paths ----------------------------------------------------------

    [Fact]
    public void NonDevelopment_with_all_explicit_non_sentinel_values_does_not_throw()
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: false,
            connectionString: RealConnectionString,
            vault: RealVault(),
            keycloak: RealKeycloak());

        Should.NotThrow(act);
    }

    [Fact]
    public void Development_with_everything_null_or_sentinel_does_not_throw()
    {
        var act = () => StartupGuards.EnsureNonDevelopmentSecrets(
            isDevelopment: true,
            connectionString: null,
            vault: new VaultOptions { Token = null! },
            keycloak: new KeycloakOptions { AdminClientSecret = null! });

        Should.NotThrow(act);
    }
}
