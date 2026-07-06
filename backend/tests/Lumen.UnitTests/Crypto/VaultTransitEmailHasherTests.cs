using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Lumen.Infrastructure.Crypto;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Crypto;

/// <summary>
/// Unit tests for <see cref="VaultTransitEmailHasher"/> against a fake <see cref="HttpMessageHandler"/>
/// — no live Vault required. Pins the exact request shape Vault's Transit HMAC endpoint expects
/// (P3c-T3) and proves a non-success response surfaces as an exception.
/// </summary>
public sealed class VaultTransitEmailHasherTests
{
    private static readonly VaultOptions Options = new()
    {
        Address = "http://127.0.0.1:8200",
        Token = "root",
        EmailHmacKeyName = "lumen-dev-email-hmac",
    };

    /// <summary>Captures the single request it receives and returns a canned response.</summary>
    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        public string? LastRequestBody { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            LastRequestBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(ct);
            return respond(request);
        }
    }

    [Fact]
    public async Task Sends_expected_request_and_returns_hmac_verbatim()
    {
        var handler = new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = JsonContent.Create(new { data = new { hmac = "vault:v1:abc123==" } }),
        });
        var sut = new VaultTransitEmailHasher(new HttpClient(handler), Options);

        var result = await sut.HashEmailAsync("user@example.com");

        result.ShouldBe("vault:v1:abc123==");

        var request = handler.LastRequest.ShouldNotBeNull();
        request.Method.ShouldBe(HttpMethod.Post);
        request.RequestUri.ShouldNotBeNull();
        request.RequestUri!.AbsolutePath.ShouldBe("/v1/transit/hmac/lumen-dev-email-hmac/sha2-256");
        request.Headers.GetValues("X-Vault-Token").ShouldContain("root");

        using var body = JsonDocument.Parse(handler.LastRequestBody!);
        body.RootElement.GetProperty("input").GetString()
            .ShouldBe(Convert.ToBase64String(Encoding.UTF8.GetBytes("user@example.com")));
        body.RootElement.GetProperty("key_version").GetInt32().ShouldBe(1);
    }

    [Fact]
    public async Task Non_success_status_throws()
    {
        var handler = new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError));
        var sut = new VaultTransitEmailHasher(new HttpClient(handler), Options);

        await Should.ThrowAsync<HttpRequestException>(() => sut.HashEmailAsync("user@example.com"));
    }
}
