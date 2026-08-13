using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Proof that T4's extraction of <c>POST /onboarding/start</c> out of <c>Program.cs</c> into
/// <see cref="Lumen.Api.Onboarding.OnboardingEndpoints"/> is a <b>pure move</b>.
///
/// <para>
/// The OpenAPI document can show the route survived, but not the two pieces of metadata that actually
/// matter here and are invisible to it: <c>.AllowAnonymous()</c> — drop it and sign-up requires a
/// token nobody can have yet — and <c>.RequireRateLimiting("onboarding-start")</c>, the per-IP policy
/// that keeps an anonymous endpoint which creates Keycloak users and Vault keys from being a free
/// resource tap. Both are asserted off the built host's <see cref="EndpointDataSource"/>.
/// </para>
///
/// <para>
/// This is a characterization test: it passes before the move and after it, which is the whole point.
/// T16/T17/T18 add further endpoints to <c>MapOnboardingEndpoints()</c>; this fails the moment one of
/// them rewires the start endpoint. (Static host — needs no DB/Keycloak; not a [Category=LiveStack] test.)
/// </para>
/// </summary>
public class OnboardingEndpointsMoveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Route = "/onboarding/start";

    [Fact]
    public void Onboarding_start_keeps_its_route_verb_anonymous_access_and_named_rate_limit()
    {
        // Force the host (and therefore routing) to build before reading the endpoint table.
        _ = factory.CreateClient();

        var endpoint = factory.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .OfType<RouteEndpoint>()
            .SingleOrDefault(e => string.Equals(e.RoutePattern.RawText, Route, StringComparison.Ordinal));

        endpoint.ShouldNotBeNull(
            $"'{Route}' must still be mapped exactly once after the move into OnboardingEndpoints.");

        var httpMethods = endpoint!.Metadata.GetMetadata<IHttpMethodMetadata>();
        httpMethods.ShouldNotBeNull($"'{Route}' must declare an HTTP method");
        httpMethods!.HttpMethods.ShouldBe(["POST"]);

        endpoint.Metadata.GetMetadata<IAllowAnonymous>().ShouldNotBeNull(
            $"'{Route}' must stay anonymous: it is the sign-up endpoint, so the caller has no token yet.");

        var rateLimiting = endpoint.Metadata.GetMetadata<EnableRateLimitingAttribute>();
        rateLimiting.ShouldNotBeNull($"'{Route}' must keep its named rate-limiting policy");
        rateLimiting!.PolicyName.ShouldBe(
            "onboarding-start",
            "the per-IP policy is what stops an anonymous endpoint that provisions Keycloak users " +
            "and Vault keys from being abused; the global per-user limiter cannot key on a `sub` that does not exist yet.");
    }
}
