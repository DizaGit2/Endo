using Lumen.Application.Auth;
using Lumen.Application.Time;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Api.Time;

/// <summary>
/// <see cref="IUserDayContext"/> over the current request's JWT and the <c>users</c> table.
/// Registered scoped; the memo field needs no synchronisation because one instance serves exactly
/// one request, whose handler pipeline is sequential.
/// </summary>
public sealed class UserDayContext(
    ICurrentUserAccessor current,
    LumenDbContext db,
    IUserDayResolver dayResolver,
    TimeProvider clock) : IUserDayContext
{
    private UserDayInfo? _info;
    private bool _loaded;

    public async Task<UserDayInfo?> GetAsync(CancellationToken ct)
    {
        if (_loaded) return _info;

        var userId = current.UserId;

        // NO IgnoreQueryFilters(): the User soft-delete filter is load-bearing here. A crypto-shredded
        // user must resolve to null so every P4a endpoint 404s on their still-valid token (§F / D-13).
        var user = await db.Users.AsNoTracking()
            .Where(u => u.Id == userId)
            .Select(u => new { u.Id, u.Timezone, u.CreatedAt })
            .FirstOrDefaultAsync(ct);

        _loaded = true; // memoise the miss too — a 404 must not re-query on every validator
        if (user is null) return _info = null;

        // One instant for the whole request (plan §2), so Today and any timestamp stamped from
        // NowUtc are guaranteed to describe the same moment.
        var now = clock.GetUtcNow();

        _info = new UserDayInfo(
            UserId: user.Id,
            Today: dayResolver.ToUserDay(now, user.Timezone),
            // Two years back from the user-local creation DAY (not the UTC day, and not the raw
            // instant). DateOnly.AddYears clamps 29 February to the 28th in a non-leap year.
            BackdateFloor: dayResolver.ToUserDay(user.CreatedAt, user.Timezone).AddYears(-2),
            TimezoneId: user.Timezone,
            NowUtc: now);

        return _info;
    }
}
