using System.Diagnostics;
using Lumen.Api.Symptoms;
using Lumen.Api.Validation;

namespace Lumen.Api.Cycle;

/// <summary>
/// Route registrations for the cycle write surface (T9) — the first feature endpoints of P4a, and the
/// shape the eight endpoint tasks after it copy.
/// </summary>
/// <remarks>
/// No <c>MapGroup</c>, no <c>.WithTags</c>, no <c>.WithName</c> (§G12): a tag would split these
/// operations out of the generated Dart client's <c>LumenApiApi</c> class and break
/// <c>client/lib/core/network/api_client.dart</c> plus both repositories. The handlers stay thin —
/// every decision lives in <see cref="CycleService"/>, where it is unit-testable without HTTP — and
/// each one does exactly two things: translate a result into a status, and route every 404 through
/// <see cref="NotFoundProblem"/> and every 400 through <see cref="ValidationProblemBuilder"/> so the
/// phase keeps one error body each (§G12).
/// </remarks>
public static class CycleEndpoints
{
    public static IEndpointRouteBuilder MapCycleEndpoints(this IEndpointRouteBuilder app)
    {
        // Upsert on (user, kind, day) — see CycleService for the §G9 tombstone-revival contract.
        app.MapPost("/cycle/events", async (
            LogCycleEventRequest request,
            CycleService cycle,
            CancellationToken ct) =>
        {
            var result = await cycle.LogEventAsync(request, ct);
            return result switch
            {
                CycleEventResult.Saved saved => Results.Ok(saved.Event),
                CycleEventResult.Invalid invalid => Problem(invalid.Errors),
                CycleEventResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleEventResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleEventResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // Soft delete (D-13). §C.2 had no DELETE; OQ-5 added it and the same branch amends §C.2.
        // The `:guid` constraint keeps a malformed id out of the handler entirely.
        app.MapDelete("/cycle/events/{id:guid}", async (
            Guid id,
            CycleService cycle,
            CancellationToken ct) =>
        {
            var result = await cycle.DeleteEventAsync(id, ct);
            return result switch
            {
                CycleEventDeleteResult.Deleted => Results.NoContent(),
                CycleEventDeleteResult.NotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleEventDeleteResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // Replace-the-set for one cycle; `boundaries: []` is screen 14's "Reset to predicted".
        app.MapPost("/cycle/phase-override", async (
            SavePhaseOverridesRequest request,
            CycleService cycle,
            CancellationToken ct) =>
        {
            var result = await cycle.SavePhaseOverridesAsync(request, ct);
            return result switch
            {
                PhaseOverrideResult.Saved saved => Results.Ok(saved.Overrides),
                PhaseOverrideResult.Invalid invalid => Problem(invalid.Errors),
                PhaseOverrideResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(PhaseOverrideResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<PhaseOverridesResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // The D-11 one-row-per-day upsert (screen 11). `{date}` is left UNCONSTRAINED on purpose: a
        // `:datetime` route constraint would answer an unparseable date with a 404, which on this
        // route means "no such user". Unconstrained, the binder throws and ProblemExceptionHandler
        // turns it into the phase's one 400 under `errors.request` (T3).
        app.MapPost("/cycle/day/{date}", async (
            DateOnly date,
            LogCycleDayRequest request,
            CycleDayService days,
            CancellationToken ct) =>
        {
            var result = await days.UpsertDayAsync(date, request, ct);
            return result switch
            {
                CycleDayResult.Saved saved => Results.Ok(saved.Log),
                CycleDayResult.Invalid invalid => Problem(invalid.Errors),
                CycleDayResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleDayResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleDayLogResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // Screen 9. §C.3 owns this route (symptoms module) but it writes only `cycle_day_logs`, so it
        // is served by CycleDayService and registered here rather than splitting the day upsert across
        // two services that would race each other on the same row.
        app.MapPost("/checkin/quick", async (
            QuickCheckinRequest request,
            CycleDayService days,
            CancellationToken ct) =>
        {
            var result = await days.QuickCheckinAsync(request, ct);
            return result switch
            {
                QuickCheckinResult.Saved saved => Results.Ok(saved.Checkin),
                QuickCheckinResult.Invalid invalid => Problem(invalid.Errors),
                QuickCheckinResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(QuickCheckinResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<QuickCheckinResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // The single-day read. No 400 is documented: the read validates nothing (an empty day is a
        // 200 with a null log), so the only failures are an unbindable date and an unknown user.
        app.MapGet("/cycle/day/{date}", async (
            DateOnly date,
            CycleDayService days,
            CancellationToken ct) =>
        {
            var result = await days.GetDayAsync(date, ct);
            return result switch
            {
                CycleDayReadResult.Found found => Results.Ok(found.Day),
                CycleDayReadResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleDayReadResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleDayResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        // The windowed read behind screens 10 and 8 (T13). Both bounds are optional and default
        // independently to the edges of the user's current month; a future `to` is legitimate here,
        // because a month view spans forward even though every write is capped by today. `DateOnly?`
        // so an out-of-range window reaches the validator and comes back attached to its own field —
        // an UNPARSEABLE bound still fails at the binder and becomes T3's one 400 under `request`,
        // which is the right answer for a parameter that could not be read at all.
        app.MapGet("/cycle/calendar", async (
            DateOnly? from,
            DateOnly? to,
            CycleCalendarService calendar,
            CancellationToken ct) =>
        {
            var result = await calendar.GetCalendarAsync(from, to, ct);
            return result switch
            {
                CycleCalendarResult.Found found => Results.Ok(found.Calendar),
                CycleCalendarResult.Invalid invalid => Problem(invalid.Errors),
                CycleCalendarResult.UserNotFound => NotFoundProblem.Result(),
                _ => throw new UnreachableException($"Unhandled {nameof(CycleCalendarResult)}: {result.GetType()}"),
            };
        })
        .RequireAuthorization()
        .Produces<CycleCalendarResponse>(StatusCodes.Status200OK)
        .ProducesValidationProblem()
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return app;
    }

    /// <summary>
    /// Replays the service's field errors into the phase's one 400 body. Several messages may share a
    /// key (the builder keeps them in order), which is why this loops rather than building a map.
    /// </summary>
    private static IResult Problem(IReadOnlyList<CycleFieldError> errors)
    {
        var problems = new ValidationProblemBuilder();
        foreach (var error in errors) problems.Add(error.Field, error.Message);
        return problems.Build();
    }
}
