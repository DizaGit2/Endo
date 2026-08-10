using System.Globalization;

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

    /// <summary>
    /// The canonical domain and encoding of <see cref="RasrmStageEnc"/> — <b>added by T16, the
    /// column's first writer</b>. T7 deliberately shipped no type here, because the column is
    /// ciphertext and the 1–4 range therefore <b>cannot be a DB CHECK</b>; until something wrote the
    /// column, a constants type would have guarded nothing.
    ///
    /// <para><b>This type and the endpoint that consumes it are the ONLY enforcement of the range.</b>
    /// Delete either and a stage of 9 is stored with nothing anywhere failing — no constraint, no
    /// exception, no failing test — and the value comes back out of <c>GET /me</c> for screen 31 to
    /// render as a roman numeral that does not exist.</para>
    ///
    /// <para><b>This is a STORAGE shape, not a clinical threshold</b> (§G7): 1–4 is the arity of the
    /// rASRM staging scale, exactly as <c>smallint</c> is the arity of a cycle-length column. The
    /// stage's clinical <i>meaning</i> is a C-14 PO-interim, clinician-UNSIGNED value, is never
    /// inferred from (C-14: rASRM <i>"does NOT correlate with pain"</i>), and appears nowhere in
    /// <c>backend/src</c>.</para>
    /// </summary>
    public static class RasrmStages
    {
        /// <summary>Stage I.</summary>
        public const int Min = 1;

        /// <summary>Stage IV. The scale has four stages and has never had a fifth.</summary>
        public const int Max = 4;

        /// <summary>The four stages, in order. Rendered I–IV in the UI, never stored that way.</summary>
        public static readonly IReadOnlyList<int> All = [1, 2, 3, 4];

        /// <summary>Whether <paramref name="stage"/> is a stage at all.</summary>
        public static bool Contains(int stage) => stage >= Min && stage <= Max;

        /// <summary>
        /// The <b>one</b> canonical plaintext encoding: the invariant-culture digit <c>"1"</c>–<c>"4"</c>.
        /// Invariant because a culture-sensitive <c>ToString()</c> writes eastern-arabic digit shapes
        /// under <c>ar-SA</c>, which <see cref="Decode"/> would then refuse to read back.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">
        /// <paramref name="stage"/> is outside 1–4. A programming-error guard on a caller expected to
        /// have validated already: this is the last point at which an impossible stage can be stopped,
        /// because the column carries no CHECK.
        /// </exception>
        public static string Encode(int stage)
        {
            if (!Contains(stage))
                throw new ArgumentOutOfRangeException(nameof(stage), stage, $"the rASRM stage must be {Min}–{Max}");

            return stage.ToString(CultureInfo.InvariantCulture);
        }

        /// <summary>
        /// The inverse of <see cref="Encode"/>. <see cref="NumberStyles.None"/> allows no sign, no
        /// decimal point, no thousands separator and no surrounding whitespace, so anything that is not
        /// a bare digit string is a <see cref="FormatException"/> rather than a coerced value.
        /// </summary>
        public static int Decode(string canonical) =>
            int.Parse(canonical, NumberStyles.None, CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// The canonical plaintext format of <see cref="DiagnosedOnEnc"/>: <b>month precision</b>. Screens
    /// 4 and 31 collect a month and a year, so a stored day would be a value the user never gave.
    /// </summary>
    public const string DiagnosedOnFormat = "yyyy-MM";

    /// <summary>
    /// The canonical plaintext format of <see cref="DobEnc"/>. A full date, unlike
    /// <see cref="DiagnosedOnFormat"/>, because §A:60 fixes the stored value as a date of birth (the
    /// age screen 4 shows is derived from it, never the other way round).
    /// </summary>
    public const string DobFormat = "yyyy-MM-dd";

    /// <summary>Encodes a diagnosis month as <see cref="DiagnosedOnFormat"/>; the day is discarded.</summary>
    public static string EncodeDiagnosedOn(DateOnly month) =>
        month.ToString(DiagnosedOnFormat, CultureInfo.InvariantCulture);

    /// <summary>
    /// The inverse of <see cref="EncodeDiagnosedOn"/>, answering the first day of the month.
    /// <b>Exact-format parsing is the whole point:</b> a <c>"yyyy-MM-dd"</c> value in this column is a
    /// <see cref="FormatException"/>, so the field cannot be silently widened into a full date by a
    /// later writer — the day it would carry is fabricated data.
    /// </summary>
    public static DateOnly DecodeDiagnosedOn(string canonical) =>
        DateOnly.ParseExact(canonical, DiagnosedOnFormat, CultureInfo.InvariantCulture);

    /// <summary>Non-throwing <see cref="DecodeDiagnosedOn"/>, for validating client input.</summary>
    public static bool TryDecodeDiagnosedOn(string canonical, out DateOnly month) =>
        DateOnly.TryParseExact(
            canonical, DiagnosedOnFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out month);

    /// <summary>Encodes a date of birth as <see cref="DobFormat"/>, invariant-culture.</summary>
    public static string EncodeDob(DateOnly dob) => dob.ToString(DobFormat, CultureInfo.InvariantCulture);

    /// <summary>The inverse of <see cref="EncodeDob"/>.</summary>
    public static DateOnly DecodeDob(string canonical) =>
        DateOnly.ParseExact(canonical, DobFormat, CultureInfo.InvariantCulture);

    /// <summary>
    /// The <b>one</b> canonical plaintext encoding of <see cref="HeightCmEnc"/>: an invariant-culture
    /// integer number of centimetres (D-06 — metric-only v1, so the unit is part of the column, not a
    /// sibling field). Same rule and same reason as <see cref="BodyMetric.EncodeValue"/>.
    /// </summary>
    public static string EncodeHeightCm(int centimetres) => centimetres.ToString(CultureInfo.InvariantCulture);

    /// <summary>
    /// The inverse of <see cref="EncodeHeightCm"/>. <see cref="NumberStyles.None"/> keeps a stray sign,
    /// separator or space a hard error rather than a silently different height.
    /// </summary>
    public static int DecodeHeightCm(string canonical) =>
        int.Parse(canonical, NumberStyles.None, CultureInfo.InvariantCulture);
}
