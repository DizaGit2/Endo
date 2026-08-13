using Lumen.Api.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Api;

/// <summary>
/// <see cref="ConcurrencyRetry"/> — the one retry every P4a upsert is wrapped in (§G12, owned by
/// T10, reused by T15).
///
/// <para>The whole reason this is a standalone helper rather than three <c>try/catch</c> blocks
/// inside the services is <b>testability</b>: provoking a genuine unique-violation race against
/// Postgres needs two requests interleaved between the same two statements, which is not something a
/// test can arrange deterministically. With the DB work behind a delegate, every branch below is a
/// fake that throws on demand — no database, no race, no flake — so the retry is proven rather than
/// hoped for. Untested defensive code on a write path is not acceptable here.</para>
///
/// <para><b>Scope, stated so it is not over-read.</b> Everything here is the retry POLICY — when the
/// helper runs the action again and when it must not. It says nothing about whether a retry actually
/// RECOVERS, and it structurally cannot: a fake delegate has no change tracker, so the losing insert
/// that a real second attempt has to clear does not exist in this file. That half lives in
/// <see cref="ConcurrencyRecoveryTests"/>, which stages a lost race against the real services and
/// fails if <c>ChangeTracker.Clear()</c> is deleted from one of them. Do not read a green run here as
/// "the concurrency handling is covered".</para>
///
/// <para>The exception shape is exactly what EF Core surfaces for a duplicate key on Npgsql: a
/// <see cref="DbUpdateException"/> wrapping <see cref="PostgresException"/> with
/// <c>SqlState = 23505</c>. Nothing else is retried — an FK violation, a check violation, a
/// cancellation or a bug would only be made worse by running the write twice.</para>
/// </summary>
public sealed class ConcurrencyRetryTests
{
    private const string ForeignKeyViolation = "23503";

    private static PostgresException Pg(string sqlState) =>
        new("duplicate key value violates unique constraint \"ix_cycle_day_logs_user_day\"", "ERROR", "ERROR", sqlState);

    private static DbUpdateException UniqueViolation() =>
        new("An error occurred while saving the entity changes.", Pg(ConcurrencyRetry.UniqueViolationSqlState));

    // --- the happy path ------------------------------------------------------------------

    [Fact]
    public async Task A_successful_action_runs_exactly_once_and_returns_its_result()
    {
        var calls = 0;

        var result = await ConcurrencyRetry.ExecuteAsync(_ =>
        {
            calls++;
            return Task.FromResult("ok");
        }, CancellationToken.None);

        result.ShouldBe("ok");
        calls.ShouldBe(1);
    }

    [Fact]
    public async Task The_cancellation_token_is_handed_to_the_action()
    {
        using var cts = new CancellationTokenSource();
        CancellationToken seen = default;

        await ConcurrencyRetry.ExecuteAsync(token =>
        {
            seen = token;
            return Task.FromResult(0);
        }, cts.Token);

        seen.ShouldBe(cts.Token);
    }

    // --- the retry -----------------------------------------------------------------------

    [Fact]
    public async Task A_unique_violation_is_retried_exactly_once_and_the_second_result_is_returned()
    {
        var calls = 0;

        var result = await ConcurrencyRetry.ExecuteAsync(_ =>
        {
            calls++;
            if (calls == 1) throw UniqueViolation();
            return Task.FromResult($"attempt {calls}");
        }, CancellationToken.None);

        result.ShouldBe("attempt 2");
        calls.ShouldBe(2, "one retry, not a loop");
    }

    [Fact]
    public async Task A_second_unique_violation_propagates_instead_of_retrying_again()
    {
        // A key that is still taken on the second attempt is not a race — it is a real conflict, and
        // retrying forever would turn a 500 into a hung request.
        var calls = 0;

        var exception = await Should.ThrowAsync<DbUpdateException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(_ =>
            {
                calls++;
                throw UniqueViolation();
            }, CancellationToken.None));

        exception.InnerException.ShouldBeOfType<PostgresException>()
            .SqlState.ShouldBe(ConcurrencyRetry.UniqueViolationSqlState);
        calls.ShouldBe(2);
    }

    // --- what is deliberately NOT retried -------------------------------------------------

    [Fact]
    public async Task A_foreign_key_violation_is_not_retried()
    {
        var calls = 0;

        await Should.ThrowAsync<DbUpdateException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(_ =>
            {
                calls++;
                throw new DbUpdateException("fk", Pg(ForeignKeyViolation));
            }, CancellationToken.None));

        calls.ShouldBe(1);
    }

    [Fact]
    public async Task A_DbUpdateException_with_a_non_Postgres_inner_is_not_retried()
    {
        // Sqlite (the unit suites) and any future provider raise their own exception type. Only the
        // Postgres duplicate-key shape means "someone else won the same key a moment ago".
        var calls = 0;

        await Should.ThrowAsync<DbUpdateException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(_ =>
            {
                calls++;
                throw new DbUpdateException("sqlite", new InvalidOperationException("UNIQUE constraint failed"));
            }, CancellationToken.None));

        calls.ShouldBe(1);
    }

    [Fact]
    public async Task A_DbUpdateException_with_no_inner_exception_is_not_retried()
    {
        var calls = 0;

        await Should.ThrowAsync<DbUpdateException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(_ =>
            {
                calls++;
                throw new DbUpdateException("bare");
            }, CancellationToken.None));

        calls.ShouldBe(1);
    }

    [Fact]
    public async Task An_unrelated_exception_is_not_retried()
    {
        var calls = 0;

        await Should.ThrowAsync<InvalidOperationException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(_ =>
            {
                calls++;
                throw new InvalidOperationException("boom");
            }, CancellationToken.None));

        calls.ShouldBe(1);
    }

    [Fact]
    public async Task A_cancellation_is_not_retried()
    {
        var calls = 0;

        await Should.ThrowAsync<OperationCanceledException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(_ =>
            {
                calls++;
                throw new OperationCanceledException();
            }, CancellationToken.None));

        calls.ShouldBe(1);
    }

    // --- guards --------------------------------------------------------------------------

    [Fact]
    public async Task A_null_action_is_rejected()
    {
        await Should.ThrowAsync<ArgumentNullException>(() =>
            ConcurrencyRetry.ExecuteAsync<string>(null!, CancellationToken.None));
    }

    [Fact]
    public void The_retried_sql_state_is_frozen()
    {
        // A wire-adjacent constant: 23505 is Postgres' unique_violation. Retyping it anywhere else,
        // or "fixing" it to a different class of error, silently changes which failures are retried.
        ConcurrencyRetry.UniqueViolationSqlState.ShouldBe("23505");
    }
}
