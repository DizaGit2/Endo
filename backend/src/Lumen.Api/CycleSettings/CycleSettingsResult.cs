namespace Lumen.Api.CycleSettings;

/// <summary>
/// One rejected field, carried out of <see cref="CycleSettingsService"/> so the service can stay free
/// of <c>IResult</c> and be unit-tested on its decisions rather than on an HTTP body.
/// <see cref="CycleSettingsEndpoints"/> replays these into
/// <see cref="Validation.ValidationProblemBuilder"/>, which is still the only thing that builds the
/// phase's one 400.
/// </summary>
/// <param name="Field">
/// The camelCase JSON field name, exactly as it appears on the wire — <c>avgCycleLengthDays</c>,
/// <c>pauseReason</c> — or <see cref="Validation.ValidationProblemBuilder.RequestKey"/> for an error
/// that belongs to no single field. Passed through verbatim; the client matches it against its own
/// field names to attach the message to an input.
/// </param>
public sealed record CycleSettingsFieldError(string Field, string Message);

/// <summary>Outcome of <see cref="CycleSettingsService.GetAsync"/>.</summary>
/// <remarks>
/// There is deliberately <b>no "settings not found" case</b>. A user with no
/// <c>user_cycle_settings</c> row is answered with the T6 defaults and a 200: 404 on this route means
/// "no such user" and nothing else (§G12), and spending it on a missing row would make an erased
/// account indistinguishable from one whose onboarding cycle step has not run yet.
/// </remarks>
public abstract record CycleSettingsReadResult
{
    /// <summary>The resource was read — from a stored row, or from the entity defaults. → 200.</summary>
    public sealed record Found(CycleSettingsResponse Settings) : CycleSettingsReadResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404. On a READ this is a security control in its own right: even a defaults
    /// body would confirm the account exists.
    /// </summary>
    public sealed record UserNotFound : CycleSettingsReadResult;
}

/// <summary>Outcome of <see cref="CycleSettingsService.UpdateAsync"/>.</summary>
public abstract record CycleSettingsUpdateResult
{
    /// <summary>
    /// The row was created or updated and the pause span reconciled. → <b>200 with the full
    /// resource</b>, not 204: the body carries the non-blocking warnings and the derived
    /// <c>phasesUnavailable</c> flag that an online-only client would otherwise have to re-fetch.
    /// </summary>
    public sealed record Saved(CycleSettingsResponse Settings) : CycleSettingsUpdateResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<CycleSettingsFieldError> Errors) : CycleSettingsUpdateResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row. → 404, decided <b>before</b> validation so
    /// an erased token cannot learn that its request shape was understood.
    /// </summary>
    public sealed record UserNotFound : CycleSettingsUpdateResult;
}
