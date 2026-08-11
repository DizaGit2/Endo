using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Hangfire;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// The host this file's sweep runs against. Two deliberate departures from
/// <see cref="LumenApiFactory"/>, both about making a sweep that grows with the API possible at all:
///
/// <para><b>1. The global rate limiter is raised.</b> Production partitions on <c>sub</c> at 60
/// requests per minute, and every anonymous request in a run shares one <c>"anonymous"</c> partition
/// (the TestServer has no <c>RemoteIpAddress</c>). A sweep walks EVERY authenticated route as one user,
/// so at 60 it would sit a handful of endpoints away from answering 429 — and a 429 in this file reads
/// as an isolation failure while being nothing of the kind. Raised here only; both limiter suites
/// (<c>RateLimitLiveTests</c>, <c>OnboardingRateLimitLiveTests</c>) build their own hosts with explicit
/// low limits, so the coverage that actually asserts the limiter is untouched.</para>
///
/// <para><b>2. <see cref="IBackgroundJobClient"/> is the recording stub</b> (the same one
/// <c>DeleteMeLiveTests</c> uses). <c>DELETE /me</c> is one of the routes swept, and it is the only one
/// whose isolation claim is about a JOB ARGUMENT rather than a row: the shred it enqueues must name the
/// caller and never the other tenant. The stub makes that observable, and keeps the sweep from posting
/// real jobs into the dev Hangfire schema.</para>
/// </summary>
public sealed class TenantIsolationApiFactory : LumenApiFactory
{
    public RecordingBackgroundJobClient Jobs { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.UseSetting("RateLimit:PermitPerMinute", "1000");
        builder.ConfigureTestServices(s => s.AddSingleton<IBackgroundJobClient>(Jobs));
    }
}

/// <summary>
/// LIVE-STACK — <b>the phase-wide tenant-isolation suite (T19)</b>: the single file that proves no user
/// can reach another user's health data through ANY P4a endpoint. Earlier tasks asserted isolation for
/// their own resource; this is the systematic sweep, and it is the phase's headline exit criterion.
///
/// <para><b>The sweep is derived from the ROUTE TABLE, not from a hand list.</b> A hand-maintained list
/// of endpoints is exactly what goes stale the moment P5 adds one, and a stale isolation suite is worse
/// than none because it advertises a safety it no longer provides. So
/// <see cref="Every_authenticated_route_in_the_endpoint_table_is_swept_by_this_file"/> reads the built
/// host's <see cref="EndpointDataSource"/> — the same mechanism <c>OnboardingEndpointsMoveTests</c> uses
/// — and asserts SET EQUALITY against <see cref="Swept"/>. Three things therefore fail this suite:
/// <list type="number">
///   <item>a new authenticated endpoint with no entry in <see cref="Swept"/>;</item>
///   <item>an entry in <see cref="Swept"/> whose route no longer exists (a rename, a dropped
///   <c>MapXEndpoints()</c>);</item>
///   <item>a new endpoint registered with <b>neither</b> <c>.RequireAuthorization()</c> nor
///   <c>.AllowAnonymous()</c> — it lands in neither declared bucket and the partition assertion fails.
///   Without that third check a P5 endpoint that simply FORGOT its authorization call would vanish from
///   the authenticated set and be swept by nobody.</item>
/// </list>
/// Every request URL below is built from the same <see cref="Routes"/> constants the table is built
/// from, so the two cannot drift apart.</para>
///
/// <para><b>What isolation means here.</b> Tenant isolation is <b>404, never 403</b> — a 403 confirms
/// the id exists — and <see cref="NotFoundProblemTitle"/> is asserted verbatim on the wire. Reads must
/// not leak existence: asking for another user's row must be answered <i>identically</i> to asking for
/// a row that never existed, which is why several assertions compare response FINGERPRINTS rather than
/// status codes. Writes must not touch another tenant's rows and must not be able to move a row between
/// tenants. Soft-deleted rows stay invisible across the boundary, and no write may revive another
/// tenant's tombstone (the §G9 unfiltered-index upserts are the live hazard there). An erased user's
/// still-valid JWT gets 404 everywhere — there is no write fence behind crypto-shred, so those 404s are
/// a security control rather than politeness.</para>
///
/// <para><b>The one deliberate exception is <c>POST /me/devices</c></b>, which detaches a push token
/// from every other account on purpose (<c>DeviceRegistrationService</c> rule 4: a token addresses the
/// app install, not the account, so leaving the old row delivers one user's cycle notifications to a
/// handset somebody else is signed in on). Two consequences for this file, both load-bearing: the
/// generic write sweep uses <b>distinct tokens per user</b>, because a generic "B's write left A's rows
/// untouched" assertion would fail on a shared token and that failure would be a false positive; and
/// the detach gets its own POSITIVE test asserting the narrower guarantee that actually holds — a
/// caller can never read or modify another user's device, and can only remove a row whose token it
/// demonstrably holds.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class TenantIsolationLiveTests(TenantIsolationApiFactory factory) : IClassFixture<TenantIsolationApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    /// <summary>
    /// <c>Lumen.Api.Validation.NotFoundProblem.Title</c>, restated here as a literal on purpose: this
    /// suite exists to pin what goes out ON THE WIRE, and importing the production constant would make
    /// the assertion pass for any value the two happened to share.
    /// </summary>
    private const string NotFoundProblemTitle = "The requested resource was not found.";

    private static readonly TimeZoneInfo Madrid = TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid");

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), Madrid).Date);

    // ---------------------------------------------------------------- the route table

    /// <summary>
    /// The route templates, exactly as <c>Program.cs</c> and the <c>MapXEndpoints()</c> files register
    /// them. <see cref="Swept"/> is built from these AND every request this file sends is built from
    /// these, so a template that stops matching the endpoint table fails the guard rather than silently
    /// sweeping a 404-for-the-wrong-reason.
    /// </summary>
    private static class Routes
    {
        public const string Me = "/me";
        public const string MeDevices = "/me/devices";
        public const string CycleEvents = "/cycle/events";
        public const string CycleEventById = "/cycle/events/{id:guid}";
        public const string CyclePhaseOverride = "/cycle/phase-override";
        public const string CycleDayByDate = "/cycle/day/{date}";
        public const string CheckinQuick = "/checkin/quick";
        public const string CycleCalendar = "/cycle/calendar";
        public const string Symptoms = "/symptoms";
        public const string SymptomById = "/symptoms/{id:guid}";
        public const string SettingsCycle = "/settings/cycle";
        public const string OnboardingBaseline = "/onboarding/baseline";
        public const string OnboardingGoals = "/onboarding/goals";
        public const string OnboardingHormones = "/onboarding/hormones";
        public const string OnboardingNotifications = "/onboarding/notifications";
        public const string OnboardingCycle = "/onboarding/cycle";
        public const string OnboardingComplete = "/onboarding/complete";
        public const string OnboardingState = "/onboarding/state";
    }

    private static string CycleEventUrl(Guid id) => Routes.CycleEventById.Replace("{id:guid}", id.ToString());

    private static string SymptomUrl(Guid id) => Routes.SymptomById.Replace("{id:guid}", id.ToString());

    private static string CycleDayUrl(DateOnly date) =>
        Routes.CycleDayByDate.Replace("{date}", date.ToString("yyyy-MM-dd"));

    private static string SymptomWindowUrl(DateOnly from, DateOnly to) =>
        $"{Routes.Symptoms}?from={from:yyyy-MM-dd}&to={to:yyyy-MM-dd}";

    private static string CalendarWindowUrl(DateOnly from, DateOnly to) =>
        $"{Routes.CycleCalendar}?from={from:yyyy-MM-dd}&to={to:yyyy-MM-dd}";

    /// <summary>
    /// The routes registered WITHOUT authorization, declared so the endpoint-table guard can partition
    /// the whole table into "declared anonymous" and "requires a token" with nothing left over. Adding a
    /// route here is a deliberate act with a reviewer attached; forgetting
    /// <c>.RequireAuthorization()</c> on a new endpoint is not, and that is the difference this list
    /// exists to catch.
    ///
    /// <para><b>Keyed on <c>"METHOD template"</c>, exactly like the authenticated half.</b> Keying this
    /// set on the bare template would let a new UNAUTHENTICATED endpoint hide behind an existing
    /// anonymous one: <c>app.MapPost("/health", …)</c> shares a template with the anonymous
    /// <c>GET /health</c>, so a template-keyed set would filter it out of <c>unclassified</c> while its
    /// lack of <see cref="IAuthorizeData"/> kept it out of the authenticated set too — a new
    /// unauthenticated route on a live API, and this suite green. The method is part of the identity of
    /// an endpoint, so it is part of the key on both sides.</para>
    /// </summary>
    private static readonly string[] DeclaredAnonymousRoutes =
    [
        "GET /health",       // P0a liveness — no user, no data
        "GET /health/ready", // P0a readiness — dependency probe only
        "POST /onboarding/start", // sign-up: the caller cannot have a token yet (per-IP policy protects it)
    ];

    /// <summary>
    /// The Hangfire dashboard, excluded from the guard by EXACT template rather than by a
    /// <c>/hangfire</c> prefix — a prefix rule would wave through any future route under that path. It
    /// carries no ASP.NET authorization metadata because it is gated by
    /// <c>HangfireDashboardAuthorizationFilter</c> (deny-by-default) inside <c>DashboardOptions</c>, and
    /// <c>HangfireLiveTests</c> owns that assertion. It serves no tenant data.
    /// </summary>
    private const string HangfireDashboardTemplate = "/hangfire/{**path}";

    /// <summary>
    /// One authenticated route and how this file sweeps it. <paramref name="Assertions"/> is the
    /// endpoint × assertion matrix, kept next to the code rather than in a document that would rot.
    /// <paramref name="Request"/> is a canned, well-formed request used by the erased-user walk: every
    /// P4a service resolves the day context (the 404 fence) BEFORE validating, so the body only has to
    /// be shaped well enough to reach a handler.
    /// </summary>
    private sealed record SweptRoute(
        string Method,
        string Template,
        string Assertions,
        Func<HttpRequestMessage> Request)
    {
        public string Key => $"{Method} {Template}";
    }

    private static HttpRequestMessage Req(HttpMethod method, string url, object? body = null) =>
        new(method, url) { Content = body is null ? null : JsonContent.Create(body) };

    private static readonly IReadOnlyList<SweptRoute> Swept =
    [
        new("GET", Routes.Me,
            "read: answers the CALLER's identity and baseline, never the other tenant's; erased → 404",
            () => Req(HttpMethod.Get, Routes.Me)),
        new("DELETE", Routes.Me,
            "write: self-scoped — the enqueued shred names the caller only; erased → 202 (idempotent guard)",
            () => Req(HttpMethod.Delete, Routes.Me)),
        new("PATCH", Routes.Me,
            "write: leaves the other tenant's users/user_profile_enc rows byte-unchanged; erased → 404",
            () => Req(HttpMethod.Patch, Routes.Me, new { })),
        new("POST", Routes.MeDevices,
            "write: THE DELIBERATE EXCEPTION — distinct token leaves the other tenant untouched; a held "
            + "token detaches (own test, new row id, never a tenant move); erased → 404",
            () => Req(HttpMethod.Post, Routes.MeDevices, new { platform = UserDevice.Platforms.Ios, pushToken = NewPushToken("fcm") })),
        new("POST", Routes.CycleEvents,
            "write: same (kind, day) as the owner creates the CALLER's own row and neither hijacks nor "
            + "revives the owner's §G9 tombstone; erased → 404",
            () => Req(HttpMethod.Post, Routes.CycleEvents, new { kind = CycleEvent.Kinds.Spotting, occurredOn = Today.ToString("yyyy-MM-dd") })),
        new("DELETE", Routes.CycleEventById,
            "id-addressed: another tenant's id → 404 with a body byte-identical to an id that never "
            + "existed; the owner's row keeps DeletedAt == null; erased → 404",
            () => Req(HttpMethod.Delete, CycleEventUrl(Guid.NewGuid()))),
        new("POST", Routes.CyclePhaseOverride,
            "keyed write, BOTH branches: the other tenant's cycleStartOn is answered exactly as any day "
            + "the caller never logged (400 'must match a logged period start'), AND — once the caller "
            + "has its own anchor on that same date — the 200 replace-the-set neither overwrites nor "
            + "retracts the other tenant's corrections for that cycle; erased → 404",
            () => Req(HttpMethod.Post, Routes.CyclePhaseOverride, new { cycleStartOn = Today.ToString("yyyy-MM-dd"), boundaries = Array.Empty<object>() })),
        new("POST", Routes.CycleDayByDate,
            "write: the same day as the owner writes the CALLER's own row (§G9 unfiltered upsert); the "
            + "owner's day log is byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, CycleDayUrl(Today), new { pain = 3 })),
        new("POST", Routes.CheckinQuick,
            "write: writes only the caller's today row; the owner's day log is byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.CheckinQuick, new { pain = 2, mood = 3 })),
        new("GET", Routes.CycleDayByDate,
            "read: TWO of the owner's days — the busiest (log + event + symptom) and the one their phase "
            + "correction is dated on — each answer identically to a day nobody ever logged (null log, "
            + "empty events, empty overrides); erased → 404",
            () => Req(HttpMethod.Get, CycleDayUrl(Today))),
        new("GET", Routes.CycleCalendar,
            "range read: the owner's window comes back with zero days; erased → 404",
            () => Req(HttpMethod.Get, Routes.CycleCalendar)),
        new("POST", Routes.Symptoms,
            "write: creates the caller's own rows; the owner's symptoms are byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.Symptoms, new { entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 4 } } })),
        new("GET", Routes.Symptoms,
            "range read: total 0 and items empty over the owner's window, live rows and tombstones alike; erased → 404",
            () => Req(HttpMethod.Get, Routes.Symptoms)),
        new("PUT", Routes.SymptomById,
            "id-addressed: another tenant's id → 404 byte-identical to a never-existing id; the owner's "
            + "row keeps its intensity, side and DeletedAt; erased → 404",
            () => Req(HttpMethod.Put, SymptomUrl(Guid.NewGuid()), new { intensity = 1 })),
        new("DELETE", Routes.SymptomById,
            "id-addressed: another tenant's id → 404 byte-identical to a never-existing id, live row or "
            + "tombstone alike; erased → 404",
            () => Req(HttpMethod.Delete, SymptomUrl(Guid.NewGuid()))),
        new("GET", Routes.SettingsCycle,
            "read: answers the CALLER's own settings (its untouched defaults, not the owner's edits); erased → 404",
            () => Req(HttpMethod.Get, Routes.SettingsCycle)),
        new("PATCH", Routes.SettingsCycle,
            "write: creates/updates the caller's own user_cycle_settings row; the owner's is byte-unchanged; erased → 404",
            () => Req(HttpMethod.Patch, Routes.SettingsCycle, new { avgCycleLengthDays = 30 })),
        new("POST", Routes.OnboardingBaseline,
            "write: writes the caller's own user_profile_enc/body_metrics; the owner's are byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.OnboardingBaseline, new { heightCm = 170 })),
        new("POST", Routes.OnboardingGoals,
            "write: writes the caller's own user_goals; the owner's are byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.OnboardingGoals, new { goals = new[] { UserGoal.Codes.JustCurious } })),
        new("POST", Routes.OnboardingHormones,
            "write: writes the caller's own user_hormone_prefs; the owner's are byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.OnboardingHormones, new { chartedHormones = new[] { "lh" } })),
        new("POST", Routes.OnboardingNotifications,
            "write: writes the caller's own user_notification_prefs, and stages a device row under the "
            + "SAME rule-4 detach as POST /me/devices; the owner's rows are byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.OnboardingNotifications, new { enabledCategories = new[] { "daily_checkin" } })),
        new("POST", Routes.OnboardingCycle,
            "write: seeds the caller's own period_start + settings; the owner's anchor is byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.OnboardingCycle, new { lastPeriodStart = Today.ToString("yyyy-MM-dd") })),
        new("POST", Routes.OnboardingComplete,
            "write: stamps the caller's own users.onboarding_completed_at; the owner's is byte-unchanged; erased → 404",
            () => Req(HttpMethod.Post, Routes.OnboardingComplete)),
        new("GET", Routes.OnboardingState,
            "read: reports the CALLER's own progress and last period start, never the owner's; erased → 404",
            () => Req(HttpMethod.Get, Routes.OnboardingState)),
    ];

    // ---------------------------------------------------------------- 1. the route-table guard

    [Fact]
    public void Every_authenticated_route_in_the_endpoint_table_is_swept_by_this_file()
    {
        // Force the host (and therefore routing) to build before reading the endpoint table — the same
        // move OnboardingEndpointsMoveTests makes.
        _ = factory.CreateClient();

        var endpoints = factory.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .OfType<RouteEndpoint>()
            .Where(e => !string.Equals(e.RoutePattern.RawText, HangfireDashboardTemplate, StringComparison.Ordinal))
            .ToList();

        endpoints.ShouldNotBeEmpty("the endpoint table must have been built before it is read");

        // (a) PARTITION. Every route is either declared anonymous or requires authorization. A new
        // endpoint that forgot .RequireAuthorization() is in neither bucket and lands here — which is
        // the only reason (b) can be trusted, since such an endpoint would otherwise never appear in
        // the authenticated set at all.
        //
        // BOTH buckets are keyed on "METHOD template" (see DeclaredAnonymousRoutes). Keying the
        // anonymous half on the bare template would make this guard blind to a new unauthenticated
        // endpoint added under a template that is ALREADY anonymous — `app.MapPost("/health", …)` would
        // be swallowed by the anonymous `GET /health` and appear in neither half.
        var anonymous = endpoints
            .Where(e => e.Metadata.GetMetadata<IAllowAnonymous>() is not null)
            .SelectMany(RouteKeys)
            .ToHashSet(StringComparer.Ordinal);
        var registered = endpoints
            .Where(e => e.Metadata.GetMetadata<IAllowAnonymous>() is null
                        && e.Metadata.GetMetadata<IAuthorizeData>() is not null)
            .SelectMany(RouteKeys)
            .ToHashSet(StringComparer.Ordinal);

        var unclassified = endpoints
            .SelectMany(RouteKeys)
            .Where(key => !anonymous.Contains(key) && !registered.Contains(key))
            .ToList();
        unclassified.ShouldBeEmpty(
            "every route must be either declared anonymous (DeclaredAnonymousRoutes) or carry "
            + ".RequireAuthorization(). A route in neither bucket is an endpoint whose authorization "
            + "call was forgotten, and it would slip past the coverage check below unnoticed.");

        anonymous.ShouldBe(
            DeclaredAnonymousRoutes.ToHashSet(StringComparer.Ordinal),
            ignoreOrder: true,
            "an endpoint became (or stopped being) anonymous. Anonymous access to a route that touches "
            + "tenant data is the failure this whole file exists to prevent, so the list is explicit.");

        // (b) COVERAGE. Set equality both ways: a new authenticated endpoint with no entry in `Swept`
        // fails here, and so does a `Swept` entry whose route was renamed or unregistered.
        registered.ShouldBe(
            Swept.Select(s => s.Key).ToHashSet(StringComparer.Ordinal),
            ignoreOrder: true,
            "the tenant-isolation sweep is derived from the ROUTE TABLE. Every authenticated route must "
            + "have an entry in TenantIsolationLiveTests.Swept (route + the assertions that cover it) "
            + "and every entry must name a route that still exists. If you added an endpoint, add its "
            + "isolation coverage here in the same commit.");

        Swept.Select(s => s.Key).ShouldBeUnique();
    }

    /// <summary>
    /// The <c>"METHOD template"</c> keys one registered endpoint contributes — the single unit BOTH
    /// halves of the guard above are keyed on, and the same shape as <see cref="SweptRoute.Key"/>. A
    /// route registered without any method constraint keys as <c>* template</c>.
    /// </summary>
    private static IEnumerable<string> RouteKeys(RouteEndpoint endpoint) =>
        (endpoint.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods ?? ["*"])
            .Select(m => $"{m} {endpoint.RoutePattern.RawText}");

    // ---------------------------------------------------------------- 2. reads

    [Fact]
    public async Task Reads_answer_only_the_callers_own_data_and_never_leak_that_another_tenants_row_exists()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            var owner = await SeedTenantAsync("iso-read-own");
            ownerId = owner.UserId;
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"iso-read-int-{Guid.NewGuid():N}@example.com");
            var intruder = Authed(intruderToken);

            // GET /me — the caller's own identity, and none of the owner's baseline.
            var me = await intruder.GetAsync(Routes.Me);
            me.StatusCode.ShouldBe(HttpStatusCode.OK);
            var meBody = await me.Content.ReadFromJsonAsync<JsonElement>();
            meBody.GetProperty("id").GetGuid().ShouldBe(intruderId);
            meBody.GetProperty("displayName").GetString().ShouldBe("Isolation Tester");
            meBody.GetProperty("heightCm").ValueKind.ShouldBe(JsonValueKind.Null, "the owner's height must not appear");
            meBody.GetProperty("endoStatus").ValueKind.ShouldBe(JsonValueKind.Null);
            meBody.GetProperty("latestWeightKg").ValueKind.ShouldBe(JsonValueKind.Null);
            meBody.GetProperty("onboardingCompleted").GetBoolean().ShouldBeFalse("the owner completed, the caller did not");

            // GET /onboarding/state — progress is the caller's, and so is lastPeriodStart.
            var state = await intruder.GetAsync(Routes.OnboardingState);
            state.StatusCode.ShouldBe(HttpStatusCode.OK);
            var stateBody = await state.Content.ReadFromJsonAsync<JsonElement>();
            stateBody.GetProperty("completed").GetBoolean().ShouldBeFalse();
            stateBody.GetProperty("cycleProvided").GetBoolean().ShouldBeFalse();
            stateBody.GetProperty("lastPeriodStart").ValueKind.ShouldBe(
                JsonValueKind.Null, "the owner's anchor day is another tenant's health datum");

            // GET /settings/cycle — the caller's untouched defaults, never the owner's edited row.
            var settings = await intruder.GetAsync(Routes.SettingsCycle);
            settings.StatusCode.ShouldBe(HttpStatusCode.OK);
            var settingsBody = await settings.Content.ReadFromJsonAsync<JsonElement>();
            settingsBody.GetProperty("avgCycleLengthDays").GetInt32()
                .ShouldNotBe(SeededAvgCycleLengthDays, "that value belongs to the other tenant's row");
            settingsBody.GetProperty("createdAt").ValueKind.ShouldBe(
                JsonValueKind.Null, "no row of the caller's has ever been saved");
            settingsBody.GetProperty("regularity").GetString().ShouldBe(UserCycleSettings.RegularityValues.Default);

            // GET /cycle/calendar over the owner's populated window — zero days.
            var calendar = await intruder.GetAsync(CalendarWindowUrl(owner.Anchor.AddDays(-5), Today));
            calendar.StatusCode.ShouldBe(HttpStatusCode.OK);
            var calendarBody = await calendar.Content.ReadFromJsonAsync<JsonElement>();
            calendarBody.GetProperty("days").GetArrayLength()
                .ShouldBe(0, "a sparse calendar over another tenant's month is empty, not merely phase-less");

            // GET /cycle/day/{date} — a day the owner filled must answer EXACTLY as a day nobody ever
            // logged. Status-code equality is not enough: the point is that the two responses are
            // indistinguishable, so the fingerprints are compared with the echoed `date` normalised out.
            //
            // TWO owner days are read, because the response carries THREE collections and no single day
            // populates all of them. `owner.Anchor` is the busiest day — day log, cycle event, symptom —
            // but every phase correction the owner has is dated AFTER it (SeedTenantAsync), so reading
            // the anchor alone leaves the `phaseOverrides` leg asserting emptiness against a day that is
            // empty for everyone: it would pass with `CycleDayService`'s override query unscoped.
            var barren = await intruder.GetAsync(CycleDayUrl(owner.Anchor.AddDays(-400)));
            var barrenFingerprint = await FingerprintAsync(barren, "date");

            var populated = await intruder.GetAsync(CycleDayUrl(owner.Anchor));
            populated.StatusCode.ShouldBe(HttpStatusCode.OK);
            var populatedBody = await populated.Content.ReadFromJsonAsync<JsonElement>();
            populatedBody.GetProperty("log").ValueKind.ShouldBe(JsonValueKind.Null);
            populatedBody.GetProperty("events").GetArrayLength().ShouldBe(0);
            (await FingerprintAsync(populated, "date"))
                .ShouldBe(barrenFingerprint,
                    "a day the OTHER tenant filled must be answered identically to a day nobody has ever "
                    + "touched — otherwise the shape of the answer is itself the leak");

            // The day the owner's phase correction is actually dated on.
            var corrected = await intruder.GetAsync(CycleDayUrl(owner.Anchor.AddDays(SeededOverrideOffsetDays)));
            corrected.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await corrected.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("phaseOverrides").GetArrayLength()
                .ShouldBe(0, "the owner's phase correction is dated on this day and is theirs alone");
            (await FingerprintAsync(corrected, "date"))
                .ShouldBe(barrenFingerprint,
                    "the day carrying the other tenant's phase correction must be answered identically "
                    + "to a day nobody has ever touched");

            // GET /symptoms over the owner's window — nothing, in items OR in total.
            var symptoms = await intruder.GetAsync(SymptomWindowUrl(owner.Anchor.AddDays(-5), Today));
            symptoms.StatusCode.ShouldBe(HttpStatusCode.OK);
            var symptomsBody = await symptoms.Content.ReadFromJsonAsync<JsonElement>();
            symptomsBody.GetProperty("total").GetInt32()
                .ShouldBe(0, "a total that counted another tenant's rows leaks their existence without showing them");
            symptomsBody.GetProperty("items").GetArrayLength().ShouldBe(0);

            (await SnapshotAsync(ownerId)).ShouldBe(owner.Snapshot, "a read must not write");
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ---------------------------------------------------------------- 3. id-addressed routes

    [Fact]
    public async Task Id_addressed_routes_answer_the_shared_404_never_a_403_and_leave_the_owners_rows_byte_unchanged()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            var owner = await SeedTenantAsync("iso-id-own");
            ownerId = owner.UserId;
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"iso-id-int-{Guid.NewGuid():N}@example.com");
            var intruder = Authed(intruderToken);

            // A guid that has never named anything. Every answer below must be indistinguishable from it.
            var phantom = Guid.NewGuid();

            var deleteEventPhantom = await intruder.DeleteAsync(CycleEventUrl(phantom));
            var deleteEventOwners = await intruder.DeleteAsync(CycleEventUrl(owner.CycleEventId));
            await AssertSharedNotFoundAsync(deleteEventOwners, $"DELETE {Routes.CycleEventById}");
            (await FingerprintAsync(deleteEventOwners)).ShouldBe(await FingerprintAsync(deleteEventPhantom));

            var putSymptomPhantom = await intruder.PutAsJsonAsync(SymptomUrl(phantom), new { intensity = 1 });
            var putSymptomOwners = await intruder.PutAsJsonAsync(SymptomUrl(owner.SymptomId), new { intensity = 1 });
            await AssertSharedNotFoundAsync(putSymptomOwners, $"PUT {Routes.SymptomById}");
            (await FingerprintAsync(putSymptomOwners)).ShouldBe(await FingerprintAsync(putSymptomPhantom));

            var deleteSymptomPhantom = await intruder.DeleteAsync(SymptomUrl(phantom));
            var deleteSymptomOwners = await intruder.DeleteAsync(SymptomUrl(owner.SymptomId));
            await AssertSharedNotFoundAsync(deleteSymptomOwners, $"DELETE {Routes.SymptomById}");
            (await FingerprintAsync(deleteSymptomOwners)).ShouldBe(await FingerprintAsync(deleteSymptomPhantom));

            // POST /cycle/phase-override is keyed on a DAY rather than an id, and it is the one route
            // whose non-leaking answer is a 400 rather than a 404: the day is checked against the
            // CALLER's own live period_start rows, so the owner's anchor is answered exactly as any day
            // the caller never logged. Same fingerprint, same message, no existence disclosed.
            var overrideOwners = await intruder.PostAsJsonAsync(Routes.CyclePhaseOverride, new
            {
                cycleStartOn = owner.Anchor.ToString("yyyy-MM-dd"),
                boundaries = Array.Empty<object>(),
            });
            var overrideNeverLogged = await intruder.PostAsJsonAsync(Routes.CyclePhaseOverride, new
            {
                cycleStartOn = owner.Anchor.AddDays(-400).ToString("yyyy-MM-dd"),
                boundaries = Array.Empty<object>(),
            });
            overrideOwners.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            overrideOwners.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            (await overrideOwners.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("cycleStartOn")[0].GetString()
                .ShouldBe("must match a logged period start");
            (await FingerprintAsync(overrideOwners)).ShouldBe(await FingerprintAsync(overrideNeverLogged),
                "the owner's real anchor and a day nobody logged must be answered identically");

            (await SnapshotAsync(ownerId)).ShouldBe(
                owner.Snapshot,
                "not one row of the owner's changed — including every DeletedAt staying null");
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ---------------------------------------------------------------- 4. writes

    [Fact]
    public async Task A_second_tenants_writes_leave_every_row_of_the_first_byte_unchanged()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            var owner = await SeedTenantAsync("iso-write-own");
            ownerId = owner.UserId;
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"iso-write-int-{Guid.NewGuid():N}@example.com");
            var intruder = Authed(intruderToken);
            factory.Jobs.Captured.Clear();

            // Every write below deliberately COLLIDES with the owner on its natural key — the same
            // (kind, day) cycle event, the same day log, the same anchor — because a UserId predicate
            // dropped from one of the §G9 unfiltered upsert lookups shows up here and nowhere else.
            var seedEvent = await intruder.PostAsJsonAsync(Routes.CycleEvents, new
            {
                kind = CycleEvent.Kinds.Spotting,
                occurredOn = owner.Anchor.ToString("yyyy-MM-dd"),
                flowIntensity = 1,
                notes = "intruder note",
            });
            seedEvent.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await seedEvent.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid()
                .ShouldNotBe(owner.CycleEventId, "the write must mint the caller's OWN row, never adopt the owner's");

            (await intruder.PostAsJsonAsync(CycleDayUrl(owner.Anchor), new { pain = 9, mood = 1, notes = "intruder day" }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await intruder.PostAsJsonAsync(Routes.CheckinQuick, new { pain = 7, mood = 2 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await intruder.PostAsJsonAsync(Routes.Symptoms, new
            {
                entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 10, notes = "intruder symptom" } },
            })).StatusCode.ShouldBe(HttpStatusCode.Created);
            (await intruder.PatchAsJsonAsync(Routes.Me, new { timezone = "America/Bogota", locale = "en-GB", displayName = "Intruder" }))
                .StatusCode.ShouldBe(HttpStatusCode.NoContent);
            (await intruder.PatchAsJsonAsync(Routes.SettingsCycle, new { avgCycleLengthDays = 33, regularity = UserCycleSettings.RegularityValues.Irregular }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // DISTINCT push token — see the class remark. Reusing the owner's here would trip the one
            // deliberate cross-tenant write and fail the byte-unchanged assertion for a reason that is
            // not a defect. That path has its own positive test.
            (await intruder.PostAsJsonAsync(Routes.MeDevices, new { platform = UserDevice.Platforms.Android, pushToken = NewPushToken("fcm") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // The six onboarding step endpoints, in the order the flow allows: /onboarding/cycle is
            // 409'd after completion, so completion comes last.
            (await intruder.PostAsJsonAsync(Routes.OnboardingBaseline, new
            {
                dob = "1988-02-29",
                heightCm = 150,
                weightKg = 99.9,
                endoStatus = UserProfileEnc.EndoStatuses.NotApplicable,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);
            (await intruder.PostAsJsonAsync(Routes.OnboardingGoals, new { goals = new[] { UserGoal.Codes.JustCurious } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await intruder.PostAsJsonAsync(Routes.OnboardingHormones, new { chartedHormones = new[] { "cortisol" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await intruder.PostAsJsonAsync(Routes.OnboardingNotifications, new
            {
                enabledCategories = new[] { "period_prediction" },
                platform = UserDevice.Platforms.Ios,
                pushToken = NewPushToken("apns"),
            })).StatusCode.ShouldBe(HttpStatusCode.OK);
            (await intruder.PostAsJsonAsync(Routes.OnboardingCycle, new
            {
                lastPeriodStart = owner.Anchor.ToString("yyyy-MM-dd"),
                avgCycleLengthDays = 21,
                regularity = UserCycleSettings.RegularityValues.Regular,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            // POST /cycle/phase-override, on the 200 PATH — and it has to come after the step above,
            // which is what makes the 200 reachable at all: the endpoint anchors a correction on the
            // CALLER's own live period_start, and `/onboarding/cycle` has just seeded the intruder one
            // on the owner's exact anchor day. Two tenants therefore hold a cycle keyed
            // `(cycleStartOn = owner.Anchor)` — ordinary, not contrived — and the replace-the-set write
            // below runs over it.
            //
            // Without this request the endpoint's WRITE half is unswept anywhere in the repository: the
            // 400 branch (asserted in Id_addressed_routes…) returns before `ApplyOverridesAsync` is ever
            // called. Dropping the UserId predicate from that method's IgnoreQueryFilters() lookup would
            // then let a second tenant do both halves of replace-the-set to the owner's corrections —
            // OVERWRITE `menstrual/end` in place (the request names that pair) and SOFT-DELETE
            // `ovulatory/start` (the request omits it) — with this whole file green.
            (await intruder.PostAsJsonAsync(Routes.CyclePhaseOverride, new
            {
                cycleStartOn = owner.Anchor.ToString("yyyy-MM-dd"),
                boundaries = new[]
                {
                    new
                    {
                        phase = CyclePhaseOverride.Phases.Menstrual,
                        boundary = CyclePhaseOverride.Boundaries.End,
                        occurredOn = owner.Anchor.AddDays(SeededOverrideOffsetDays - 1).ToString("yyyy-MM-dd"),
                    },
                },
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            (await intruder.PostAsJsonAsync(Routes.OnboardingComplete, new { }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // The caller really did write — otherwise "the owner is unchanged" would be vacuously true
            // for a suite that was simply 404-ing everything.
            await using (var db = TestFixtures.NewDb())
            {
                (await db.CycleEvents.CountAsync(e => e.UserId == intruderId)).ShouldBeGreaterThan(0);
                (await db.CycleDayLogs.CountAsync(l => l.UserId == intruderId)).ShouldBeGreaterThan(0);
                (await db.Symptoms.CountAsync(s => s.UserId == intruderId)).ShouldBe(1);
                // The caller's own correction row. Under a dropped UserId predicate the write lands on
                // the owner's `menstrual/end` row instead and the caller ends up owning none.
                (await db.CyclePhaseOverrides.CountAsync(o => o.UserId == intruderId)).ShouldBe(1);
                (await db.CycleSettings.CountAsync(s => s.UserId == intruderId)).ShouldBe(1);
                (await db.UserDevices.CountAsync(d => d.UserId == intruderId)).ShouldBe(2);
                (await db.UserGoals.CountAsync(g => g.UserId == intruderId)).ShouldBeGreaterThan(0);
            }

            // DELETE /me last: it tombstones the caller, so every write above had to happen first. Its
            // isolation claim is about the JOB ARGUMENT — the shred must name the caller and no one else.
            var deleteMe = await intruder.DeleteAsync(Routes.Me);
            deleteMe.StatusCode.ShouldBe(HttpStatusCode.Accepted);
            factory.Jobs.Captured.Count.ShouldBe(1);
            ((Guid)factory.Jobs.Captured[0].Job.Args[0]).ShouldBe(
                intruderId, "the erasure the caller asked for is the caller's own, never the other tenant's");

            (await SnapshotAsync(ownerId)).ShouldBe(
                owner.Snapshot,
                "fifteen writes by a second tenant, and not one byte of the first tenant's rows moved");
        }
        finally
        {
            if (intruderId != default) await TryDeleteKeycloakUserAsync(intruderId);
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ---------------------------------------------------------------- 5. soft-deleted rows

    [Fact]
    public async Task Soft_deleted_rows_stay_invisible_across_the_boundary_and_no_write_revives_another_tenants_tombstone()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"iso-tomb-own-{Guid.NewGuid():N}@example.com");
            var ownerClient = Authed(ownerToken);
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"iso-tomb-int-{Guid.NewGuid():N}@example.com");
            var intruder = Authed(intruderToken);

            var day = Today.AddDays(-3);

            var createdEvent = await ownerClient.PostAsJsonAsync(Routes.CycleEvents, new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day.ToString("yyyy-MM-dd"),
                flowIntensity = 3,
                notes = "owner note",
            });
            createdEvent.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await createdEvent.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            var createdSymptoms = await ownerClient.PostAsJsonAsync(Routes.Symptoms, new
            {
                entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 6, occurredAt = Midday(day) } },
            });
            createdSymptoms.StatusCode.ShouldBe(HttpStatusCode.Created);
            var symptomId = (await createdSymptoms.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("items")[0].GetProperty("id").GetGuid();

            (await ownerClient.DeleteAsync(CycleEventUrl(eventId))).StatusCode.ShouldBe(HttpStatusCode.NoContent);
            (await ownerClient.DeleteAsync(SymptomUrl(symptomId))).StatusCode.ShouldBe(HttpStatusCode.NoContent);

            var snapshotAfterDeletes = await SnapshotAsync(ownerId);

            // A tombstone across the tenant boundary is answered exactly like a live row of somebody
            // else's and exactly like an id that never existed: one 404, no third answer.
            await AssertSharedNotFoundAsync(await intruder.DeleteAsync(CycleEventUrl(eventId)), "tombstoned cycle event");
            await AssertSharedNotFoundAsync(await intruder.DeleteAsync(SymptomUrl(symptomId)), "tombstoned symptom");
            await AssertSharedNotFoundAsync(
                await intruder.PutAsJsonAsync(SymptomUrl(symptomId), new { intensity = 0 }), "tombstoned symptom");

            var window = await intruder.GetAsync(SymptomWindowUrl(day.AddDays(-1), Today));
            (await window.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("total").GetInt32().ShouldBe(0);

            // THE §G9 HAZARD. `cycle_events (UserId, Kind, OccurredOn)` is an UNFILTERED unique index, so
            // the upsert looks the row up with IgnoreQueryFilters() and revives the tombstone. Drop the
            // UserId predicate from that lookup and this exact request — same kind, same day, different
            // tenant — resurrects the owner's retracted period start, notes and all, under the intruder.
            var collide = await intruder.PostAsJsonAsync(Routes.CycleEvents, new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day.ToString("yyyy-MM-dd"),
                flowIntensity = 1,
            });
            collide.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await collide.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid()
                .ShouldNotBe(eventId, "the caller's write must mint a new row, never revive the owner's tombstone");

            (await SnapshotAsync(ownerId)).ShouldBe(
                snapshotAfterDeletes,
                "the owner's tombstones are still tombstones — DeletedAt intact, notes ciphertext intact");

            await using (var db = TestFixtures.NewDb())
            {
                var tombstone = await db.CycleEvents.IgnoreQueryFilters().AsNoTracking()
                    .SingleAsync(e => e.Id == eventId);
                tombstone.UserId.ShouldBe(ownerId, "a write must never move a row between tenants");
                tombstone.DeletedAt.ShouldNotBeNull();
            }

            // And the owner's own re-log still revives the owner's own row: the isolation fix must not
            // have been "nobody can revive anything".
            var revive = await ownerClient.PostAsJsonAsync(Routes.CycleEvents, new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day.ToString("yyyy-MM-dd"),
                flowIntensity = 2,
            });
            revive.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await revive.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid()
                .ShouldBe(eventId, "§G9: the owner's own re-log revives the owner's own tombstone");
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ---------------------------------------------------------------- 6. the deliberate exception

    [Fact]
    public async Task Registering_a_push_token_is_the_one_deliberate_cross_tenant_write_and_its_guarantee_is_narrower()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"iso-dev-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"iso-dev-int-{Guid.NewGuid():N}@example.com");
            var ownerClient = Authed(ownerToken);
            var intruder = Authed(intruderToken);

            // The handset that changes hands, and a second device the owner keeps.
            var handset = NewPushToken("fcm");
            var tablet = NewPushToken("apns");
            var handsetRegistration = await ownerClient.PostAsJsonAsync(
                Routes.MeDevices, new { platform = UserDevice.Platforms.Ios, pushToken = handset });
            handsetRegistration.StatusCode.ShouldBe(HttpStatusCode.OK);
            var ownerHandsetId = (await handsetRegistration.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("deviceId").GetGuid();
            (await ownerClient.PostAsJsonAsync(Routes.MeDevices, new { platform = UserDevice.Platforms.Ios, pushToken = tablet }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            UserDevice ownerTabletBefore;
            await using (var db = TestFixtures.NewDb())
                ownerTabletBefore = await db.UserDevices.AsNoTracking().SingleAsync(d => d.PushToken == tablet);

            // (a) A token the caller does NOT hold changes nothing of the owner's.
            (await intruder.PostAsJsonAsync(Routes.MeDevices, new { platform = UserDevice.Platforms.Android, pushToken = NewPushToken("fcm") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            await using (var db = TestFixtures.NewDb())
            {
                (await db.UserDevices.AsNoTracking().CountAsync(d => d.UserId == ownerId))
                    .ShouldBe(2, "an unrelated registration touches nobody else's rows");
            }

            // (b) The DELIBERATE cross-tenant write. Registering a token the owner holds REMOVES the
            // owner's row — correct behaviour: the token addresses the app install, so leaving it would
            // deliver the owner's cycle notifications to a handset this caller is signed in on.
            var handover = await intruder.PostAsJsonAsync(
                Routes.MeDevices, new { platform = UserDevice.Platforms.Android, pushToken = handset });
            handover.StatusCode.ShouldBe(HttpStatusCode.OK);
            var handoverBody = await handover.Content.ReadFromJsonAsync<JsonElement>();
            var newDeviceId = handoverBody.GetProperty("deviceId").GetGuid();

            await using (var db = TestFixtures.NewDb())
            {
                var rows = await db.UserDevices.AsNoTracking().Where(d => d.PushToken == handset).ToListAsync();
                rows.Count.ShouldBe(1, "a push token addresses one install, so it must name one account");
                rows[0].UserId.ShouldBe(intruderId, "the account that last proved possession owns the device");

                // REMOVED AND RE-CREATED, not moved: the row the owner's notifications were addressed to
                // no longer exists, and the caller never gained a handle on the owner's row.
                newDeviceId.ShouldNotBe(ownerHandsetId, "the owner's row is deleted and a fresh one minted — a row never changes tenant");
                (await db.UserDevices.AsNoTracking().AnyAsync(d => d.Id == ownerHandsetId)).ShouldBeFalse();

                // THE PRECISE CLAIM: only a row whose token the caller demonstrably held was removed.
                // The owner's other device is byte-identical.
                var tabletAfter = await db.UserDevices.AsNoTracking().SingleAsync(d => d.PushToken == tablet);
                tabletAfter.Id.ShouldBe(ownerTabletBefore.Id);
                tabletAfter.UserId.ShouldBe(ownerId);
                tabletAfter.Platform.ShouldBe(ownerTabletBefore.Platform);
                tabletAfter.CreatedAt.ShouldBe(ownerTabletBefore.CreatedAt);
                tabletAfter.LastSeenAt.ShouldBe(ownerTabletBefore.LastSeenAt);
            }

            // NO READ, NO MODIFY. The response of the deliberate write discloses nothing about the row
            // it displaced — not the token, not the owner, not the previous device id — and §C.9
            // publishes no other verb under /me/devices for a caller to read or edit one with. That
            // second half is asserted off the ROUTE TABLE, so a P5 `GET /me/devices` cannot quietly
            // widen this endpoint's guarantee without failing here.
            var raw = await handover.Content.ReadAsStringAsync();
            raw.ShouldNotContain(handset, Case.Sensitive);
            raw.ShouldNotContain(ownerId.ToString(), Case.Sensitive);
            raw.ShouldNotContain(ownerHandsetId.ToString(), Case.Sensitive);

            Swept.Where(s => s.Template.StartsWith(Routes.MeDevices, StringComparison.Ordinal))
                .Select(s => s.Key)
                .ShouldBe([$"POST {Routes.MeDevices}"],
                    "POST is the ONLY device verb in P4a. A read or an id-addressed write on this "
                    + "resource would need its own isolation coverage before it could ship, because the "
                    + "rule-4 detach makes 'the caller can hold a row it did not create' reachable here "
                    + "and nowhere else.");
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ---------------------------------------------------------------- 7. the erased-user fence

    [Fact]
    public async Task An_erased_users_still_valid_JWT_gets_the_shared_404_from_every_authenticated_route()
    {
        Guid userId = default;
        try
        {
            var tenant = await SeedTenantAsync("iso-shred");
            userId = tenant.UserId;
            var authed = Authed(tenant.Token);
            factory.Jobs.Captured.Clear();

            // Crypto-shred, exactly as DELETE /me's job would. The bearer token stays cryptographically
            // valid until it expires and NOTHING else fences these paths — inserting a child row takes
            // only a share lock on `users`, which never conflicts with the shred's UPDATE. The 404s
            // below are the whole of the defence, which is why this walk is driven off the route table
            // rather than a list somebody has to remember to extend.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            var afterShred = await SnapshotAsync(userId);

            foreach (var route in Swept)
            {
                using var request = route.Request();
                var response = await authed.SendAsync(request);

                if (string.Equals(route.Key, $"DELETE {Routes.Me}", StringComparison.Ordinal))
                {
                    // The one deliberate non-404: erasure is idempotent by design (an already-tombstoned
                    // user must never re-enqueue a shred), so it answers 202 and does nothing.
                    response.StatusCode.ShouldBe(HttpStatusCode.Accepted, route.Key);
                    factory.Jobs.Captured.ShouldBeEmpty("an already-erased user must not re-enqueue a shred");
                    continue;
                }

                response.StatusCode.ShouldBe(HttpStatusCode.NotFound, route.Key);
                await AssertSharedNotFoundAsync(response, route.Key);
            }

            // The token wrote nothing back — stated over EVERY table at once rather than a list of
            // counts, because a resurrection is only interesting if it is complete: an erased user's
            // JWT that re-created one preference row is as much a failure as one that re-created a
            // symptom. (`user_profile_enc` and `consent_records` legitimately SURVIVE the shred — the
            // first is ciphertext the deleted DEK already made permanently unreadable, the second is
            // GDPR Art. 7(1) consent proof — so "count == 0" would be the wrong claim there and
            // "unchanged" is the right one.)
            (await SnapshotAsync(userId)).ShouldBe(
                afterShred,
                "twenty-four requests on a still-valid JWT after crypto-shred, and the database is "
                + "exactly as the shred left it");

            // And the §F/OQ-1 headline separately, so a regression that made the snapshot trivially
            // equal (by, say, erasing nothing at all) cannot hide here.
            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(0);
            (await db.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId)).ShouldBe(0);
            (await db.Symptoms.IgnoreQueryFilters().CountAsync(s => s.UserId == userId)).ShouldBe(0);
            (await db.CyclePhaseOverrides.IgnoreQueryFilters().CountAsync(o => o.UserId == userId)).ShouldBe(0);
            (await db.CycleSettings.CountAsync(s => s.UserId == userId)).ShouldBe(0);
            (await db.UserDevices.CountAsync(d => d.UserId == userId)).ShouldBe(0);
            (await db.UserGoals.CountAsync(g => g.UserId == userId)).ShouldBe(0);
            (await db.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            (await db.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            (await db.BodyMetrics.IgnoreQueryFilters().CountAsync(m => m.UserId == userId)).ShouldBe(0);
            (await db.UserKeys.CountAsync(k => k.UserId == userId)).ShouldBe(0, "the DEK is gone: the surviving user_profile_enc row is unreadable for ever");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // ---------------------------------------------------------------- 8. the crypto boundary

    [Fact]
    public async Task Another_tenants_crypto_context_cannot_decrypt_a_stored_blob()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"iso-crypto-own-{Guid.NewGuid():N}@example.com");
            (intruderId, _) = await OnboardAndLoginAsync($"iso-crypto-int-{Guid.NewGuid():N}@example.com");

            var created = await Authed(ownerToken).PostAsJsonAsync(Routes.Symptoms, new
            {
                entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 7, notes = "dolor pélvico" } },
            });
            created.StatusCode.ShouldBe(HttpStatusCode.Created);
            var symptomId = (await created.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("items")[0].GetProperty("id").GetGuid();

            await using var db = TestFixtures.NewDb();
            var stored = await db.Symptoms.AsNoTracking().SingleAsync(s => s.Id == symptomId);
            stored.NotesEnc.ShouldNotBeNull();

            // The last line of defence, below every route check above: even a caller that somehow got
            // the ciphertext cannot read it, because the DEK is per user and AES-GCM authenticates.
            var contexts = new JobCryptoContextFactory(
                db, new VaultTransitKeyWrapper(TestFixtures.Vault()), new AesGcmFieldCipher());

            await using (var ownerContext = contexts.Create(ownerId))
                (await ownerContext.DecryptStringAsync(stored.NotesEnc!)).ShouldBe("dolor pélvico");

            await using var intruderContext = contexts.Create(intruderId);
            await Should.ThrowAsync<CryptographicException>(
                async () => await intruderContext.DecryptAsync(stored.NotesEnc!));
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ---------------------------------------------------------------- seeding

    /// <summary>The value <see cref="SeedTenantAsync"/> patches onto the owner's cycle settings.</summary>
    private const int SeededAvgCycleLengthDays = 41;

    /// <summary>
    /// Days after the anchor that <see cref="SeedTenantAsync"/> dates the owner's first phase correction
    /// on. Named because the day-read assertion has to aim at THIS day: the anchor itself carries the
    /// day log, the cycle event and the symptom but no override, so an override assertion pointed at
    /// the anchor asserts nothing.
    /// </summary>
    private const int SeededOverrideOffsetDays = 4;

    private sealed record SeededTenant(
        Guid UserId,
        string Token,
        DateOnly Anchor,
        Guid CycleEventId,
        Guid SymptomId,
        string Snapshot);

    /// <summary>
    /// Onboards a user and writes at least one row into every P4a table the phase's endpoints can
    /// write, then snapshots the lot. "Every table" is what makes
    /// <see cref="SeededTenant.Snapshot"/> a meaningful byte-unchanged baseline — a snapshot of a
    /// half-populated tenant would pass while whole resources went unguarded.
    /// </summary>
    private async Task<SeededTenant> SeedTenantAsync(string prefix)
    {
        var (userId, token) = await OnboardAndLoginAsync($"{prefix}-{Guid.NewGuid():N}@example.com");
        var authed = Authed(token);
        var anchor = Today.AddDays(-10);
        var pushToken = NewPushToken("fcm");

        (await authed.PostAsJsonAsync(Routes.OnboardingBaseline, new
        {
            dob = "1991-06-15",
            heightCm = 167,
            weightKg = 61.5,
            endoStatus = UserProfileEnc.EndoStatuses.Diagnosed,
            rasrmStage = 3,
            diagnosedOn = "2019-04",
        })).StatusCode.ShouldBe(HttpStatusCode.OK);

        (await authed.PostAsJsonAsync(Routes.OnboardingCycle, new
        {
            lastPeriodStart = anchor.ToString("yyyy-MM-dd"),
            avgCycleLengthDays = 28,
            avgPeriodLengthDays = 5,
            regularity = UserCycleSettings.RegularityValues.Regular,
        })).StatusCode.ShouldBe(HttpStatusCode.OK);

        (await authed.PostAsJsonAsync(Routes.OnboardingGoals, new
        {
            goals = new[] { UserGoal.Codes.ManageSymptoms, UserGoal.Codes.PlanFertility },
        })).StatusCode.ShouldBe(HttpStatusCode.OK);
        (await authed.PostAsJsonAsync(Routes.OnboardingHormones, new { chartedHormones = new[] { "lh", "fsh" } }))
            .StatusCode.ShouldBe(HttpStatusCode.OK);
        (await authed.PostAsJsonAsync(Routes.OnboardingNotifications, new
        {
            enabledCategories = new[] { "daily_checkin", "phase_shift" },
        })).StatusCode.ShouldBe(HttpStatusCode.OK);

        var cycleEvent = await authed.PostAsJsonAsync(Routes.CycleEvents, new
        {
            kind = CycleEvent.Kinds.Spotting,
            occurredOn = anchor.ToString("yyyy-MM-dd"),
            flowIntensity = 2,
            notes = "sangrado leve",
        });
        cycleEvent.StatusCode.ShouldBe(HttpStatusCode.OK);
        var cycleEventId = (await cycleEvent.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

        (await authed.PostAsJsonAsync(CycleDayUrl(anchor), new { pain = 6, mood = 2, notes = "día difícil" }))
            .StatusCode.ShouldBe(HttpStatusCode.OK);

        var symptoms = await authed.PostAsJsonAsync(Routes.Symptoms, new
        {
            entries = new[]
            {
                new
                {
                    symptomCode = Symptom.Codes.Pain,
                    intensity = 8,
                    region = Symptom.Regions.Pelvis,
                    side = Symptom.Sides.Back,
                    notes = "dolor punzante",
                    occurredAt = Midday(anchor),
                },
            },
        });
        symptoms.StatusCode.ShouldBe(HttpStatusCode.Created);
        var symptomId = (await symptoms.Content.ReadFromJsonAsync<JsonElement>())
            .GetProperty("items")[0].GetProperty("id").GetGuid();

        // TWO corrections on the one cycle, in a single request because this endpoint REPLACES the set.
        // Two is what makes the write sweep able to exercise both halves of that replacement across the
        // tenant boundary: an intruder's request naming `menstrual/end` and omitting `ovulatory/start`
        // would, with the UserId predicate gone, overwrite the first and retract the second.
        (await authed.PostAsJsonAsync(Routes.CyclePhaseOverride, new
        {
            cycleStartOn = anchor.ToString("yyyy-MM-dd"),
            boundaries = new[]
            {
                new
                {
                    phase = CyclePhaseOverride.Phases.Menstrual,
                    boundary = CyclePhaseOverride.Boundaries.End,
                    occurredOn = anchor.AddDays(SeededOverrideOffsetDays).ToString("yyyy-MM-dd"),
                },
                new
                {
                    phase = CyclePhaseOverride.Phases.Ovulatory,
                    boundary = CyclePhaseOverride.Boundaries.Start,
                    occurredOn = anchor.AddDays(SeededOverrideOffsetDays + 3).ToString("yyyy-MM-dd"),
                },
            },
        })).StatusCode.ShouldBe(HttpStatusCode.OK);

        (await authed.PatchAsJsonAsync(Routes.SettingsCycle, new
        {
            avgCycleLengthDays = SeededAvgCycleLengthDays,
            trackingPaused = true,
            pauseReason = UserCycleSettings.PauseReasons.Other,
        })).StatusCode.ShouldBe(HttpStatusCode.OK);

        (await authed.PostAsJsonAsync(Routes.MeDevices, new { platform = UserDevice.Platforms.Ios, pushToken }))
            .StatusCode.ShouldBe(HttpStatusCode.OK);

        (await authed.PostAsJsonAsync(Routes.OnboardingComplete, new { })).StatusCode.ShouldBe(HttpStatusCode.OK);

        return new SeededTenant(
            userId, token, anchor, cycleEventId, symptomId, await SnapshotAsync(userId));
    }

    // ---------------------------------------------------------------- the byte-unchanged snapshot

    private static readonly JsonSerializerOptions SnapshotJson = new() { WriteIndented = false };

    /// <summary>
    /// Every row this user owns, in every table, serialised field by field — <c>byte[]</c> columns
    /// included, as base64, so a re-encryption with a fresh nonce shows up as a difference. Rows are
    /// ordered by their own serialisation so the string is stable across runs.
    ///
    /// <para>The entity types carry no navigation properties, so serialising them wholesale is safe and
    /// — unlike a hand-written projection — automatically picks up a column added later.
    /// <see cref="Snapshot_covers_every_table_that_belongs_to_a_user"/> guards the other axis: that no
    /// user-owned TABLE is missing from the set below.</para>
    /// </summary>
    private static async Task<string> SnapshotAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        var tables = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["users"] = Rows(await db.Users.IgnoreQueryFilters().AsNoTracking().Where(u => u.Id == userId).ToListAsync()),
            ["user_keys"] = Rows(await db.UserKeys.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_profile_enc"] = Rows(await db.UserProfiles.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["consent_records"] = Rows(await db.ConsentRecords.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_devices"] = Rows(await db.UserDevices.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["cycle_events"] = Rows(await db.CycleEvents.IgnoreQueryFilters().AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["cycle_day_logs"] = Rows(await db.CycleDayLogs.IgnoreQueryFilters().AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["symptoms"] = Rows(await db.Symptoms.IgnoreQueryFilters().AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["cycle_phase_overrides"] = Rows(await db.CyclePhaseOverrides.IgnoreQueryFilters().AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_cycle_settings"] = Rows(await db.CycleSettings.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["cycle_tracking_pause_spans"] = Rows(await db.CycleTrackingPauseSpans.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_goals"] = Rows(await db.UserGoals.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_hormone_prefs"] = Rows(await db.UserHormonePrefs.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_notification_prefs"] = Rows(await db.UserNotificationPrefs.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["body_metrics"] = Rows(await db.BodyMetrics.IgnoreQueryFilters().AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
            ["user_insight_snapshot"] = Rows(await db.UserInsightSnapshots.AsNoTracking().Where(x => x.UserId == userId).ToListAsync()),
        };

        return string.Join("\n", tables.Select(t => $"{t.Key}: {t.Value}"));
    }

    private static string Rows<T>(IEnumerable<T> rows) =>
        !rows.Any()
            ? "[]"
            : string.Join(" ", rows
                .Select(r => JsonSerializer.Serialize(r, SnapshotJson))
                .OrderBy(s => s, StringComparer.Ordinal));

    /// <summary>
    /// The snapshot above is only a "byte-unchanged" guarantee if it covers every table a user owns.
    /// This reads the EF model rather than a list, so a table added in a later phase fails here instead
    /// of quietly falling outside the baseline the write sweep compares against.
    /// </summary>
    [Fact]
    public async Task Snapshot_covers_every_table_that_belongs_to_a_user()
    {
        await using var db = TestFixtures.NewDb();

        var userOwned = db.Model.GetEntityTypes()
            .Where(e => e.FindProperty("UserId") is not null || e.ClrType == typeof(User))
            .Select(e => e.GetTableName()!)
            .ToHashSet(StringComparer.Ordinal);

        // admin_audit_log is keyed by a string EntityId, not a UserId, and holds operational records
        // rather than tenant data; GdprErasureBaselineTests owns it.
        userOwned.Remove("admin_audit_log");

        var snapshotted = (await SnapshotAsync(Guid.NewGuid()))
            .Split('\n')
            .Select(line => line[..line.IndexOf(':', StringComparison.Ordinal)])
            .ToHashSet(StringComparer.Ordinal);

        snapshotted.ShouldBe(userOwned, ignoreOrder: true,
            "SnapshotAsync is the baseline the write sweep compares against. A user-owned table missing "
            + "from it would let another tenant's write go unnoticed there forever.");
    }

    // ---------------------------------------------------------------- helpers

    /// <summary>
    /// A comparable fingerprint of a response: status, media type and every JSON member except the ones
    /// that legitimately differ per request. <c>traceId</c> is always dropped — ASP.NET stamps it on
    /// every ProblemDetails body, and it is the only thing that would make two otherwise identical
    /// answers compare unequal.
    /// </summary>
    private static async Task<string> FingerprintAsync(HttpResponseMessage response, params string[] ignore)
    {
        var raw = await response.Content.ReadAsStringAsync();
        var dropped = ignore.Append("traceId").ToHashSet(StringComparer.Ordinal);
        using var document = JsonDocument.Parse(raw);
        var members = document.RootElement.EnumerateObject()
            .Where(p => !dropped.Contains(p.Name))
            .OrderBy(p => p.Name, StringComparer.Ordinal)
            .Select(p => $"{p.Name}={p.Value.GetRawText()}");
        return $"{(int)response.StatusCode} {response.Content.Headers.ContentType?.MediaType} "
               + string.Join("|", members);
    }

    private static async Task AssertSharedNotFoundAsync(HttpResponseMessage response, string what)
    {
        response.StatusCode.ShouldBe(HttpStatusCode.NotFound, $"{what} must answer 404, never 403");
        response.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json", what);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("title").GetString().ShouldBe(NotFoundProblemTitle, what);
        body.GetProperty("status").GetInt32().ShouldBe(404, what);
    }

    /// <summary>A token shaped like the real thing: long, opaque, and unique per call.</summary>
    private static string NewPushToken(string prefix) => $"{prefix}:{Guid.NewGuid():N}{Guid.NewGuid():N}";

    /// <summary>Midday on a user-local day, as the wire format <c>occurredAt</c> takes.</summary>
    private static string Midday(DateOnly day) =>
        new DateTimeOffset(day.ToDateTime(new TimeOnly(12, 0)), TimeSpan.Zero).ToString("O");

    private HttpClient Authed(string token)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private async Task<(Guid userId, string token)> OnboardAndLoginAsync(string email)
    {
        var client = factory.CreateClient();
        var start = await client.PostAsJsonAsync("/onboarding/start", new
        {
            email,
            password = Password,
            displayName = "Isolation Tester",
            locale = "es-ES",
            timezone = "Europe/Madrid",
            policyVersion = "v1-test",
        });
        start.StatusCode.ShouldBe(HttpStatusCode.OK);
        var userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();
        return (userId, await TestFixtures.GetUserTokenAsync(email, Password));
    }

    /// <summary>
    /// Best-effort removal of the Keycloak identity, for the one test that calls <c>DELETE /me</c> and
    /// therefore leaves a DISABLED Keycloak account behind. Failures are ignored: this is hygiene, not a
    /// claim under test.
    /// </summary>
    private static async Task TryDeleteKeycloakUserAsync(Guid userId)
    {
        try
        {
            using var http = new HttpClient();
            var adminToken = await TestFixtures.GetServiceAccountTokenAsync();
            using var request = new HttpRequestMessage(
                HttpMethod.Delete, $"http://localhost:8080/admin/realms/lumen/users/{userId}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", adminToken);
            await http.SendAsync(request);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[TenantIsolationLiveTests cleanup] {ex.Message}");
        }
    }

    /// <summary>
    /// FK order, and every P4a table — the same list <see cref="SnapshotAsync"/> reads. §G4's "no new
    /// tables from T8 onward" is what keeps the two in step; the dev database already carries orphan
    /// <c>users</c> rows from earlier runs and this file must not add to them.
    /// </summary>
    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.CycleEvents.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.CycleDayLogs.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.Symptoms.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.CycleTrackingPauseSpans.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.CycleSettings.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserGoals.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserHormonePrefs.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserNotificationPrefs.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.BodyMetrics.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserInsightSnapshots.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(x => x.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
