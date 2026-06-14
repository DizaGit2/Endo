using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace Lumen.IntegrationTests;

/// <summary>
/// Shared WebApplicationFactory for live-stack tests. Keeps the app in the Development environment
/// (so dev secrets + plaintext OIDC metadata work) but disables the Hangfire background server so
/// enqueued jobs never execute mid-test.
/// </summary>
public sealed class LumenApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.ConfigureAppConfiguration((_, cfg) =>
            cfg.AddInMemoryCollection(new Dictionary<string, string?> { ["Hangfire:EnableServer"] = "false" }));
}
