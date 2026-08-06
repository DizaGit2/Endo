namespace Lumen.Api.Validation;

/// <summary>
/// The shared error vocabulary behind every P4a 400 (T3). These are <b>wire strings</b>: they travel
/// in the <c>errors</c> map of the ProblemDetails body, reach the Flutter client through the
/// generated contract, and are asserted verbatim in tests — so changing one is a contract change,
/// not a copy edit.
///
/// <para>
/// Only genuinely <b>cross-cutting</b> messages live here. A message that belongs to one endpoint
/// (for example "at least one of pain, mood or notes is required") is declared and asserted in that
/// endpoint's own task; putting it here would imply a reuse that does not exist. No endpoint may
/// invent a new error <i>body</i> — the shape is <see cref="ValidationProblemBuilder"/>'s.
/// </para>
///
/// <para>
/// Style: field-scoped messages start lowercase and never name the field (the map key already does),
/// so a client can render "avgCycleLengthDays: value is required" or localise on the key alone.
/// <see cref="RequestDetail"/> is the one exception — it is a whole-sentence body-level
/// <c>detail</c>, not a field message.
/// </para>
/// </summary>
public static class ValidationMessages
{
    /// <summary>
    /// The <c>detail</c> on every builder-produced 400. Deliberately identical to the fallback string
    /// in <c>client/lib/core/error/error_mapper.dart</c>, which reads <c>detail</c> first: sending it
    /// means the user sees the same sentence whether or not the body survived the round trip.
    /// </summary>
    public const string RequestDetail = "The request contained invalid data.";

    /// <summary>A mandatory field was absent, null, or blank.</summary>
    public const string Required = "value is required";

    /// <summary>
    /// The value is outside a frozen vocabulary (§G10) — a symptom code, region, side, pain type,
    /// trigger, cycle-event kind, pause reason, goal, hormone, platform, and so on. The allowed
    /// members are deliberately NOT listed: they are append-only and already in the contract.
    /// </summary>
    public const string NotAllowedValue = "value is not one of the allowed values";

    /// <summary>
    /// A count or measure that may be zero but never negative. Note 0 is a valid datum on the NRS-11
    /// intensity scale (D-08), so "none today" must never be rejected by this.
    /// </summary>
    public const string NotNegative = "value must be 0 or greater";

    /// <summary>
    /// The date is after the user's local today (D-12/D-13). Applies to every dated write; "today" is
    /// always <c>UserDayInfo.Today</c>, never a re-derived UTC date.
    /// </summary>
    public const string FutureDate = "date must not be in the future";

    /// <summary>
    /// The date is before <c>UserDayInfo.BackdateFloor</c>. <b>Only <c>cycle_events</c> writes may use
    /// this (§G8)</b> — every other dated write is capped by today alone, and applying a floor to them
    /// would reject the historical logging D-13 explicitly permits.
    /// </summary>
    public const string BeforeFloor = "date is before the earliest allowed date";

    /// <summary>The string is not a zone id <c>TimeZoneInfo</c> can resolve (e.g. <c>Europe/Madrid</c>).</summary>
    public const string NotAnIanaTimeZone = "value is not a recognized IANA time zone";

    /// <summary>
    /// The request could not be bound at all — unparseable JSON, a route/query value of the wrong
    /// type, a missing required parameter. Emitted only by <see cref="ProblemExceptionHandler"/>,
    /// under <see cref="ValidationProblemBuilder.RequestKey"/>. Intentionally vague: the framework's
    /// own message quotes the value that failed to bind, which in this app is health data (§F).
    /// </summary>
    public const string MalformedRequest = "the request body or parameters could not be read";

    /// <summary>
    /// An inclusive numeric range. Parameterised rather than constant because the bounds differ per
    /// field and the message must state them; the caller supplies the bounds so no clinical number is
    /// ever frozen into this file (§G7 — sanity bounds live at the call site, clinical bounds are not
    /// in <c>backend/src</c> at all this phase).
    /// </summary>
    public static string Between(int min, int max) =>
        // Invariant: this is a wire string, so it must not vary with the server's thread culture.
        FormattableString.Invariant($"value must be between {min} and {max}");

    /// <summary>A text field exceeded its character limit (e.g. <c>notes</c> at 2000, D-13).</summary>
    public static string MaxLength(int maxLength) =>
        FormattableString.Invariant($"text exceeds the maximum length of {maxLength} characters");
}
