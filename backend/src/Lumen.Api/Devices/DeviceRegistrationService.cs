using Lumen.Api.Persistence;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Devices;

/// <summary>
/// The §C.9 push-device resource: <c>POST /me/devices</c>, the upsert onto the pre-existing
/// <c>user_devices</c> table (migration <c>20260614150634</c> — §G4/§G14 forbid a new one).
/// Registered scoped, alongside the request-scoped <see cref="IUserDayContext"/> it depends on.
/// </summary>
/// <remarks>
/// <para><b>1. A null day context is a 404, before anything else happens.</b> Erasure has no write
/// fence behind it: a crypto-shred tombstones the <c>users</c> row, but the account's JWT stays
/// cryptographically valid until it expires and inserting a child row takes only a share lock on
/// <c>users</c>, which does not conflict with the shred job's UPDATE. Resolving the day context FIRST
/// and returning "not found" on null is the whole of the defence — which is why it is checked before
/// validation, and (see rule 4) before the cross-user detach.</para>
///
/// <para><b>2. Validate then act (T3).</b> Every field error is collected before the first write, so a
/// rejected request has changed nothing.</para>
///
/// <para><b>3. This is an UPSERT on the existing unique <c>(UserId, PushToken)</c>, and it is the P4a
/// endpoint most likely to race with itself.</b> The client calls it on first launch and on every
/// push-token refresh for the life of the install, so two app processes waking together — a
/// notification tap during a cold start — can both miss the lookup and both insert. The loser gets a
/// <c>23505</c> on an index the user cannot see and has no way to work around, which is why the write
/// runs inside <see cref="ConcurrencyRetry"/> (§G12: owned by T10, reused here). §G9 does <b>not</b>
/// apply: <c>user_devices</c> has no <c>DeletedAt</c> column and no query filter, so there is no
/// tombstone to revive and <b>no <c>IgnoreQueryFilters()</c> anywhere on this path</b>. Erasure
/// hard-deletes these rows (§F/T8).</para>
///
/// <para><b>4. Registering a token DETACHES it from every OTHER user, and that is a deliberate,
/// deliberately-narrow exception to "never touch another tenant's row".</b> The unique index is
/// <c>(UserId, PushToken)</c>, so the database is perfectly happy to hold one token on two rows. That
/// state is not hypothetical — a phone handed on, or an app reinstalled under a different account,
/// keeps the same FCM/APNs registration token, because the token addresses the app <i>install</i> and
/// not the account. Leaving the old row behind means P9a delivers "your period is predicted to start
/// tomorrow" to a handset somebody else is now signed in on: a disclosure of special-category data to
/// the wrong person, which is the failure this codebase consistently ranks worst. The usual provider
/// mechanism does not save us — FCM only reports <c>NotRegistered</c> for an <i>invalid</i> token, and
/// in the handover case the token is perfectly valid — and <b>P4a ships no unregister endpoint at
/// all</b>, so a stale row would be permanent until P9a. So the account that last proved possession of
/// the token owns the device, and every other row carrying it is removed in the same unit of work.
/// <list type="bullet">
///   <item><b>The cost, stated plainly:</b> anyone holding a victim's push token can unregister their
///   device. That is bounded — a registration token is high-entropy, is never logged (T8 redacts
///   <c>pushToken</c>), is never echoed in a response, and reaches nobody but the client and the
///   provider — and it is <b>self-healing</b>, because the victim's app re-registers on its next
///   launch or token refresh, which is exactly what this endpoint exists for. It costs a notification,
///   not data. The 404 fence above runs first, so an erased token cannot pull the lever at all.</item>
///   <item><b>What this obliges P9a to do:</b> after T15 a token names one account <i>in practice</i>,
///   but the index still does not <i>enforce</i> that — two users registering the same token
///   concurrently can interleave — so the dispatcher must still tolerate finding more than one row for
///   a token and prefer the most recent <see cref="UserDevice.LastSeenAt"/>. P9a also owns the proper
///   fix this endpoint cannot ship: an unregister call on sign-out, and deleting on the provider's
///   <c>NotRegistered</c>.</item>
///   <item><b>T19</b> (the phase-wide tenant-isolation suite) must read this row as the one endpoint
///   that writes across tenants on purpose. Its isolation guarantee here is narrower and precise: a
///   caller can never <i>read</i> or <i>modify</i> another user's device, and can only remove a row
///   whose token it demonstrably holds.</item>
/// </list></para>
///
/// <para><b>5. The token is PII and never leaves the row (§F).</b> It is absent from
/// <see cref="RegisterDeviceResponse"/> by construction, absent from every log line (T8's
/// <c>PiiRedactionEnricher</c> redacts the name <c>pushToken</c>), and nothing in this file logs at
/// all. Encryption at rest stays out of scope — an open P9a precondition.</para>
///
/// <para><b>6. WARNING — <see cref="RegisterAsync"/> CLEARS THE WHOLE CHANGE TRACKER, so a caller must
/// not stage un-saved work before invoking it.</b> Its <see cref="ConcurrencyRetry"/> action calls
/// <c>ChangeTracker.Clear()</c> to be re-runnable, and that acts on the request-scoped
/// <c>LumenDbContext</c>: anything staged earlier in the same scope is <b>silently discarded</b>.
/// <see cref="StageRegistrationAsync"/> is the deliberate opposite — it <b>stages only</b>, exactly so
/// T17 can compose it. See its own remarks.</para>
/// </remarks>
public sealed class DeviceRegistrationService(LumenDbContext db, IUserDayContext dayContext)
{
    /// <summary>
    /// Registers (or re-registers) the caller's push device. Answers <b>200 with the stored row minus
    /// its token</b> on both the insert and the update paths.
    /// </summary>
    /// <remarks>
    /// <b>Not composable.</b> This method owns the whole unit of work and clears the change tracker
    /// (rule 6). A later task that needs to write a device row alongside something else must call
    /// <see cref="StageRegistrationAsync"/> from inside its own single retried action instead — which
    /// is exactly what T17's <c>POST /onboarding/notifications</c> does.
    /// </remarks>
    public async Task<DeviceRegistrationResult> RegisterAsync(RegisterDeviceRequest request, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(request);

        // Rule 1: the 404 fence comes first, so a body that would be a 400 still answers "no such
        // user" for an erased token — and so an erased token can never reach the detach in rule 4.
        var day = await dayContext.GetAsync(ct);
        if (day is null) return new DeviceRegistrationResult.UserNotFound();

        var errors = new List<DeviceFieldError>();

        var platform = Trimmed(request.Platform);
        if (platform is null)
            errors.Add(new DeviceFieldError("platform", ValidationMessages.Required));
        else if (!UserDevice.Platforms.All.Contains(platform, StringComparer.Ordinal))
            errors.Add(new DeviceFieldError("platform", ValidationMessages.NotAllowedValue));

        // Trim first: the cap bounds the token, not a trailing newline — the same rule `notes` follows.
        var pushToken = Trimmed(request.PushToken);
        if (pushToken is null)
            errors.Add(new DeviceFieldError("pushToken", ValidationMessages.Required));
        else if (pushToken.Length > UserDevice.PushTokenMaxLength)
        {
            errors.Add(new DeviceFieldError(
                "pushToken", ValidationMessages.MaxLength(UserDevice.PushTokenMaxLength)));
        }

        if (errors.Count > 0) return new DeviceRegistrationResult.Invalid(errors);

        var now = day.NowUtc; // one instant for the whole request (plan §2), never a re-read clock

        return await ConcurrencyRetry.ExecuteAsync<DeviceRegistrationResult>(async token =>
        {
            // The action must be genuinely re-runnable: a second attempt happens only because the
            // first one's INSERT lost a race, and that insert is still sitting in the tracker.
            // Whole-context, hence rule 6's caller restriction.
            db.ChangeTracker.Clear();

            var row = await StageRegistrationAsync(day.UserId, platform!, pushToken!, now, token);
            await db.SaveChangesAsync(token);

            return new DeviceRegistrationResult.Saved(ToResponse(row));
        }, ct);
    }

    /// <summary>
    /// Stages the device upsert for <paramref name="userId"/> — and the rule-4 detach of the same
    /// token from every other user — without saving. <b>Shared with T17's
    /// <c>POST /onboarding/notifications</c>, which must not duplicate it</b> (§G12).
    /// </summary>
    /// <remarks>
    /// <para><b>THIS METHOD STAGES ONLY. It calls no <c>SaveChangesAsync</c>, no
    /// <c>ChangeTracker.Clear()</c> and no <see cref="ConcurrencyRetry"/>, and it must never start
    /// to.</b> That is §G12's unit-of-work rule, and it exists because <see cref="ConcurrencyRetry"/>
    /// recovers via <c>ChangeTracker.Clear()</c> — a <b>whole-context</b> operation on the
    /// request-scoped <c>LumenDbContext</c>. T17 composes two writes in one request: this device row
    /// AND the four <c>user_notification_prefs</c> rows. If this method cleared the tracker or saved on
    /// its own, T17's other staged writes would be <b>silently discarded</b> — no exception, no failing
    /// test, just a lost onboarding answer.</para>
    ///
    /// <para><b>So the contract for T17 is:</b> resolve the day context, validate the request, then
    /// open exactly ONE <see cref="ConcurrencyRetry"/> action that clears the tracker, stages the
    /// preference rows, calls this method, and saves once. That exact shape is pinned by
    /// <c>DeviceRegistrationServiceTests.StageRegistrationAsync_composes_inside_ONE_ConcurrencyRetry_action_the_way_T17_will</c>,
    /// and <c>..._STAGES_ONLY_so_T17_can_compose_it_with_another_write</c> fails the moment a save or a
    /// clear is added here.</para>
    ///
    /// <para><b>The detach is a TRACKED delete, never <c>ExecuteDeleteAsync</c>.</b> ExecuteDelete
    /// issues its own statement immediately, outside the caller's <c>SaveChanges</c> transaction — so a
    /// composed unit of work that failed afterwards would already have unregistered the other user's
    /// device, with no way back. Staged, the delete and the insert commit or roll back together.</para>
    ///
    /// <para><b>The two guards below are PROGRAMMING-ERROR guards</b> on a caller expected to have
    /// validated already: <see cref="RegisterAsync"/> owns the 400. Storing an out-of-vocabulary
    /// platform would leave a device P9a can never dispatch to, and an overlength token would surface
    /// as an opaque <c>DbUpdateException</c> from the caller's own save.</para>
    /// </remarks>
    /// <param name="userId">The registering user. Taken explicitly because T17 has already resolved it.</param>
    /// <param name="platform">One of <see cref="UserDevice.Platforms"/>.</param>
    /// <param name="pushToken">
    /// The already-trimmed token, 1–<see cref="UserDevice.PushTokenMaxLength"/> characters.
    /// </param>
    /// <param name="now">The caller's single instant for the whole request (plan §2).</param>
    /// <returns>The staged entity, tracked and <b>unsaved</b>.</returns>
    /// <exception cref="ArgumentException">
    /// <paramref name="platform"/> is outside the ratified vocabulary, or <paramref name="pushToken"/>
    /// is blank or longer than the column allows.
    /// </exception>
    public async Task<UserDevice> StageRegistrationAsync(
        Guid userId,
        string platform,
        string pushToken,
        DateTimeOffset now,
        CancellationToken ct)
    {
        if (!UserDevice.Platforms.All.Contains(platform, StringComparer.Ordinal))
        {
            throw new ArgumentException(
                $"'{platform}' is not a ratified device platform; the caller validates this before staging.",
                nameof(platform));
        }

        // The token itself is never quoted in an exception message: §F keeps it out of every log line,
        // and PiiRedactionEnricher walks log PROPERTIES, not exception messages (its known gap).
        if (string.IsNullOrWhiteSpace(pushToken) || pushToken.Length > UserDevice.PushTokenMaxLength)
        {
            throw new ArgumentException(
                $"the push token must be 1–{UserDevice.PushTokenMaxLength} characters; the caller " +
                "validates this before staging.",
                nameof(pushToken));
        }

        // NO ChangeTracker.Clear() here: the caller may already have staged its own rows.
        // No IgnoreQueryFilters() either — user_devices has no DeletedAt and no query filter (rule 3).
        var rows = await db.UserDevices.Where(d => d.PushToken == pushToken).ToListAsync(ct);

        // Rule 4: the account that last proved possession owns the device. Removing the others is
        // staged, not executed, so it shares the caller's transaction.
        foreach (var foreign in rows.Where(d => d.UserId != userId)) db.UserDevices.Remove(foreign);

        var row = rows.Find(d => d.UserId == userId);
        if (row is null)
        {
            row = new UserDevice
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                PushToken = pushToken,
                CreatedAt = now,
            };
            db.UserDevices.Add(row);
        }

        // Both fields move on a re-registration. Platform because a restored install can genuinely
        // change it, and a stale value sends P9a's dispatcher to the wrong provider; LastSeenAt
        // because that is what a re-registration is FOR. CreatedAt is deliberately left alone.
        row.Platform = platform;
        row.LastSeenAt = now;

        // NO SaveChangesAsync: the caller owns the single save for the whole unit of work.
        return row;
    }

    // ------------------------------------------------------------------ projection

    /// <summary>Projects the stored row onto the wire — <b>without its token</b> (rule 5).</summary>
    private static RegisterDeviceResponse ToResponse(UserDevice row) => new(
        row.Id,
        row.Platform,
        // Non-null by construction: StageRegistrationAsync stamps LastSeenAt on every path, insert and
        // update alike. The column stays nullable only for rows written before this endpoint existed.
        row.LastSeenAt!.Value,
        row.CreatedAt);

    /// <summary>
    /// Blank is absent, matching <c>PATCH /me</c> and <c>PATCH /settings/cycle</c>: an empty or
    /// whitespace-only string is not a value, so it is reported as a missing field rather than stored.
    /// </summary>
    private static string? Trimmed(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
