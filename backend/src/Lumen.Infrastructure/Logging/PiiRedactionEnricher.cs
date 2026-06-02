using System.Text.RegularExpressions;
using Serilog.Core;
using Serilog.Events;

namespace Lumen.Infrastructure.Logging;

/// <summary>
/// Serilog enricher that redacts PII from log-event properties (§F logging rules): any email is
/// replaced with <c>[redacted-email]</c> and any standalone GUID (e.g. a user <c>sub</c>) with
/// <c>[id]</c>. Combined with not logging request/response bodies and not embedding identifiers in
/// exception messages, this keeps emails and user identifiers out of logs.
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
            if (logEvent.Properties[key] is not ScalarValue { Value: string original })
                continue;

            var scrubbed = EmailRegex().Replace(original, "[redacted-email]");
            scrubbed = GuidRegex().Replace(scrubbed, "[id]");

            if (scrubbed != original)
                logEvent.AddOrUpdateProperty(propertyFactory.CreateProperty(key, scrubbed));
        }
    }
}
