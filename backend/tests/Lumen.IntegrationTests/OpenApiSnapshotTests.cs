using System.Reflection;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
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
public class OpenApiSnapshotTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string UpdateEnvVar = "LUMEN_OPENAPI_UPDATE";

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

    private static void AssertSpineEndpoints(string normalizedJson)
    {
        using var doc = JsonDocument.Parse(normalizedJson);
        var root = doc.RootElement;

        root.TryGetProperty("paths", out var paths).ShouldBeTrue("emitted doc must have a paths object");

        paths.TryGetProperty("/onboarding/start", out _).ShouldBeTrue("/onboarding/start must be documented");
        paths.TryGetProperty("/health", out _).ShouldBeTrue("/health must be documented");

        paths.TryGetProperty("/me", out var mePath).ShouldBeTrue("/me must be documented");
        mePath.TryGetProperty("get", out _).ShouldBeTrue("GET /me must be documented");
        mePath.TryGetProperty("patch", out _).ShouldBeTrue("PATCH /me must be documented");
        mePath.TryGetProperty("delete", out var deleteOp).ShouldBeTrue("DELETE /me must be documented");

        var deleteResponses = deleteOp.GetProperty("responses");
        deleteResponses.TryGetProperty("202", out _).ShouldBeTrue("DELETE /me must document 202 Accepted");
        deleteResponses.TryGetProperty("401", out _).ShouldBeTrue("DELETE /me must document 401 Unauthorized");

        root.TryGetProperty("components", out var components).ShouldBeTrue("emitted doc must have components");
        components.TryGetProperty("schemas", out var schemas).ShouldBeTrue("emitted doc must have components.schemas");
        schemas.EnumerateObject().Any().ShouldBeTrue("components.schemas must be non-empty");
    }

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
