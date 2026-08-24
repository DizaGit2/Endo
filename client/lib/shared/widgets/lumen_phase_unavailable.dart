import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

// ---------------------------------------------------------------------------
// The reasons
// ---------------------------------------------------------------------------

/// The only `unavailableReason` P4a can answer.
///
/// `ARCHITECTURE.md` §C.0.3: the phase envelope is always
/// `phase: { available: false, unavailableReason: "phase_engine_not_implemented" }`
/// and **no day row carries a `phase`, `cycleDay` or `confidence` key**.
/// *Render the unavailable state; do not infer one.*
const String kPhaseEngineNotImplemented = 'phase_engine_not_implemented';

/// The heading and body a given [reason] is explained with.
typedef PhaseUnavailableCopy = ({String heading, String body});

/// The neutral copy — true of every reason the phase engine can give, because
/// in all of them Lumen does not know the phase.
const PhaseUnavailableCopy _neutral = (
  heading: "Cycle phases aren't available yet",
  body: 'Lumen needs more of your cycle history before it can show phases.',
);

/// Resolves [reason] to the copy that explains it.
///
/// **P6 adds cases here; it does not rewrite the widget.** When the phase
/// engine lands it can answer `tracking_paused`, `insufficient_data` and
/// `no_period_logged`, each of which deserves its own sentence — "you paused
/// tracking" and "we need more history" are different things to tell someone.
/// That copy is deliberately NOT written here: it is clinical-facing wording
/// that needs the review this phase does not have, and inventing it now would
/// ship an unreviewed clinical claim behind a plausible-looking `case`.
///
/// Until then every reason, known or not, resolves to the neutral copy. That is
/// the safe direction: an unrecognised reason renders a true statement rather
/// than a blank band or a raw wire code.
PhaseUnavailableCopy phaseUnavailableCopy(String? reason) {
  switch (reason) {
    case kPhaseEngineNotImplemented:
      return _neutral;
    // TODO(P6): add `tracking_paused`, `insufficient_data` and
    // `no_period_logged` cases, each with clinically reviewed copy.
    case _:
      return _neutral;
  }
}

// ---------------------------------------------------------------------------
// The gate
// ---------------------------------------------------------------------------

/// Whether the phase-unavailable block should render at all, given the phase
/// envelope's own `available` flag.
///
/// **Fix round 1, I-1: the block is gated on AVAILABILITY, never on the
/// reason.** Before this function existed nothing in `lib/features/` or
/// `lib/shared/` read `available` at all — all three call sites rendered
/// [LumenPhaseUnavailable] unconditionally. That is invisible today, because
/// `ARCHITECTURE.md` §C.0.3 fixes the envelope at `available: false` for every
/// P4a account, so the block is always the right thing to draw; it becomes a
/// lie the day P6 ships the engine, with three screens telling a user whose
/// phases work that *"cycle phases aren't available yet"*.
/// [phaseUnavailableCopy] cannot fix that on its own — it returns a
/// non-nullable [PhaseUnavailableCopy] and therefore has no way to express
/// *render nothing* — which is why the decision lives here, at the call sites,
/// rather than as one more `case` in there.
///
/// **Every value other than `true` means unavailable**, deliberately:
///  * `false` — P4a's answer, stated;
///  * `null` because the response carried no `phase` envelope at all, or
///    carried one with the flag omitted. Every generated DTO field is
///    nullable, and an absent flag is not a claim that phases work. Inferring
///    availability from silence would be §C.0.3's own mistake pointing the
///    other way: *render the unavailable state; do not infer one.*
///
/// So only an explicit `available: true` hides the block, and P6 flipping that
/// flag is the whole of what makes these three screens stop claiming the
/// engine is missing.
bool phasesAreUnavailable(bool? available) => available != true;

// ---------------------------------------------------------------------------
// The widget
// ---------------------------------------------------------------------------

/// What screens 8, 10 and 14 render where the mockups draw a phase band —
/// **when, and only when, [phasesAreUnavailable] says the envelope reports
/// phases unavailable.** The three call sites carry that gate (fix round 1,
/// I-1); this widget itself is unconditional and draws the block it is given,
/// which is what keeps `find.byType(LumenPhaseUnavailable)` a truthful
/// question in every test that asks it.
///
/// **Screen 11 is deliberately NOT in that list, and this line used to say it
/// was** — P4b-T16 cut every phase treatment from the day detail, not because
/// it would have needed a second read, but because screen 10 is one tap away
/// and already carries this block, so repeating a constant string on every day
/// view is noise rather than information. Screen 14 became the third real call
/// site at P4b-T23.
///
/// P4a answers `phase: { available: false, unavailableReason: ... }` for every
/// user, and no day row carries a phase, cycle-day or confidence value. The
/// mockups draw "Luteal · Day 22" because they were drawn against a future
/// backend; rendering that from nothing would be an invented clinical claim,
/// which is why `ARCHITECTURE.md` §C.0.3 states the obligation as *render the
/// unavailable state; do not infer one*.
///
/// The [reason] is passed through to [phaseUnavailableCopy] rather than
/// switched on here, so P6 changes one function instead of this widget.
///
/// It carries no date and no promise, per ruling R-10 — the same rule the tab
/// placeholders follow. It is informational, so it is a [MergeSemantics] unit
/// and never a button: nothing is wired behind it, and announcing "button"
/// for a tap that does nothing is worse than announcing nothing.
class LumenPhaseUnavailable extends StatelessWidget {
  const LumenPhaseUnavailable({required this.reason, super.key});

  /// The `unavailableReason` the API gave, verbatim. `null` when the envelope
  /// omitted it — every generated DTO field is nullable.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final copy = phaseUnavailableCopy(reason);

    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.heading,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              copy.body,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: c.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
