using System.Reflection;
using Xunit.Abstractions;
using Xunit.Sdk;

namespace Lumen.IntegrationTests;

/// <summary>
/// The once-per-run hook that drives <see cref="TestResidueSweep"/>. Registered by the
/// <c>[assembly: TestFramework]</c> attribute in <c>AssemblyInfo.cs</c>.
/// </summary>
/// <remarks>
/// <para>
/// The sweep is driven from <see cref="CreateExecutor"/> rather than from the constructor so it runs
/// when tests EXECUTE and not on every discovery pass (an IDE refreshing its test list has no business
/// deleting rows).
/// </para>
/// <para>
/// This is the only assembly-wide "before anything" hook xUnit v2 offers — there is no
/// <c>[AssemblyFixture]</c> until v3 — and it is where the sweep belongs: an aborted run's residue must
/// be reclaimed before the first test asserts anything, and no individual test class is guaranteed to
/// run. <see cref="TestResidueSweep.RunOnceAsync"/> never throws, so a docker-less run (CI's
/// <c>openapi-contract</c> job runs the static contract tests with no stack at all) reports a skipped
/// sweep to the diagnostic sink and proceeds.
/// </para>
/// </remarks>
public sealed class ResidueSweepingTestFramework(IMessageSink messageSink) : XunitTestFramework(messageSink)
{
    protected override ITestFrameworkExecutor CreateExecutor(AssemblyName assemblyName)
    {
        TestResidueSweep
            .RunOnceAsync(message => DiagnosticMessageSink.OnMessage(new DiagnosticMessage(message)))
            .GetAwaiter()
            .GetResult();

        return base.CreateExecutor(assemblyName);
    }
}
