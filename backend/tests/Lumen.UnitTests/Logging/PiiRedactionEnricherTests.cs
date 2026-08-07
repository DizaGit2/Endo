using System.Reflection;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Logging;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Logging;

public class PiiRedactionEnricherTests
{
    private sealed class CapturingSink : ILogEventSink
    {
        public List<LogEvent> Events { get; } = [];
        public void Emit(LogEvent logEvent) => Events.Add(logEvent);
    }

    private static (ILogger logger, CapturingSink sink) BuildLogger()
    {
        var sink = new CapturingSink();
        var logger = new LoggerConfiguration()
            .Enrich.With(new PiiRedactionEnricher())
            .WriteTo.Sink(sink)
            .CreateLogger();
        return (logger, sink);
    }

    [Fact]
    public void Redacts_email_in_properties()
    {
        // "Email" is now a sensitive property NAME (defense-in-depth, name-based redaction) — the
        // whole property value is replaced, not just the email-shaped substring within it.
        var (logger, sink) = BuildLogger();
        logger.Information("User {Email} signed in", "maria@example.com");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("maria@example.com");
    }

    [Fact]
    public void Rewrites_user_guid_path()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Request to {Path}", "/users/87dd6291-d2cd-49f7-b8ea-a29a0bae4f49");

        sink.Events.Single().RenderMessage().ShouldContain("/users/[id]");
    }

    [Fact]
    public void Leaves_clean_messages_untouched()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Health check {Status}", "ok");

        sink.Events.Single().RenderMessage().ShouldContain("ok");
    }

    [Fact]
    public void Redacts_pii_nested_in_destructured_object()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { Email = "nested@example.com", UserId = Guid.NewGuid() });

        var rendered = sink.Events.Single().RenderMessage();
        // "Email" is a sensitive property NAME (see Redacts_email_in_properties) — whole-value redact.
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("nested@example.com");
        rendered.ShouldContain("[id]"); // UserId isn't a sensitive name — still value-based Guid scrub
    }

    // ── name-based redaction (defense-in-depth) ──────────────────────────────────────────────────

    [Fact]
    public void Redacts_top_level_password_property()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Login attempt {Password}", "hunter2");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("hunter2");
    }

    [Fact]
    public void Redacts_top_level_property_by_sensitive_name_case_insensitively()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Login attempt {PASSWORD}", "hunter2");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("hunter2");
    }

    [Fact]
    public void Redacts_structure_property_by_name_leaves_sibling_properties_untouched()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("profile {@Profile}", new { DisplayName = "Maya", Count = 3 });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("Maya");
        rendered.ShouldContain("3");
    }

    [Fact]
    public void Redacts_dictionary_value_by_sensitive_key_name()
    {
        var (logger, sink) = BuildLogger();
        var device = new Dictionary<string, object> { ["pushToken"] = "abc123token", ["platform"] = "ios" };
        logger.Information("device registered {@Device}", device);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("abc123token");
        rendered.ShouldContain("ios");
    }

    [Fact]
    public void Redacts_sensitive_name_nested_two_levels_deep()
    {
        // A structure (User) nested inside another structure (Payload) — one level deeper than the
        // immediate destructured object — still gets its sensitive-named property fully redacted.
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { User = new { Password = "hunter2", Id = 7 } });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted]");
        rendered.ShouldNotContain("hunter2");
        rendered.ShouldContain("7");
    }

    // ── negative controls: value-based scrubbing is unchanged for non-sensitive names ───────────

    [Fact]
    public void Non_sensitive_property_name_with_email_shaped_value_still_gets_value_based_scrub()
    {
        var (logger, sink) = BuildLogger();
        logger.Information("Preferences {Locale} status {Status}", "someone@example.com", "ok");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted-email]"); // Locale isn't a sensitive name — old value scrub
        rendered.ShouldNotContain("someone@example.com");
        rendered.ShouldContain("ok"); // benign name + benign value passes through untouched
    }

    [Fact]
    public void Non_sensitive_nested_property_with_email_shaped_value_still_gets_value_based_scrub()
    {
        // `Note` USED to be the benign name in this control. P4a makes free-text notes health data
        // (§F), so `note` joined SensitiveNames in T8 and the control moved to `Label`, which is not
        // a P4a field name.
        var (logger, sink) = BuildLogger();
        logger.Information("req {@Payload}", new { Label = "contact-me@example.com", Count = 1 });

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldContain("[redacted-email]"); // Label isn't a sensitive name — old value scrub
        rendered.ShouldNotContain("contact-me@example.com");
        rendered.ShouldContain("1");
    }

    // ── T8: the P4a health-data field names, plus the P3c-deferred credential names ─────────────

    /// <summary>
    /// The P4a entity types, <b>derived from the domain assembly</b> rather than typed out: every
    /// class in <c>Lumen.Domain.Entities</c> carrying a <c>UserId</c>, minus the four user-owned
    /// entities that predate P4a (named by <c>typeof</c>, so a rename breaks the build rather than
    /// silently widening the set). A user-owned entity added by any later phase lands here
    /// automatically and its columns must then be classified — redacted by name, or listed in
    /// <see cref="BenignColumnNames"/> with the reason it carries no special-category fact.
    ///
    /// <para>This is the point of the whole section. The first version of these theories enumerated a
    /// verbatim COPY of <c>PiiRedactionEnricher.SensitiveNames</c>, so it could only ever prove the
    /// list equals itself — it passed while <c>Reason</c> (where <c>pause_reason = 'pregnancy'</c>
    /// actually lives), <c>GoalCode</c>, <c>Kind</c>, <c>Phase</c>, <c>Metric</c>, <c>Day</c> and
    /// eighteen more were missing from the net.</para>
    /// </summary>
    private static readonly IReadOnlyList<Type> P4aEntityTypes =
    [
        .. typeof(Symptom).Assembly.GetTypes()
            .Where(t => t is { IsClass: true, IsAbstract: false, IsPublic: true }
                        && t.Namespace == typeof(Symptom).Namespace
                        && t.GetProperty("UserId", BindingFlags.Public | BindingFlags.Instance) is not null)
            .Except([typeof(UserKey), typeof(UserDevice), typeof(UserProfileEnc), typeof(ConsentRecord)])
            .OrderBy(t => t.Name, StringComparer.Ordinal),
    ];

    /// <summary>
    /// Surrogate key, tenant key and audit timestamps — present on every entity, identical in meaning
    /// everywhere, and already handled: <c>Id</c>/<c>UserId</c> are GUIDs the value-based scrub turns
    /// into <c>[id]</c>, and the three lifecycle timestamps say only WHEN a row changed.
    /// </summary>
    private static readonly HashSet<string> StructuralColumnNames =
        new(StringComparer.Ordinal) { "Id", "UserId", "CreatedAt", "UpdatedAt", "DeletedAt" };

    /// <summary>
    /// The explicit allow-list: P4a columns that genuinely carry no special-category fact, each with
    /// the reason. Everything else on an entity above MUST be redacted by name. Adding an entry here
    /// is a deliberate §F decision — and a stale one (a name no entity declares any more) fails
    /// <see cref="The_derived_p4a_column_set_is_live_and_its_benign_allow_list_is_not_stale"/>.
    /// </summary>
    private static readonly IReadOnlyDictionary<string, string> BenignColumnNames =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Source"] =
                "provenance code ({user, onboarding} / {user_correction} / {manual, apple_health, " +
                "google_fit}) — says how a row arrived, never anything about the user's body.",
            ["ComputedBy"] =
                "engine provenance ('placeholder' in P4a, §G6) — an operational fact about the code.",
            ["RefreshedAt"] =
                "when the snapshot was last recomputed — a job timestamp, not an observation.",
            ["Selected"] = "the boolean half of a (GoalCode, Selected) pair whose CODE half is redacted.",
            ["Charted"] = "the boolean half of a (HormoneCode, Charted) pair whose CODE half is redacted.",
            ["Enabled"] = "the boolean half of a (CategoryCode, Enabled) pair whose CODE half is redacted.",
            ["PhasePredictionEnabled"] = "engine feature toggle — a display preference, not a datum.",
            ["AutoDetectPeriodStartEnabled"] = "engine feature toggle — a display preference, not a datum.",
        };

    /// <summary>Every P4a column that must be redacted by name, derived from the entities above.</summary>
    private static IEnumerable<string> DerivedP4aColumnNames() =>
        P4aEntityTypes
            .SelectMany(t => t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            .Select(p => p.Name)
            .Where(n => !StructuralColumnNames.Contains(n) && !BenignColumnNames.ContainsKey(n))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(n => n, StringComparer.Ordinal);

    /// <summary>
    /// The sensitive names that are NOT entity columns and so cannot be derived: request/response DTO
    /// spellings, the batch envelope, the encrypted profile bundle's plaintext DTO fields, and the
    /// credential names P3c deferred. Hand-maintained by necessity — but small, and every name here
    /// is one the entity reflection above provably cannot reach.
    /// </summary>
    private static readonly string[] NonEntitySensitiveNames =
    [
        // free-text notes (D-13) — the DTO spellings; the NotesEnc column itself is derived
        "notes", "note",
        // the POST /symptoms batch envelope (§G6/OQ-6: 1–50 rows under one property)
        "entries",
        // rider-4 condition bundle + onboarding weight: DTO names for user_profile_enc's *_enc columns
        "endoStatus", "rasrmStage", "diagnosedOn", "heightCm", "weightKg",
        // onboarding cycle/goals payloads
        "lastPeriodStart", "goals",
        // credentials — deferred in P3c, in scope now
        "token", "refreshToken", "idToken", "authorization", "secret", "dek",
    ];

    /// <summary>Derived entity columns ∪ the non-derivable DTO/credential names.</summary>
    public static TheoryData<string> SensitiveP4aNames =>
    [
        .. DerivedP4aColumnNames()
            .Concat(NonEntitySensitiveNames)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(n => n, StringComparer.Ordinal),
    ];

    [Fact]
    public void The_derived_p4a_column_set_is_live_and_its_benign_allow_list_is_not_stale()
    {
        // Anti-vacuity: if the reflection above ever returns nothing (namespace move, trimming, a
        // renamed UserId convention) every theory below would pass with zero cases.
        P4aEntityTypes.Count.ShouldBe(11,
            "§G4 freezes the P4a table set at eleven user-owned entities. A twelfth means a later " +
            "phase added one: classify its columns here (and extend the erasure path — see " +
            "Lumen.SecurityTests.GdprErasurePlaintextCompletenessTests).");

        foreach (var type in P4aEntityTypes)
            type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Select(p => p.Name)
                .Any(n => !StructuralColumnNames.Contains(n) && !BenignColumnNames.ContainsKey(n))
                .ShouldBeTrue($"{type.Name} contributes no name to the redaction net — every column " +
                              "it declares is structural or allow-listed, which is almost certainly wrong.");

        var declared = P4aEntityTypes
            .SelectMany(t => t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            .Select(p => p.Name)
            .ToHashSet(StringComparer.Ordinal);
        BenignColumnNames.Keys.Except(declared).OrderBy(n => n, StringComparer.Ordinal).ShouldBeEmpty(
            "these names are allow-listed as benign but no P4a entity declares them any more — a " +
            "stale allow-list silently exempts a future column that happens to reuse the name.");
    }

    [Theory]
    [MemberData(nameof(SensitiveP4aNames))]
    public void Redacts_every_p4a_sensitive_field_name(string name)
    {
        var (logger, sink) = BuildLogger();
        logger.Information("write {" + name + "}", "leaked-health-datum");

        var rendered = sink.Events.Single().RenderMessage();
        rendered.Contains("leaked-health-datum").ShouldBeFalse(
            $"'{name}' must be a redacted property name — P4a stores health data under it");
        rendered.ShouldContain("[redacted]");
    }

    [Theory]
    [MemberData(nameof(SensitiveP4aNames))]
    public void Redacts_every_p4a_sensitive_field_name_nested_in_a_destructured_object(string name)
    {
        // The request-body shapes P4a logs are objects, not top-level scalars, so the nested path is
        // the one that actually matters in production.
        var (logger, sink) = BuildLogger();
        var payload = new Dictionary<string, object> { [name] = "leaked-health-datum", ["ok"] = "benign" };
        logger.Information("write {@Payload}", payload);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.Contains("leaked-health-datum").ShouldBeFalse(
            $"'{name}' must be redacted when nested inside a destructured payload");
        rendered.ShouldContain("benign"); // siblings survive
    }

    [Fact]
    public void Redacts_a_numeric_pain_score_not_just_strings()
    {
        // Intensity/pain/mood are SHORTS, not strings — a value-shape-based scrub would miss them
        // entirely. Name-based redaction is what makes an ordinal health score safe.
        var (logger, sink) = BuildLogger();
        logger.Information("day log {Pain} {Mood}", 9, 1);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldBe("day log \"[redacted]\" \"[redacted]\"");
    }

    [Fact]
    public void RequestPath_with_a_date_keyed_route_is_not_emitted_raw()
    {
        // §F: `/cycle/day/2026-08-06` is a health-adjacent fact — it says this user logged something
        // on that day. Request logging must emit the route TEMPLATE, never the raw path, so the
        // enricher redacts RequestPath outright rather than trying to parse dates out of it.
        var (logger, sink) = BuildLogger();
        logger.Information("HTTP {RequestMethod} {RequestPath} responded {StatusCode}",
            "POST", "/cycle/day/2026-08-06", 200);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldNotContain("2026-08-06");
        rendered.ShouldNotContain("/cycle/day");
        rendered.ShouldContain("[redacted]");
        rendered.ShouldContain("200"); // status code is not PII and must stay legible
    }

    // ── never throws, even on odd shapes ─────────────────────────────────────────────────────────

    [Fact]
    public void Does_not_throw_on_null_or_empty_shapes()
    {
        var (logger, sink) = BuildLogger();

        var act = () =>
        {
            logger.Information("null sensitive value {DisplayName}", (string?)null);
            logger.Information("empty struct {@Empty}", new { });
            logger.Information(
                "nested null under sensitive name {@Payload}",
                new { DisplayName = (string?)null, Nested = new { Password = (string?)null, Count = 0 } });
        };

        Should.NotThrow(act);
        sink.Events.Count.ShouldBe(3);
    }
}
