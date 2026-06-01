namespace Lumen.Domain.Entities;

/// <summary>
/// A Lumen user. <see cref="Id"/> mirrors the Keycloak subject (sub) so the
/// identity provider and the app share one stable key. No plaintext email is
/// stored — only <see cref="EmailHash"/> for lookup (§D / §F).
/// </summary>
public class User
{
    public Guid Id { get; set; }
    public string EmailHash { get; set; } = string.Empty;
    public string Locale { get; set; } = "es-ES";
    public string Timezone { get; set; } = "Europe/Madrid";
    public DateTimeOffset? OnboardingCompletedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }
}
