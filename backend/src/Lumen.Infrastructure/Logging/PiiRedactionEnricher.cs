using System.Text.RegularExpressions;
using Serilog.Core;
using Serilog.Events;

namespace Lumen.Infrastructure.Logging;

/// <summary>
/// Serilog enricher that redacts PII from log-event property values (§F): emails → <c>[redacted-email]</c>
/// and any GUID (e.g. a user <c>sub</c>) → <c>[id]</c>. It walks the full value tree — scalars,
/// destructured structures (<c>{@Obj}</c>), sequences, and dictionaries — and also redacts <see cref="Guid"/>
/// scalars, so PII nested one or more levels deep does not slip through.
/// </summary>
public sealed partial class PiiRedactionEnricher : ILogEventEnricher
{
    [GeneratedRegex(@"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")]
    private static partial Regex GuidRegex();

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        foreach (var key in logEvent.Properties.Keys.ToArray())
        {
            var original = logEvent.Properties[key];
            var scrubbed = Scrub(original);
            if (!ReferenceEquals(scrubbed, original))
                logEvent.AddOrUpdateProperty(new LogEventProperty(key, scrubbed));
        }
    }

    private static LogEventPropertyValue Scrub(LogEventPropertyValue value) => value switch
    {
        ScalarValue scalar => ScrubScalar(scalar),
        SequenceValue sequence => new SequenceValue(sequence.Elements.Select(Scrub)),
        StructureValue structure => new StructureValue(
            structure.Properties.Select(p => new LogEventProperty(p.Name, Scrub(p.Value))), structure.TypeTag),
        DictionaryValue dictionary => new DictionaryValue(
            dictionary.Elements.Select(kv =>
                new KeyValuePair<ScalarValue, LogEventPropertyValue>((ScalarValue)Scrub(kv.Key), Scrub(kv.Value)))),
        _ => value,
    };

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
