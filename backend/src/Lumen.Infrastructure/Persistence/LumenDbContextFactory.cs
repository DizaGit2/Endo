using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Lumen.Infrastructure.Persistence;

/// <summary>
/// Design-time factory so <c>dotnet ef</c> can build migrations without booting the API host.
/// The connection string is only used by <c>database update</c>; <c>migrations add</c> needs it
/// merely to be parseable. Default points at the local compose Postgres (host port 55432).
/// </summary>
public class LumenDbContextFactory : IDesignTimeDbContextFactory<LumenDbContext>
{
    public LumenDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("LUMEN_DB")
            ?? "Host=localhost;Port=55432;Database=lumen;Username=postgres;Password=postgres";

        var options = new DbContextOptionsBuilder<LumenDbContext>()
            .UseNpgsql(connectionString)
            .Options;

        return new LumenDbContext(options);
    }
}
