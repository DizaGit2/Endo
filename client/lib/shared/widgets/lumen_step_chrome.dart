import 'package:flutter/material.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

/// The onboarding eyebrow — "Step 3 of 7 · Cycle" — and the one place the
/// flow's position is announced to assistive tech.
///
/// Every screen from 1 to 7 carries this line (`Screens/screen_0*.html`, the
/// `.tag` rule: 11 px, sage, `text-transform: uppercase`, 1.5 px tracking,
/// weight 500). It is promoted to a shared widget because seven screens print
/// it, but the reason it is a widget rather than a string is accessibility.
///
/// **The deficiency it closes (recorded by P4b-T5b).** [LumenStepDots] is
/// decoration and announces nothing — correct for seven coloured boxes — so the
/// eyebrow is the only place the step position reaches a screen reader at all.
/// And it did not reach one usefully: [LumenSectionLabel] renders
/// `text.toUpperCase()`, so what assistive tech received was
/// `STEP 3 OF 7 · CYCLE` — an all-caps run that many screen readers spell out
/// letter by letter, punctuated by a middle dot read as noise.
///
/// So this widget draws the uppercased string and **announces a sentence-case
/// one**, with the separator spoken as a comma:
///
/// | | drawn | announced |
/// |---|---|---|
/// | screens 3-7 | `STEP 3 OF 7 · CYCLE` | `Step 3 of 7, Cycle` |
/// | screen 2 | `STEP 2 OF 7` | `Step 2 of 7` |
/// | screen 1 | `LUMEN · 1 OF 7` | `Lumen, step 1 of 7` |
///
/// The visible text is excluded from semantics rather than merely accompanied
/// by a better label — otherwise both strings are in the tree and the user
/// hears the shouted one too. `excludeSemantics` drops no action here: the
/// chrome is not interactive and has none.
///
/// It is flagged `header: true` so a heading-navigation gesture lands on it:
/// the eyebrow is the first thing on every onboarding screen, and "which step
/// am I on" should not require swiping from the top.
///
/// Props:
/// - [step] — the 1-based position in the flow (1-7).
/// - [totalSteps] — the flow's length; the eyebrow's denominator.
/// - [title] — the eyebrow's trailing word(s) (`Cycle`, `About you`, …), or
///   null on the screens whose mockup prints none (screen 2).
/// - [lead] — a word the mockup puts BEFORE the position instead of "Step".
///   Screen 1 alone prints `Lumen · 1 of 7`, and it is the reason this is a
///   parameter rather than a raw visible-string override: the drawn text is the
///   only place the product's name appears on that screen, so an override that
///   changed only what is drawn would delete "Lumen" from what a screen reader
///   ever hears. [lead] carries into BOTH strings.
class LumenStepChrome extends StatelessWidget {
  const LumenStepChrome({
    required this.step,
    required this.totalSteps,
    this.title,
    this.lead,
    super.key,
  }) : assert(
         step >= 1 && step <= totalSteps,
         'A step outside the flow cannot be announced honestly: the eyebrow is '
         'a promise about how much of the flow remains.',
       ),
       assert(
         lead == null || title == null,
         'No mockup prints both a lead word and a title, and the eyebrow has '
         'room for one separator. Pick the one the screen actually draws.',
       );

  /// The 1-based position in the flow.
  final int step;

  /// How many steps the flow has.
  final int totalSteps;

  /// The eyebrow's trailing word(s), verbatim from the mockup, or null.
  final String? title;

  /// A word the mockup puts before the position instead of "Step", or null.
  final String? lead;

  /// What is drawn (before the uppercase transform [LumenSectionLabel]
  /// applies).
  String get eyebrowText {
    if (lead != null) return '$lead · $step of $totalSteps';
    return title == null
        ? 'Step $step of $totalSteps'
        : 'Step $step of $totalSteps · $title';
  }

  /// What a screen reader announces.
  ///
  /// Sentence case, with every separator spoken as a comma, so the shape is the
  /// same on all seven screens even where the drawn copy is not. Composed from
  /// the parts rather than transformed from [eyebrowText]: the drawn string is
  /// where the shouting and the middle dots live, and deriving one from the
  /// other is how they would come back.
  String get announcement {
    final buffer = StringBuffer();
    buffer.write(lead == null ? 'Step ' : '$lead, step ');
    buffer.write('$step of $totalSteps');
    if (title != null) buffer.write(', $title');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: announcement,
      excludeSemantics: true,
      child: LumenSectionLabel(eyebrowText, fontSize: 11, letterSpacing: 1.5),
    );
  }
}
