// ---------------------------------------------------------------------------
// period_vocabulary.dart — the `cycle_events` display labels (P4b-T16c)
// ---------------------------------------------------------------------------
//
// Two vocabularies, read by screen 11's Period section and by the period
// editor over it. They live in one file for the reason `mood_labels.dart`
// gives: the same scale rendered from two places drifts, and a drift shows the
// user a different word for the same stored row.
//
// **EVERY DISPLAY LABEL BELOW IS AUTHORED.** No mockup in the 38-screen design
// system draws a flow, spotting or bleeding control at all, and
// `definitions.md`'s 2026-07-08 ratification block contains no cycle-event
// vocabulary — it freezes mood, regions, pain types, triggers and the symptom
// catalogue, and nothing here. What IS ratified is the wire: the three `kind`
// codes (`CycleEvent.Kinds`) and the four-level shape of `flow_intensity`
// (`CycleEvent.FlowIntensityScale`). The words are a title-cased
// transliteration of those codes and go to the T25 PO copy pass beside screen
// 12's and screen 11's other authored strings.
//
// **C-04 is PO-interim and its RED-FLAG note does not ship (RULING T16-C).**
// The four flow words are exactly the C-04 level names, which is the same
// PO-interim standing every other C-value ships with. What is forbidden until
// clinician AND legal sign-off is the C-15 red-flag note that level 4
// triggers: so `Heavy` ships as a label and NOTHING here or in either caller
// characterises heaviness as a concern — no warning, no alarm chrome, no
// advisory copy. C-04's clinical gloss (the FIGO wording, and the
// "flow >= 2 is period-qualifying" rule) stays in `clinical-asks.md` and out
// of `client/lib` entirely (R-17).
//
// **No cross-field rule ties a kind to a flow level (RULING T16-D).** The
// server imposes none — `flowIntensity` is accepted on `period_end` and
// `spotting` too, and `CycleContracts.cs` says so at the site — so nothing
// here forbids `kind: spotting` with `flow: heavy`. Inventing a clinical
// consistency rule in the client is what R-17 exists to stop.
//
// **`spotting` is deliberately in BOTH vocabularies** — it is event kind 3 and
// flow level 1, one word for two fields on one sheet. It renders as ratified,
// disambiguated by its field label, which is the ruling the phase already made
// for screen 12's `Cramping`/`Cramping / joint pain` collision. Recorded for
// the PO copy pass, not resolved with invented separating copy.

// ---------------------------------------------------------------------------
// kind
// ---------------------------------------------------------------------------

/// The three ratified `cycle_events.kind` codes, in the backend's own
/// declaration order (`CycleEvent.Kinds.All`).
///
/// That order is the chip order on the editor. It is NOT alphabetical and NOT
/// the order `GET /cycle/day/{date}` returns events in (that one sorts by
/// `Kind`, so it reads `period_end`, `period_start`, `spotting`) — the
/// declaration order is the one a person would name them in.
const List<String> kPeriodKindCodes = <String>[
  'period_start',
  'period_end',
  'spotting',
];

/// `cycle_events.kind` -> its label. AUTHORED; see this file's header.
const Map<String, String> kPeriodKindLabels = <String, String>{
  'period_start': 'Period start',
  'period_end': 'Period end',
  'spotting': 'Spotting',
};

/// What a row with an unrecognisable `kind` is called.
///
/// AUTHORED, and unreachable through the shipped UI — the editor can only
/// send one of [kPeriodKindCodes] and the server rejects anything else with a
/// 400. It exists so a row that DOES arrive malformed still renders as a row:
/// hiding it would report the day as having no period event when it has one.
const String kPeriodKindUnknownLabel = 'Cycle event';

/// [kind]'s label — the ratified word, else the raw code, else
/// [kPeriodKindUnknownLabel].
///
/// The raw-code fallback is `moodLabel`'s rule, for its reason: a value
/// outside the ratified set still means something WAS logged, which is a
/// different fact from nothing being logged, and the honest way to say so is
/// to show what arrived rather than to invent a word for it or drop the row.
String periodKindLabel(String? kind) =>
    kPeriodKindLabels[kind] ?? kind ?? kPeriodKindUnknownLabel;

// ---------------------------------------------------------------------------
// flowIntensity
// ---------------------------------------------------------------------------

/// The 1-4 `flow_intensity` scale's labels, `kFlowLabels[value - 1]`.
///
/// **1-BASED on the wire**, like `mood` and unlike `pain`. A control built on
/// a bare list index writes `spotting` when the user picked `light`; the
/// `+ 1` lives at the one place that renders the chips and is not re-derived
/// in any controller, exactly as screen 11's mood row already does it.
const List<String> kFlowLabels = <String>[
  'Spotting',
  'Light',
  'Medium',
  'Heavy',
];

/// [value]'s label, or the raw integer for a value outside `1..4`.
///
/// The fallback is `'$value'` — `mood_labels.dart`'s rule again. Clamping to
/// the nearest legal level would render a wrong flow as a real one, on a
/// column whose only bound is server-side.
String flowLabel(int value) =>
    (value >= 1 && value <= kFlowLabels.length) ? kFlowLabels[value - 1] : '$value';
