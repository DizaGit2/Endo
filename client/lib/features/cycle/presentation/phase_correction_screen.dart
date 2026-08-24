// Screen 14 — phase correction (P4b-T23).
//
// **It ships as the documented phase-unavailable state, and it writes
// nothing.** That is ruling R-08, and the reasons are worth reading before
// anyone is tempted to improve on it: `ARCHITECTURE.md` §C.0.3 fixes the phase
// envelope at `{ available: false, unavailableReason: ... }` for every account
// and puts **no** `phase`, `cycleDay` or `confidence` key on any day row, so
// there is no predicted timeline to correct *from*; there is no endpoint to
// read a cycle's existing overrides *back*; and §C.0.1 calls that endpoint's
// `boundaries` field — verbatim — *"the most dangerous field on the P4a
// surface"*, because `boundaries: []` soft-deletes every correction while
// `boundaries: null` is a 400 and the generated Dart renders both as one
// nullable field. A correction UI over an absent prediction would be a form
// that invents the thing it claims to correct, and wiring a destructive write
// with no read-back and no baseline is how user data is lost. The write, the
// editor and the entry affordance all land together in P6.
//
// ## What the mockup draws, and what is CUT
//
// `Screens/screen_14_phase_correction.html` is an editor. Everything in it
// that edits is gone, under R-08 and R-16 (*copy describing machinery this
// phase does not ship is removed, not reworded into a promise*):
//
//  * the four-band phase timeline SVG with its three draggable markers, and
//    its `Mens` / `Foll` / `Ovul` / `Luteal` band labels — there is no
//    predicted timeline to draw, and drawing one would be the invented
//    clinical claim §C.0.3 exists to forbid;
//  * `EDITING — OVULATION START`, the `Day 14` readout and its `−` / `+`
//    steppers — the boundary editor itself;
//  * `Your edit will retrain the prediction model` — named in R-16 as copy
//    that never renders: `ARCHITECTURE.md` locks the phase engine as
//    deterministic C# rules, so there is no model and nothing retrains. Its
//    leading `✦` (U+2726) is outside `kAllowedNonAsciiGlyphs` and could not
//    have shipped as text regardless;
//  * `Save correction` and `Reset to predicted` — both are writes;
//  * `Correct phase`, `Adjust your timeline` and `Drag the markers to match
//    what you felt` — three headings for a control set that is not here.
//    **Cut rather than reworded**: a heading is what advertises a feature, and
//    this screen advertises none.
//
// `test/features/cycle/phase_correction_screen_test.dart` asserts every one of
// those strings absent, so a later edit cannot restore one silently — the
// shape T22c used for screen 36's cut App-lock section. The full list is in
// this task's report for P6 to pick up.
//
// ## What is left, and why it is a screen at all
//
// The back chevron, and [LumenPhaseUnavailable] — its **third** production
// call site after screens 8 and 10 (R1: reuse it, do not author a second
// unavailable-state widget and do not restyle the shared one to suit this
// screen). No new user-visible string is authored here: the chevron is named
// by `MaterialLocalizations`, and the block's own copy already ships on two
// screens.
//
// ## Nothing navigates here
//
// R-08 requires the route, the screen, the goldens and the semantics; it does
// not require reachability, and an affordance whose destination can only
// answer *"phases aren't available yet"* is the inert navigation R-10 hides
// rather than disables. R-20 forbids shipping half an affordance, so the entry
// point lands in P6 with the write. See [Routes.cyclePhase]'s own dartdoc for
// the full ruling and for the deliberate contrast with screen 36, which was
// unreachable while advertising a feature that WORKED.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

// ---------------------------------------------------------------------------
// PhaseCorrectionScreen
// ---------------------------------------------------------------------------

/// Screen 14 — the Cycle tab's phase-correction surface, which in P4b can only
/// state that there is no phase to correct.
///
/// **The reason is READ off the response, never embedded here.** P4a answers
/// `phase_engine_not_implemented` for every account today, so hard-coding that
/// string would render identically and pass every text assertion — and would
/// keep this screen claiming the engine is missing *after P6 ships it*. P4a's
/// review caught the identical shape one layer down, where a `[DefaultValue]`
/// on the nullable `unavailableReason` would have left the generated client
/// unable to ever observe `null`; a screen that embeds the reason is that same
/// defect wearing a different hat. [LumenPhaseUnavailable] resolves whatever
/// arrives through `phaseUnavailableCopy`, which is the one function P6 edits.
class PhaseCorrectionScreen extends ConsumerWidget {
  const PhaseCorrectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;

    // The SAME envelope the calendar beneath this route is rendering —
    // `cycle_calendar_screen.dart`'s `_Body` passes `CycleCalendarView.phase`'s
    // own `unavailableReason` to this same widget, off this same controller.
    // Screen 14 is a CHILD of `Routes.cycle`, so that controller is
    // already built and already holds the answer, deep link included (go_router
    // materialises the branch root's page beneath a child route; T21b's probe
    // C measured it for `/cycle/day/:date` and `_leaveDayDetail` records it).
    // Reading it here rather than issuing a second calendar read costs no round
    // trip and, more importantly, makes it impossible for this screen and the
    // one it sits on top of to disagree about the phase state — which is the
    // whole of what this screen says. What it does NOT take from that
    // controller is the visible month, the day rows or the paging: only
    // `CycleCalendarView.phase`, whose own dartdoc records that P4a answers
    // the same envelope for every window.
    //
    // **The nullable `AsyncValue.value` rather than a `when`, deliberately:
    // this screen has no loading state and no retry.** Every arm of that read
    // means the same thing here — Lumen cannot tell you your phase.
    // `phaseUnavailableCopy`'s neutral copy is documented as true of every
    // reason the engine can give and is what it resolves an ABSENT reason to,
    // calling that "the safe direction". So a spinner would report something
    // in flight that cannot change the answer (`TabPlaceholderScreen`'s own
    // rule: *no progress indicator — there is nothing in flight to report*),
    // and a retry affordance would be an affordance pointing at nothing, which
    // is exactly what R-10 removes. **The read is still real**: when the
    // envelope resolves, ITS reason is what this screen forwards — which is
    // the whole of R2, and what the varying-reason tests pin.
    //
    // `AsyncValue.value` is `ValueT?` and never throws — `requireValue` is the
    // accessor that does (`riverpod-3.3.2/lib/src/core/async_value.dart`) —
    // and it is the same accessor every controller in this package reads its
    // own state through.
    final reason = ref
        .watch(cycleCalendarControllerProvider)
        .value
        ?.phase
        ?.unavailableReason;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // In the LAYOUT rather than a `Positioned` overlay — screen 11's
            // arrangement (`day_detail_screen.dart`, `DayDetailScreen.build`),
            // adopted here so the three Cycle-branch screens agree. Nothing
            // scrolls on this screen today, which is precisely when to adopt
            // it: there is nothing to lose yet.
            //
            // `semanticLabel` on the Icon, NOT `tooltip:` — Material surfaces
            // a tooltip as a separate semantics field rather than the button's
            // own label, which would leave this control announcing nothing.
            // The WORD is `MaterialLocalizations`' own translated name for
            // this control, not copy this screen invented.
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(
                    Icons.chevron_left,
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                  ),
                  color: c.muted,
                  onPressed: () => _leavePhaseCorrection(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: LumenPhaseUnavailable(reason: reason),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leaves screen 14: pops when there is something to pop, and otherwise goes
/// to the Cycle tab.
///
/// **The `canPop` guard is the house idiom, and on this screen the deep link
/// is not a corner case — it is the only way in.** Nothing navigates here in
/// P4b (R3), so every arrival is a cold link, which makes "where does Back go"
/// the whole of this screen's navigation contract rather than an edge of it.
/// The measured answer is that it pops: `/cycle/phase` is a CHILD `GoRoute`
/// under `/cycle` inside the Cycle `StatefulShellBranch`, so go_router
/// materialises the calendar page beneath it even on a cold link — T21b's
/// probe C measured exactly that for `/cycle/day/:date`, and
/// `_leaveDayDetail`'s dartdoc records it. The guard ships anyway, for the
/// reason that dartdoc gives: a future route-table change must not be able to
/// turn a cold link into `context.pop()` on the root of the stack, which
/// throws.
///
/// [Routes.cycle] rather than [Routes.home], for screen 11's reason: this
/// screen's own branch root IS the cycle calendar, so a user with no back
/// stack lands where the ordinary pop would have taken them rather than in
/// another tab.
void _leavePhaseCorrection(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.cycle);
  }
}
