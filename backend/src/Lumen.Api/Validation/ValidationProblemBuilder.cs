namespace Lumen.Api.Validation;

/// <summary>
/// Accumulates field errors and turns them into <b>the one 400 body</b> every P4a endpoint returns
/// (T3). Roughly twenty endpoints share it, and its shape reaches the Flutter client through the
/// OpenAPI contract, so no endpoint may hand-roll a different rejection body.
///
/// <para>
/// <b>Validate then act.</b> Collect every error before the first write — never return on the first
/// failure. A form with three bad fields must come back with three messages, or the user fixes them
/// one round trip at a time; and a partial write followed by a late rejection would leave health data
/// half-saved.
/// </para>
///
/// <para>
/// <b>Keys are the camelCase JSON field name</b>, exactly as it appears on the wire —
/// <c>avgCycleLengthDays</c>, <c>occurredOn</c>, and for collections the indexed path
/// <c>boundaries[0].occurredOn</c>. The client matches these against its own field names to attach a
/// message to an input, so any normalisation here orphans the message. <see cref="RequestKey"/> is
/// reserved for errors that belong to no single field.
/// </para>
///
/// <example>
/// <code>
/// var problems = new ValidationProblemBuilder();
/// problems.AddIf(request.OccurredOn > day.Today, "occurredOn", ValidationMessages.FutureDate);
/// problems.AddIf(request.Notes?.Length > 2000, "notes", ValidationMessages.MaxLength(2000));
/// if (problems.HasErrors) return problems.Build();
/// </code>
/// </example>
///
/// <para>
/// Not thread-safe, and not meant to be: one instance belongs to one request handler.
/// </para>
/// </summary>
public sealed class ValidationProblemBuilder
{
    /// <summary>
    /// The reserved key for cross-field and whole-request errors — a combination of fields that is
    /// invalid though each field is fine on its own ("at least one of ... is required"), or a body
    /// that could not be read at all. Never use it for an error a real field owns: a message under
    /// <c>request</c> cannot be attached to an input on screen.
    /// </summary>
    public const string RequestKey = "request";

    private readonly Dictionary<string, List<string>> _errors = new(StringComparer.Ordinal);

    /// <summary>Whether anything has been accumulated. The guard before <see cref="Build"/>.</summary>
    public bool HasErrors => _errors.Count > 0;

    /// <summary>
    /// Records <paramref name="message"/> against <paramref name="field"/>. Several messages may
    /// accumulate under one key; they are kept in the order they were added.
    /// </summary>
    /// <param name="field">The camelCase JSON field name, or <see cref="RequestKey"/>.</param>
    public ValidationProblemBuilder Add(string field, string message)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(field);
        ArgumentException.ThrowIfNullOrWhiteSpace(message);

        if (!_errors.TryGetValue(field, out var messages))
            _errors[field] = messages = [];

        messages.Add(message);
        return this;
    }

    /// <summary>
    /// Records the error only when <paramref name="condition"/> holds. Lets a handler state all of its
    /// rules as one straight-line block, which is what keeps validate-then-act easy to get right.
    /// </summary>
    public ValidationProblemBuilder AddIf(bool condition, string field, string message) =>
        condition ? Add(field, message) : this;

    /// <summary>Records a cross-field error under <see cref="RequestKey"/>.</summary>
    public ValidationProblemBuilder AddRequest(string message) => Add(RequestKey, message);

    /// <summary>Records a cross-field error under <see cref="RequestKey"/> when the condition holds.</summary>
    public ValidationProblemBuilder AddRequestIf(bool condition, string message) =>
        condition ? AddRequest(message) : this;

    /// <summary>
    /// Builds the 400: <c>application/problem+json</c> with <c>errors: { field: [messages] }</c> and
    /// <see cref="ValidationMessages.RequestDetail"/> as the body-level <c>detail</c> — the same
    /// envelope <see cref="ProblemExceptionHandler"/> writes for an unbindable request, so the client
    /// has exactly one 400 to parse.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// Nothing was accumulated. A 400 with an empty <c>errors</c> map tells the client nothing and
    /// always means a missing <see cref="HasErrors"/> guard, so it fails loudly rather than shipping a
    /// rejection the user cannot act on.
    /// </exception>
    public IResult Build()
    {
        if (!HasErrors)
        {
            throw new InvalidOperationException(
                $"{nameof(ValidationProblemBuilder)}.{nameof(Build)}() was called with no errors. " +
                $"Guard the call with `if ({nameof(HasErrors)})`.");
        }

        var errors = _errors.ToDictionary(entry => entry.Key, entry => entry.Value.ToArray(), StringComparer.Ordinal);
        return Results.ValidationProblem(errors, detail: ValidationMessages.RequestDetail);
    }
}
