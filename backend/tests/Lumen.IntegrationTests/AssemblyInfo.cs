// Serialize all tests in this assembly so multiple WebApplicationFactory cold-starts and
// live-stack connections (Keycloak / Vault) do not contend under parallel xUnit collection
// runners, which caused transient BadGateway failures in CI.
[assembly: Xunit.CollectionBehavior(DisableTestParallelization = true)]
