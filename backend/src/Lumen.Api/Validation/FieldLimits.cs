namespace Lumen.Api.Validation;

/// <summary>
/// Input limits that more than one feature enforces. Sibling of <see cref="ValidationMessages"/> and
/// governed by the same rule: only genuinely <b>cross-cutting</b> numbers belong here. A limit one
/// endpoint owns stays at that endpoint, and every <b>clinical</b> bound stays out of
/// <c>backend/src</c> entirely this phase (§G7 — those live in P6's <c>ref_insight_rule</c> seed).
/// </summary>
public static class FieldLimits
{
    /// <summary>
    /// The D-13 free-text cap, <b>measured on the trimmed plaintext</b> — 2000 characters wrapped in
    /// whitespace is a 2000-character note, and the limit exists to bound the column, not to punish a
    /// trailing newline.
    ///
    /// <para>Hoisted out of <c>CycleService</c> (T9) when <c>cycle_day_logs</c> became the second
    /// table to need it; T11's <c>symptoms</c> is the third. D-13 states one cap for all free-text
    /// notes, so three copies of the literal <c>2000</c> could only ever drift apart — and because
    /// the number reaches the client inside a wire string ("text exceeds the maximum length of 2000
    /// characters"), a drift would be a silent contract change rather than a compile error.</para>
    ///
    /// <para>The columns themselves are <c>bytea</c> ciphertext and carry no length constraint: this
    /// is an input rule, which is why it lives beside the validators rather than on the entities.</para>
    /// </summary>
    public const int MaxNotesLength = 2000;
}
