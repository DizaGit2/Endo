using System.Reflection;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Emits the live Swashbuckle OpenAPI document via the in-process <see cref="LumenApiFactory"/> and
/// compares it against the committed snapshot at <c>backend/contract/openapi.json</c>.
///
/// <para>
/// Normal runs ASSERT the committed file is byte-for-byte equal to the freshly-emitted (normalized)
/// document — this is the drift guard CI (T9) builds on. To regenerate the snapshot after an
/// intentional contract change, run with the environment variable <c>LUMEN_OPENAPI_UPDATE=1</c>; the
/// test then writes the file (and also keeps the client-pinned copy in sync) instead of asserting.
/// </para>
///
/// <para>
/// The document is normalized to indented JSON with recursively sorted object keys so the committed
/// file is diff-stable across machines and Swashbuckle internal ordering changes. (Static doc — needs
/// no DB/Keycloak; not a [Category=LiveStack] test.)
/// </para>
/// </summary>
public partial class OpenApiSnapshotTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string UpdateEnvVar = "LUMEN_OPENAPI_UPDATE";

    /// <summary>
    /// Hangfire's dashboard is a catch-all route (<c>/hangfire/{**path}</c>) owned by the Hangfire
    /// middleware, not a minimal-API handler: it has no <c>ApiExplorer</c> description and therefore no
    /// OpenAPI representation, by design. Same exclusion, same constant, as
    /// <c>TenantIsolationLiveTests</c>.
    /// </summary>
    private const string HangfireDashboardTemplate = "/hangfire/{**path}";

    /// <summary>
    /// Every operation the API ships, as <c>"METHOD path"</c> with route constraints stripped (the form
    /// both the OpenAPI document and <see cref="NormalizeTemplate"/> produce).
    ///
    /// <para>
    /// This list is the P4a spine. It is deliberately a HAND LIST even though
    /// <see cref="RegisteredOperations"/> derives the same set from the route table, because the two
    /// catch different failures and only their combination catches all three:
    /// </para>
    /// <list type="bullet">
    /// <item><b>A dropped route</b> — deleting <c>app.MapSymptomEndpoints()</c> from <c>Program.cs</c>
    /// removes the operations from the route table AND from the document, so a route-table-derived
    /// check alone stays green while four endpoints vanish. Only this list notices.</item>
    /// <item><b>An undocumented route</b> — a handler that ships but is invisible to ApiExplorer (an
    /// added <c>.ExcludeFromDescription()</c>, a broken <c>AddEndpointsApiExplorer()</c>) leaves the
    /// route table intact while the document shrinks. Only the route-table cross-check notices.</item>
    /// <item><b>An unreviewed addition</b> — a new endpoint lands in both, and set equality against
    /// this list forces the author to declare it here, which is the moment T19's isolation sweep and
    /// the client-facing contract get considered.</item>
    /// </list>
    /// </summary>
    private static readonly string[] Spine =
    [
        // spine (P0a/P3c)
        "GET /health",
        "GET /health/ready",
        "POST /onboarding/start",
        "GET /me",
        "PATCH /me",
        "DELETE /me",

        // onboarding steps (T16–T18)
        "POST /onboarding/baseline",
        "POST /onboarding/goals",
        "POST /onboarding/hormones",
        "POST /onboarding/notifications",
        "POST /onboarding/cycle",
        "POST /onboarding/complete",
        "GET /onboarding/state",

        // cycle (T9/T10/T13)
        "GET /cycle/calendar",
        "GET /cycle/day/{date}",
        "POST /cycle/day/{date}",
        "POST /cycle/events",
        "DELETE /cycle/events/{id}",
        "POST /cycle/phase-override",
        "POST /checkin/quick",

        // symptoms (T11/T12)
        "GET /symptoms",
        "POST /symptoms",
        "PUT /symptoms/{id}",
        "DELETE /symptoms/{id}",

        // settings + devices (T14/T15)
        "GET /settings/cycle",
        "PATCH /settings/cycle",
        "POST /me/devices",
    ];

    /// <summary>The OpenAPI path-item members that are operations; everything else is metadata.</summary>
    private static readonly HashSet<string> OperationVerbs = new(StringComparer.Ordinal)
    {
        "get", "put", "post", "delete", "options", "head", "patch", "trace",
    };

    /// <summary>
    /// Strips an inline route constraint / optionality marker from each template parameter, so
    /// <c>/symptoms/{id:guid}</c> keys the same as the document's <c>/symptoms/{id}</c>.
    /// </summary>
    [GeneratedRegex(@"\{([^:?*}]+)[^}]*\}")]
    private static partial Regex TemplateParameter();

    [Fact]
    public async Task OpenApi_snapshot_matches_committed_contract()
    {
        var client = factory.CreateClient();
        var rawJson = await client.GetStringAsync("/swagger/v1/swagger.json");
        var normalized = NormalizeJson(rawJson);

        // Sanity-check the emitted doc carries the spine endpoints before we trust it as a snapshot.
        AssertSpineEndpoints(normalized);

        var repoRoot = FindRepoRoot();
        var backendSnapshot = Path.Combine(repoRoot, "backend", "contract", "openapi.json");
        var clientSnapshot = Path.Combine(repoRoot, "client", "openapi", "lumen.openapi.json");

        if (string.Equals(Environment.GetEnvironmentVariable(UpdateEnvVar), "1", StringComparison.Ordinal))
        {
            WriteSnapshot(backendSnapshot, normalized);
            WriteSnapshot(clientSnapshot, normalized);
            return;
        }

        File.Exists(backendSnapshot).ShouldBeTrue(
            $"Committed OpenAPI snapshot is missing at '{backendSnapshot}'. " +
            $"Regenerate it by running this test with {UpdateEnvVar}=1.");

        var committed = File.ReadAllText(backendSnapshot);

        // Compare on normalized text so line endings don't cause spurious drift across OSes.
        NormalizeLineEndings(committed).ShouldBe(
            NormalizeLineEndings(normalized),
            $"The committed OpenAPI snapshot is out of date with the backend contract. " +
            $"Regenerate it by running this test with {UpdateEnvVar}=1.");

        // The pinned client copy must stay byte-identical to the backend snapshot.
        File.Exists(clientSnapshot).ShouldBeTrue(
            $"Pinned client OpenAPI copy is missing at '{clientSnapshot}'. " +
            $"Regenerate it by running this test with {UpdateEnvVar}=1.");

        NormalizeLineEndings(File.ReadAllText(clientSnapshot)).ShouldBe(
            NormalizeLineEndings(committed),
            "The pinned client OpenAPI copy has drifted from backend/contract/openapi.json.");
    }

    /// <summary>
    /// The drift guard's floor, run BEFORE the snapshot is compared — and, crucially, before the
    /// <c>LUMEN_OPENAPI_UPDATE</c> branch writes anything, so a regeneration run cannot bake a
    /// dropped endpoint into the committed contract.
    ///
    /// <para>
    /// Three checks, deliberately overlapping (see <see cref="Spine"/> for which failure each one is
    /// the only witness to): the document's operations equal <see cref="Spine"/>, the route table's
    /// operations equal <see cref="Spine"/>, and the individually load-bearing details that set
    /// equality cannot express — <c>DELETE /me</c>'s 202/401, and the two schemas every other
    /// contract assertion in <c>OpenApiContractTests</c> resolves through.
    /// </para>
    /// </summary>
    private void AssertSpineEndpoints(string normalizedJson)
    {
        using var doc = JsonDocument.Parse(normalizedJson);
        var root = doc.RootElement;

        root.TryGetProperty("paths", out var paths).ShouldBeTrue("emitted doc must have a paths object");

        var expected = Spine.ToHashSet(StringComparer.Ordinal);
        Spine.ShouldBeUnique();

        // (a) THE DOCUMENT. Set equality both ways: an operation that stopped being documented fails
        // here (a dropped Map*Endpoints() call, a renamed route), and so does one that appeared
        // without being declared above.
        var documented = paths.EnumerateObject()
            .SelectMany(path => path.Value.EnumerateObject()
                .Where(member => OperationVerbs.Contains(member.Name))
                .Select(member => $"{member.Name.ToUpperInvariant()} {path.Name}"))
            .ToHashSet(StringComparer.Ordinal);

        documented.ShouldBe(
            expected,
            ignoreOrder: true,
            "the emitted OpenAPI document no longer describes exactly the operations P4a ships. If you "
            + "added an endpoint, add it to OpenApiSnapshotTests.Spine in the same commit (and give it "
            + "an entry in TenantIsolationLiveTests.Swept); if one disappeared, a Map*Endpoints() call "
            + "or a route registration was lost.");

        // (b) THE ROUTE TABLE, read off the built host exactly as TenantIsolationLiveTests does. This
        // is the half (a) cannot see: a route that still serves traffic but has fallen out of the
        // document (an added .ExcludeFromDescription(), a broken AddEndpointsApiExplorer()) shrinks
        // the document and the Spine list together only if somebody edits both — whereas here the
        // route is still in the table and the mismatch is immediate.
        RegisteredOperations().ShouldBe(
            expected,
            ignoreOrder: true,
            "the ROUTE TABLE no longer matches the declared spine. A route present here but absent from "
            + "the document above is an endpoint that serves traffic the contract does not describe — "
            + "the generated Dart client cannot call it and no reviewer reading openapi.json knows it "
            + "exists.");

        // (c) The details set equality cannot carry.
        var deleteResponses = paths.GetProperty("/me").GetProperty("delete").GetProperty("responses");
        deleteResponses.TryGetProperty("202", out _).ShouldBeTrue("DELETE /me must document 202 Accepted");
        deleteResponses.TryGetProperty("401", out _).ShouldBeTrue("DELETE /me must document 401 Unauthorized");

        root.TryGetProperty("components", out var components).ShouldBeTrue("emitted doc must have components");
        components.TryGetProperty("schemas", out var schemas).ShouldBeTrue("emitted doc must have components.schemas");

        schemas.TryGetProperty("OnboardingStartResponse", out _).ShouldBeTrue(
            "OnboardingStartResponse is the named 200 body sign-up depends on; lose it and Swashbuckle "
            + "emits the untyped `{}` the generated Dart client cannot bind (T4).");

        schemas.TryGetProperty("HttpValidationProblemDetails", out var validationProblem).ShouldBeTrue(
            "the phase has exactly one 400 body and every endpoint's failure mode references it (T3).");
        validationProblem.GetProperty("properties").TryGetProperty("errors", out _).ShouldBeTrue(
            "the validation-problem schema is identified by its `errors` field map, not by its name — "
            + "a bare ProblemDetails under the same $ref would satisfy the name and not the contract.");
    }

    /// <summary>
    /// The <c>"METHOD path"</c> operations the built host actually routes, normalized to the document's
    /// spelling. Only Hangfire's dashboard catch-all is excluded (see
    /// <see cref="HangfireDashboardTemplate"/>); nothing else is filtered, deliberately — an endpoint
    /// hidden from ApiExplorer stays in this set and therefore fails the comparison, which is the point.
    /// </summary>
    private ISet<string> RegisteredOperations()
    {
        // Force the host (and therefore routing) to build before reading the endpoint table — the same
        // move OnboardingEndpointsMoveTests and TenantIsolationLiveTests make.
        _ = factory.CreateClient();

        return factory.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .OfType<RouteEndpoint>()
            .Where(e => !string.Equals(e.RoutePattern.RawText, HangfireDashboardTemplate, StringComparison.Ordinal))
            .SelectMany(e => (e.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods ?? ["*"])
                .Select(method => $"{method} {NormalizeTemplate(e.RoutePattern.RawText ?? string.Empty)}"))
            .ToHashSet(StringComparer.Ordinal);
    }

    private static string NormalizeTemplate(string rawTemplate) =>
        TemplateParameter().Replace(rawTemplate, "{$1}");

    /// <summary>
    /// Parses, recursively sorts object keys, and re-serializes the document as indented JSON so the
    /// committed snapshot is stable regardless of the order Swashbuckle happens to emit members.
    /// </summary>
    private static string NormalizeJson(string rawJson)
    {
        var node = JsonNode.Parse(rawJson)!;
        var sorted = SortNode(node);

        var options = new JsonSerializerOptions
        {
            WriteIndented = true,
            // Keep '+' etc. readable rather than \u-escaped so the file is human-diffable.
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        };

        return sorted.ToJsonString(options);
    }

    private static JsonNode SortNode(JsonNode node)
    {
        switch (node)
        {
            case JsonObject obj:
            {
                var sorted = new JsonObject();
                foreach (var kvp in obj.OrderBy(p => p.Key, StringComparer.Ordinal))
                {
                    var child = kvp.Value;
                    sorted[kvp.Key] = child is null ? null : SortNode(child);
                }

                return sorted;
            }

            case JsonArray arr:
            {
                var sorted = new JsonArray();
                foreach (var item in arr.ToArray())
                {
                    // Detach before re-parenting (a JsonNode can only have one parent).
                    item?.Parent?.AsArray().Remove(item);
                    sorted.Add(item is null ? null : SortNode(item));
                }

                return sorted;
            }

            default:
                // Value node: clone so it can be re-parented under the sorted tree.
                return JsonNode.Parse(node.ToJsonString())!;
        }
    }

    private static void WriteSnapshot(string path, string normalizedJson)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        // Trailing newline keeps the file POSIX-friendly and diff-clean.
        File.WriteAllText(path, normalizedJson + "\n", new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static string NormalizeLineEndings(string text) =>
        text.Replace("\r\n", "\n").TrimEnd('\n');

    /// <summary>Walks up from the test assembly directory until it finds the repo root (the dir with .git).</summary>
    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!);

        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, ".git")) ||
                File.Exists(Path.Combine(dir.FullName, ".git")))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            "Could not locate the repo root (no .git found walking up from the test assembly).");
    }
}
