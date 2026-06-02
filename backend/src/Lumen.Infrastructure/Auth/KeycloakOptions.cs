namespace Lumen.Infrastructure.Auth;

/// <summary>Keycloak connection + client settings (bound from config; dev defaults shown).</summary>
public sealed class KeycloakOptions
{
    public const string SectionName = "Keycloak";

    public string BaseUrl { get; set; } = "http://localhost:8080";
    public string Realm { get; set; } = "lumen";
    public string AdminClientId { get; set; } = "api";
    public string AdminClientSecret { get; set; } = "dev-api-secret";

    /// <summary>OIDC authority/issuer for JWT validation: <c>{BaseUrl}/realms/{Realm}</c>.</summary>
    public string Authority => $"{BaseUrl}/realms/{Realm}";
}
