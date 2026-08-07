using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Lumen.Api.Persistence;

/// <summary>
/// One retry for the lost race in a read-then-upsert (§G12: owned by T10, reused by T15).
///
/// <para><b>The race.</b> Every P4a upsert looks its row up by a natural key and inserts when it
/// finds nothing. Two requests from the same account — the phone retrying a request the user thinks
/// timed out, or the quick-check-in sheet double-tapped — can both miss the lookup and both try to
/// insert the same key. Postgres serialises them at the unique index: one commits, the other gets
/// <c>23505</c>, which EF Core surfaces as a <see cref="DbUpdateException"/> and the API surfaces as
/// a 500. The row the loser wanted now exists, so simply running the operation again succeeds — the
/// lookup finds the winner's row and updates it, which is exactly what the user asked for.</para>
///
/// <para><b>Why a helper and not a <c>try/catch</c> in each service.</b> Provoking that race for
/// real needs two requests interleaved between the same two statements, which no test can arrange
/// deterministically. Behind this delegate the retry is a fake that throws on demand, so
/// <c>ConcurrencyRetryTests</c> proves every branch with no database and no flake. Untested
/// defensive code on a write path is worse than none: it looks like a guarantee.</para>
///
/// <para><b>Exactly one retry.</b> A second <c>23505</c> is not a race — the key is genuinely taken
/// by something the action does not account for — and looping would turn a 500 into a hung request.
/// Nothing else is retried: an FK or check violation, a cancellation or a bug is only made worse by
/// running a write twice.</para>
///
/// <para><b>The action must be re-runnable.</b> A failed <c>SaveChanges</c> leaves the losing insert
/// sitting in the change tracker, so a second attempt that only re-queried would try to insert it
/// again and fail identically. Callers therefore start their action with
/// <c>db.ChangeTracker.Clear()</c> and re-read everything they touch — see
/// <see cref="Cycle.CycleDayService"/>. That statement runs on the first attempt too, which is what
/// keeps it covered by the ordinary service tests instead of being reachable only under a real
/// race.</para>
/// </summary>
public static class ConcurrencyRetry
{
    /// <summary>
    /// Postgres <c>unique_violation</c>. The only failure this helper treats as a lost race.
    /// Named rather than inlined so the tests pin the value instead of restating it.
    /// </summary>
    public const string UniqueViolationSqlState = "23505";

    /// <summary>
    /// Runs <paramref name="action"/>, and runs it once more if it lost a unique-key race.
    /// </summary>
    /// <param name="action">
    /// The whole read-then-write operation, not just the <c>SaveChanges</c>. It may run twice, so it
    /// must re-read the state it depends on and must not have side effects outside the transaction.
    /// </param>
    public static async Task<T> ExecuteAsync<T>(Func<CancellationToken, Task<T>> action, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(action);

        try
        {
            return await action(ct);
        }
        catch (DbUpdateException exception) when (IsUniqueViolation(exception))
        {
            // Deliberately no logging here: the caller's arguments are health data (§F), and a lost
            // race that the retry absorbs is not an operational event.
        }

        return await action(ct);
    }

    /// <summary>
    /// Whether the failure is a Postgres duplicate-key violation. Matching on the provider exception
    /// is the point: only Postgres' <c>23505</c> means "another writer took this key", and a
    /// provider that raises something else (Sqlite in the unit suites) must not be retried on a
    /// guess about its message text.
    /// </summary>
    public static bool IsUniqueViolation(DbUpdateException exception) =>
        exception?.InnerException is PostgresException { SqlState: UniqueViolationSqlState };
}
