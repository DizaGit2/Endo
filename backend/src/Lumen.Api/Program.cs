using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Lumen.Api.Auth;
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

// --- identity ---
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUserAccessor, CurrentUserAccessor>();
builder.Services.AddHttpClient<IKeycloakAdmin, KeycloakAdminClient>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = keycloakOptions.Authority;
        options.RequireHttpsMetadata = false; // dev only; prod terminates TLS at Caddy
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
                if (azp is not ("mobile" or "api"))
                    context.Fail("Token authorized party (azp) is not an allowed Lumen client.");
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

builder.Services.AddProblemDetails();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseExceptionHandler(); // clean ProblemDetails on unhandled errors; no stack traces (with env=Production)
app.UseSerilogRequestLogging();
app.UseSwagger();
app.UseSwaggerUI();
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

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
    IDekProvisioner dekProvisioner,
    IKeyWrapper keyWrapper,
    IFieldCipher cipher,
    TimeProvider clock,
    CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
        return Results.BadRequest(new { error = "email and password are required" });
    if (!System.Net.Mail.MailAddress.TryCreate(request.Email.Trim(), out _))
        return Results.BadRequest(new { error = "invalid email format" });
    if (request.Password.Length is < 12 or > 128) // D-01 minimum; defense-in-depth with the realm policy
        return Results.BadRequest(new { error = "password must be between 12 and 128 characters" });
    if ((request.DisplayName?.Length ?? 0) > 200 || (request.Locale?.Length ?? 0) > 35 ||
        (request.Timezone?.Length ?? 0) > 64 || (request.PolicyVersion?.Length ?? 0) > 64)
        return Results.BadRequest(new { error = "a field exceeds its maximum length" });

    var userId = await keycloak.CreateUserAsync(request.Email, request.Password, ct);
    var now = clock.GetUtcNow();
    var emailHash = Convert.ToHexStringLower(
        SHA256.HashData(Encoding.UTF8.GetBytes(request.Email.Trim().ToLowerInvariant())));

    db.Users.Add(new User
    {
        Id = userId,
        EmailHash = emailHash,
        Locale = string.IsNullOrWhiteSpace(request.Locale) ? "es-ES" : request.Locale,
        Timezone = string.IsNullOrWhiteSpace(request.Timezone) ? "Europe/Madrid" : request.Timezone,
        CreatedAt = now,
        UpdatedAt = now,
    });
    db.ConsentRecords.Add(new ConsentRecord
    {
        Id = Guid.NewGuid(),
        UserId = userId,
        PolicyVersion = string.IsNullOrWhiteSpace(request.PolicyVersion) ? "v1-draft" : request.PolicyVersion,
        Locale = string.IsNullOrWhiteSpace(request.Locale) ? "es-ES" : request.Locale!,
        ConsentedAt = now,
    });
    await db.SaveChangesAsync(ct);

    await dekProvisioner.ProvisionAsync(userId, ct);

    if (!string.IsNullOrWhiteSpace(request.DisplayName))
    {
        var keyRow = await db.UserKeys.AsNoTracking().FirstAsync(k => k.UserId == userId, ct);
        var dek = await keyWrapper.UnwrapAsync(keyRow.WrappedDek, ct);
        try
        {
            db.UserProfiles.Add(new UserProfileEnc
            {
                UserId = userId,
                DisplayNameEnc = cipher.EncryptString(request.DisplayName, dek),
                CreatedAt = now,
                UpdatedAt = now,
            });
            await db.SaveChangesAsync(ct);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(dek);
        }
    }

    return Results.Ok(new { userId });
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
