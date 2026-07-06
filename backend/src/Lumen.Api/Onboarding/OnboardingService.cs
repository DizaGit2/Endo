using System.Security.Cryptography;
using System.Text;
using Lumen.Application.Auth;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Onboarding;

/// <summary>
/// Creates the Keycloak user, provisions the Vault-wrapped DEK, and writes the encrypted profile +
/// consent (POST /onboarding/start). Extracted from the minimal-API handler verbatim (P3c-T2) to
/// create a unit-test seam — this is a mechanical move, not a rewrite.
/// </summary>
public sealed class OnboardingService(
    LumenDbContext db,
    IKeycloakAdmin keycloak,
    IKeyWrapper keyWrapper,
    IFieldCipher cipher,
    VaultOptions vaultOptions,
    TimeProvider clock)
{
    public async Task<OnboardingStartResult> StartAsync(OnboardingStartRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
            return new OnboardingStartResult.Invalid("email and password are required");

        // One canonical email form used for BOTH Keycloak (username/email) and the lookup hash.
        var email = request.Email.Trim().ToLowerInvariant();
        if (!System.Net.Mail.MailAddress.TryCreate(email, out var parsed) || parsed.Address != email)
            return new OnboardingStartResult.Invalid("invalid email format");
        if (request.Password.Length is < 12 or > 128) // D-01 minimum; defense-in-depth with the realm policy
            return new OnboardingStartResult.Invalid("password must be between 12 and 128 characters");
        if ((request.DisplayName?.Length ?? 0) > 200 || (request.Locale?.Length ?? 0) > 35 ||
            (request.Timezone?.Length ?? 0) > 64 || (request.PolicyVersion?.Length ?? 0) > 64)
            return new OnboardingStartResult.Invalid("a field exceeds its maximum length");

        var userId = await keycloak.CreateUserAsync(email, request.Password, ct);

        try
        {
            var now = clock.GetUtcNow();
            var emailHash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(email)));
            var locale = string.IsNullOrWhiteSpace(request.Locale) ? "es-ES" : request.Locale;
            var timezone = string.IsNullOrWhiteSpace(request.Timezone) ? "Europe/Madrid" : request.Timezone;

            // Vault wrap + field encryption BEFORE the transaction, so we never hold a pooled DB connection
            // across external HTTP round-trips. The plaintext DEK is zeroed before any DB work.
            var dek = RandomNumberGenerator.GetBytes(32);
            byte[] wrappedDek;
            byte[]? displayNameEnc = null;
            try
            {
                wrappedDek = await keyWrapper.WrapAsync(dek, ct);
                if (!string.IsNullOrWhiteSpace(request.DisplayName))
                    displayNameEnc = cipher.EncryptString(request.DisplayName, dek);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(dek);
            }

            // Atomic Lumen-side state — all rows commit together or not at all.
            await using var transaction = await db.Database.BeginTransactionAsync(ct);

            db.Users.Add(new User
            {
                Id = userId,
                EmailHash = emailHash,
                Locale = locale,
                Timezone = timezone,
                CreatedAt = now,
                UpdatedAt = now,
            });
            db.ConsentRecords.Add(new ConsentRecord
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                PolicyVersion = string.IsNullOrWhiteSpace(request.PolicyVersion) ? "v1-draft" : request.PolicyVersion,
                Locale = locale,
                ConsentedAt = now,
            });
            db.UserKeys.Add(new UserKey
            {
                UserId = userId,
                WrappedDek = wrappedDek,
                KeyVersion = 1,
                VaultKeyName = vaultOptions.KeyName,
                CreatedAt = now,
            });
            if (displayNameEnc is not null)
            {
                db.UserProfiles.Add(new UserProfileEnc
                {
                    UserId = userId,
                    DisplayNameEnc = displayNameEnc,
                    CreatedAt = now,
                    UpdatedAt = now,
                });
            }
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return new OnboardingStartResult.Success(userId);
        }
        catch
        {
            // The Keycloak identity was created but Lumen-side state failed — remove the orphan (best effort)
            // so the email is not permanently bricked for sign-up.
            try { await keycloak.DeleteUserAsync(userId, ct); } catch { /* compensation is best-effort */ }
            throw;
        }
    }
}
