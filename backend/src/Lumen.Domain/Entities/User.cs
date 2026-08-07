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

    /// <summary>
    /// One of <see cref="UnitSystems"/>. <b>D-06 reserved column</b>: v1 is metric-only, so this has
    /// no endpoint and no write path in P4a — it exists so a future imperial <i>display</i> toggle
    /// lands without a migration (§A:45). It is a single-valued preference today, so it is not a
    /// quasi-identifier and does <b>not</b> join T8's shred blanking list. It never changes what is
    /// stored, only how a future client renders it.
    /// </summary>
    public string UnitSystem { get; set; } = UnitSystems.Default;

    public DateTimeOffset? OnboardingCompletedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>
    /// Canonical <see cref="UnitSystem"/> values — one member today (D-06, 2026-06-14: metric-only
    /// v1, kg / cm / %). Append-only: <c>imperial</c> joins it when the display toggle ships.
    /// </summary>
    public static class UnitSystems
    {
        public const string Metric = "metric";

        /// <summary>The DB default and the only value P4a can hold.</summary>
        public const string Default = Metric;

        public static readonly IReadOnlyList<string> All = [Metric];
    }
}
