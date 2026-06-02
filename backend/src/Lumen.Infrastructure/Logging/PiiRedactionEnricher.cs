using System.Text.RegularExpressions;
using Serilog.Core;
using Serilog.Events;

namespace Lumen.Infrastructure.Logging;

/// <summary>
/// Serilog enricher that redacts PII from log-event properties (§F logging rules). Scalar string
/// properties containing an email address have it replaced with <c>[redacted-email]</c>, and a
/// <c>/users/{guid}</c> path segment is rewritten to <c>/users/[id]</c>. Combined with not logging
/// request/response bodies, this keeps emails and user identifiers out of logs.
/// </summary>
public sealed partial class PiiRedactionEnricher : ILogEventEnricher
{
    [GeneratedRegex(@"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"/users/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")]
    private static partial Regex UserGuidPathRegex();

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        foreach (var key in logEvent.Properties.Keys.ToArray())
        {
            if (logEvent.Properties[key] is not ScalarValue { Value: string original })
                continue;

            var scrubbed = EmailRegex().Replace(original, "[redacted-email]");
            scrubbed = UserGuidPathRegex().Replace(scrubbed, "/users/[id]");

            if (!ReferenceEquals(scrubbed, original) && scrubbed != original)
                logEvent.AddOrUpdateProperty(propertyFactory.CreateProperty(key, scrubbed));
        }
    }
}
