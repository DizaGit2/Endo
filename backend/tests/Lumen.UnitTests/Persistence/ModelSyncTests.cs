using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Persistence;

/// <summary>
/// Guards model/migration drift without touching the database — safe to run in any CI environment.
/// HasPendingModelChanges() compares the EF compiled model against the last migration snapshot;
/// it does NOT open a connection.
/// </summary>
public class ModelSyncTests
{
    [Fact]
    public void EF_model_matches_last_migration_snapshot()
    {
        // Construct the context without connecting — UseNpgsql just configures the provider.
        var options = new DbContextOptionsBuilder<LumenDbContext>()
            .UseNpgsql("Host=localhost;Database=x;Username=x;Password=x")
            .Options;

        using var context = new LumenDbContext(options);
        context.Database.HasPendingModelChanges().ShouldBeFalse();
    }
}
