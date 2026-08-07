using System.Text.RegularExpressions;
using Serilog.Core;
using Serilog.Events;

namespace Lumen.Infrastructure.Logging;

/// <summary>
/// Serilog enricher that redacts PII from log-event property values (§F). Two layers:
/// <list type="bullet">
/// <item>Value-based: emails → <c>[redacted-email]</c>, any GUID (e.g. a user <c>sub</c>) → <c>[id]</c>.</item>
/// <item>Name-based (defense-in-depth): a fixed set of sensitive property/key names — see
/// <see cref="SensitiveNames"/> — always has its ENTIRE value replaced with <c>[redacted]</c>,
/// regardless of the value's shape (string, number, nested structure). This catches PII logged
/// under a known-sensitive name even if the value itself doesn't look like an email or GUID
/// (e.g. a plaintext password or a display name).</item>
/// </list>
/// It walks the full value tree — scalars, destructured structures (<c>{@Obj}</c>), sequences, and
/// dictionaries — checking names at every level the walker visits (top-level log properties,
/// <see cref="StructureValue"/> property names, <see cref="DictionaryValue"/> string keys), so PII
/// nested one or more levels deep does not slip through either layer.
///
/// <para><b>KNOWN GAP (tracked for P11 log shipping):</b> this walks <c>logEvent.Properties</c> only,
/// never <c>logEvent.Exception</c>. An exception MESSAGE therefore reaches sinks unredacted — e.g. a
/// <c>DbUpdateException</c> that quotes a rejected value. It is out of scope here and must be closed
/// before logs leave the host.</para>
/// </summary>
public sealed partial class PiiRedactionEnricher : ILogEventEnricher
{
    [GeneratedRegex(@"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")]
    private static partial Regex GuidRegex();

    /// <summary>
    /// Property/key names that are always fully redacted, regardless of value shape. Case-insensitive,
    /// so one entry covers both the C# property name (<c>PauseReason</c>) and the JSON/DTO spelling
    /// (<c>pauseReason</c>).
    ///
    /// <para><b>Name-based, not value-based, is the point.</b> Most P4a health data is a small integer
    /// (<c>intensity</c>, <c>pain</c>, <c>mood</c>, <c>flowIntensity</c>) or a short code
    /// (<c>symptomCode</c>, <c>region</c>). No value-shape heuristic can distinguish "9" the pain
    /// score from "9" the page size — only the NAME can, so every P4a field that can carry a
    /// special-category fact is listed here (§F).</para>
    ///
    /// <para><b>Completeness is enforced, not asserted.</b>
    /// <c>Lumen.UnitTests.Logging.PiiRedactionEnricherTests</c> reflects over the eleven P4a entity
    /// types and requires every column they declare to be either in this list or in that file's
    /// explicit benign allow-list. A column added by a later phase therefore fails there by name.
    /// (The first version of this list said it covered every P4a field while missing twenty-seven of
    /// them — including <c>Reason</c>, which is where <c>pause_reason = 'pregnancy'</c> actually
    /// lives on <c>cycle_tracking_pause_spans</c>; the test that "proved" the claim was a verbatim
    /// copy of this list.)</para>
    /// </summary>
    private static readonly HashSet<string> SensitiveNames = new(StringComparer.OrdinalIgnoreCase)
    {
        // ── identity / credentials (P2/P3c) ─────────────────────────────────────────────────────
        "password", "newPassword", "currentPassword", "email", "displayName", "pushToken",
        "dob", "dateOfBirth", "bio", "phone",
        // deferred in P3c, in scope from P4a: anything that is or wraps a bearer secret
        "token", "refreshToken", "idToken", "authorization", "secret", "dek",

        // ── P4a health data (§D plaintext columns + the note ciphertext) ────────────────────────
        // free-text notes (D-13) — DTO field, entity column and plural spellings
        "notes", "note", "notesEnc",
        // symptom classification
        "symptomCode", "painTypes", "triggers", "region", "side", "intensity",
        // day-log / quick check-in ordinals (0 is a real datum, so a falsy check would not save us)
        "pain", "mood", "energy", "libido", "flowIntensity",
        // the POST /symptoms batch envelope — one property holding up to 50 symptom rows
        "entries",
        // rider-4 condition bundle and body metrics
        "endoStatus", "rasrmStage", "diagnosedOn", "heightCm", "weightKg",
        // cycle settings and onboarding
        "pauseReason", "lastPeriodStart", "goals",
        // WHAT was observed: the classification codes on the observation tables. "period_start",
        // "menstrual" or "weight_kg" under a generic name is still a statement about this user.
        "kind", "phase", "boundary", "metric", "currentPhase",
        // WHEN it was observed. A date alone asserts that this user logged something that day, which
        // is the same health-adjacent fact §F bars from a request path.
        "day", "occurredOn", "occurredAt", "measuredOn", "measuredAt", "cycleStartOn", "phaseStart",
        // cycle_tracking_pause_spans: `reason` is the column that actually holds 'pregnancy' —
        // `pauseReason` above is only the user_cycle_settings/DTO spelling — and the two dates bound
        // the pregnancy/suppression/surgical span itself.
        // ACCEPTED FALSE POSITIVE: ASP.NET Core's DefaultAuthorizationService logs
        // "Authorization failed. {Reason}", so that line now renders "Authorization failed.
        // [redacted]". Name-based redaction cannot tell the two apart, and a false positive on one
        // framework diagnostic beats a false negative on pause_reason = 'pregnancy'. The signal is not
        // lost: the JwtBearer line ("Bearer was not authenticated. Failure message: …") still carries
        // the actual cause, including the perimeter guard's own context.Fail message.
        "reason", "startedOn", "endedOn",
        // user_cycle_settings: the typed self-reports and the pause state (a paused tracker plus its
        // start date says as much as the reason code does).
        "avgCycleLengthDays", "avgPeriodLengthDays", "regularity", "trackingPaused", "pausedSince",
        // showFertilityWindowEnabled is a reproductive-intent signal in the same class as
        // goal_code = 'plan_fertility'; the other two engine toggles are allow-listed as benign.
        "showFertilityWindowEnabled",
        // preference rows: the CODE half of each (code, flag) pair — which hormones this user tracks
        // and which nudges they took. The boolean halves are allow-listed as benign.
        "goalCode", "hormoneCode", "categoryCode",
        // user_insight_snapshot and body_metrics: a completeness score profiles the record itself,
        // and the two ciphertext columns are named here for the same reason notesEnc is — a byte[]
        // rendered into a log line is a value nobody chose to publish.
        "dataCompleteness", "valueEnc", "missingDataCardsEnc",

        // ── request routing ─────────────────────────────────────────────────────────────────────
        // Serilog's request-logging middleware attaches RequestPath unconditionally, whatever the
        // message template says. "/cycle/day/2026-08-06" is a health-adjacent fact — it asserts that
        // this user logged something on that day — so the raw path never reaches a sink. Program.cs
        // logs the route TEMPLATE ("/cycle/day/{date}") under RouteTemplate instead, which keeps the
        // operational signal without the datum.
        "requestPath",
    };

    private static readonly ScalarValue RedactedValue = new("[redacted]");

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        foreach (var key in logEvent.Properties.Keys.ToArray())
        {
            var original = logEvent.Properties[key];
            var scrubbed = SensitiveNames.Contains(key) ? RedactedValue : Scrub(original);
            if (!ReferenceEquals(scrubbed, original))
                logEvent.AddOrUpdateProperty(new LogEventProperty(key, scrubbed));
        }
    }

    private static LogEventPropertyValue Scrub(LogEventPropertyValue value) => value switch
    {
        ScalarValue scalar => ScrubScalar(scalar),
        SequenceValue sequence => new SequenceValue(sequence.Elements.Select(Scrub)),
        StructureValue structure => new StructureValue(
            structure.Properties.Select(p => new LogEventProperty(
                p.Name, SensitiveNames.Contains(p.Name) ? RedactedValue : Scrub(p.Value))),
            structure.TypeTag),
        DictionaryValue dictionary => new DictionaryValue(
            dictionary.Elements.Select(kv =>
                new KeyValuePair<ScalarValue, LogEventPropertyValue>(
                    (ScalarValue)Scrub(kv.Key),
                    IsSensitiveKey(kv.Key) ? RedactedValue : Scrub(kv.Value)))),
        _ => value,
    };

    private static bool IsSensitiveKey(ScalarValue key) => key.Value is string s && SensitiveNames.Contains(s);

    private static ScalarValue ScrubScalar(ScalarValue scalar) => scalar.Value switch
    {
        string s when ScrubString(s) is var scrubbed && scrubbed != s => new ScalarValue(scrubbed),
        Guid => new ScalarValue("[id]"), // a GUID value is a user/correlation id — redact
        _ => scalar,
    };

    private static string ScrubString(string original)
    {
        var scrubbed = EmailRegex().Replace(original, "[redacted-email]");
        return GuidRegex().Replace(scrubbed, "[id]");
    }
}
