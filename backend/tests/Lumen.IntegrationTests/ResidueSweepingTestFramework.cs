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
/// <b>This hook fires on every run of this assembly and cannot be filtered out</b> — that is what an
/// assembly-level <c>[TestFramework]</c> is. It is therefore the wrong place to decide WHETHER to
/// delete anything, and it does not: <see cref="TestResidueSweep.RunOnceAsync"/> returns immediately
/// unless the run set <see cref="TestResidueSweep.EnableVariable"/>, so the default cost of this hook
/// is one environment-variable read. Before that gate existed, a <c>--filter</c> run of tests that
/// touch no database at all still reclaimed accounts, silently.
/// </para>
/// <para>
/// The sweep is driven from <see cref="CreateExecutor"/> rather than from the constructor so it runs
/// when tests EXECUTE and not on every discovery pass (an IDE refreshing its test list has no business
/// deleting rows).
/// </para>
/// <para>
/// This is the only assembly-wide "before anything" hook xUnit v2 offers — there is no
/// <c>[AssemblyFixture]</c> until v3 — and it is where an ENABLED sweep belongs: an aborted run's
/// residue must be reclaimed before the first test asserts anything, and no individual test class is
/// guaranteed to run. <see cref="TestResidueSweep.RunOnceAsync"/> never throws, so a docker-less run
/// (CI's <c>openapi-contract</c> job runs the static contract tests with no stack at all) proceeds
/// regardless. The message sink below is a SECONDARY sink — the sweep prints to the console itself,
/// because <c>DiagnosticMessage</c>s are invisible unless a runner config enables them and this repo
/// has no <c>xunit.runner.json</c>.
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
