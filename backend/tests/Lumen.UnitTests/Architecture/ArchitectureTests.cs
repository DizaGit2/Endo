using System.Reflection;
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
}
