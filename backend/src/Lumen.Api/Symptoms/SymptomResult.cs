namespace Lumen.Api.Symptoms;

/// <summary>
/// One rejected field, carried out of <see cref="SymptomService"/> so the service can stay free of
/// <c>IResult</c> and be unit-tested on its decisions rather than on an HTTP body.
/// <see cref="SymptomEndpoints"/> replays these into
/// <see cref="Validation.ValidationProblemBuilder"/>, which is still the only thing that builds the
/// phase's one 400.
/// </summary>
/// <remarks>
/// Deliberately a sibling of <c>Cycle.CycleFieldError</c> rather than a reuse of it: <c>Lumen.Api.Cycle</c>
/// already depends on this namespace (<c>CycleDayService</c> serves <c>POST /checkin/quick</c>), so
/// consuming its error type here would close a cycle between two feature folders for a type that
/// never reaches the wire and carries no schema. If a third feature needs the same two strings, hoist
/// one shared record into <c>Lumen.Api/Validation</c> and retire both — a T22 cleanup, not a thing to
/// do from inside one endpoint task.
/// </remarks>
/// <param name="Field">
/// The camelCase JSON field name exactly as it appears on the wire, including the indexed path for a
/// batch: <c>entries[3].intensity</c>, <c>entries[0].painTypes[1]</c>. Passed through verbatim; the
/// client matches it against its own field names to attach the message to an input, so any
/// normalisation here orphans the message.
/// </param>
public sealed record SymptomFieldError(string Field, string Message);

/// <summary>Outcome of <see cref="SymptomService.CreateAsync"/>.</summary>
public abstract record SymptomCreateResult
{
    /// <summary>
    /// Every entry in the batch was inserted, in one unit of work. → <b>201</b> (no <c>Location</c>:
    /// a batch creates N resources and the header holds one URI).
    /// </summary>
    public sealed record Saved(CreateSymptomsResponse Created) : SymptomCreateResult;

    /// <summary>
    /// <b>Nothing was written</b> — not even the entries that were fine (all-or-nothing, OQ-6) — and
    /// every field error found across the whole batch is listed. → 400.
    /// </summary>
    public sealed record Invalid(IReadOnlyList<SymptomFieldError> Errors) : SymptomCreateResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404. See <see cref="SymptomService"/>'s remarks for why this is a security
    /// control and not a formality.
    /// </summary>
    public sealed record UserNotFound : SymptomCreateResult;
}

/// <summary>Outcome of <see cref="SymptomService.ListAsync"/>.</summary>
public abstract record SymptomListResult
{
    /// <summary>
    /// The window was read — possibly empty. → 200. There is deliberately no "nothing in range" case:
    /// a month with no symptoms in it is a legitimate question whose answer is an empty page, and 404
    /// on this route means "no such user" and nothing else (§G12).
    /// </summary>
    public sealed record Found(SymptomListResponse Page) : SymptomListResult;

    /// <summary>The window or the paging arguments were out of contract; nothing was read. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<SymptomFieldError> Errors) : SymptomListResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404, checked before the arguments are even looked at.
    /// </summary>
    public sealed record UserNotFound : SymptomListResult;
}

/// <summary>Outcome of <see cref="SymptomService.ReplaceAsync"/>.</summary>
public abstract record SymptomReplaceResult
{
    /// <summary>The row now equals the request. → 200, carrying the stored row.</summary>
    public sealed record Saved(SymptomResponse Symptom) : SymptomReplaceResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<SymptomFieldError> Errors) : SymptomReplaceResult;

    /// <summary>
    /// No live row of the caller's has that id. → 404. Covers all four cases on purpose: an unknown
    /// id, an already-deleted one (a <c>PUT</c> must not resurrect a tombstone), <b>another user's
    /// id</b> — tenant isolation is 404, never 403, because a 403 would itself confirm the id exists —
    /// and an erased caller.
    /// </summary>
    public sealed record NotFound : SymptomReplaceResult;
}

/// <summary>Outcome of <see cref="SymptomService.DeleteAsync"/>.</summary>
public abstract record SymptomDeleteResult
{
    /// <summary>The row was tombstoned (D-13 soft delete, never a row removal). → 204.</summary>
    public sealed record Deleted : SymptomDeleteResult;

    /// <summary>
    /// No live row of the caller's has that id. → 404, covering the same four cases as
    /// <see cref="SymptomReplaceResult.NotFound"/>. A second delete lands here because the query
    /// filter hides the tombstone — P4b treats that as success, since the user's intent is already
    /// satisfied.
    /// </summary>
    public sealed record NotFound : SymptomDeleteResult;
}
