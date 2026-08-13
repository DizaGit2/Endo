using System.Security.Cryptography;
using System.Text;
using Lumen.Api.Onboarding;
using Lumen.Application.Auth;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Unit tests for <see cref="OnboardingService"/> — the extracted POST /onboarding/start logic
/// (P3c-T2). DbContext is Sqlite in-memory (kept alive via an open connection for the test's
/// lifetime); Sqlite is lenient enough to create the whole model, including the Postgres-only
/// <c>jsonb</c> columns on AdminAuditLog, which this suite never touches. Keycloak and the Vault
/// key wrapper are hand-rolled fakes; the real <see cref="AesGcmFieldCipher"/> is used since it's
/// a pure unit with no external dependencies.
/// </summary>
public sealed class OnboardingServiceTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly LumenDbContext _db;
    private readonly FakeKeycloakAdmin _keycloak = new();
    private readonly FakeKeyWrapper _keyWrapper = new();
    private readonly FakeEmailHasher _emailHasher = new();
    private readonly VaultOptions _vaultOptions = new() { KeyName = "test-kek" };

    public OnboardingServiceTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();
        var options = new DbContextOptionsBuilder<LumenDbContext>().UseSqlite(_connection).Options;
        _db = new LumenDbContext(options);
        _db.Database.EnsureCreated();
    }

    public void Dispose()
    {
        _db.Dispose();
        _connection.Dispose();
    }

    // --- helpers ------------------------------------------------------------

    private OnboardingService CreateSut() =>
        new(_db, _keycloak, _keyWrapper, _emailHasher, new AesGcmFieldCipher(), _vaultOptions, TimeProvider.System);

    private static OnboardingStartRequest ValidRequest(
        string? email = "user@example.com",
        string? password = "Sup3rSecretPassw0rd!",
        string? displayName = "María José",
        string? locale = "es-ES",
        string? timezone = "Europe/Madrid",
        string? policyVersion = "v1-test")
        // Null-forgiving: Email/Password are non-nullable on the record, but a client can still
        // send a null over the wire (nullable annotations aren't enforced at runtime), and the
        // "missing/empty email or password" validation branch must handle exactly that.
        => new(email!, password!, displayName, locale, timezone, policyVersion);

    // --- validation: email / password required -------------------------------
    //
    // Every case below pins BOTH halves of OnboardingStartResult.Invalid (T4). The message strings are
    // GRANDFATHERED and asserted as literals: they predate ValidationMessages, they are already on the
    // wire, and rewording one would be a contract change dressed up as a copy edit. The `Field` is the
    // camelCase JSON field name the client attaches the message to — "request" (the reserved
    // ValidationProblemBuilder key) whenever no single input owns the error.

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Missing_or_empty_email_is_invalid(string? email)
    {
        var result = await CreateSut().StartAsync(ValidRequest(email: email), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("request"); // neither field alone owns "one of the two is missing"
        invalid.Error.ShouldBe("email and password are required");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Missing_or_empty_password_is_invalid(string? password)
    {
        var result = await CreateSut().StartAsync(ValidRequest(password: password), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("request");
        invalid.Error.ShouldBe("email and password are required");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    // --- validation: email format ---------------------------------------------

    [Fact]
    public async Task Malformed_email_is_invalid()
    {
        var result = await CreateSut().StartAsync(ValidRequest(email: "not-an-email"), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("email");
        invalid.Error.ShouldBe("invalid email format");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    [Fact]
    public async Task Non_canonical_email_is_invalid()
    {
        // MailAddress.TryCreate DOES parse this (display-name + angle-bracket address), but the
        // recovered .Address ("inner@example.com") does not round-trip to the original string —
        // exercising the `parsed.Address != email` half of the check, distinct from a bare parse
        // failure (verified empirically: TryCreate returns true, Address != the raw input).
        var result = await CreateSut().StartAsync(
            ValidRequest(email: "display name <inner@example.com>"), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("email");
        invalid.Error.ShouldBe("invalid email format");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    // --- validation: password length -----------------------------------------

    [Theory]
    [InlineData(11)]  // one under the 12 minimum
    [InlineData(129)] // one over the 128 maximum
    public async Task Password_outside_12_to_128_chars_is_invalid(int length)
    {
        var result = await CreateSut().StartAsync(
            ValidRequest(password: new string('a', length)), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("password");
        invalid.Error.ShouldBe("password must be between 12 and 128 characters");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    // --- validation: field max lengths ---------------------------------------

    [Fact]
    public async Task Overlength_display_name_is_invalid()
    {
        var result = await CreateSut().StartAsync(
            ValidRequest(displayName: new string('a', 201)), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        // One message covers four fields, so it cannot name the offending input — "request" is the
        // honest key. Splitting it per field would change the four grandfathered strings.
        invalid.Field.ShouldBe("request");
        invalid.Error.ShouldBe("a field exceeds its maximum length");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    [Fact]
    public async Task Overlength_locale_is_invalid()
    {
        var result = await CreateSut().StartAsync(
            ValidRequest(locale: new string('a', 36)), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("request");
        invalid.Error.ShouldBe("a field exceeds its maximum length");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    [Fact]
    public async Task Overlength_timezone_is_invalid()
    {
        var result = await CreateSut().StartAsync(
            ValidRequest(timezone: new string('a', 65)), CancellationToken.None);

        // Length is checked before the IANA lookup, so an overlength zone id keeps the grandfathered
        // message rather than becoming the new timezone error.
        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("request");
        invalid.Error.ShouldBe("a field exceeds its maximum length");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    [Fact]
    public async Task Overlength_policy_version_is_invalid()
    {
        var result = await CreateSut().StartAsync(
            ValidRequest(policyVersion: new string('a', 65)), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("request");
        invalid.Error.ShouldBe("a field exceeds its maximum length");
        _keycloak.CreateCalls.ShouldBeEmpty();
    }

    // --- validation: timezone must be a real IANA zone (T4) -----------------------
    //
    // Until T4 this was a length check only, so "Mars/Olympus" persisted happily. That is not a
    // cosmetic defect: P4a resolves the user's local day on every request (D-12), and UserDayResolver
    // logs a PII-free WARN each time a zone id fails to resolve — so one bad value emits a warning per
    // request, forever. T4 also puts `timezone` on PATCH /me, which would hand that lever to the user.

    [Fact]
    public async Task Unknown_timezone_is_rejected()
    {
        var result = await CreateSut().StartAsync(ValidRequest(timezone: "Mars/Olympus"), CancellationToken.None);

        var invalid = result.ShouldBeOfType<OnboardingStartResult.Invalid>();
        invalid.Field.ShouldBe("timezone");
        invalid.Error.ShouldBe("value is not a recognized IANA time zone");
        _keycloak.CreateCalls.ShouldBeEmpty(); // rejected before any Keycloak identity is provisioned
    }

    [Fact]
    public async Task Valid_iana_timezone_is_accepted()
    {
        // Deliberately not the column default, and deliberately a three-segment id: the check must be
        // a real TimeZoneInfo lookup, not a shape heuristic.
        const string timezone = "America/Argentina/Buenos_Aires";

        var result = await CreateSut().StartAsync(ValidRequest(timezone: timezone), CancellationToken.None);

        var success = result.ShouldBeOfType<OnboardingStartResult.Success>();
        (await _db.Users.SingleAsync(u => u.Id == success.UserId)).Timezone.ShouldBe(timezone);
    }

    [Fact]
    public async Task Null_timezone_is_accepted()
    {
        // Absent stays valid — the field is optional and falls back to the users.timezone default.
        var result = await CreateSut().StartAsync(ValidRequest(timezone: null), CancellationToken.None);

        var success = result.ShouldBeOfType<OnboardingStartResult.Success>();
        (await _db.Users.SingleAsync(u => u.Id == success.UserId)).Timezone.ShouldBe("Europe/Madrid");
    }

    [Fact]
    public async Task Null_locale_is_accepted()
    {
        var result = await CreateSut().StartAsync(ValidRequest(locale: null), CancellationToken.None);

        var success = result.ShouldBeOfType<OnboardingStartResult.Success>();
        (await _db.Users.SingleAsync(u => u.Id == success.UserId)).Locale.ShouldBe("es-ES");
    }

    // --- defaults --------------------------------------------------------------

    [Fact]
    public async Task Null_locale_timezone_and_policy_version_fall_back_to_defaults()
    {
        var request = ValidRequest(locale: null, timezone: null, policyVersion: null);

        var result = await CreateSut().StartAsync(request, CancellationToken.None);

        var success = result.ShouldBeOfType<OnboardingStartResult.Success>();
        var user = await _db.Users.SingleAsync(u => u.Id == success.UserId);
        user.Locale.ShouldBe("es-ES");
        user.Timezone.ShouldBe("Europe/Madrid");

        var consent = await _db.ConsentRecords.SingleAsync(c => c.UserId == success.UserId);
        consent.PolicyVersion.ShouldBe("v1-draft");
    }

    // --- happy path --------------------------------------------------------------

    [Fact]
    public async Task Happy_path_persists_all_four_tables_with_encrypted_display_name()
    {
        const string displayName = "María José";

        var result = await CreateSut().StartAsync(ValidRequest(displayName: displayName), CancellationToken.None);

        var success = result.ShouldBeOfType<OnboardingStartResult.Success>();
        (await _db.Users.CountAsync(u => u.Id == success.UserId)).ShouldBe(1);
        (await _db.ConsentRecords.CountAsync(c => c.UserId == success.UserId)).ShouldBe(1);
        (await _db.UserKeys.CountAsync(k => k.UserId == success.UserId)).ShouldBe(1);

        var profile = await _db.UserProfiles.SingleAsync(p => p.UserId == success.UserId);
        profile.DisplayNameEnc.ShouldNotBeNull();
        profile.DisplayNameEnc.ShouldNotBe(Encoding.UTF8.GetBytes(displayName)); // ciphertext, not plaintext
        Encoding.UTF8.GetString(profile.DisplayNameEnc!).ShouldNotContain("María");

        _keycloak.CreateCalls.ShouldHaveSingleItem();
        _keycloak.DeleteCalls.ShouldBeEmpty(); // no compensation needed on the happy path
    }

    // --- email hash: Vault Transit HMAC, not raw SHA-256 (P3c-T3) --------------------

    [Fact]
    public async Task Persisted_email_hash_comes_from_the_email_hasher_not_a_raw_sha256_digest()
    {
        const string email = "user@example.com";

        var result = await CreateSut().StartAsync(ValidRequest(email: email), CancellationToken.None);

        var success = result.ShouldBeOfType<OnboardingStartResult.Success>();
        var user = await _db.Users.SingleAsync(u => u.Id == success.UserId);

        user.EmailHash.ShouldBe(FakeEmailHasher.FakeHmac);
        _emailHasher.HashCalls.ShouldBe([email]);

        // Negative control: proves there is no raw-SHA fallback left in the production code path.
        user.EmailHash.ShouldNotBe(Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(email))));
    }

    // --- compensation --------------------------------------------------------------

    [Fact]
    public async Task KeyWrapper_failure_after_keycloak_create_compensates_and_rethrows()
    {
        _keyWrapper.ThrowOnWrap = new InvalidOperationException("vault unreachable");

        var thrown = await Should.ThrowAsync<InvalidOperationException>(
            () => CreateSut().StartAsync(ValidRequest(), CancellationToken.None));

        thrown.Message.ShouldBe("vault unreachable");
        _keycloak.CreateCalls.ShouldHaveSingleItem();
        _keycloak.DeleteCalls.ShouldHaveSingleItem();
        _keycloak.DeleteCalls[0].ShouldBe(_keycloak.UserIdToReturn);
        (await _db.Users.CountAsync()).ShouldBe(0); // the transaction never began — no orphaned rows
    }

    // --- duplicate propagation --------------------------------------------------------------

    [Fact]
    public async Task Keycloak_duplicate_user_exception_propagates_uncaught()
    {
        _keycloak.ThrowOnCreate = new DuplicateUserException("An account with that email already exists.");

        var thrown = await Should.ThrowAsync<DuplicateUserException>(
            () => CreateSut().StartAsync(ValidRequest(), CancellationToken.None));

        thrown.Message.ShouldBe("An account with that email already exists.");
        _keycloak.DeleteCalls.ShouldBeEmpty(); // create itself failed — nothing was provisioned to compensate
    }
}
