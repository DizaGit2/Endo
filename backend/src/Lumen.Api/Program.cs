using System.Net;
using System.Net.Sockets;
using Hangfire;
using Hangfire.PostgreSql;
using Lumen.Api;
using Lumen.Api.Auth;
using Lumen.Api.Hangfire;
using Lumen.Api.Onboarding;
using Lumen.Application.Auth;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Auth;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
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
var connectionString = builder.Configuration.GetConnectionString("Lumen")
    ?? "Host=localhost;Port=55432;Database=lumen;Username=postgres;Password=postgres";
builder.Services.AddDbContext<LumenDbContext>(o => o.UseNpgsql(connectionString));

// --- background jobs (Hangfire) ---
// CryptoShredJob (GDPR erasure, §F) ships since P2; this registers the runtime and secures the dashboard.
builder.Services.AddHangfire(cfg => cfg
    .UsePostgreSqlStorage(options => options.UseNpgsqlConnection(connectionString)));
// The background server is disabled in integration tests (Hangfire:EnableServer=false) so enqueued
// jobs don't execute non-deterministically; job logic is tested by invoking jobs directly.
if (builder.Configuration.GetValue("Hangfire:EnableServer", true))
    builder.Services.AddHangfireServer();
// Resolvable from a job scope by Hangfire's activator (e.g. the GDPR crypto-shred erasure job).
builder.Services.AddScoped<CryptoShredJob>();

// Fail closed: never start outside Development with the dev sentinel secrets (prod hardening is P11).
if (!builder.Environment.IsDevelopment() &&
    (vaultOptions.Token is "root" or "" ||
     keycloakOptions.AdminClientSecret is "dev-api-secret" or "" ||
     connectionString.Contains("Password=postgres", StringComparison.Ordinal)))
{
    throw new InvalidOperationException(
        "Refusing to start outside Development with dev sentinel secrets. Configure real Vault/Keycloak/DB secrets.");
}

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

// --- onboarding ---
// Extracted from the /onboarding/start handler (P3c-T2) so validation/compensation are unit-testable.
builder.Services.AddScoped<OnboardingService>();

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
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

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

app.UseSerilogRequestLogging();
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

// Creates the Keycloak user, provisions the Vault-wrapped DEK, writes the encrypted profile + consent.
app.MapPost("/onboarding/start", async (
    OnboardingStartRequest request,
    OnboardingService onboarding,
    CancellationToken ct) =>
{
    var result = await onboarding.StartAsync(request, ct);
    return result switch
    {
        OnboardingStartResult.Success success => Results.Ok(new { userId = success.UserId }),
        OnboardingStartResult.Invalid invalid => Results.BadRequest(new { error = invalid.Error }),
        _ => throw new System.Diagnostics.UnreachableException($"Unhandled {nameof(OnboardingStartResult)}: {result.GetType()}"),
    };
})
.AllowAnonymous()
.RequireRateLimiting("onboarding-start")
.Produces<object>(StatusCodes.Status200OK)
.ProducesProblem(StatusCodes.Status400BadRequest);

app.MapGet("/me", async (
    ICurrentUserAccessor current,
    LumenDbContext db,
    IUserCryptoContext crypto,
    CancellationToken ct) =>
{
    var userId = current.UserId;
    var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId, ct);
    if (user is null) return Results.NotFound();

    var profile = await db.UserProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.UserId == userId, ct);
    var displayName = profile?.DisplayNameEnc is { } enc ? await crypto.DecryptStringAsync(enc, ct) : null;

    return Results.Ok(new MeResponse(userId, displayName, user.Locale, user.Timezone, user.OnboardingCompletedAt is not null));
})
.RequireAuthorization()
.Produces<MeResponse>(StatusCodes.Status200OK)
.ProducesProblem(StatusCodes.Status401Unauthorized);

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
.ProducesProblem(StatusCodes.Status401Unauthorized);

app.Run();

static int ParsePort(string? value, int fallback) => int.TryParse(value, out var port) ? port : fallback;

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
public record OnboardingStartRequest(string Email, string Password, string? DisplayName, string? Locale, string? Timezone, string? PolicyVersion);
public record MeResponse(Guid Id, string? DisplayName, string Locale, string Timezone, bool OnboardingCompleted);
public record UpdateMeRequest(string? DisplayName);

// Exposed for WebApplicationFactory in integration tests.
public partial class Program;
