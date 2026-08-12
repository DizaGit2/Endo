// Serialize all tests in this assembly so multiple WebApplicationFactory cold-starts and
// live-stack connections (Keycloak / Vault) do not contend under parallel xUnit collection
// runners, which caused transient BadGateway failures in CI.
[assembly: Xunit.CollectionBehavior(DisableTestParallelization = true)]

// Reclaim the Postgres rows and Keycloak accounts an ABORTED live run leaves behind, once, before the
// first test executes. See TestResidueSweep for the rule and why it cannot delete anything it should
// not; see ResidueSweepingTestFramework for why this is the hook. The sweep never throws, so a
// docker-less run (CI's openapi-contract job) is unaffected.
[assembly: Xunit.TestFramework(
    "Lumen.IntegrationTests.ResidueSweepingTestFramework",
    "Lumen.IntegrationTests")]
