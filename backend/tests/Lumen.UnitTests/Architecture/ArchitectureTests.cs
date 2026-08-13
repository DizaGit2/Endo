using System.Reflection;
using Lumen.Api;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using NetArchTest.Rules;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Architecture;

/// <summary>
/// Guards the module boundaries from §C / §2 invariants: Domain stays pure (no Infrastructure/EF),
/// Application depends only on Domain. These run as ordinary unit tests.
/// </summary>
public class ArchitectureTests
{
    private static readonly Assembly DomainAssembly = typeof(User).Assembly;
    private static readonly Assembly ApplicationAssembly = typeof(IFieldCipher).Assembly;
    private static readonly Assembly ApiAssembly = typeof(StartupGuards).Assembly;

    /// <summary>
    /// The full name of the entity §G6 forbids the API surface from touching, spelled out rather
    /// than derived, because <see cref="UserInsightSnapshot_is_unreachable_from_the_API_surface"/>
    /// must fail on a rename instead of quietly guarding nothing.
    /// </summary>
    private const string InsightSnapshotTypeName = "Lumen.Domain.Entities.UserInsightSnapshot";

    [Fact]
    public void Domain_does_not_depend_on_Infrastructure_or_Application()
    {
        var result = Types.InAssembly(DomainAssembly)
            .ShouldNot()
            .HaveDependencyOnAny("Lumen.Infrastructure", "Lumen.Application")
            .GetResult();

        result.IsSuccessful.ShouldBeTrue(string.Join(", ", result.FailingTypeNames ?? []));
    }

    [Fact]
    public void Domain_does_not_depend_on_EntityFrameworkCore_or_Npgsql()
    {
        var result = Types.InAssembly(DomainAssembly)
            .ShouldNot()
            .HaveDependencyOnAny("Microsoft.EntityFrameworkCore", "Npgsql")
            .GetResult();

        result.IsSuccessful.ShouldBeTrue(string.Join(", ", result.FailingTypeNames ?? []));
    }

    [Fact]
    public void Application_does_not_depend_on_Infrastructure()
    {
        var result = Types.InAssembly(ApplicationAssembly)
            .ShouldNot()
            .HaveDependencyOnAny("Lumen.Infrastructure")
            .GetResult();

        result.IsSuccessful.ShouldBeTrue(string.Join(", ", result.FailingTypeNames ?? []));
    }

    [Fact]
    public void Application_does_not_depend_on_EntityFrameworkCore_or_Npgsql()
    {
        var result = Types.InAssembly(ApplicationAssembly)
            .ShouldNot()
            .HaveDependencyOnAny("Microsoft.EntityFrameworkCore", "Npgsql")
            .GetResult();

        result.IsSuccessful.ShouldBeTrue(string.Join(", ", result.FailingTypeNames ?? []));
    }

    [Fact]
    public void UserInsightSnapshot_is_unreachable_from_the_API_surface()
    {
        // §G6, build-enforced: P4a ships ZERO clinical inference. `user_insight_snapshot` exists as
        // a table with zero rows and NO read endpoint — an endpoint, DTO, mapper or service in
        // Lumen.Api that so much as names the entity would let a caller read a value the phase
        // engine has not computed yet, which is exactly the "placeholder mistaken for clinical
        // output" failure this table is shaped to prevent. P6 lifts this fact when it ships the
        // engine. Demonstrated red by temporarily referencing the entity from a Lumen.Api file
        // (see the T7 commit body).
        //
        // The companion assertion below matters as much as the rule: NetArchTest matches
        // dependencies by name, so a rename of the entity would leave a vacuously-green guard.
        Type.GetType($"{InsightSnapshotTypeName}, {DomainAssembly.GetName().Name}")
            .ShouldNotBeNull($"{InsightSnapshotTypeName} must exist, or this fact guards nothing");
        typeof(UserInsightSnapshot).FullName.ShouldBe(InsightSnapshotTypeName);

        var result = Types.InAssembly(ApiAssembly)
            .ShouldNot()
            .HaveDependencyOn(InsightSnapshotTypeName)
            .GetResult();

        result.IsSuccessful.ShouldBeTrue(
            "no Lumen.Api type may depend on UserInsightSnapshot (§G6 — no read endpoint): "
            + string.Join(", ", result.FailingTypeNames ?? []));
    }
}
