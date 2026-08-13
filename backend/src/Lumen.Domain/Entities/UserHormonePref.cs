using Lumen.Domain.Reference;

namespace Lumen.Domain.Entities;

/// <summary>
/// One row per user per hormone code (onboarding screen 6, settings screen 33): whether that
/// hormone is <b>charted</b>.
///
/// <para><b>Charted ≠ extracted.</b> D-14: all seven hormones are always extracted from labs;
/// this flag only controls whether the series is drawn. Hiding a hormone must never make its lab
/// values disappear.</para>
///
/// <para><b>No <c>DeletedAt</c>.</b> A tombstone would keep occupying <c>(UserId, HormoneCode)</c>
/// and block re-charting the hormone; the boolean is the retraction. Account deletion hard-deletes
/// these rows (§F, T8).</para>
/// </summary>
public class UserHormonePref
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>
    /// One of <see cref="HormoneCatalog.Codes"/>. Membership is enforced in code, not by a DB CHECK.
    /// The wire/DB code is <c>estradiol</c>/<c>glp1</c>; the display labels "Estrogen"/"GLP-1" live
    /// in <see cref="HormoneCatalog"/> and are never stored as data (B16).
    /// </summary>
    public string HormoneCode { get; set; } = string.Empty;

    /// <summary>Whether this hormone's series is drawn on the charts. False is a real answer, not a delete.</summary>
    public bool Charted { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// The hormone codes seeded ON at onboarding — <b>all seven</b> (D-14; screen 33's four-ON
    /// state is a populated sample, not the spec).
    /// </summary>
    public static readonly IReadOnlyList<string> DefaultCharted = HormoneCatalog.Codes.All;
}
