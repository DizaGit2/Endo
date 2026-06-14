// Serialize all tests in this assembly so the live-stack cold-start (Postgres/Vault) does not
// contend with parallel test collection runners causing transient failures.
[assembly: Xunit.CollectionBehavior(DisableTestParallelization = true)]
