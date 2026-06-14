using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Hangfire;
using Hangfire.PostgreSql;
using Lumen.Api;
using Lumen.Api.Auth;
using Lumen.Api.Hangfire;
using Lumen.Application.Auth;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Auth;
using Lumen.Infrastructure.Crypto;
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
// Job classes land in later tasks; this only registers the runtime and secures the dashboard.
builder.Services.AddHangfire(cfg => cfg
    .UsePostgreSqlStorage(options => options.UseNpgsqlConnection(connectionString)));
// The background server is disabled in integration tests (Hangfire:EnableServer=false) so enqueued
// jobs don't execute non-deterministically; job logic is tested by invoking jobs directly.
if (builder.Configuration.GetValue("Hangfire:EnableServer", true))
    builder.Services.AddHangfireServer();

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
builder.Services.AddScoped<IDekProvisioner, DekProvisioner>();
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
            ValidateIssuer = true,
            ValidIssuer = keycloakOptions.Authority,
            ValidateAudience = false, // TODO(P11): add a Keycloak audience mapper (aud=lumen-api), then validate
            ValidateLifetime = true,
            NameClaimType = "sub",
            ValidAlgorithms = ["RS256"],
            ClockSkew = TimeSpan.FromSeconds(30),
        };
        // Interim token-confusion guard until the audience mapper lands: only realm clients we issue.
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

// Global per-user (else per-IP) rate limit — protects costly endpoints like POST /onboarding/start.
var permitPerMinute = builder.Configuration.GetValue<int?>("RateLimit:PermitPerMinute") ?? 60;
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
app.UseSwagger();
app.UseSwaggerUI();
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

// --- Hangfire dashboard (lumen-admin only) ---
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
    LumenDbContext db,
    IKeycloakAdmin keycloak,
    IKeyWrapper keyWrapper,
    IFieldCipher cipher,
    VaultOptions vaultOptions,
    TimeProvider clock,
    CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
        return Results.BadRequest(new { error = "email and password are required" });

    // One canonical email form used for BOTH Keycloak (username/email) and the lookup hash.
    var email = request.Email.Trim().ToLowerInvariant();
    if (!System.Net.Mail.MailAddress.TryCreate(email, out var parsed) || parsed.Address != email)
        return Results.BadRequest(new { error = "invalid email format" });
    if (request.Password.Length is < 12 or > 128) // D-01 minimum; defense-in-depth with the realm policy
        return Results.BadRequest(new { error = "password must be between 12 and 128 characters" });
    if ((request.DisplayName?.Length ?? 0) > 200 || (request.Locale?.Length ?? 0) > 35 ||
        (request.Timezone?.Length ?? 0) > 64 || (request.PolicyVersion?.Length ?? 0) > 64)
        return Results.BadRequest(new { error = "a field exceeds its maximum length" });

    var userId = await keycloak.CreateUserAsync(email, request.Password, ct);

    try
    {
        var now = clock.GetUtcNow();
        var emailHash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(email)));
        var locale = string.IsNullOrWhiteSpace(request.Locale) ? "es-ES" : request.Locale;
        var timezone = string.IsNullOrWhiteSpace(request.Timezone) ? "Europe/Madrid" : request.Timezone;

        // Vault wrap + field encryption BEFORE the transaction, so we never hold a pooled DB connection
        // across external HTTP round-trips. The plaintext DEK is zeroed before any DB work.
        var dek = RandomNumberGenerator.GetBytes(32);
        byte[] wrappedDek;
        byte[]? displayNameEnc = null;
        try
        {
            wrappedDek = await keyWrapper.WrapAsync(dek, ct);
            if (!string.IsNullOrWhiteSpace(request.DisplayName))
                displayNameEnc = cipher.EncryptString(request.DisplayName, dek);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(dek);
        }

        // Atomic Lumen-side state — all rows commit together or not at all.
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        db.Users.Add(new User
        {
            Id = userId,
            EmailHash = emailHash,
            Locale = locale,
            Timezone = timezone,
            CreatedAt = now,
            UpdatedAt = now,
        });
        db.ConsentRecords.Add(new ConsentRecord
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            PolicyVersion = string.IsNullOrWhiteSpace(request.PolicyVersion) ? "v1-draft" : request.PolicyVersion,
            Locale = locale,
            ConsentedAt = now,
        });
        db.UserKeys.Add(new UserKey
        {
            UserId = userId,
            WrappedDek = wrappedDek,
            KeyVersion = 1,
            VaultKeyName = vaultOptions.KeyName,
            CreatedAt = now,
        });
        if (displayNameEnc is not null)
        {
            db.UserProfiles.Add(new UserProfileEnc
            {
                UserId = userId,
                DisplayNameEnc = displayNameEnc,
                CreatedAt = now,
                UpdatedAt = now,
            });
        }
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return Results.Ok(new { userId });
    }
    catch
    {
        // The Keycloak identity was created but Lumen-side state failed — remove the orphan (best effort)
        // so the email is not permanently bricked for sign-up.
        try { await keycloak.DeleteUserAsync(userId, ct); } catch { /* compensation is best-effort */ }
        throw;
    }
}).AllowAnonymous();

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
}).RequireAuthorization();

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
}).RequireAuthorization();

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
