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
    public async Task OpenApi_calendar_200_documents_the_phase_availability_envelope()
    {
        // What actually buys P6 its freedom is that the FIELD EXISTS on the calendar's 200: a client
        // generated in T21 against `{ available, unavailableReason }` binds any future reason code
        // without being regenerated, because a new code is a value on an existing `string?`, not a
        // schema change. So the contract obligation worth pinning is the envelope's SHAPE — asserted
        // on the emitted document rather than only on the committed snapshot, so dropping the member
        // fails here instead of producing a snapshot diff somebody regenerates away.
        //
        // The reason CODES are deliberately NOT asserted here: they are backend constants
        // (CyclePhaseAvailability) with no representation in the generated Dart client, and the value
        // P4a emits at runtime is pinned where it is actually produced — CycleCalendarServiceTests
        // (unit) and CycleCalendarLiveTests (over real HTTP).
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

        phase.TryGetProperty("available", out var available).ShouldBeTrue(
            "the client branches on `phase.available`, so it must be in the contract");
        available.GetProperty("type").GetString().ShouldBe("boolean");

        phase.TryGetProperty("unavailableReason", out var reason).ShouldBeTrue(
            "`unavailableReason` existing is the whole mechanism: P6 emits a new code as a VALUE on " +
            "this field, and a client generated in T21 reads it without regeneration. Remove the " +
            "member and P6 becomes a breaking contract change.");
        reason.GetProperty("type").GetString().ShouldBe("string");
        reason.GetProperty("nullable").GetBoolean().ShouldBeTrue(
            "`available: true` must be expressible with no reason, so the member is nullable");
    }

    [Fact]
    public async Task OpenApi_unavailable_reason_declares_no_default_so_null_survives_into_the_client()
    {
        // A schema `default` on a NULLABLE member is a client-side lie in this toolchain. The pinned
        // generator (openapi-generator-cli 7.11.0, dart-dio + built_value) turns a `default` into a
        // builder default:
        //
        //     static void _defaults(CyclePhaseAvailabilityResponseBuilder b) => b
        //         ..unavailableReason = 'phase_engine_not_implemented';
        //
        // and its deserializer SKIPS explicit nulls (`if (valueDes == null) continue;`). So a
        // documented default here would mean the Dart client can NEVER observe null on this field —
        // when P6 answers `{ "available": true, "unavailableReason": null }` (or omits the key) the
        // client would still read "phase_engine_not_implemented", contradicting the DTO's own doc and
        // the flag the client is told to branch on.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var phase = doc.RootElement.GetProperty("components").GetProperty("schemas")
            .GetProperty("CyclePhaseAvailabilityResponse").GetProperty("properties");

        phase.GetProperty("unavailableReason").TryGetProperty("default", out _).ShouldBeFalse(
            "a [DefaultValue] on the nullable UnavailableReason becomes a built_value builder default " +
            "that an explicit null cannot clear — the client would read the P4a code forever. The " +
            "reason codes belong on CyclePhaseAvailability (backend constants); the contract only owes " +
            "the client the FIELD.");
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

    // --- T14: the cycle-settings resource, and the nullable members that must carry no default ----

    [Fact]
    public async Task OpenApi_documents_both_cycle_settings_operations()
    {
        // Asserted on the EMITTED document, not only on the committed snapshot: dropping
        // `MapCycleSettingsEndpoints()` from Program.cs must fail here rather than produce a snapshot
        // diff somebody regenerates away.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var root = doc.RootElement;

        root.GetProperty("paths").TryGetProperty("/settings/cycle", out var settings)
            .ShouldBeTrue("GET/PATCH /settings/cycle must be documented (§C.9)");

        settings.GetProperty("get").GetProperty("responses").GetProperty("200")
            .GetProperty("content").GetProperty("application/json").GetProperty("schema")
            .GetProperty("$ref").GetString().ShouldBe("#/components/schemas/CycleSettingsResponse");

        var patch = settings.GetProperty("patch");
        patch.GetProperty("responses").GetProperty("200")
            .GetProperty("content").GetProperty("application/json").GetProperty("schema")
            .GetProperty("$ref").GetString().ShouldBe(
                "#/components/schemas/CycleSettingsResponse",
                "the PATCH answers the full resource, not 204: the body carries the §G7 warnings and " +
                "the derived phasesUnavailable flag an online-only client would otherwise re-fetch");

        var responses = patch.GetProperty("responses");
        responses.TryGetProperty("400", out var badRequest).ShouldBeTrue();
        AssertIsValidationProblemSchema(
            root,
            badRequest.GetProperty("content").GetProperty("application/problem+json").GetProperty("schema"),
            "PATCH /settings/cycle");
        responses.TryGetProperty("404", out _).ShouldBeTrue(
            "an erased user's still-valid token gets the shared 404 from both routes");

        // The pause triple must be writable, or the C-12 state machine is unreachable from the client.
        var request = root.GetProperty("components").GetProperty("schemas")
            .GetProperty("UpdateCycleSettingsRequest").GetProperty("properties");
        foreach (var member in new[]
                 {
                     "avgCycleLengthDays", "avgPeriodLengthDays", "regularity", "phasePredictionEnabled",
                     "autoDetectPeriodStartEnabled", "showFertilityWindowEnabled",
                     "trackingPaused", "pauseReason", "pausedSince",
                 })
        {
            request.TryGetProperty(member, out _).ShouldBeTrue($"PATCH /settings/cycle must accept '{member}'");
        }
    }

    [Fact]
    public async Task OpenApi_cycle_settings_response_carries_the_derived_flag_and_the_warnings_and_nothing_clinical()
    {
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var response = doc.RootElement.GetProperty("components").GetProperty("schemas")
            .GetProperty("CycleSettingsResponse").GetProperty("properties");

        response.GetProperty("phasesUnavailable").GetProperty("type").GetString().ShouldBe(
            "boolean",
            "ARCHITECTURE.md §A:59's explicit 'phases unavailable' state — the client branches on it " +
            "so a paused user is shown an unavailable state, never a confidently wrong phase");
        response.GetProperty("warnings").GetProperty("type").GetString().ShouldBe("array");

        // §G6 on the WIRE CONTRACT: P4a computes none of these, and a documented key is exactly how a
        // not-yet-implemented estimate becomes a clinical fact in a client author's mental model.
        // `hormoneRangeInterpretationEnabled` is additionally barred: it would encode the
        // clinician-UNSIGNED C-12 pregnancy rule, whose only consumers (P6/P7b) do not exist.
        foreach (var forbidden in new[]
                 {
                     "phase", "cycleDay", "confidence", "dataCompleteness",
                     "nextPeriodPredictedOn", "hormoneRangeInterpretationEnabled",
                 })
        {
            response.TryGetProperty(forbidden, out _).ShouldBeFalse(
                $"CycleSettingsResponse must not document '{forbidden}' (§G6)");
        }
    }

    [Fact]
    public async Task OpenApi_no_nullable_cycle_settings_member_declares_a_default()
    {
        // The T13 defect, generalised. A schema `default` on a NULLABLE member is a client-side lie in
        // this toolchain: openapi-generator's dart-dio + built_value output turns it into a builder
        // default and its deserializer SKIPS explicit nulls (`if (valueDes == null) continue;`), so the
        // client could never observe null on that field again. `createdAt`/`updatedAt` are null exactly
        // when no row has been saved — the one signal that GET's defaults answer is not a stored row —
        // and `pausedSince` is null exactly when the user is not paused. A default on any of them would
        // make the client unable to read either state.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var schemas = doc.RootElement.GetProperty("components").GetProperty("schemas");

        foreach (var (schema, member) in new[]
                 {
                     ("CycleSettingsResponse", "avgPeriodLengthDays"),
                     ("CycleSettingsResponse", "pauseReason"),
                     ("CycleSettingsResponse", "pausedSince"),
                     ("CycleSettingsResponse", "createdAt"),
                     ("CycleSettingsResponse", "updatedAt"),
                     ("UpdateCycleSettingsRequest", "avgCycleLengthDays"),
                     ("UpdateCycleSettingsRequest", "avgPeriodLengthDays"),
                     ("UpdateCycleSettingsRequest", "regularity"),
                     ("UpdateCycleSettingsRequest", "phasePredictionEnabled"),
                     ("UpdateCycleSettingsRequest", "autoDetectPeriodStartEnabled"),
                     ("UpdateCycleSettingsRequest", "showFertilityWindowEnabled"),
                     ("UpdateCycleSettingsRequest", "trackingPaused"),
                     ("UpdateCycleSettingsRequest", "pauseReason"),
                     ("UpdateCycleSettingsRequest", "pausedSince"),
                 })
        {
            schemas.GetProperty(schema).GetProperty("properties").GetProperty(member)
                .TryGetProperty("default", out _)
                .ShouldBeFalse(
                    $"{schema}.{member} is nullable, so a schema default becomes a built_value builder " +
                    $"default an explicit null can never clear — on the PATCH request that would turn " +
                    $"'leave unchanged' into an unavoidable write");
        }
    }

    // --- T15: the device-registration upsert, and the token that must not appear in the contract ---

    [Fact]
    public async Task OpenApi_documents_the_device_registration_endpoint()
    {
        // Asserted on the EMITTED document, not only on the committed snapshot: dropping
        // `MapDeviceEndpoints()` from Program.cs must fail here rather than produce a snapshot diff
        // somebody regenerates away.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var root = doc.RootElement;

        root.GetProperty("paths").TryGetProperty("/me/devices", out var devices)
            .ShouldBeTrue("POST /me/devices must be documented (§C.9)");

        var post = devices.GetProperty("post");
        post.GetProperty("responses").GetProperty("200")
            .GetProperty("content").GetProperty("application/json").GetProperty("schema")
            .GetProperty("$ref").GetString().ShouldBe(
                "#/components/schemas/RegisterDeviceResponse",
                "an upsert has no actionable created/updated distinction, so both paths answer 200");

        var responses = post.GetProperty("responses");
        responses.TryGetProperty("400", out var badRequest).ShouldBeTrue();
        AssertIsValidationProblemSchema(
            root,
            badRequest.GetProperty("content").GetProperty("application/problem+json").GetProperty("schema"),
            "POST /me/devices");
        responses.TryGetProperty("401", out _).ShouldBeTrue();
        responses.TryGetProperty("404", out _).ShouldBeTrue(
            "an erased user's still-valid token gets the shared 404 from this route too");

        var request = root.GetProperty("components").GetProperty("schemas")
            .GetProperty("RegisterDeviceRequest").GetProperty("properties");
        request.TryGetProperty("platform", out _).ShouldBeTrue();
        request.TryGetProperty("pushToken", out _).ShouldBeTrue();
    }

    [Fact]
    public async Task OpenApi_device_response_never_documents_the_push_token()
    {
        // §F on the WIRE CONTRACT: a documented `pushToken` on the RESPONSE would make the generated
        // Dart client bind and hold it, putting the token into client logs and support HAR files for
        // no gain — the caller already has it. The response carries the row's identity and nothing else.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());

        var response = doc.RootElement.GetProperty("components").GetProperty("schemas")
            .GetProperty("RegisterDeviceResponse").GetProperty("properties");

        foreach (var forbidden in new[] { "pushToken", "token", "push_token" })
            response.TryGetProperty(forbidden, out _).ShouldBeFalse($"RegisterDeviceResponse must not document '{forbidden}'");

        response.GetProperty("deviceId").GetProperty("type").GetString().ShouldBe("string");
        response.GetProperty("platform").GetProperty("type").GetString().ShouldBe("string");
    }

    [Fact]
    public async Task OpenApi_no_device_member_declares_a_default()
    {
        // The T13 defect, generalised (see the cycle-settings case above). Nothing on either device
        // schema may carry a schema `default`: on the REQUEST both members are nullable so a default
        // would become a built_value builder default the caller cannot clear, and a defaulted
        // `platform` would silently register every device as one platform.
        using var doc = JsonDocument.Parse(await GetSwaggerJsonAsync());
        var schemas = doc.RootElement.GetProperty("components").GetProperty("schemas");

        foreach (var (schema, member) in new[]
                 {
                     ("RegisterDeviceRequest", "platform"),
                     ("RegisterDeviceRequest", "pushToken"),
                     ("RegisterDeviceResponse", "deviceId"),
                     ("RegisterDeviceResponse", "platform"),
                     ("RegisterDeviceResponse", "lastSeenAt"),
                     ("RegisterDeviceResponse", "createdAt"),
                 })
        {
            schemas.GetProperty(schema).GetProperty("properties").GetProperty(member)
                .TryGetProperty("default", out _)
                .ShouldBeFalse($"{schema}.{member} must not carry a schema default");
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
