namespace Lumen.Domain.Entities;

/// <summary>
/// Envelope-encrypted profile fields. Each <c>*Enc</c> column is AES-256-GCM
/// ciphertext (nonce ‖ ciphertext ‖ tag) produced with the user's DEK — never plaintext.
///
/// <para><b>Why the rider-4 condition fields are encrypted rather than plaintext</b> (unlike
/// <see cref="UserCycleSettings"/>, which is deliberately plaintext): none of them is ever a SQL
/// predicate, sort or aggregate input. The endo status and rASRM stage feed no estimator — C-14 is
/// explicit that rASRM <i>"does NOT correlate with pain, never inferred"</i> — the diagnosis month
/// is display-only, and BMI could not be computed in SQL anyway because weight lives in
/// <c>body_metrics.ValueEnc</c>, already encrypted. A new plaintext quasi-identifier would also
/// have to join T8's shred blanking list; ciphertext is erased by destroying the DEK.
/// <b>All four get a write path in T16</b> — no dead columns.</para>
///
/// <para><b>Deliberately absent:</b> weight (rider 4 — onboarding seeds
/// <c>body_metrics.weight_kg</c> so weight has one source of truth) and surgeries (C-14,
/// clinician-UNSIGNED, deferred).</para>
/// </summary>
public class UserProfileEnc
{
    public Guid UserId { get; set; }
    public byte[]? DisplayNameEnc { get; set; }
    public byte[]? DobEnc { get; set; }
    public byte[]? BioEnc { get; set; }

    /// <summary>
    /// Encrypted endo status. <b>Canonical plaintext:</b> one of <see cref="EndoStatuses"/>, e.g.
    /// <c>"diagnosed"</c>. Nullable — D-02 makes every onboarding step after account + last period
    /// skippable.
    /// </summary>
    public byte[]? EndoStatusEnc { get; set; }

    /// <summary>
    /// Encrypted rASRM stage. <b>Canonical plaintext:</b> the invariant-culture digit
    /// <c>"1"</c>–<c>"4"</c> (rendered I–IV in the UI). Nullable and independent of
    /// <see cref="EndoStatusEnc"/>: a diagnosed user often does not know their stage. The 1–4 range
    /// cannot be a DB CHECK — the column is ciphertext — so T16's writer enforces it. The stage's
    /// clinical meaning is a C-14 PO-interim, clinician-UNSIGNED value and is never inferred from.
    /// </summary>
    public byte[]? RasrmStageEnc { get; set; }

    /// <summary>
    /// Encrypted diagnosis date. <b>Canonical plaintext:</b> <c>"yyyy-MM"</c> — month precision, not
    /// a day, because that is what screens 4/31 collect and a fabricated day would read as data the
    /// user never gave.
    /// </summary>
    public byte[]? DiagnosedOnEnc { get; set; }

    /// <summary>
    /// Encrypted height in centimetres. <b>Canonical plaintext:</b> an invariant-culture integer,
    /// e.g. <c>"165"</c> (D-06: metric-only v1). Stored on the profile rather than in
    /// <c>body_metrics</c> because height is a stable attribute, not a tracked time series.
    /// </summary>
    public byte[]? HeightCmEnc { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// Canonical <see cref="EndoStatusEnc"/> plaintext values — the three ratified codes
    /// (definitions.md 2026-07-08 / §A:60). Append-only. There is no default: an unanswered
    /// question stays null rather than being recorded as <see cref="NotApplicable"/>, which is a
    /// real answer.
    /// </summary>
    public static class EndoStatuses
    {
        public const string Diagnosed = "diagnosed";
        public const string Suspected = "suspected";
        public const string NotApplicable = "not_applicable";

        public static readonly IReadOnlyList<string> All = [Diagnosed, Suspected, NotApplicable];
    }
}
