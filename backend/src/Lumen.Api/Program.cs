using System.Net.Sockets;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Structured logging to console (PII-scrubbing enricher arrives in P1).
builder.Host.UseSerilog((context, config) => config
    .MinimumLevel.Information()
    .Enrich.FromLogContext()
    .WriteTo.Console());

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseSerilogRequestLogging();
app.UseSwagger();
app.UseSwaggerUI();

// Liveness: the process is up and serving.
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
   .WithName("Health");

// Readiness: shallow TCP reachability of Postgres + Vault (no app logic, no SDK — P0a only).
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
})
   .WithName("Ready");

app.Run();

static int ParsePort(string? value, int fallback) =>
    int.TryParse(value, out var port) ? port : fallback;

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
