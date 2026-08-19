// ---------------------------------------------------------------------------
// a11y_guard.dart — the shipped accessibility rules, as matchers (P4b-T3)
// ---------------------------------------------------------------------------
//
// Nothing here is a NEW standard. Every matcher is a promotion of an assertion
// the P3c `*_semantics_test.dart` files already make; the point is that a
// screen's semantics test should be three lines per rule, not thirty, because
// thirteen more screens are about to need them.
//
// The rules, and why each exists:
//
//   [expectNoDingbats]      Decorative glyphs are `Icon`s, not text. A screen
//                           reader announces "✦" as punctuation noise, and
//                           CLAUDE.md's no-emoji rule extends to them in
//                           spirit. The rule is a CLOSED one — every codepoint
//                           above U+007F fails unless it is on
//                           [kAllowedNonAsciiGlyphs] — because the blocklist it
//                           replaced held three glyphs out of the 31 the
//                           mockups draw, and the wrong chevron among them.
//   [expectLabeledButton]   Anything that announces itself as a button must
//                           have BOTH an accessible name and a tap action.
//                           `Semantics(excludeSemantics: true)` silently drops
//                           the child GestureDetector's action, so "looks like
//                           a button, cannot be activated" is the default
//                           failure mode, not an exotic one.
//   [expectNotAButton]      The converse, and just as load-bearing: a row with
//                           no wired onTap must be `MergeSemantics`, never
//                           `Semantics(button: true)`. Announcing "button" for
//                           a dead tap is worse than announcing nothing.
//   [expectLabeledField]    A text field's accessible name must start with its
//                           label. A field with no label of its own announces
//                           its PLACEHOLDER, and the label rendered above it is
//                           associated with nothing.
//   [expectLiveRegion]      An error/stale banner that appears after a failed
//                           write must announce itself, rather than waiting for
//                           the user to swipe onto it.
//   [expectLabeledSpinner]  A loading state must say what it is loading. An
//                           unlabeled spinner inside a button also steals that
//                           button's accessible name.
//
// Every matcher that inspects semantics needs the semantics tree switched on.
// Declare such a test with [testWidgetsWithSemantics] and it is handled — and
// handled correctly on failure, which the hand-written bracket was not.
//
// ## Every matcher reads `getSemanticsData()`, never the node's own fields
// (P4b-T5d)
//
// `SemanticsNode.label` and `SemanticsNode.flagsCollection` are a node's OWN
// annotation. What assistive tech receives is `getSemanticsData()`, which on a
// merging node folds in every descendant that KEPT a node of its own. Two
// separate mechanisms decide that, and they are worth telling apart:
//
//   * a descendant's configuration CONFLICTS with its ancestor's, so the two
//     cannot be folded — intersecting action bits, conflicting flags, both
//     carrying a non-empty value, an explicit role
//     (`SemanticsConfiguration.isCompatibleWith`, `semantics.dart:6684-6725`);
//   * or the descendant declares itself a boundary outright — `MergeSemantics`,
//     a `Semantics(container: true)`, an `identifier` — which sets
//     `config.isSemanticBoundary` (`object.dart:4929`) and never consults
//     `isCompatibleWith` at all.
//
// A nested button or text field is the first kind; an explicit container is the
// second. Either way the two views differ, which is the shape half the
// remaining screens have.
//
// Three matchers read the own fields, and one of them failed SILENTLY:
// [expectNotAButton] passed a row whose `button: true` sat on a merged
// descendant, which is precisely the case it exists to catch. All three now
// read `getSemanticsData()`. Non-merging nodes are unaffected — for them
// `getSemanticsData()` returns the node's own data — so this changed no call
// site (`test/shared/a11y_guard_test.dart` pins both halves).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

/// [testWidgets] with the semantics tree switched on for the whole body.
///
/// Replaces the `final handle = tester.ensureSemantics(); … handle.dispose();`
/// bracket every P3c test wrote by hand. That bracket was not merely verbose:
/// an `expect` failure part-way through skipped the `dispose()`, and the
/// leaked handle then failed the test with "A SemanticsHandle was active at
/// the end of the test" INSTEAD of the assertion that actually broke. The
/// `finally` here means the real failure is the one you read.
///
/// (`addTearDown(handle.dispose)` cannot do this job — flutter_test verifies
/// handle disposal at the end of the test BODY, before tearDowns run.)
void testWidgetsWithSemantics(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  bool? skip,
  Timeout? timeout,
}) {
  testWidgets(
    description,
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        handle.dispose();
      }
    },
    skip: skip,
    timeout: timeout,
  );
}

// ---------------------------------------------------------------------------
// Dingbats
// ---------------------------------------------------------------------------

/// The codepoints above U+007F a rendered [Text] may legitimately contain.
///
/// The rule [expectNoDingbats] enforces is the INVERSE of a blocklist: anything
/// above U+007F fails unless it is here. It was a blocklist — `✦ ✓ ›`, three of
/// the 31 distinct non-ASCII codepoints across the 38 mockups — and it held the
/// wrong chevron: the mockups draw `‹` (U+2039) 33 times and `›` (U+203A) not
/// once, so screens 6 and 7 would have caught none of theirs.
///
/// Every entry is here because a real string needs it. The first two are
/// load-bearing today — without them the rule reddens screens that ship:
///
///  * `·` U+00B7 — `lib/shared/widgets/lumen_step_chrome.dart:82,85` draws it
///    in all seven onboarding eyebrows, and
///    `lib/features/settings/presentation/help_about_screen.dart:83` prints
///    `Version 1.0 · build 142`.
///  * `•` U+2022 — the password placeholder
///    `lib/features/onboarding/presentation/account_screen.dart:173` hands
///    `LumenInputField`. `InputDecorator` renders `hintText` as a real [Text],
///    so it is inside this rule's reach (`test/widgets/
///    lumen_input_field_semantics_test.dart:97` draws the same string).
///  * `—` U+2014 — `profile_screen.dart:151,156,158,279` uses a lone em dash
///    as the "not set" value, and `cycle_setup_controller.dart:74,77` uses one
///    mid-sentence.
///
/// The rest are admitted so that legitimate copy the next screens will carry
/// does not have to argue with the guard: the es-ES letters and marks (R-04
/// permits English strings today; `localeProvider` already resolves es-ES),
/// typographic punctuation, and the measure signs the hormone and body screens
/// need.
///
/// **This is the narrowing, stated rather than left to the matcher's name.**
/// An entry admits a codepoint EVERYWHERE, so a screen may legally print `·`
/// anywhere. What the rule still guarantees is that no glyph outside this set
/// reaches a [Text] — including every dingbat, arrow and emoji.
///
/// **Precomposed forms only.** Each entry is one codepoint (`glyph.runes.single`
/// asserts that), so `ñ` here is U+00F1 and NOT `n` + U+0303. Decomposed (NFD)
/// text therefore fails, naming the combining mark — and the message's advice
/// to "add it to kAllowedNonAsciiGlyphs" would be the wrong fix: admitting bare
/// combining marks would let any accented glyph through. **Normalise the copy
/// to NFC instead.** Nothing in the app normalises today, so a localisation
/// pass that pastes NFD Spanish is where this would first be seen.
const kAllowedNonAsciiGlyphs = <String>{
  // ── Load-bearing in shipped copy ──────────────────────────────────────────
  '·', // U+00B7 MIDDLE DOT — the step eyebrows, the about screen's build line
  '•', // U+2022 BULLET — screen 2's password placeholder
  // ── es-ES letters and marks ───────────────────────────────────────────────
  'á', 'é', 'í', 'ó', 'ú', 'ü', 'ñ',
  'Á', 'É', 'Í', 'Ó', 'Ú', 'Ü', 'Ñ',
  '¿', '¡',
  // ── Typographic punctuation ───────────────────────────────────────────────
  '’', '‘', '“', '”', // U+2019 U+2018 U+201C U+201D
  '—', '–', // U+2014 EM DASH, U+2013 EN DASH
  '…', // U+2026 HORIZONTAL ELLIPSIS
  // ── Units and measure signs ───────────────────────────────────────────────
  'µ', // U+00B5 MICRO SIGN — what a keyboard types
  'μ', // U+03BC GREEK SMALL LETTER MU — what a lab report pastes
  '°', '±', '×', // U+00B0 U+00B1 U+00D7
  '≤', '≥', // U+2264 U+2265
};

/// [kAllowedNonAsciiGlyphs] as the codepoints [expectNoDingbats] compares
/// against.
final Set<int> _allowedCodepoints = <int>{
  for (final String glyph in kAllowedNonAsciiGlyphs) glyph.runes.single,
};

/// `U+00B7` for 0xB7 — four hex digits minimum, more when the codepoint needs
/// them, which is the notation the Unicode standard uses.
String _codepointName(int rune) =>
    'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// The DRAWN plain-text content of a [Text], covering both the plain `data`
/// constructor and the rich `Text.rich` (`textSpan`) form.
///
/// Two of `toPlainText`'s defaults are wrong for this job and both were caught
/// by real screens:
///
///  * `includePlaceholders` substitutes U+FFFC (OBJECT REPLACEMENT CHARACTER)
///    for every `WidgetSpan`. Screens 36 and 37 inline an `Icon` that way, so
///    the default reports a codepoint that is not drawn and belongs to no
///    glyph.
///  * `includeSemanticsLabels` substitutes a span's `semanticsLabel` for its
///    text — the opposite of what a rule about what is DRAWN wants to read.
String effectiveText(Text widget) {
  if (widget.data != null) return widget.data!;
  return widget.textSpan?.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      ) ??
      '';
}

/// Asserts no live [Text] renders a codepoint above U+007F that is not on
/// [kAllowedNonAsciiGlyphs].
///
/// The name is shorthand; the body is the general rule, and it fails CLOSED —
/// a glyph nobody thought of is a failure, not a pass. That is the whole reason
/// it replaced a blocklist: the blocklist covered 3 of the 31 non-ASCII
/// codepoints in the mockups, so it could only ever catch what someone had
/// already noticed. See [kAllowedNonAsciiGlyphs] for what is admitted and why.
///
/// The failure names the codepoint as `U+XXXX`, because half the glyphs this
/// catches are indistinguishable on a terminal from the one that is allowed —
/// `·` (U+00B7) against `•` (U+2022), `‹` (U+2039) against `<`.
///
/// Also fails when the tree contains no [Text] at all — that means the harness
/// never mounted the screen, and a guard that passes on an empty tree is the
/// guard this task exists to delete.
///
/// Every screen's `*_semantics_test.dart` must call this; the screen registry
/// (`test/shared/screen_registry_test.dart`) checks that it does.
void expectNoDingbats(WidgetTester tester, {String screen = 'The screen'}) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  expect(
    texts,
    isNotEmpty,
    reason: '$screen rendered no Text widgets — harness is likely broken.',
  );
  for (final widget in texts) {
    final text = effectiveText(widget);
    final int? offender = _firstDisallowedRune(text);
    // An `expect` rather than a `fail`, and the codepoint is the value under
    // test rather than a sentence: a bare `fail` prints no `Expected:`/
    // `Actual:` block, and that block is what the phase's mutation rule uses to
    // tell a failed expectation from a tap that missed. Three mutations aimed
    // at this matcher reported INVALID_RUN until it reported this way.
    expect(
      offender,
      isNull,
      reason: offender == null
          ? null
          : '$screen renders ${_codepointName(offender)} '
                '("${String.fromCharCode(offender)}") in Text: "$text". A '
                'decorative glyph belongs in an Icon — a screen reader '
                'announces it as punctuation noise. If it is legitimate copy, '
                'add it to kAllowedNonAsciiGlyphs with the string that needs '
                'it.',
    );
  }
}

/// The first codepoint in [text] above U+007F that is not allowlisted, or null.
int? _firstDisallowedRune(String text) {
  for (final int rune in text.runes) {
    if (rune <= 0x7F || _allowedCodepoints.contains(rune)) continue;
    return rune;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// Asserts the node at [finder] is a button, is named [label], and carries a
/// tap action assistive tech can actually invoke.
///
/// [exactLabel] makes the name assertion an EQUALITY rather than a
/// containment. Prefer it whenever the button's accessible name is fully known:
/// containment cannot see extra text merging INTO the name, which is exactly
/// the "a spinner inside a button steals that button's accessible name" failure
/// this guard exists to catch — `"Continue"` becoming `"Continue Signing in"`
/// passes a `contains` check and fails an equality one. Containment remains the
/// default only for nodes whose full name legitimately carries more than the
/// caller knows (a merged row, an icon-plus-text control).
///
/// [requireTapAction] exists only for the rare control whose activation is not
/// a tap; leaving it on is the rule.
///
/// Everything here is read from `getSemanticsData()` — the merged view. Before
/// P4b-T5d the flags and the name came from the node's OWN annotation while
/// only `hasAction` was merged, so a row whose button flag or name arrived from
/// a nested control read as an unnamed non-button and this matcher rejected a
/// perfectly good control.
///
/// **[finder] names a widget; the assertion is about the NODE it resolves
/// into.** `tester.getSemantics` walks up past every `isMergedIntoParent`
/// ancestor, so inside a merging row every descendant resolves to the SAME
/// node — the row's. That is right, because that node is what a screen reader
/// announces, but it means
/// `expectLabeledButton(tester, find.text('Sleep quality'), 'Sleep quality')`
/// passes against a row whose only button is a nested `Add`: the text is not
/// the button, and the assertion cannot fail. **Pass the row's own handle**
/// (its `Key`, or its widget type) and state the whole announced name, one
/// assertion per row rather than one per line. The same applies to
/// [expectNotAButton] and [expectLiveRegionAt].
void expectLabeledButton(
  WidgetTester tester,
  Finder finder,
  String label, {
  bool exactLabel = false,
  bool requireTapAction = true,
}) {
  final data = tester.getSemantics(finder).getSemanticsData();
  expect(
    data.flagsCollection.isButton,
    isTrue,
    reason: 'Expected a node flagged as a button for "$label".',
  );
  expect(
    data.label,
    exactLabel ? label : contains(label),
    reason: exactLabel
        ? 'Expected the button\'s accessible name to be exactly "$label". '
              'Anything merged into it (a spinner\'s semanticsLabel, a badge) '
              'replaces what a screen reader announces for this control.'
        : 'Expected the button\'s accessible name to contain "$label".',
  );
  if (requireTapAction) {
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason:
          'The button-flagged, labeled node "$label" has no tap action — a '
          'screen reader\'s "activate" gesture has nothing to invoke. If the '
          'control is wrapped in Semantics(excludeSemantics: true), that '
          'Semantics needs its own onTap, wired to the SAME callback as the '
          'child GestureDetector.',
    );
  }
}

// ---------------------------------------------------------------------------
// Text fields
// ---------------------------------------------------------------------------

/// Asserts the node at [finder] is a text field whose accessible name STARTS
/// with [label].
///
/// What must never happen is the placeholder arriving FIRST, which is what a
/// field with no label of its own does — it announces the hint, and the visible
/// label beside it is never associated with anything. (P4b-T5b.
/// `LumenInputField` shipped that way, promoted verbatim from
/// `account_screen.dart`'s private `_InputField`.)
///
/// **"Starts with", not "equals" — and the reason changed at P4b-T5d.** A plain
/// Material `TextField` appends its `hintText` to its accessible name while it
/// is empty, so `label` genuinely is a prefix there; that is pinned by
/// `test/shared/a11y_guard_test.dart`'s
/// `a plain Material field still appends its placeholder`.
/// **[LumenInputField] no longer does** — it draws its placeholder through
/// `ExcludeSemantics`, so its name is exactly its label — and a test about THAT
/// widget should assert the equality directly rather than leaning on this
/// matcher's looser contract (see `lumen_input_field_semantics_test.dart`).
///
/// One thing that never merged, recorded because the repo believed otherwise:
/// a `suffixText` does NOT join the field's name. `_AffixText` gives it a
/// `Semantics` node of its own beside the field
/// (`input_decorator.dart:1830-1834`), so screen 4's height field announces
/// `"Height"` and never `"Height\ncm"` — measured on both sides of T5d.
void expectLabeledField(WidgetTester tester, Finder finder, String label) {
  final data = tester.getSemantics(_fieldNode(finder)).getSemanticsData();
  expect(
    data.flagsCollection.isTextField,
    isTrue,
    reason: 'Expected a node flagged as a text field for "$label".',
  );
  expect(
    data.label.startsWith(label),
    isTrue,
    reason:
        'Expected the field\'s accessible name to begin with "$label", and it '
        'is "${data.label}". A screen reader announces this name when the user '
        'lands on the field: if it begins with the placeholder, the label '
        'rendered above the field was never associated with it.',
  );
}

/// The element whose semantics node IS the field's.
///
/// `tester.getSemantics(find.byType(TextField))` does not answer that:
/// `TextField`'s own render object carries no semantics, so the lookup walks UP
/// and returns whatever encloses it — the page, typically, whose label is empty.
/// The node belongs to the [EditableText] inside. Resolving it here is what
/// makes the failure read "the name is «Maya»" instead of "this is not a text
/// field", which is the message that sends someone debugging the harness rather
/// than fixing the field.
Finder _fieldNode(Finder finder) {
  final editable = find.descendant(
    of: finder,
    matching: find.byType(EditableText),
  );
  return editable.evaluate().isEmpty ? finder : editable.first;
}

/// Asserts the node at [finder] is NOT announced as a button, and (when
/// [merged] is given) that it reads as one unit containing those strings.
///
/// The house rule for an informational row: `MergeSemantics`, not
/// `Semantics(button: true)`.
///
/// Read from `getSemanticsData()`, and that is the point of the matcher rather
/// than a detail of it. Reading the node's OWN flags — which is what this did
/// before P4b-T5d — meant a row containing a nested button passed: the flag
/// sits on the descendant, the merge puts it on what the user hears, and the
/// guard looked at neither. It is the one failure in this file that was
/// silent, so nothing about the suite's colour ever hinted at it.
///
/// **[finder] names a widget; the assertion is about the NODE it resolves
/// into** — see [expectLabeledButton]. Inside a merging row every descendant
/// resolves to the row's node, so passing one line of a row asserts about the
/// whole row and not about that line. Pass the row's own handle.
void expectNotAButton(
  WidgetTester tester,
  Finder finder, {
  List<String> merged = const <String>[],
}) {
  final data = tester.getSemantics(finder).getSemanticsData();
  expect(
    data.flagsCollection.isButton,
    isFalse,
    reason:
        'This node announces itself as a button. If nothing is wired to it, '
        'that is a promise the screen cannot keep — use MergeSemantics.',
  );
  for (final part in merged) {
    expect(
      data.label,
      contains(part),
      reason: 'Expected the merged row to read "$part" as part of one unit.',
    );
  }
}

/// Every node in the live semantics tree that announces itself as a button.
final SemanticsFinder kAnyButtonSemantics = find.semantics.byPredicate(
  (SemanticsNode node) => node.getSemanticsData().flagsCollection.isButton,
  describeMatch: (_) => 'SemanticsNodes flagged as buttons',
);

/// Asserts the screen offers no button at all — for a destination that has
/// nothing to offer yet, where an affordance pointing at nothing is dishonest.
void expectNoButtons(WidgetTester tester, {String? reason}) {
  expect(kAnyButtonSemantics, findsNothing, reason: reason);
}

// ---------------------------------------------------------------------------
// Live regions
// ---------------------------------------------------------------------------

/// Asserts [message] is on screen exactly once AND is announced as a live
/// region.
void expectLiveRegion(WidgetTester tester, String message) {
  expect(
    find.text(message),
    findsOneWidget,
    reason: 'Expected the message "$message" to be on screen.',
  );
  expectLiveRegionAt(tester, find.text(message), describedAs: '"$message"');
}

/// [expectLiveRegion] for a banner that cannot be located by its exact string.
///
/// Reads `getSemanticsData()`: a banner nested inside a merging row carries its
/// live-region flag on the descendant, and the merged node is what announces
/// itself.
void expectLiveRegionAt(
  WidgetTester tester,
  Finder finder, {
  String describedAs = 'this node',
}) {
  final data = tester.getSemantics(finder).getSemanticsData();
  expect(
    data.flagsCollection.isLiveRegion,
    isTrue,
    reason:
        'Expected $describedAs to be a live region — otherwise a screen reader '
        'never hears about the failure unless the user happens to swipe onto '
        'it. Wrap the Text in Semantics(liveRegion: true, …).',
  );
}

// ---------------------------------------------------------------------------
// Spinners
// ---------------------------------------------------------------------------

/// Asserts a progress indicator is on screen and is announced as [label].
///
/// Note for the caller: never `pumpAndSettle()` a tree containing an
/// indeterminate `CircularProgressIndicator` — it animates forever, so settle
/// never arrives. Pump a fixed number of frames instead.
void expectLabeledSpinner(WidgetTester tester, String label) {
  // byWidgetPredicate, not byType: find.byType matches runtimeType exactly, so
  // it would never match CircularProgressIndicator against the abstract base.
  expect(
    find.byWidgetPredicate(
      (Widget w) => w is ProgressIndicator,
      description: 'a ProgressIndicator',
    ),
    findsWidgets,
    reason: 'Expected a progress indicator for the "$label" loading state.',
  );
  expect(
    find.bySemanticsLabel(label),
    findsOneWidget,
    reason:
        'Expected the spinner to carry semanticsLabel "$label". An unlabeled '
        'spinner announces nothing, and one inside a button takes over that '
        "button's accessible name.",
  );
}
