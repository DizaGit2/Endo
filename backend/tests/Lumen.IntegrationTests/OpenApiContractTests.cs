using System.Text.Json;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Verifies Swashbuckle emits an OpenAPI document covering the spine endpoints. The committed
/// snapshot (<c>backend/contract/openapi.json</c>) + the CI drift-guard land with T12.
/// (Static doc — needs no DB/Keycloak.)
///
/// <para>
/// T4 additionally pins the spine onto the P4a problem contract: <c>POST /onboarding/start</c> answers
/// with a named response schema instead of the untyped <c>{}</c> Swashbuckle emits for an anonymous
/// object, both of its failure modes reference the validation-problem schema rather than the bare
/// <c>ProblemDetails</c>, and <c>/me</c> documents the 404 an erased-or-missing user now receives. The
/// class is also re-run as proof that moving the handler into
/// <see cref="Lumen.Api.Onboarding.OnboardingEndpoints"/> changed nothing the contract can see —
/// the route, and (via <c>OnboardingEndpointsMoveTests</c>) the metadata it cannot.
/// </para>
/// </summary>
public class OpenApiContractTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private async Task<string> GetSwaggerJsonAsync() =>
        await factory.CreateClient().GetStringAsync("/swagger/v1/swagger.json");

    [Fact]
    public async Task OpenApi_documents_the_spine_endpoints()
    {
        var client = factory.CreateClient();

        var json = await client.GetStringAsync("/swagger/v1/swagger.json");
        using var doc = JsonDocument.Parse(json);
        var paths = doc.RootElement.GetProperty("paths");

        paths.TryGetProperty("/onboarding/start", out _).ShouldBeTrue();
        paths.TryGetProperty("/me", out _).ShouldBeTrue();
        paths.TryGetProperty("/health", out _).ShouldBeTrue();
    }

    [Fact]
    public async Task OpenApi_DELETE_me_documents_202_as_success_response()
    {
        var client = factory.CreateClient();

        var json = await client.GetStringAsync("/swagger/v1/swagger.json");
        using var doc = JsonDocument.Parse(json);
        var paths = doc.RootElement.GetProperty("paths");

        // DELETE /me must be present in the contract.
        paths.TryGetProperty("/me", out var mePath).ShouldBeTrue("/me path must exist");
        mePath.TryGetProperty("delete", out var deleteOp).ShouldBeTrue("DELETE /me operation must be documented");

        // The documented success status must be 202 Accepted, not 200.
        deleteOp.GetProperty("responses").TryGetProperty("202", out _)
            .ShouldBeTrue("DELETE /me must document 202 Accepted as its success response");

        // 401 must be documented because the endpoint requires authorization.
        deleteOp.GetProperty("responses").TryGetProperty("401", out _)
            .ShouldBeTrue("DELETE /me must document 401 Unauthorized");
    }

    // --- T4: the spine on the P4a problem contract -------------------------------------------

    [Fact]
    public async Task OpenApi_onboarding_start_200_references_the_typed_response_schema()
    {
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var schema = doc.RootElement
            .GetProperty("paths").GetProperty("/onboarding/start").GetProperty("post")
            .GetProperty("responses").GetProperty("200")
            .GetProperty("content").GetProperty("application/json").GetProperty("schema");

        schema.TryGetProperty("$ref", out var reference).ShouldBeTrue(
            "POST /onboarding/start must document a named 200 body; an anonymous object emits the " +
            "untyped `{}` schema, which the generated Dart client cannot bind to anything.");
        reference.GetString().ShouldBe("#/components/schemas/OnboardingStartResponse");
    }

    [Fact]
    public async Task OpenApi_onboarding_start_400_references_the_validation_problem_schema()
    {
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var root = doc.RootElement;

        var schema = root
            .GetProperty("paths").GetProperty("/onboarding/start").GetProperty("post")
            .GetProperty("responses").GetProperty("400")
            .GetProperty("content").GetProperty("application/problem+json").GetProperty("schema");

        AssertIsValidationProblemSchema(root, schema, "POST /onboarding/start");
    }

    [Fact]
    public async Task OpenApi_get_me_documents_the_404()
    {
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var responses = doc.RootElement
            .GetProperty("paths").GetProperty("/me").GetProperty("get").GetProperty("responses");

        responses.TryGetProperty("404", out var notFound).ShouldBeTrue(
            "GET /me returns the shared 404 problem when the users row is gone (crypto-shredded or " +
            "never provisioned), so the contract must document it.");
        notFound.GetProperty("content").TryGetProperty("application/problem+json", out _).ShouldBeTrue(
            "the 404 body is application/problem+json (NotFoundProblem.Result()).");
    }

    [Fact]
    public async Task OpenApi_patch_me_request_documents_timezone_and_locale()
    {
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var properties = doc.RootElement
            .GetProperty("components").GetProperty("schemas").GetProperty("UpdateMeRequest")
            .GetProperty("properties");

        properties.TryGetProperty("timezone", out _).ShouldBeTrue(
            "PATCH /me must accept the user's IANA timezone — a stale users.timezone mis-files every " +
            "day-keyed write (D-12).");
        properties.TryGetProperty("locale", out _).ShouldBeTrue("PATCH /me must accept the user's locale (D-05).");
    }

    [Fact]
    public async Task OpenApi_patch_me_documents_the_validation_problem_400_and_the_404()
    {
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var root = doc.RootElement;

        var responses = root
            .GetProperty("paths").GetProperty("/me").GetProperty("patch").GetProperty("responses");

        responses.TryGetProperty("400", out var badRequest).ShouldBeTrue(
            "PATCH /me now rejects an unknown timezone / malformed locale, so the contract must document the 400.");
        AssertIsValidationProblemSchema(
            root,
            badRequest.GetProperty("content").GetProperty("application/problem+json").GetProperty("schema"),
            "PATCH /me");

        responses.TryGetProperty("404", out _).ShouldBeTrue(
            "PATCH /me returns the shared 404 problem when the users row is gone.");
    }

    // --- T13: the §G6 phase envelope, and the absence of everything else phase-shaped -------------

    [Fact]
    public async Task OpenApi_carries_the_phase_engine_not_implemented_code_into_the_contract()
    {
        // The POINT of CyclePhaseAvailability is that P6 can start emitting real phase data without a
        // client-visible vocabulary change — and a constant reaches the generated Dart client only if
        // a DTO carries it into the contract. The Dart client is regenerated exactly once, in T21, so
        // GET /cycle/calendar is the last chance to put this code there. Asserted on the emitted
        // document rather than only on the committed snapshot, so deleting the attribute fails here
        // instead of merely producing a snapshot diff somebody regenerates away.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var root = doc.RootElement;

        root.GetProperty("paths").TryGetProperty("/cycle/calendar", out var calendar)
            .ShouldBeTrue("GET /cycle/calendar must be documented");
        calendar.GetProperty("get").GetProperty("responses").GetProperty("200")
            .GetProperty("content").GetProperty("application/json").GetProperty("schema")
            .GetProperty("$ref").GetString().ShouldBe("#/components/schemas/CycleCalendarResponse");

        var phaseRef = root.GetProperty("components").GetProperty("schemas")
            .GetProperty("CycleCalendarResponse").GetProperty("properties")
            .GetProperty("phase").GetProperty("$ref").GetString()!;

        var phase = root.GetProperty("components").GetProperty("schemas")
            .GetProperty(phaseRef.Split('/')[^1]).GetProperty("properties");

        phase.GetProperty("available").GetProperty("type").GetString().ShouldBe("boolean");

        phase.GetProperty("unavailableReason").TryGetProperty("default", out var reason).ShouldBeTrue(
            "the §G6 reason code must reach the generated client through the CONTRACT, not just exist " +
            "as a C# constant with no consumer — `unavailableReason` documents no value, so the " +
            "[DefaultValue] on CyclePhaseAvailabilityResponse is gone");
        reason.GetString().ShouldBe("phase_engine_not_implemented");
    }

    [Fact]
    public async Task OpenApi_no_calendar_day_row_documents_a_phase_a_cycle_day_or_a_confidence()
    {
        // §G6 enforced on the WIRE CONTRACT, which is where it matters: P4a computes none of these,
        // and a documented key is exactly how a not-yet-implemented estimate becomes a clinical fact
        // in a client author's mental model. The response-level `phase` envelope is the one exception
        // and it says the engine does not exist.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var day = doc.RootElement.GetProperty("components").GetProperty("schemas")
            .GetProperty("CycleCalendarDay").GetProperty("properties");

        foreach (var forbidden in new[] { "phase", "cycleDay", "confidence", "notes" })
        {
            day.TryGetProperty(forbidden, out _).ShouldBeFalse(
                $"CycleCalendarDay must not document '{forbidden}' (§G6 / no note plaintext on this read)");
        }
    }

    /// <summary>
    /// Asserts the response schema is the validation-problem one (the shape carrying the
    /// <c>errors</c> map) rather than the bare <c>ProblemDetails</c>. Matched on the referenced
    /// component's shape, not its name, so the assertion states the contract obligation rather than
    /// a Swashbuckle naming detail.
    /// </summary>
    private static void AssertIsValidationProblemSchema(JsonElement root, JsonElement schema, string operation)
    {
        schema.TryGetProperty("$ref", out var reference).ShouldBeTrue($"{operation} must reference a named 400 schema");

        var name = reference.GetString()!.Split('/')[^1];
        var component = root.GetProperty("components").GetProperty("schemas").GetProperty(name);

        component.GetProperty("properties").TryGetProperty("errors", out _).ShouldBeTrue(
            $"{operation} must document the P4a validation-problem body (an `errors` field map), " +
            $"but its 400 references '{name}', which has no `errors` member.");
    }
}
