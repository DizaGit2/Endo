// Serialize all tests in this assembly so multiple WebApplicationFactory cold-starts and
// live-stack connections (Keycloak / Vault) do not contend under parallel xUnit collection
// runners, which caused transient BadGateway failures in CI.
[assembly: Xunit.CollectionBehavior(DisableTestParallelization = true)]

// Installs the hook that CAN reclaim the Postgres rows and Keycloak accounts an ABORTED live run
// leaves behind, once, before the first test executes.
//
//   OPT-IN: it does nothing unless the run sets LUMEN_SWEEP_TEST_RESIDUE=1, and when it does run it
//   announces every delete on three channels (console, xUnit diagnostics, TestResults/residue-sweep.log).
//   Registering a test framework applies to the WHOLE assembly and survives any --filter, so the
//   decision to delete cannot live here; it lives in that variable.
//
//     PS>  $env:LUMEN_SWEEP_TEST_RESIDUE=1
//     PS>  dotnet test backend/tests/Lumen.IntegrationTests --logger "console;verbosity=normal"
//
// See TestResidueSweep for the rule, the fail-closed age floor and the dev-stack identity proof; see
// ResidueSweepingTestFramework for why this is the hook. The sweep never throws, so a docker-less run
// (CI's openapi-contract job) is unaffected.
[assembly: Xunit.TestFramework(
    "Lumen.IntegrationTests.ResidueSweepingTestFramework",
    "Lumen.IntegrationTests")]
