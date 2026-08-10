namespace Lumen.Api.Devices;

/// <summary>
/// One rejected field, carried out of <see cref="DeviceRegistrationService"/> so the service can stay
/// free of <c>IResult</c> and be unit-tested on its decisions rather than on an HTTP body.
/// <see cref="DeviceEndpoints"/> replays these into
/// <see cref="Validation.ValidationProblemBuilder"/>, which is still the only thing that builds the
/// phase's one 400.
/// </summary>
/// <param name="Field">
/// The camelCase JSON field name, exactly as it appears on the wire — <c>platform</c>,
/// <c>pushToken</c>. Passed through verbatim; the client matches it against its own field names to
/// attach the message to an input.
/// </param>
public sealed record DeviceFieldError(string Field, string Message);

/// <summary>Outcome of <see cref="DeviceRegistrationService.RegisterAsync"/>.</summary>
/// <remarks>
/// There is deliberately <b>no "created" case distinct from "updated"</b>. An upsert has no
/// actionable distinction for this caller — the client re-registers on every token refresh and does
/// nothing differently on the first one — so both are <see cref="Saved"/> and both are 200.
/// </remarks>
public abstract record DeviceRegistrationResult
{
    /// <summary>The device row was created or updated in place. → <b>200</b>.</summary>
    public sealed record Saved(RegisterDeviceResponse Device) : DeviceRegistrationResult;

    /// <summary>Nothing was written; every field error found is listed. → 400.</summary>
    public sealed record Invalid(IReadOnlyList<DeviceFieldError> Errors) : DeviceRegistrationResult;

    /// <summary>
    /// The token's <c>sub</c> has no live <c>users</c> row — it never existed, or the account was
    /// crypto-shredded. → 404, decided <b>before</b> validation so an erased token cannot learn that
    /// its request shape was understood, and before the cross-user detach so it cannot be used as an
    /// unregister lever against a live account.
    /// </summary>
    public sealed record UserNotFound : DeviceRegistrationResult;
}
