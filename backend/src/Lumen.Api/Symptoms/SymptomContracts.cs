namespace Lumen.Api.Symptoms;

// The DTOs and wire strings of the symptoms feature (§C.3), per the T3 convention
// `<Feature>/<Feature>Contracts.cs`.
//
// T10 seeds this file with the quick check-in alone; T11 adds the symptom batch. The check-in lives
// here because §C.3 owns `POST /checkin/quick` (screen 9 is a symptoms-module screen), but it
// deliberately writes ONLY `cycle_day_logs` — see QuickCheckinRequest's remarks.
//
// Schema ids are the bare type names and are namespace-INDEPENDENT (§G12, verified in T9), so the
// `namespace` above is a style choice. The real hazard is a short-type-name COLLISION across feature
// folders, which throws a duplicate-schemaId error at document generation: `QuickCheckinRequest`,
// `QuickCheckinResponse`, `CreateSymptomsRequest`, `SymptomEntryInput`, `CreateSymptomsResponse`,
// `SymptomResponse`, `ReplaceSymptomRequest` and `SymptomListResponse` are each unique across the
// whole API.

/// <summary>
/// Body of <c>POST /checkin/quick</c> (screen 9, "How's today?") — the app's most-tapped write.
///
/// <para><b>No date.</b> The row is always the user's local <i>today</i> (D-12): screen 9 asks about
/// today and D-11 says a repeat check-in updates today's value. Explicit dates belong to
/// <c>POST /cycle/day/{date}</c>, which already owns them.</para>
///
/// <para><b>This is a PARTIAL write.</b> It touches only the two columns it offers, and only the
/// ones actually supplied: a check-in never clears the <c>notes</c> the day-detail screen wrote,
/// never touches the deferred <c>energy</c>/<c>libido</c> columns, and tapping only the mood chip
/// leaves the morning's pain score alone.</para>
///
/// <para><b><c>POST /cycle/day/{date}</c> (<see cref="Cycle.LogCycleDayRequest"/>) applies the SAME
/// rule — it MERGES.</b> An omitted field there is left UNCHANGED, not cleared, because
/// <c>cycle_day_logs</c> is the one row both screens write and a full upsert from either would
/// silently destroy what the user entered on the other. The two endpoints exist because they offer
/// different fields — this one carries no note and no date — not because they disagree about what an
/// omission means. <b>The endpoint that genuinely replaces its row is
/// <c>POST /cycle/events</c></b> (<see cref="Cycle.LogCycleEventRequest"/>): a FULL UPSERT where an
/// omitted field CLEARS the stored value, which is safe there and only there because
/// <c>cycle_events</c> is a single-writer, small row and clearing is the only way a user takes a
/// flow level back off. <b>The deciding question is not the HTTP verb, it is how many surfaces write
/// the row.</b></para>
///
/// <para>The split is <b>invisible in the generated Dart client</b> — every request is nullable
/// members on a <c>built_value</c> class and nothing on the wire says which one clears — so it is
/// stated on each DTO rather than in one place. Its documented cost, spelled out on
/// <see cref="Cycle.LogCycleDayRequest"/>, is that <b>P4a ships no way to clear an individual
/// field</b> on the day row; screens 9 and 11 offer no clear affordance, so nothing is lost today.
/// A blank or whitespace-only value is absent input, never an erase instruction.</para>
///
/// <para><b>It writes no <c>symptoms</c> row</b> (D-11 as modified): the day log is the headline
/// daily series, while <c>symptoms</c> holds classified episodes that only the full form creates.
/// Writing both here would double-count every tap in every later aggregate.</para>
/// </summary>
/// <param name="Pain">
/// Headline pain on the 0–10 NRS-11 scale. <b>0 is a real datum</b> ("none today", D-08) and
/// satisfies the at-least-one rule; only <see langword="null"/> means "not supplied".
/// </param>
/// <param name="Mood">Mood on the 1–4 scale {low, tired, steady, bright}.</param>
public record QuickCheckinRequest(
    int? Pain,
    int? Mood);

/// <summary>
/// The 200 body of <c>POST /checkin/quick</c>: the day log after the write. Always 200 — an upsert
/// has no actionable created/updated distinction, and §C.2 exposes no <c>GET /cycle/day-log/{id}</c>
/// for a <c>Location</c> header to point at.
/// </summary>
/// <param name="Day">
/// The user-local day the check-in landed on, echoed back so the client never has to re-derive it
/// from its own clock — the server's answer is the one that keyed the row.
/// </param>
/// <param name="Pain">The stored value, which may be a field an <i>earlier</i> write supplied.</param>
/// <param name="Mood">The stored value, same caveat as <see cref="Pain"/>.</param>
public record QuickCheckinResponse(
    DateOnly Day,
    int? Pain,
    int? Mood,
    DateTimeOffset UpdatedAt);

/// <summary>
/// The structural size bounds of one <c>POST /symptoms</c> payload. <b>A P4a INVENTION (§G11)</b>,
/// recorded here and in the T22 STATUS block so a later phase does not mistake 1–50 for a ratified
/// clinical or product number: it bounds a request body, and it means nothing else.
/// </summary>
/// <remarks>
/// The batch exists because D-09 makes one user action multi-row (see
/// <see cref="CreateSymptomsRequest"/>), so the floor of 1 is simply "a save must save something"
/// and the ceiling of 50 is comfortably above the largest real save — screen 12's pain row plus every
/// one of the 20 RELATED chips is 21 rows, and screen 13's body map is one row per placed point.
/// It is a denial-of-service bound on an authenticated write, not a limit the user is expected to
/// meet; if a real client ever needs more, raising it is additive and breaks no stored data.
/// </remarks>
public static class SymptomBatch
{
    /// <summary>A save must contain at least one entry; an empty array is a client bug, not a no-op.</summary>
    public const int MinEntries = 1;

    /// <summary>The inclusive ceiling: 50 entries are accepted, 51 are rejected.</summary>
    public const int MaxEntries = 50;
}

/// <summary>
/// The D-13 pagination bounds for <c>GET /symptoms</c>. <b>Not a P4a invention</b> — §G11 lists what
/// is, and these are not on it: D-13 states 50 default / 100 max for paginated reads.
/// </summary>
/// <remarks>
/// They live in the symptoms feature rather than in <see cref="Validation.FieldLimits"/> because
/// <c>GET /symptoms</c> is P4a's only paginated read, and that file's own rule is that a limit one
/// endpoint owns stays at that endpoint. <b>The second paginated read hoists them</b>, exactly as
/// <c>MaxNotesLength</c> was hoisted out of <c>CycleService</c> when <c>cycle_day_logs</c> became its
/// second caller — one number stated by one decision must not exist in two places.
/// </remarks>
public static class SymptomPaging
{
    /// <summary>Rows returned when the client asks for no particular page size.</summary>
    public const int DefaultLimit = 50;

    /// <summary>A page must contain at least one row; <c>limit=0</c> is a client bug, not an empty page.</summary>
    public const int MinLimit = 1;

    /// <summary>
    /// The inclusive ceiling: 100 is accepted, 101 is a <b>400</b>. Deliberately never a silent clamp
    /// — a client that asked for 500 and received 100 without being told cannot tell "that is all of
    /// them" from "you were truncated", and would render a partial symptom history as a complete one.
    /// </summary>
    public const int MaxLimit = 100;
}

/// <summary>
/// Messages owned by the symptoms endpoints alone (§G12: only genuinely cross-cutting strings belong
/// on <see cref="Validation.ValidationMessages"/>). These are <b>wire strings</b> asserted verbatim
/// against their literals in the unit suites — rewording one is a contract change, not a copy edit.
/// </summary>
public static class SymptomValidationMessages
{
    // `RangeEndBeforeStart` lived here until T13, when `GET /cycle/calendar` became the second
    // windowed read to state the same rule. It now lives on `ValidationMessages` — the shared home for
    // a message more than one feature genuinely uses — with the identical literal, so nothing on the
    // wire changed.

    /// <summary>
    /// A quick check-in supplied neither pain nor mood. Reported under
    /// <see cref="Validation.ValidationProblemBuilder.RequestKey"/> because it belongs to the
    /// combination, not to either field.
    /// </summary>
    public const string QuickCheckinEmpty = "at least one of pain or mood is required";

    /// <summary>
    /// <c>POST /symptoms</c> arrived with <c>entries: []</c>. Reported on the <c>entries</c> field
    /// rather than under <see cref="Validation.ValidationProblemBuilder.RequestKey"/>: the array is a
    /// real field the client can point at, and it is a different fault from an absent one (which gets
    /// <see cref="Validation.ValidationMessages.Required"/>).
    /// </summary>
    public const string BatchEmpty = "at least one entry is required";

    /// <summary>
    /// The batch exceeded <see cref="SymptomBatch.MaxEntries"/>. Parameterised for the same reason as
    /// <see cref="Validation.ValidationMessages.Between"/>: the bound is stated in the sentence, and
    /// taking it from the constant is what keeps the two from drifting apart silently.
    /// </summary>
    public static string MaxEntries(int max) =>
        // Invariant: a wire string must not vary with the server's thread culture.
        FormattableString.Invariant($"a request may contain at most {max} entries");
}

/// <summary>
/// Body of <c>POST /symptoms</c> (screens 12 and 13) — <b>a BATCH create</b>, 1–50 entries
/// (<see cref="SymptomBatch"/>), <b>all-or-nothing</b>, answered with <b>201</b> and an
/// <see cref="CreateSymptomsResponse.Items"/> array.
///
/// <para><b>Why a batch and not N single creates (OQ-6, ruled at phase entry).</b> D-09 makes one
/// user action inherently multi-row: screen 12's single "Save symptom" writes the pain row <i>plus
/// one row per RELATED chip</i>, and screen 13's "Save body map" writes one row per placed point. The
/// client is <b>online-only with no write queue</b>, so N requests per save would let a dropped
/// connection leave half an episode recorded — and a half-recorded episode is worse than none,
/// because the user believes the save succeeded and every later aggregate reads the fragment as the
/// whole truth. One request, one transaction, one outcome.</para>
///
/// <para><b>All-or-nothing is literal.</b> One invalid entry rejects the whole batch with a 400 and
/// writes NOTHING — not the valid entries, not a partial episode. Errors are keyed by the indexed
/// JSON path (<c>entries[3].intensity</c>) so the client can attach each message to the right row of
/// the form.</para>
/// </summary>
/// <param name="Entries">
/// The episodes to record, in the order the client wants them back. Absent is a validation error, not
/// an empty batch: a save that silently recorded nothing is the failure mode this endpoint exists to
/// prevent.
/// </param>
public record CreateSymptomsRequest(
    IReadOnlyList<SymptomEntryInput>? Entries);

/// <summary>
/// One symptom episode to record. <b>Only <see cref="Intensity"/> is required</b> — the date defaults
/// to now, and <b>every classification field is optional</b> (D-09): a user who taps a number and
/// saves has recorded a valid symptom.
///
/// <para><b>Write semantics — this row is FULL-REPLACE, and that is the third of the phase's three
/// rules (§G12). Decided here, on the evidence, for T12 to inherit.</b> The deciding question is not
/// the HTTP verb, it is <b>how many surfaces write the row</b>. A <c>symptoms</c> row is
/// <b>id-addressed and single-writer</b>: it is created by one save and thereafter edited only by
/// re-opening it in the form that owns it. Nothing else ever writes an existing row, so the body
/// genuinely does describe the row's whole desired state — and an omitted or <see langword="null"/>
/// classification field on T12's <c>PUT /symptoms/{id}</c> <b>CLEARS</b> the stored value
/// (<see cref="Side"/> → null, <see cref="PainTypes"/>/<see cref="Triggers"/> → empty,
/// <see cref="Notes"/> → null, <see cref="Region"/> → <c>unspecified</c>).</para>
///
/// <para><b>The second reason is decisive on its own: here, clearing IS the affordance.</b> These
/// fields are toggle chips and a body-map side switch. Under MERGE the user could add "sharp" but
/// never take it back off, set a side but never un-set it, write a note but never delete it — every
/// classification would be one-way and permanently wrong. That is the opposite of
/// <c>cycle_day_logs</c>, where merging costs nothing precisely because screens 9 and 11 offer no
/// clear affordance to lose. <b>So: <c>POST /cycle/events</c> full-upsert, <c>POST /cycle/day/{date}</c>
/// and <c>POST /checkin/quick</c> merge, <c>POST /symptoms</c> + <c>PUT /symptoms/{id}</c>
/// full-replace.</b>
/// <b>The verb was renamed in T12 as a consequence</b>: §C.3 originally named the update
/// <c>PATCH</c>, and <c>PATCH</c> has a defined meaning that full replace <i>contradicts</i> — a
/// client author who sent only the changed field would get silent data loss. <c>POST</c> is
/// semantically neutral, so <c>POST</c>=upsert and <c>POST</c>=merge mislead nobody; <c>PATCH</c>
/// would. §C.3 is amended in the same commit. See <see cref="ReplaceSymptomRequest"/>.</para>
///
/// <para>The rule is <b>invisible in the generated Dart client</b> — every field is a nullable member
/// on a <c>built_value</c> class and nothing on the wire says which one clears — which is why it is
/// stated on the DTO rather than in one place. On this CREATE endpoint it makes no observable
/// difference; it is stated now so T12 does not have to re-derive it or copy a neighbour.</para>
/// </summary>
/// <param name="SymptomCode">
/// One of the 21 ratified codes (§G10: <c>pain</c> plus the 20-member non-pain catalogue). Absent or
/// blank defaults to <c>pain</c>. Matched with <see cref="StringComparer.Ordinal"/> and <b>never
/// case-fixed</b>: the vocabulary is append-only and stored rows carry these strings forever, so two
/// spellings of one concept must not both get in.
/// </param>
/// <param name="Intensity">
/// <b>Required.</b> Severity on the 0–10 NRS-11 scale (D-08). <b>0 is a real datum</b>, never an
/// absence. Typed <c>int?</c> rather than <c>short?</c> on purpose, so an out-of-range value like
/// 40000 reaches the validator and comes back as a message attached to this field, instead of being
/// rejected by the model binder as an unreadable body.
/// </param>
/// <param name="Region">One of the 9 ratified regions (§G10). Absent or blank defaults to <c>unspecified</c>.</param>
/// <param name="Side">
/// Anatomical <c>front</c> or <c>back</c> — <b>not</b> laterality (ARCHITECTURE.md:37,:51,:184). The
/// body map has a front view and a back view; left/right was never part of the model. Blank is stored
/// as null.
/// </param>
/// <param name="PainTypes">
/// Zero or more of the 6 ratified pain qualities (§G10). De-duplicated and re-ordered into canonical
/// vocabulary order before storage, so P6 never sees order or duplicate noise and two rows recording
/// the same qualities compare equal. <see langword="null"/> is stored as an empty array, never NULL.
/// <b>Accepted on every symptom code</b> — there is no cross-field rule (§G6/§G7).
/// </param>
/// <param name="Triggers">Zero or more of the 7 ratified triggers (§G10). Same normalisation as <see cref="PainTypes"/>.</param>
/// <param name="OccurredAt">
/// When the episode happened. Absent defaults to the request's single <c>now</c>. Normalised to UTC
/// before storage (<b>mandatory</b>: Npgsql rejects a non-zero offset on a <c>timestamptz</c>
/// parameter). The stored day key is derived from it via <c>IUserDayResolver</c> and is never
/// client-supplied.
/// <para><b>Capped by the user's local today and NOTHING ELSE (§G8).</b> There is no backdate floor
/// here — D-13 gives one to <c>cycle_events</c> alone, and a symptom logged five years back is a user
/// transcribing a paper diary, which is exactly the history D-13 permits. The cap is at <b>local-day
/// granularity</b>, so an instant later today is fine and a phone whose clock runs fast does not lose
/// the entry.</para>
/// </param>
/// <param name="Notes">Optional free text, ≤ 2000 characters after trimming (D-13). Stored encrypted.</param>
public record SymptomEntryInput(
    string? SymptomCode,
    int? Intensity,
    string? Region,
    string? Side,
    IReadOnlyList<string>? PainTypes,
    IReadOnlyList<string>? Triggers,
    DateTimeOffset? OccurredAt,
    string? Notes);

/// <summary>
/// The <b>201</b> body of <c>POST /symptoms</c>: every row the batch created, in request order.
/// </summary>
/// <remarks>
/// <b>No <c>Location</c> header.</b> A batch creates N resources and <c>Location</c> is a single URI,
/// so there is nothing honest to put in it; the ids the client needs are in <see cref="Items"/>.
/// Wrapped in an object rather than returned as a bare array so the response can gain a member later
/// without breaking the generated client.
/// </remarks>
public record CreateSymptomsResponse(
    IReadOnlyList<SymptomResponse> Items);

/// <summary>
/// One stored <c>symptoms</c> row, with <see cref="Notes"/> echoed back in plaintext (the column
/// itself holds only AES-256-GCM ciphertext).
/// </summary>
/// <remarks>
/// No <c>phase</c>, <c>cycleDay</c> or <c>confidence</c> key (§G6): P4a computes none of them, and a
/// placeholder is exactly how a not-yet-implemented estimate gets rendered as a clinical fact. No
/// severity bucket either — "moderate"/"severe" is clinical inference, and this row carries the
/// number the user chose and nothing derived from it.
/// </remarks>
/// <param name="Id">The id T12's read, update and delete take.</param>
/// <param name="OccurredAt">The normalised UTC instant actually stored.</param>
/// <param name="OccurredOn">
/// The user-local day <see cref="OccurredAt"/> falls on (D-12), computed server-side. Echoed back so
/// the client never re-derives it from its own clock — the server's answer is the one that keyed the
/// row for every calendar and range read.
/// </param>
public record SymptomResponse(
    Guid Id,
    string SymptomCode,
    int Intensity,
    string Region,
    string? Side,
    IReadOnlyList<string> PainTypes,
    IReadOnlyList<string> Triggers,
    DateTimeOffset OccurredAt,
    DateOnly OccurredOn,
    string? Notes,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>
/// The 200 body of <c>GET /symptoms?from&amp;to&amp;limit&amp;offset</c>: one page of the user's
/// symptom history, <b>newest first</b>.
/// </summary>
/// <remarks>
/// The window is stated in <b>user-local days</b> and both ends are inclusive, matched against the
/// stored <c>occurredOn</c> — the column D-12 exists to provide, so a month view is a day-keyed index
/// scan rather than a per-row timezone conversion. A <c>to</c> in the <i>future</i> is legitimate here
/// and only here: every WRITE in this phase is capped by today, but a calendar shows the rest of the
/// month and rejecting that would make the client clamp the window it had just rendered.
///
/// <para><b>The span is capped at <see cref="Validation.ReadWindow.MaxDays"/> days (§G11), the same
/// cap and the same <see cref="Validation.ValidationMessages.MaxWindowDays"/> wire string
/// <c>GET /cycle/calendar</c> uses (T13).</b> A defect fix, not part of T12's original shipment: the
/// D-13 <see cref="SymptomPaging"/> bounds page <see cref="Items"/>, but <see cref="Total"/> came from
/// an unbounded <c>COUNT(*)</c> over whatever window the caller supplied — a wide-open date range was a
/// full-table count per request on an authenticated endpoint, and the page cap never touched it. The
/// two windowed reads now state the rule once rather than risk answering it differently.</para>
/// </remarks>
/// <param name="Items">
/// The page, ordered by <c>occurredAt</c> descending with the row id as a tiebreak. That tiebreak is
/// not defensive: D-09 makes several rows share one instant on <i>every</i> body-map save, and without
/// it the database may order the tied rows differently per query — so page 2 could repeat a row from
/// page 1 and drop another entirely, silently losing a symptom from the user's history.
/// </param>
/// <param name="Total">
/// How many live rows match the window, <b>ignoring the page</b> — what the client needs to render
/// "12 of 40" and to know whether to fetch again. Tombstoned rows (D-13) are excluded from this count
/// as well as from <see cref="Items"/>; a total that included them would page into rows that never
/// arrive.
/// </param>
/// <param name="Limit">The page size actually applied, echoed so a client that sent none knows the default.</param>
/// <param name="Offset">The offset actually applied.</param>
public record SymptomListResponse(
    IReadOnlyList<SymptomResponse> Items,
    int Total,
    int Limit,
    int Offset);

/// <summary>
/// Body of <c>PUT /symptoms/{id}</c> — the edit behind re-opening a saved symptom on screen 12 or 13.
///
/// <para><b>This is a FULL REPLACE, and the verb says so on purpose.</b> §C.3 originally named this
/// update <c>PATCH</c>; T12 renamed it (and amended §C.3) because <c>PATCH</c> has a defined meaning
/// that full replace contradicts. A client author who reads <c>PATCH</c> correctly assumes an omitted
/// field is untouched — here it is <b>cleared</b> — so the verb is a safety affordance, not a naming
/// preference. Keeping <c>PATCH</c> as a true merge was the alternative, and it is not available: with
/// no way to express "clear this field" it would need a tri-state DTO the generated <c>built_value</c>
/// Dart client cannot represent, and MERGE would make every toggle chip addable but never removable.</para>
///
/// <para><b>The replace rule has exactly two halves.</b> A field that has an <i>unclassified</i>
/// state is <b>CLEARED</b> when omitted: <see cref="Region"/> → <c>unspecified</c>,
/// <see cref="Side"/> → null, <see cref="PainTypes"/>/<see cref="Triggers"/> → empty,
/// <see cref="Notes"/> → null. A field with <b>no</b> unclassified state is <b>REQUIRED</b>:
/// <see cref="Intensity"/> and <see cref="OccurredAt"/>. That second half is what stops an edit from
/// fabricating data — defaulting an absent instant to the request's <c>now</c> would silently re-date
/// a transcribed five-year-old entry to today, and the edit's clock is not the episode's clock.</para>
///
/// <para><b>CLIENT OBLIGATION — read this before wiring screen 12 (P4b).</b> Because the body is the
/// row's whole desired state, <b>the client must re-hydrate the row and send every field back</b>,
/// not just the ones the user touched. The sharp edge is <see cref="Side"/>: screen 12
/// (<c>symptom_form</c>) has <b>no front/back control at all</b> — its only path to a side is a
/// drill-in to screen 13 (<c>body_map</c>) — so a row located on the body map and then edited from
/// screen 12 <b>loses its side</b> unless screen 12 echoes back the value it was given. The duty is
/// cheap to meet: <see cref="SymptomResponse"/> carries <c>side</c>, and it is what
/// <c>GET /symptoms</c>, <c>POST /symptoms</c> and this endpoint all return. Exempting
/// <see cref="Side"/> from the clear was considered and rejected — it would make one field on a
/// full-replace DTO silently merge, with nothing on the wire and nothing in the generated Dart client
/// to say which, and it would leave <c>side</c> settable but never un-settable.</para>
///
/// <para><b><see cref="SymptomEntryInput.SymptomCode"/> is absent by construction, not ignored.</b>
/// Re-coding a <c>bloating</c> row into <c>pain</c> rewrites the identity of a series the P6 engine
/// will read, so there is deliberately no wire representation of the change and no client can express
/// it. The user action for that is delete and re-create.</para>
/// </summary>
/// <param name="Intensity">
/// <b>Required.</b> Severity on the 0–10 NRS-11 scale (D-08); <b>0 is a real datum</b>. Typed
/// <c>int?</c> rather than <c>short?</c> for the same reason as on create: an out-of-range 40000 must
/// reach the validator and come back attached to this field, not be rejected as an unreadable body.
/// </param>
/// <param name="Region">One of the 9 ratified regions (§G10). Absent or blank <b>resets</b> to <c>unspecified</c>.</param>
/// <param name="Side">
/// Anatomical <c>front</c>/<c>back</c> — <b>not</b> laterality. Absent or blank <b>CLEARS</b> it; see
/// the client obligation above.
/// </param>
/// <param name="PainTypes">
/// The complete set of pain qualities after the edit. <b>Replaces, never merges</b> — an absent or
/// empty array clears every stored quality, which is precisely how a user un-taps a chip.
/// De-duplicated and re-ordered into canonical vocabulary order before storage.
/// </param>
/// <param name="Triggers">The complete set of triggers after the edit. Same rule as <see cref="PainTypes"/>.</param>
/// <param name="OccurredAt">
/// <b>Required</b> (unlike on create, where absent means "now" because the user is logging as it
/// happens). Normalised to UTC before storage, and the stored day key is re-derived from it server-side
/// via <c>IUserDayResolver</c> (D-12). <b>Capped by the user's local today and NOTHING ELSE (§G8)</b> —
/// there is no backdate floor here, so an edit may legitimately move an episode years into the past.
/// </param>
/// <param name="Notes">Optional free text, ≤ 2000 characters after trimming (D-13). Absent or blank <b>CLEARS</b> the stored note. Re-encrypted with a fresh nonce.</param>
public record ReplaceSymptomRequest(
    int? Intensity,
    string? Region,
    string? Side,
    IReadOnlyList<string>? PainTypes,
    IReadOnlyList<string>? Triggers,
    DateTimeOffset? OccurredAt,
    string? Notes);
