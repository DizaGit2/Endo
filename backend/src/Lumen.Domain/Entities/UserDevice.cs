namespace Lumen.Domain.Entities;

/// <summary>
/// A registered push-notification device for a user. The P2 crypto-shred job DELETES all
/// user_devices rows for the user — right-to-erasure removes device records entirely (§F).
/// Platform is "ios" or "android".
/// </summary>
public class UserDevice
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Platform { get; set; } = string.Empty;
    public string PushToken { get; set; } = string.Empty;
    public DateTimeOffset? LastSeenAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
