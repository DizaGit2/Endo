namespace Lumen.UnitTests.Time;

/// <summary>
/// A <see cref="TimeProvider"/> frozen at one instant, for the D-12 day-boundary suites.
/// Hand-rolled deliberately: <c>Microsoft.Extensions.TimeProvider.Testing</c> would add a NuGet
/// package to a build that runs with <c>-warnaserror</c> plus a NuGet audit, to save three lines.
/// </summary>
internal sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => now;
}
