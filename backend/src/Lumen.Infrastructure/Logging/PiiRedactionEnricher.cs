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
/// </summary>
public sealed partial class PiiRedactionEnricher : ILogEventEnricher
{
    [GeneratedRegex(@"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")]
    private static partial Regex GuidRegex();

    /// <summary>
    /// Property/key names that are always fully redacted, regardless of value shape. Case-insensitive.
    /// </summary>
    private static readonly HashSet<string> SensitiveNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "newPassword", "currentPassword", "email", "displayName", "pushToken",
        "dob", "dateOfBirth", "bio", "phone",
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
