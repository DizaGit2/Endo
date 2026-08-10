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
