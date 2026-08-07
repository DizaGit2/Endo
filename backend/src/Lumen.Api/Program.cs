using System.Net;
using System.Net.Sockets;
using Hangfire;
using Hangfire.PostgreSql;
using Lumen.Api;
using Lumen.Api.Auth;
using Lumen.Api.Cycle;
using Lumen.Api.Hangfire;
using Lumen.Api.Onboarding;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Auth;
using Lumen.Application.Crypto;
using Lumen.Application.Time;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Auth;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Lumen.Infrastructure.Time;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using System.Threading.RateLimiting;
using Lumen.Infrastructure.Logging;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((context, config) => config
    .MinimumLevel.Information()
    // Microsoft.AspNetCore.Hosting.Diagnostics logs the RAW request path three times per request at
    // Information ("Request starting/finished HTTP/1.1 GET http://host/cycle/day/2026-08-06 …", plus
    // the unhandled-request line). "/cycle/day/2026-08-06" asserts that this user logged something on
    // that day — a health-adjacent fact §F bars from a log line — and no enricher can catch it
    // reliably, because the path arrives inside a rendered URL under generic property names ({Path},
    // {Url}). Silencing that category below Warning is also the canonical Serilog.AspNetCore setup:
    // UseSerilogRequestLogging (below) exists to REPLACE those lines with one summary event, and this
    // app's summary logs the route template instead of the path.
    //
    // The override is scoped to ...Hosting, NOT the whole "Microsoft.AspNetCore" tree, and the
    // difference matters: the broader form also silenced every authentication and authorization
    // diagnostic — including the only output the token perimeter guard below (JwtBearerEvents
    // .OnTokenValidated → context.Fail) ever produces — for zero additional §F benefit. Measured on
    // the live stack: BOTH forms leave zero occurrences of the date in the log; only the narrow one
    // keeps the auth-failure lines. Microsoft.IdentityModel already replaces PII in those messages
    // with "[PII of type '…' is hidden…]". Pinned by RequestLoggingPipelineTests
    // .The_level_override_silences_hosting_diagnostics_only_not_authentication_failures.
    // Microsoft.Hosting.Lifetime is a separate category, so "Now listening on…" and the shutdown
    // lines still appear.
    .MinimumLevel.Override("Microsoft.AspNetCore.Hosting", Serilog.Events.LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.With(new PiiRedactionEnricher())
    .WriteTo.Console());

// --- options ---
var vaultOptions = builder.Configuration.GetSection(VaultOptions.SectionName).Get<VaultOptions>() ?? new VaultOptions();
var keycloakOptions = builder.Configuration.GetSection(KeycloakOptions.SectionName).Get<KeycloakOptions>() ?? new KeycloakOptions();
builder.Services.AddSingleton(vaultOptions);
builder.Services.AddSingleton(keycloakOptions);
builder.Services.AddSingleton(TimeProvider.System);

// --- persistence ---
// Fail closed: outside Development, every security-sensitive setting must be explicit — this runs
// BEFORE the hardcoded fallback below, so a non-Development config that simply omits the
// connection string throws here instead of silently picking up the dev default.
StartupGuards.EnsureNonDevelopmentSecrets(
    builder.Environment.IsDevelopment(), builder.Configuration.GetConnectionString("Lumen"), vaultOptions, keycloakOptions);

// Reachable only in Development: StartupGuards above already rejected a missing string anywhere else.
var connectionString = builder.Configuration.GetConnectionString("Lumen")
    ?? "Host=localhost;Port=55432;Database=lumen;Username=postgres;Password=postgres";
builder.Services.AddDbContext<LumenDbContext>(o => o.UseNpgsql(connectionString));

// --- background jobs (Hangfire) ---
// CryptoShredJob (GDPR erasure, §F) ships since P2; this registers the runtime and secures the dashboard.
builder.Services.AddHangfire(cfg => cfg
    .UsePostgreSqlStorage(options => options.UseNpgsqlConnection(connectionString)));
// The background server is disabled in tests (Hangfire:EnableServer=false). This matters beyond
// determinism: AddHangfireServer resolves JobStorage at startup, which constructs the Postgres-backed
// storage and connects eagerly — so with the server on and Postgres unreachable (the no-docker
// openapi-contract job), host startup/disposal stalls. Hangfire itself stays registered, so
// IBackgroundJobClient (injected by DELETE /me) still resolves.
if (builder.Configuration.GetValue("Hangfire:EnableServer", true))
    builder.Services.AddHangfireServer();
// Resolvable from a job scope by Hangfire's activator (e.g. the GDPR crypto-shred erasure job).
builder.Services.AddScoped<CryptoShredJob>();

// --- crypto ---
builder.Services.AddSingleton<IFieldCipher, AesGcmFieldCipher>();
builder.Services.AddSingleton<IKeyWrapper, VaultTransitKeyWrapper>();
builder.Services.AddHttpClient<IEmailHasher, VaultTransitEmailHasher>();
builder.Services.AddScoped<IUserCryptoContext, UserCryptoContext>();
builder.Services.AddScoped<IJobCryptoContextFactory, JobCryptoContextFactory>();

// --- identity ---
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUserAccessor, CurrentUserAccessor>();
builder.Services.AddHttpClient<IKeycloakAdmin, KeycloakAdminClient>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = keycloakOptions.Authority;
        options.RequireHttpsMetadata = !builder.Environment.IsDevelopment(); // plaintext metadata only in dev
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            // In Development the issuer is NOT pinned: native/emulator clients reach Keycloak
            // on a different host (e.g. the Android emulator's 10.0.2.2:8080) than the API
            // does over the compose network, so the token's `iss` legitimately differs from
            // this Authority. The token SIGNATURE is still validated against Keycloak's JWKS.
            // Production pins the issuer (single public Caddy host). TODO(P11): with a fixed
            // prod hostname this is always true.
            ValidateIssuer = !builder.Environment.IsDevelopment(),
            ValidIssuer = keycloakOptions.Authority,
            ValidateAudience = true,
            ValidAudiences = [keycloakOptions.Audience],
            ValidateLifetime = true,
            NameClaimType = "sub",
            ValidAlgorithms = ["RS256"],
            ClockSkew = TimeSpan.FromSeconds(30),
        };
        // Permanent guard (not interim — the audience mapper landed in T1): rejects service-account
        // and foreign-client tokens. aud=lumen-api alone can't distinguish them from a real end-user
        // token, since the mapper also lives on the api client, so its own service-account tokens
        // carry that same audience — azp + preferred_username is what actually tells them apart.
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = context =>
            {
                var azp = context.Principal?.FindFirst("azp")?.Value;
                var preferredUsername = context.Principal?.FindFirst("preferred_username")?.Value;
                var isServiceAccount = preferredUsername?.StartsWith("service-account-", StringComparison.Ordinal) ?? false;
                // Only end-user tokens from a Lumen client; reject service-account (client_credentials) tokens.
                if (azp is not ("mobile" or "api") || isServiceAccount)
                    context.Fail("Token is not an end-user token from an allowed Lumen client.");
                return Task.CompletedTask;
            },
        };
    });
builder.Services.AddAuthorization();

// --- time (D-12) ---
// The single authority on the user-local day. The resolver is stateless apart from its timezone
// cache, so it is a singleton; the context holds one memoised users read, so it is per-request.
builder.Services.AddSingleton<IUserDayResolver, UserDayResolver>();
builder.Services.AddScoped<IUserDayContext, UserDayContext>();

// --- onboarding ---
// Extracted from the /onboarding/start handler (P3c-T2) so validation/compensation are unit-testable.
builder.Services.AddScoped<OnboardingService>();

// --- cycle (P4a-T9/T10) ---
// Scoped: both consume the request-scoped day context (D-12) and crypto context (the note cipher).
builder.Services.AddScoped<CycleService>();
// Serves POST /cycle/day/{date}, POST /checkin/quick and GET /cycle/day/{date}. The check-in is a
// §C.3 route but writes only cycle_day_logs, so it shares this service rather than racing a second
// one on the same row.
builder.Services.AddScoped<CycleDayService>();

// Global per-user (else per-IP) rate limit — protects costly endpoints like POST /onboarding/start.
var permitPerMinute = builder.Configuration.GetValue<int?>("RateLimit:PermitPerMinute") ?? 60;
// Named per-IP policy layered on top of the global limiter, just for the anonymous onboarding
// endpoint (always-anonymous, so partitioned purely by IP — there is no "sub" to key on).
var onboardingStartPermitPerMinute = builder.Configuration.GetValue<int?>("RateLimit:OnboardingStartPermitPerMinute") ?? 5;
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
    {
        var partitionKey = httpContext.User.FindFirst("sub")?.Value
            ?? httpContext.Connection.RemoteIpAddress?.ToString()
            ?? "anonymous";
        return RateLimitPartition.GetFixedWindowLimiter(partitionKey, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = permitPerMinute,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
        });
    });
    options.AddPolicy("onboarding-start", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = onboardingStartPermitPerMinute,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
        }));
});

builder.Services.AddExceptionHandler<ProblemExceptionHandler>();
builder.Services.AddProblemDetails();
// Minimal-API binding failures must THROW so ProblemExceptionHandler can turn them into the one P4a
// 400 body (T3). Left alone the behaviour differs per environment and is wrong in both: Development
// defaults this to true (the throw became a generic 500), Production leaves it false (a bodyless 400
// the client renders as an empty error). Explicit here so every environment answers identically.
builder.Services.Configure<RouteHandlerOptions>(o => o.ThrowOnBadRequest = true);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// OUTERMOST on purpose (T3 review): request logging must observe the response the client actually
// received. Nested inside UseExceptionHandler it saw the in-flight exception instead, and Serilog's
// exception path hard-codes status 500 — so every handled failure, including a malformed body that
// the client was correctly answered with a 400, was written as an Error-level "responded 500" with a
// stack trace. That is an operational alarm for user input, and a binding-failure message quotes the
// value that failed to bind, which here is health data (§F bars that from a log line too).
app.UseSerilogRequestLogging(options =>
{
    // Log the ROUTE TEMPLATE, never the raw path (§F). "/cycle/day/2026-08-06" asserts that this
    // user logged something on that day — a health-adjacent fact — while "/cycle/day/{date}" carries
    // the same operational signal with none of the datum. Serilog's middleware attaches RequestPath
    // as a property unconditionally, whatever this template says, so PiiRedactionEnricher redacts
    // that name outright and this line is what keeps the log line useful. §F:303's "never log request
    // bodies for cycle/symptoms/day-logs" is unchanged and still holds.
    options.MessageTemplate =
        "HTTP {RequestMethod} {RouteTemplate} responded {StatusCode} in {Elapsed:0.0000} ms";
    options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        // Unmatched requests (404s, probes, scanners) have no endpoint and therefore no template.
        // "(unrouted)" is deliberately a constant rather than a fallback to the path.
        diagnosticContext.Set(
            "RouteTemplate",
            (httpContext.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText ?? "(unrouted)");
});

app.UseExceptionHandler(); // clean ProblemDetails on unhandled errors; no stack traces (with env=Production)

// Trust X-Forwarded-For only from private networks (the Caddy reverse proxy) so the rate limiter
// partitions on the real client IP rather than the proxy IP. P11 tightens KnownProxies to the exact proxy.
var forwardedHeaders = new ForwardedHeadersOptions { ForwardedHeaders = ForwardedHeaders.XForwardedFor, ForwardLimit = 2 };
forwardedHeaders.KnownIPNetworks.Clear();
forwardedHeaders.KnownProxies.Clear();
forwardedHeaders.KnownIPNetworks.Add(System.Net.IPNetwork.Parse("10.0.0.0/8"));
forwardedHeaders.KnownIPNetworks.Add(System.Net.IPNetwork.Parse("172.16.0.0/12"));
forwardedHeaders.KnownIPNetworks.Add(System.Net.IPNetwork.Parse("192.168.0.0/16"));
app.UseForwardedHeaders(forwardedHeaders);

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

// --- Hangfire dashboard (lumen-admin only) ---
// Bearer-gated (deny-by-default via HangfireDashboardAuthorizationFilter); intended to be reached via an
// admin reverse-proxy that injects the token. Cookie/OIDC dashboard auth is deferred to a later phase.
app.MapHangfireDashboard("/hangfire", new DashboardOptions
{
    Authorization = [new HangfireDashboardAuthorizationFilter()],
});

// --- health (P0a) ---
app.MapGet("/health", () => Results.Ok(new { status = "healthy" })).AllowAnonymous();
app.MapGet("/health/ready", async (IConfiguration cfg) =>
{
    var deps = new[]
    {
        ("postgres", cfg["POSTGRES_HOST"] ?? "postgres", ParsePort(cfg["POSTGRES_PORT"], 5432)),
        ("vault", cfg["VAULT_HOST"] ?? "vault", ParsePort(cfg["VAULT_PORT"], 8200)),
    };
    var results = new Dictionary<string, bool>();
    foreach (var (name, host, port) in deps)
        results[name] = await CanConnectAsync(host, port, TimeSpan.FromSeconds(2));
    return results.Values.All(ok => ok)
        ? Results.Ok(new { status = "ready", dependencies = results })
        : Results.Json(new { status = "not_ready", dependencies = results }, statusCode: 503);
}).AllowAnonymous();

// --- spine endpoints (P1) ---

// Onboarding routes live in Lumen.Api/Onboarding/OnboardingEndpoints.cs (T4).
app.MapOnboardingEndpoints();

// --- cycle (P4a) ---
// Cycle routes live in Lumen.Api/Cycle/CycleEndpoints.cs (T9).
app.MapCycleEndpoints();

app.MapGet("/me", async (
    ICurrentUserAccessor current,
    LumenDbContext db,
    IUserCryptoContext crypto,
    CancellationToken ct) =>
{
    var userId = current.UserId;
    // The query filter excludes soft-deleted users, so a crypto-shredded account's still-valid JWT
    // lands here — and gets the phase's ONE 404 body (T3/T4), never a bodyless Results.NotFound().
    var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId, ct);
    if (user is null) return NotFoundProblem.Result();

    var profile = await db.UserProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.UserId == userId, ct);
    var displayName = profile?.DisplayNameEnc is { } enc ? await crypto.DecryptStringAsync(enc, ct) : null;

    return Results.Ok(new MeResponse(userId, displayName, user.Locale, user.Timezone, user.OnboardingCompletedAt is not null));
})
.RequireAuthorization()
.Produces<MeResponse>(StatusCodes.Status200OK)
.ProducesProblem(StatusCodes.Status401Unauthorized)
.ProducesProblem(StatusCodes.Status404NotFound);

app.MapDelete("/me", async (
    ICurrentUserAccessor current,
    LumenDbContext db,
    IBackgroundJobClient backgroundJobs,
    IKeycloakAdmin keycloak,
    CancellationToken ct) =>
{
    var userId = current.UserId;

    // Idempotent guard: never re-enqueue the shred for an already-tombstoned (or missing) user.
    var user = await db.Users.IgnoreQueryFilters().FirstOrDefaultAsync(u => u.Id == userId, ct);
    if (user is null)
        return TypedResults.Accepted((string?)null); // nothing to disable — no Keycloak identity to act on

    if (user.DeletedAt is not null)
    {
        // Self-heal: a prior DELETE /me may have shredded (tombstoned) the user but had its
        // Keycloak disable fail (5xx), leaving the account still login-enabled. Re-attempt the
        // disable on retry — it is idempotent (204/404 no-op) — so no enqueue, just remediation.
        await keycloak.DisableUserAsync(userId, ct);
        return TypedResults.Accepted((string?)null);
    }

    // §F order: enqueue shred job, then disable in Keycloak, then 202.
    backgroundJobs.Enqueue<CryptoShredJob>(j => j.ExecuteAsync(userId, CancellationToken.None));
    await keycloak.DisableUserAsync(userId, ct);
    return TypedResults.Accepted((string?)null);
})
.RequireAuthorization()
.ProducesProblem(StatusCodes.Status401Unauthorized);

app.MapPatch("/me", async (
    UpdateMeRequest request,
    ICurrentUserAccessor current,
    LumenDbContext db,
    IUserCryptoContext crypto,
    TimeProvider clock,
    CancellationToken ct) =>
{
    var userId = current.UserId;
    var now = clock.GetUtcNow();

    // Validate-then-act (T3): every field error is collected BEFORE the first write, so a request
    // that is rejected has changed nothing — no half-saved profile, and the user fixes all of it in
    // one round trip. Absent (null/blank) means "leave it alone"; it is never a reset to the default.
    var problems = new ValidationProblemBuilder();
    var timezone = Blank(request.Timezone) ? null : request.Timezone;
    var locale = Blank(request.Locale) ? null : request.Locale;

    // D-12: users.timezone is the sole input to every "today" this API computes, and UserDayResolver
    // logs a fallback warning on every request that cannot resolve it — so an unvalidated value here
    // would be user-controlled log amplification on top of mis-filed day-keyed data.
    if (timezone is not null && !TimeZoneInfo.TryFindSystemTimeZoneById(timezone, out _))
        problems.Add("timezone", ValidationMessages.NotAnIanaTimeZone);

    if (locale is not null)
    {
        if (locale.Length > 35) // the users.locale column
            problems.Add("locale", ValidationMessages.MaxLength(35));
        else if (!IsWellFormedLocale(locale))
            problems.Add("locale", MeValidationMessages.NotABcp47Locale);
    }

    if (problems.HasErrors) return problems.Build();

    // Soft-deleted users are filtered out: an erased account's still-valid JWT gets the shared 404,
    // the same answer GET /me gives it.
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct);
    if (user is null) return NotFoundProblem.Result();

    if (timezone is not null) user.Timezone = timezone;
    if (locale is not null) user.Locale = locale;
    if (timezone is not null || locale is not null) user.UpdatedAt = now;

    var profile = await db.UserProfiles.FirstOrDefaultAsync(p => p.UserId == userId, ct);
    if (profile is null)
    {
        profile = new UserProfileEnc { UserId = userId, CreatedAt = now, UpdatedAt = now };
        db.UserProfiles.Add(profile);
    }
    if (request.DisplayName is not null)
        profile.DisplayNameEnc = await crypto.EncryptStringAsync(request.DisplayName, ct);
    profile.UpdatedAt = now;
    await db.SaveChangesAsync(ct);
    return Results.NoContent();
})
.RequireAuthorization()
.Produces(StatusCodes.Status204NoContent)
.ProducesValidationProblem()
.ProducesProblem(StatusCodes.Status401Unauthorized)
.ProducesProblem(StatusCodes.Status404NotFound);

app.Run();

static int ParsePort(string? value, int fallback) => int.TryParse(value, out var port) ? port : fallback;

static bool Blank(string? value) => string.IsNullOrWhiteSpace(value);

/// <summary>
/// Structural well-formedness check for a BCP-47 language tag, delegated to the BCL's own culture-name
/// rules rather than a hand-rolled pattern (§G11 — P4a invents no values of its own).
/// <c>predefinedOnly: false</c> keeps it permissive: any syntactically valid tag is accepted even if
/// this host's ICU data does not know that exact locale, because rejecting a real user's locale is
/// worse than storing one nobody formats against. Only genuine garbage ("not a locale!") is refused.
/// </summary>
static bool IsWellFormedLocale(string locale)
{
    try
    {
        _ = System.Globalization.CultureInfo.GetCultureInfo(locale, predefinedOnly: false);
        return true;
    }
    catch (System.Globalization.CultureNotFoundException)
    {
        return false;
    }
}

static async Task<bool> CanConnectAsync(string host, int port, TimeSpan timeout)
{
    try
    {
        using var client = new TcpClient();
        var connect = client.ConnectAsync(host, port);
        var completed = await Task.WhenAny(connect, Task.Delay(timeout));
        return completed == connect && client.Connected;
    }
    catch
    {
        return false;
    }
}

// DTOs
// `OnboardingStartRequest` moved to Onboarding/OnboardingContracts.cs (T4) — still in the global
// namespace, so its OpenAPI schema name is unchanged.
public record MeResponse(Guid Id, string? DisplayName, string Locale, string Timezone, bool OnboardingCompleted);

/// <summary>
/// Settings patch. Every member is optional and <c>null</c> means "leave unchanged" — this is a PATCH,
/// so an absent field is not a request to reset it.
/// </summary>
/// <param name="Timezone">IANA zone id (e.g. <c>Europe/Madrid</c>). D-12 resolves the user's local day from it.</param>
/// <param name="Locale">BCP-47 tag, ≤ 35 chars per the <c>users.locale</c> column (D-05).</param>
public record UpdateMeRequest(string? DisplayName, string? Locale, string? Timezone);

/// <summary>
/// Messages owned by <c>/me</c> alone (§G12: only genuinely cross-cutting strings belong on
/// <see cref="ValidationMessages"/>). Wire strings — asserted verbatim in <c>MePatchLiveTests</c>.
/// </summary>
public static class MeValidationMessages
{
    /// <summary>The string is not a syntactically valid BCP-47 language tag (e.g. <c>es-ES</c>).</summary>
    public const string NotABcp47Locale = "value is not a recognized BCP-47 locale";
}

// Exposed for WebApplicationFactory in integration tests.
public partial class Program;
