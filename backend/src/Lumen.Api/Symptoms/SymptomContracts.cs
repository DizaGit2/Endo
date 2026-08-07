namespace Lumen.Api.Symptoms;

// The DTOs and wire strings of the symptoms feature (§C.3), per the T3 convention
// `<Feature>/<Feature>Contracts.cs`.
//
// T10 seeds this file with the quick check-in alone; T11 adds the symptom batch. The check-in lives
// here because §C.3 owns `POST /checkin/quick` (screen 9 is a symptoms-module screen), but it
// deliberately writes ONLY `cycle_day_logs` — see QuickCheckinRequest's remarks.
//
// Schema ids are the bare type names and are namespace-INDEPENDENT (§G12, verified in T9), so the
// `namespace` above is a style choice. The real hazard is a short-type-name COLLISION across feature
// folders, which throws a duplicate-schemaId error at document generation: `QuickCheckinRequest` and
// `QuickCheckinResponse` are unique across the whole API.

/// <summary>
/// Body of <c>POST /checkin/quick</c> (screen 9, "How's today?") — the app's most-tapped write.
///
/// <para><b>No date.</b> The row is always the user's local <i>today</i> (D-12): screen 9 asks about
/// today and D-11 says a repeat check-in updates today's value. Explicit dates belong to
/// <c>POST /cycle/day/{date}</c>, which already owns them.</para>
///
/// <para><b>This is a PARTIAL write, unlike <c>POST /cycle/day/{date}</c>.</b> It touches only the
/// two columns it offers, and only the ones actually supplied: a check-in never clears the
/// <c>notes</c> the day-detail screen wrote, never touches the deferred <c>energy</c>/<c>libido</c>
/// columns, and tapping only the mood chip leaves the morning's pain score alone. The full form is
/// the opposite by design (it submits the whole day, so an omitted field clears), which is why the
/// two endpoints exist rather than one.</para>
///
/// <para><b>It writes no <c>symptoms</c> row</b> (D-11 as modified): the day log is the headline
/// daily series, while <c>symptoms</c> holds classified episodes that only the full form creates.
/// Writing both here would double-count every tap in every later aggregate.</para>
/// </summary>
/// <param name="Pain">
/// Headline pain on the 0–10 NRS-11 scale. <b>0 is a real datum</b> ("none today", D-08) and
/// satisfies the at-least-one rule; only <see langword="null"/> means "not supplied".
/// </param>
/// <param name="Mood">Mood on the 1–4 scale {low, tired, steady, bright}.</param>
public record QuickCheckinRequest(
    int? Pain,
    int? Mood);

/// <summary>
/// The 200 body of <c>POST /checkin/quick</c>: the day log after the write. Always 200 — an upsert
/// has no actionable created/updated distinction, and §C.2 exposes no <c>GET /cycle/day-log/{id}</c>
/// for a <c>Location</c> header to point at.
/// </summary>
/// <param name="Day">
/// The user-local day the check-in landed on, echoed back so the client never has to re-derive it
/// from its own clock — the server's answer is the one that keyed the row.
/// </param>
/// <param name="Pain">The stored value, which may be a field an <i>earlier</i> write supplied.</param>
/// <param name="Mood">The stored value, same caveat as <see cref="Pain"/>.</param>
public record QuickCheckinResponse(
    DateOnly Day,
    int? Pain,
    int? Mood,
    DateTimeOffset UpdatedAt);

/// <summary>
/// Messages owned by the symptoms endpoints alone (§G12: only genuinely cross-cutting strings belong
/// on <see cref="Validation.ValidationMessages"/>). These are <b>wire strings</b> asserted verbatim
/// against their literals in the unit suites — rewording one is a contract change, not a copy edit.
/// </summary>
public static class SymptomValidationMessages
{
    /// <summary>
    /// A quick check-in supplied neither pain nor mood. Reported under
    /// <see cref="Validation.ValidationProblemBuilder.RequestKey"/> because it belongs to the
    /// combination, not to either field.
    /// </summary>
    public const string QuickCheckinEmpty = "at least one of pain or mood is required";
}
