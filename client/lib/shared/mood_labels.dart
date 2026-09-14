// ---------------------------------------------------------------------------
// mood_labels.dart — the shared `cycle_day_logs.mood` vocabulary (P4b-T18)
// ---------------------------------------------------------------------------
//
// Promoted from two private copies that had drifted: `dashboard_screen.dart`'s
// `_kMoodLabels`/`_moodLabel` (fix round 1, M7) and `day_detail_screen.dart`'s
// own inline map. A third screen needing this exact scale — screen 9's quick
// check-in — is what promotion is for (the same threshold
// `LumenSelectableRow`'s own dartdoc names: two private copies plus a third
// caller).
//
// **Corrected at P4b-T16c.** This header used to say `day_detail_screen.dart`'s
// copy was *"still inline at its own `_MoodRow`"*. It is not, and it never was
// after this file landed: that promotion is precisely what removed it, and
// `_kMoodLabels` exists nowhere in `client/lib` today. The sentence was false
// on the commit that introduced it — a claim about a sibling file that nothing
// re-checks when that file changes.

/// `cycle_day_logs.mood`'s 4-member scale, `Codes[value - 1]` — the wire
/// carries the integer 1-4 (mood is 1-based; contrast pain, which is
/// 0-based), never the code string. Frozen order, `definitions.md`'s
/// 2026-07-08 ratification block: *"Mood {low, tired, steady, bright} =
/// 1–4"*.
const List<String> kMoodLabels = <String>['Low', 'Tired', 'Steady', 'Bright'];

/// [mood]'s ratified label, or the raw integer for an out-of-range value.
///
/// **The fallback is `'$mood'`, never the word `'Mood'`.** Fix round 1, M7
/// (`dashboard_screen.dart`): contract-constrained to 1-4 so an out-of-range
/// value is unreachable today, but a malformed one must not be dishonest —
/// and beside a section's own "MOOD"/"Mood" label, the word "Mood" alone
/// would read as the redundant "MOOD / Mood". The raw integer says something
/// WAS logged, just outside the ratified scale — a different fact from
/// nothing being logged at all (that case is the caller's own "Not logged
/// today", decided by the caller, not this function). Both call sites use
/// this fallback as of P4b-T18; `day_detail_screen.dart`'s `_MoodRow`
/// carried the superseded `'Mood'` shape until this promotion.
String moodLabel(int mood) =>
    (mood >= 1 && mood <= kMoodLabels.length) ? kMoodLabels[mood - 1] : '$mood';
