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
//                           spirit.
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

/// Glyphs that must never appear inside a [Text] widget's rendered content.
const kBannedGlyphs = <String>['✦', '✓', '›'];

/// The effective plain-text content of a [Text], covering both the plain
/// `data` constructor and the rich `Text.rich` (`textSpan`) form.
String effectiveText(Text widget) {
  if (widget.data != null) return widget.data!;
  return widget.textSpan?.toPlainText() ?? '';
}

/// Asserts no live [Text] renders any of [kBannedGlyphs].
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
    for (final glyph in kBannedGlyphs) {
      expect(
        text.contains(glyph),
        isFalse,
        reason: '$screen renders banned dingbat "$glyph" in Text: "$text"',
      );
    }
  }
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
void expectLabeledButton(
  WidgetTester tester,
  Finder finder,
  String label, {
  bool exactLabel = false,
  bool requireTapAction = true,
}) {
  final data = tester.getSemantics(finder);
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
      data.getSemanticsData().hasAction(SemanticsAction.tap),
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
/// "Starts with", not "equals": Flutter appends the placeholder to a field's
/// accessible name while the field is empty, so an empty `LumenInputField`
/// labelled `Name` with the hint `Maya` announces `"Name\nMaya"` and the same
/// field with text in it announces `"Name"` with the text as its *value*.
/// Both are correct; what must never happen is the placeholder arriving FIRST,
/// which is what a field with no label of its own does — it announces the hint
/// and the visible label beside it is never associated with anything.
///
/// (P4b-T5b. `LumenInputField` shipped that way, promoted verbatim from
/// `account_screen.dart`'s private `_InputField`, and thirteen screens are
/// about to take free text.)
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
void expectNotAButton(
  WidgetTester tester,
  Finder finder, {
  List<String> merged = const <String>[],
}) {
  final data = tester.getSemantics(finder);
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
void expectLiveRegionAt(
  WidgetTester tester,
  Finder finder, {
  String describedAs = 'this node',
}) {
  final data = tester.getSemantics(finder);
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
