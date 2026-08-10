namespace Lumen.Domain.Entities;

/// <summary>
/// A registered push-notification device for a user. The P2 crypto-shred job DELETES all
/// user_devices rows for the user — right-to-erasure removes device records entirely (§F).
/// </summary>
/// <remarks>
/// <para><b>The natural key is <c>(UserId, PushToken)</c> and it is UNIQUE</b> (migration
/// <c>20260614150634</c>). <c>POST /me/devices</c> (T15) is therefore an upsert, not an append: the
/// client calls it on every push-token refresh for the life of an install, so a blind insert would
/// violate that index the second time and surface as a 500 on the app's most routine background call.
/// The index is <b>unfiltered</b> in the trivial sense — this table has no <c>DeletedAt</c> column at
/// all, so §G9's tombstone-revival regime does not apply to it.</para>
///
/// <para><b>The token is PII (§F).</b> It is never echoed in a response, never logged (T8's
/// <c>PiiRedactionEnricher</c> redacts the name <c>pushToken</c> outright), and it is
/// <b>hard-deleted</b> on erasure rather than made unreadable. Encryption at rest is deliberately out
/// of scope for P4a and is an open P9a precondition.</para>
///
/// <para><b>A token names ONE account.</b> The unique key is per user, so the database would happily
/// hold one token on two rows — see <c>DeviceRegistrationService</c> for why registering a token
/// detaches it from every other user, and what that leaves P9a to do.</para>
/// </remarks>
public class UserDevice
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>One of <see cref="Platforms"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string Platform { get; set; } = string.Empty;

    /// <summary>
    /// The FCM/APNs registration token, at most <see cref="PushTokenMaxLength"/> characters.
    /// <b>PII</b> — see the class remarks.
    /// </summary>
    public string PushToken { get; set; } = string.Empty;

    /// <summary>
    /// When this device last re-registered. <b>Nullable because rows written before T15 existed have
    /// none</b>; every registration through <c>POST /me/devices</c> stamps it, on insert and update
    /// alike, so P9a can retire a device that has stopped calling in.
    /// </summary>
    public DateTimeOffset? LastSeenAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>
    /// The width of the existing <c>push_token varchar(512)</c> column. <b>Not a P4a invention</b>
    /// (§G11 says so explicitly): the column has carried this length since migration
    /// <c>20260614150634</c>. Named here so the EF configuration and the endpoint's validator state
    /// one number — a validator that retyped it would reject at 512 while the column accepted 513, or
    /// worse, let an overlength token through to an opaque <c>DbUpdateException</c>.
    /// </summary>
    public const int PushTokenMaxLength = 512;

    /// <summary>
    /// Canonical <see cref="Platform"/> values — the two ratified device platforms
    /// (definitions.md 2026-07-08, §G10). Append-only: never rename, reorder or remove a member.
    /// </summary>
    /// <remarks>
    /// The code decides which provider P9a dispatches through (FCM or APNs), so a value outside this
    /// set is a device that can never be reached — which is why <c>POST /me/devices</c> rejects one
    /// rather than storing it.
    /// </remarks>
    public static class Platforms
    {
        public const string Ios = "ios";
        public const string Android = "android";

        public static readonly IReadOnlyList<string> All = [Ios, Android];
    }
}
