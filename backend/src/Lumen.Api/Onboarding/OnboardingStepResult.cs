using Lumen.Domain.Entities;

namespace Lumen.Api.Onboarding;

/// <summary>
/// One rejected field, carried out of <see cref="OnboardingStepsService"/> so the service can stay free
/// of <c>IResult</c> and be unit-tested on its decisions rather than on an HTTP body.
/// <see cref="OnboardingEndpoints"/> replays these into
/// <see cref="Validation.ValidationProblemBuilder"/>, which is still the only thing that builds the
/// phase's one 400.
/// </summary>
/// <param name="Field">
/// The camelCase JSON field name, exactly as it appears on the wire — <c>heightCm</c>,
/// <c>diagnosedOn</c> — or <see cref="Validation.ValidationProblemBuilder.RequestKey"/> for an error
/// that belongs to no single field. Passed through verbatim; the client matches it against its own
/// field names to attach the message to an input.
/// </param>
public sealed record OnboardingFieldError(string Field, string Message);

/// <summary>Outcome of <see cref="OnboardingStepsService.SaveBaselineAsync"/>.</summary>
/// <remarks>
/// There is deliberately <b>no "created" case distinct from "updated"</b>. D-02 makes the baseline a
/// step the user may revisit, so the client does nothing differently on the first save; both are
/// <see cref="Saved"/> and both are 200.
/// </remarks>
public abstract record SaveBaselineResult
{
    /// <summary>
    /// The profile columns and (when a weight was supplied) the metric row were written. → <b>200 with
    /// the stored row decrypted back</b>, so a round-trip failure surfaces on the call that caused it.
    /// </summary>
    public sealed record Saved(BaselineResponse Baseline) : SaveBaselineResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<OnboardingFieldError> Errors) : SaveBaselineResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404, decided <b>before</b> validation so an erased token cannot learn that
    /// its request shape was understood, and before any write so it can create no health data.
    /// </summary>
    public sealed record UserNotFound : SaveBaselineResult;
}

/// <summary>
/// The <b>structural type-domain</b> of the baseline's two free measurements — the only thing on
/// <c>heightCm</c> and <c>weightKg</c> that can produce a 400 beyond a missing body.
///
/// <para><b>These are §G11 inventions, recorded as such.</b> Neither field has a documented range in
/// any source, so T16 picked one — and picked it to be a <b>storage domain</b>, in the same sense as
/// <see cref="CycleSettings.CycleSettingsStructuralDomain"/>'s "a positive integer that fits
/// <c>smallint</c>", never a physiological one. Both columns are <c>bytea</c> ciphertext and can carry
/// no CHECK, so without these guards the write path has no range check at all and an <c>int.MaxValue</c>
/// height is stored with nothing failing.</para>
///
/// <para><b>The line they hold, stated plainly:</b> they refuse only what cannot be a measurement at
/// all. The tallest human ever recorded was 272&#160;cm and the heaviest 635&#160;kg; these bounds sit
/// at 32767&#160;cm (327&#160;m) and 9999.9&#160;kg, so nothing a tape measure or a scale can report is
/// refused. That matters because rider 7 and <c>clinical-asks.md:34</c> are verbatim that sanity bounds
/// <i>"never block save"</i> — a guard that rejected a real observation would be exactly the entry
/// blocker the PO forbade. <b>No clinical bound is imported here</b> (§G7: those are clinician-UNSIGNED
/// and have no home in <c>backend/src</c> this phase), and there is deliberately <b>no lower bound on
/// <c>dob</c></b> at all beyond <see cref="DateOnly"/> itself — a floor there would be an age gate,
/// which C-12 explicitly forbids.</para>
/// </summary>
public static class BaselineStructuralDomain
{
    /// <summary>The smallest storable height: a measurement is positive.</summary>
    public const int MinHeightCm = 1;

    /// <summary>
    /// The largest storable height, expressed against <see cref="short.MaxValue"/> so it states a type
    /// domain rather than a transcribed number — the same shape, and the same reasoning, as the
    /// §G7 domain on the cycle self-reports.
    /// </summary>
    public const int MaxHeightCm = short.MaxValue;

    /// <summary>
    /// The largest storable weight: four integer digits, keeping the canonical
    /// <see cref="BodyMetric.EncodeValue"/> plaintext a short, obviously-numeric string. Fifteen times
    /// the heaviest weight a human has ever been recorded at.
    /// </summary>
    public const decimal MaxWeightKg = 9999.9m;

    /// <summary>
    /// The precision a body scale reports, and the precision screen 4 collects. More than this is
    /// rejected rather than rounded away, because silently storing 60.4 for a user who typed 60.44
    /// would be inventing a datum.
    /// </summary>
    public const int MaxWeightDecimals = 1;

    /// <summary>Whether a height can be stored at all.</summary>
    public static bool ContainsHeightCm(int centimetres) =>
        centimetres >= MinHeightCm && centimetres <= MaxHeightCm;

    /// <summary>Whether a weight can be stored at all. Zero is not a weight; a negative one is not either.</summary>
    public static bool ContainsWeightKg(decimal kilograms) =>
        kilograms > 0m && kilograms <= MaxWeightKg;

    /// <summary>
    /// Whether the value survives the canonical one-decimal encoding without losing anything the user
    /// typed.
    /// </summary>
    public static bool HasStorableScale(decimal kilograms) =>
        NormaliseWeightKg(kilograms) == kilograms;

    /// <summary>
    /// The value as it is stored. <b>Normalisation is not cosmetic:</b> JSON <c>60.40</c> binds to a
    /// decimal of scale 2 and <c>decimal.ToString()</c> preserves scale, so without this the column
    /// would hold <c>"60.40"</c> where an identical later save held <c>"60.4"</c> — two canonical forms
    /// for one number, on a value <see cref="BodyMetric.EncodeValue"/> is supposed to encode exactly
    /// one way.
    /// </summary>
    public static decimal NormaliseWeightKg(decimal kilograms) =>
        decimal.Round(kilograms, MaxWeightDecimals);
}

/// <summary>
/// Messages owned by the onboarding step endpoints alone (§G12: only genuinely cross-cutting strings
/// belong on <see cref="Validation.ValidationMessages"/>). These are <b>wire strings</b> asserted
/// verbatim in <c>OnboardingBaselineTests</c> and <c>OnboardingBaselineLiveTests</c> — rewording one is
/// a contract change, not a copy edit.
/// </summary>
/// <remarks>
/// House style (T3): a field-scoped message starts lowercase and never names its own field, because the
/// <c>errors</c> map key already does and the client renders "&lt;key&gt;: &lt;message&gt;".
/// </remarks>
public static class OnboardingValidationMessages
{
    /// <summary>
    /// A <c>POST /onboarding/baseline</c> body carried none of the six fields. Reported under
    /// <see cref="Validation.ValidationProblemBuilder.RequestKey"/> because it belongs to the
    /// combination rather than to any one field. D-02 makes the step skippable, and "skip" means not
    /// calling the endpoint — so an empty body is a client bug, not a skip.
    /// </summary>
    public const string BaselineEmpty = "provide at least one baseline field";

    /// <summary>
    /// The weight is outside <see cref="BaselineStructuralDomain"/>. Parameterised for the same reason
    /// as <see cref="Validation.ValidationMessages.Between"/>: the bound is stated inside the sentence,
    /// and taking it from the constant is what keeps the two from drifting apart silently.
    /// </summary>
    public static string WeightOutOfRange(decimal max) =>
        // Invariant: a wire string must not vary with the server's thread culture — under es-ES this
        // would otherwise read "9999,9" while the field itself is parsed invariant.
        FormattableString.Invariant($"value must be greater than 0 and at most {max}");

    /// <summary>
    /// The weight carried more precision than a body scale reports (and than screen 4 collects). Stated
    /// in the singular rather than parameterised, because
    /// <see cref="BaselineStructuralDomain.MaxWeightDecimals"/> is 1 and a parameterised form would
    /// read "at most 2 decimal place"; the frozen-strings test pins the constant at 1 so the two cannot
    /// drift apart unnoticed.
    /// </summary>
    public const string WeightTooPrecise = "value must have at most 1 decimal place";

    /// <summary>
    /// The diagnosis month was not <c>"yyyy-MM"</c>. A full date lands here too, deliberately: the
    /// field is month precision (§D), and accepting a day would store data the user never gave. Built
    /// from <see cref="UserProfileEnc.DiagnosedOnFormat"/> — still a compile-time constant, so the
    /// message and the format it names cannot diverge.
    /// </summary>
    public const string NotAMonth = "value must be a month in the form " + UserProfileEnc.DiagnosedOnFormat;
}
