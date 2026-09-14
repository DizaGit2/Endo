// ---------------------------------------------------------------------------
// a11y_guard_test.dart — the guard's own tests (P4b-T5d)
// ---------------------------------------------------------------------------
//
// `test/support/a11y_guard.dart` is the gate every screen must pass, and the
// screen registry MANDATES it. Until this file existed the gate had no tests of
// its own, and three of its matchers asserted more than their bodies enforced:
//
//   * [expectLabeledButton] read `SemanticsNode.label` and the node's OWN
//     flags, while reading MERGED `hasAction` — so a control whose name or
//     button flag arrives from a merged descendant read as an unnamed
//     non-button, which is the shape every two-line chip has.
//   * [expectNotAButton] had the SILENT form of the same bug: own flags, so a
//     row that a screen reader announces as a button passed the "this is not a
//     button" guard.
//   * [expectLiveRegionAt] likewise read the node's own live-region flag.
//   * [expectNoDingbats] was a three-item blocklist (`✦ ✓ ›`) holding the wrong
//     chevron — the mockups draw `‹` (U+2039) 33 times and `›` (U+203A) never.
//
// Every fixture below is built from `MergeSemantics`, because that is what the
// house rule asks a row to be and what `SemanticsNode.getSemanticsData()` — the
// data assistive tech actually receives — is defined against. Each test that
// asserts a matcher SEES something first asserts the node's own data does not,
// so the fixture is doing the work the test claims it is.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_step_chrome.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The stable handle for the row under test in every fixture.
const Key _row = ValueKey<String>('row');

Finder get _rowFinder => find.byKey(_row);

/// A merged row whose BUTTON-ness and second name both arrive from a nested
/// control that owns its own semantics node.
///
/// This is the shape of any row with an inline affordance (screen 32's "Edit"
/// beside the display name is the shipped example). The row's own node
/// announces only the plain text beside the control; what a screen reader
/// receives is the merge of the two.
Widget _rowWithNestedButton({bool enabled = true}) => Scaffold(
  body: MergeSemantics(
    key: _row,
    child: Row(
      children: <Widget>[
        const Text('Sleep quality'),
        TextButton(
          onPressed: enabled ? () {} : null,
          child: const Text('Add'),
        ),
      ],
    ),
  ),
);

/// A merged two-line chip: the button flag is the chip's own, the FIRST line of
/// its name belongs to a descendant that owns a node.
///
/// The chip announces "Includes estradiol\nEstrogen"; its own label is only the
/// half that was absorbed.
Widget _mergedChip() => MergeSemantics(
  key: _row,
  child: Semantics(
    button: true,
    onTap: () {},
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(container: true, child: const Text('Estrogen')),
        const Text('Includes estradiol'),
      ],
    ),
  ),
);

/// A merged informational row — the house shape for a row with no wired tap.
Widget _informationalRow() => const MergeSemantics(
  key: _row,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[Text('Face ID'), Text('Required to open')],
  ),
);

/// A merged row whose live region is a descendant that owns its own node —
/// a field label with a failure message beneath it.
Widget _rowWithNestedLiveRegion() => MergeSemantics(
  key: _row,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const Text('Weight'),
      Semantics(
        container: true,
        liveRegion: true,
        child: const Text('Could not save'),
      ),
    ],
  ),
);

/// One [Text] carrying [content], and nothing else — the smallest tree
/// [expectNoDingbats] will accept.
Widget _text(String content) => Text(content);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The node's OWN data — what the defective matchers read.
SemanticsNode _own(WidgetTester tester) => tester.getSemantics(_rowFinder);

/// What assistive tech receives.
SemanticsData _merged(WidgetTester tester) => _own(tester).getSemanticsData();

/// Runs [body] and returns the [TestFailure] it threw.
///
/// Fails the test when [body] returns normally — "the matcher rejected this"
/// is the assertion, so a matcher that quietly accepted must not read as a
/// pass.
TestFailure _failureFrom(void Function() body) {
  Object? thrown;
  try {
    body();
  } on TestFailure catch (failure) {
    thrown = failure;
  }
  // An `expect` rather than a `fail`, deliberately: a bare `fail` prints a
  // sentence with no `Expected:`/`Actual:` block, and that block is what the
  // phase's mutation rule uses to tell a failed EXPECTATION from a tap that
  // missed or a finder that matched nothing. Without it a real kill here reads
  // as an INVALID_RUN.
  expect(
    thrown,
    isA<TestFailure>(),
    reason: 'Expected the matcher to reject this tree, and it accepted it.',
  );
  return thrown! as TestFailure;
}

void main() {
  // -------------------------------------------------------------------------
  // expectLabeledButton — reads the merged name and the merged flags
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'expectLabeledButton sees a button flag carried by a merged descendant',
    (tester) async {
      await pumpApp(tester, home: _rowWithNestedButton());

      // Premise: the node's OWN data says this is not a button and is not
      // named "Add" — which is all the matcher used to read.
      expect(_own(tester).flagsCollection.isButton, isFalse);
      expect(_own(tester).label, 'Sleep quality');
      // …while what a screen reader receives is a button called "Add".
      expect(_merged(tester).flagsCollection.isButton, isTrue);
      expect(_merged(tester).label, 'Sleep quality\nAdd');

      expectLabeledButton(tester, _rowFinder, 'Add');
    },
  );

  testWidgetsWithSemantics(
    'expectLabeledButton sees a name carried by a merged descendant',
    (tester) async {
      await pumpApp(tester, home: _mergedChip());

      // Premise: the flag is the chip's own — only the NAME is merged, so this
      // case isolates the label read from the flag read.
      expect(_own(tester).flagsCollection.isButton, isTrue);
      expect(_own(tester).label, 'Includes estradiol');
      expect(_merged(tester).label, 'Includes estradiol\nEstrogen');

      expectLabeledButton(tester, _rowFinder, 'Estrogen');
    },
  );

  testWidgetsWithSemantics('expectLabeledButton compares the MERGED name when '
      'exactLabel is set', (tester) async {
    await pumpApp(tester, home: _rowWithNestedButton());

    expectLabeledButton(
      tester,
      _rowFinder,
      'Sleep quality\nAdd',
      exactLabel: true,
    );

    // The control: exactLabel is still an equality, so the half of the name
    // the old matcher read is now rejected.
    final TestFailure failure = _failureFrom(
      () => expectLabeledButton(
        tester,
        _rowFinder,
        'Sleep quality',
        exactLabel: true,
      ),
    );
    expect(failure.message, contains('accessible name'));
  });

  testWidgetsWithSemantics(
    'expectLabeledButton still rejects a node that no screen reader calls a '
    'button',
    (tester) async {
      await pumpApp(tester, home: _informationalRow());

      // Nothing in this row is a button — merged or own.
      expect(_merged(tester).flagsCollection.isButton, isFalse);

      final TestFailure failure = _failureFrom(
        () => expectLabeledButton(tester, _rowFinder, 'Face ID'),
      );
      expect(failure.message, contains('flagged as a button'));
    },
  );

  testWidgetsWithSemantics(
    'expectLabeledButton still rejects a button with nothing to activate',
    (tester) async {
      await pumpApp(tester, home: _rowWithNestedButton(enabled: false));

      // Premise: it still ANNOUNCES a button — that is the failure mode, not
      // the absence of one.
      expect(_merged(tester).flagsCollection.isButton, isTrue);
      expect(_merged(tester).hasAction(SemanticsAction.tap), isFalse);

      final TestFailure failure = _failureFrom(
        () => expectLabeledButton(tester, _rowFinder, 'Add'),
      );
      expect(failure.message, contains('no tap action'));
    },
  );

  // -------------------------------------------------------------------------
  // expectNotAButton — the converse, and the silent one
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'expectNotAButton rejects a row whose button flag sits on a merged '
    'descendant',
    (tester) async {
      await pumpApp(tester, home: _rowWithNestedButton());

      // Premise: the row's OWN flags say "not a button", which is exactly why
      // this passed the guard while a screen reader announced one.
      expect(_own(tester).flagsCollection.isButton, isFalse);
      expect(_merged(tester).flagsCollection.isButton, isTrue);

      final TestFailure failure = _failureFrom(
        () => expectNotAButton(tester, _rowFinder),
      );
      expect(failure.message, contains('announces itself as a button'));
    },
  );

  testWidgetsWithSemantics(
    'expectNotAButton accepts the informational row it exists to bless',
    (tester) async {
      await pumpApp(tester, home: _informationalRow());

      expectNotAButton(
        tester,
        _rowFinder,
        merged: const <String>['Face ID', 'Required to open'],
      );
    },
  );

  testWidgetsWithSemantics(
    'expectNotAButton reads its merged: strings from the merged name',
    (tester) async {
      await pumpApp(tester, home: _rowWithNestedLiveRegion());

      // Premise: "Could not save" is NOT in the row's own label.
      expect(_own(tester).label, 'Weight');
      expect(_merged(tester).label, 'Weight\nCould not save');

      expectNotAButton(
        tester,
        _rowFinder,
        merged: const <String>['Weight', 'Could not save'],
      );

      // The control: a string that is in neither is still rejected.
      final TestFailure failure = _failureFrom(
        () => expectNotAButton(
          tester,
          _rowFinder,
          merged: const <String>['Height'],
        ),
      );
      expect(failure.message, contains('one unit'));
    },
  );

  // -------------------------------------------------------------------------
  // expectLiveRegionAt
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'expectLiveRegionAt sees a live region carried by a merged descendant',
    (tester) async {
      await pumpApp(tester, home: _rowWithNestedLiveRegion());

      // Premise: the row's own flag says it is not a live region.
      expect(_own(tester).flagsCollection.isLiveRegion, isFalse);
      expect(_merged(tester).flagsCollection.isLiveRegion, isTrue);

      expectLiveRegionAt(tester, _rowFinder);
    },
  );

  testWidgetsWithSemantics(
    'expectLiveRegionAt still rejects a row that announces nothing',
    (tester) async {
      await pumpApp(tester, home: _informationalRow());

      expect(_merged(tester).flagsCollection.isLiveRegion, isFalse);

      final TestFailure failure = _failureFrom(
        () => expectLiveRegionAt(tester, _rowFinder, describedAs: 'the row'),
      );
      expect(failure.message, contains('live region'));
    },
  );

  // -------------------------------------------------------------------------
  // expectNoDingbats — a closed rule, not a three-item blocklist
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'expectNoDingbats rejects the chevron the mockups actually draw (U+2039)',
    (tester) async {
      await pumpApp(tester, home: _text('‹ Back'));

      final TestFailure failure = _failureFrom(() => expectNoDingbats(tester));
      expect(failure.message, contains('U+2039'));
    },
  );

  testWidgetsWithSemantics(
    'expectNoDingbats rejects any un-allowlisted codepoint above U+007F',
    (tester) async {
      // Neither of these was on the old three-item blocklist, and neither is
      // an emoji: the rule is the codepoint range, not a curated list.
      for (final String glyph in const <String>['→', '✓', '✦']) {
        await pumpApp(tester, home: _text('Continue $glyph'));
        final TestFailure failure = _failureFrom(
          () => expectNoDingbats(tester),
        );
        expect(
          failure.message,
          contains('U+${glyph.runes.single.toRadixString(16).toUpperCase()}'),
        );
      }
    },
  );

  testWidgetsWithSemantics('expectNoDingbats rejects an emoji, and names the '
      'codepoint above U+FFFF in full', (tester) async {
    await pumpApp(tester, home: _text('Saved \u{1F319}'));

    final TestFailure failure = _failureFrom(() => expectNoDingbats(tester));
    expect(failure.message, contains('U+1F319'));
  });

  testWidgetsWithSemantics(
    'expectNoDingbats reads Text.rich, not only Text.data',
    (tester) async {
      await pumpApp(
        tester,
        home: const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: 'Step 1 '),
              TextSpan(text: '‹'),
            ],
          ),
        ),
      );

      final TestFailure failure = _failureFrom(() => expectNoDingbats(tester));
      expect(failure.message, contains('U+2039'));
    },
  );

  testWidgetsWithSemantics(
    'expectNoDingbats does not mistake an inlined widget for a glyph',
    (tester) async {
      // `TextSpan.toPlainText` substitutes U+FFFC for a WidgetSpan, and screens
      // 36 and 37 inline an Icon exactly that way — so the naive read reports a
      // codepoint that is not drawn.
      await pumpApp(
        tester,
        home: const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              WidgetSpan(child: Icon(Icons.auto_awesome, size: 12)),
              TextSpan(text: ' Lumen has never received a request'),
            ],
          ),
        ),
      );

      expectNoDingbats(tester, screen: 'An inlined icon');

      // The control: the rest of the same rich text is still read.
      await pumpApp(
        tester,
        home: const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              WidgetSpan(child: Icon(Icons.auto_awesome, size: 12)),
              TextSpan(text: ' Lumen ✦'),
            ],
          ),
        ),
      );
      final TestFailure failure = _failureFrom(() => expectNoDingbats(tester));
      expect(failure.message, contains('U+2726'));
    },
  );

  testWidgetsWithSemantics(
    'expectNoDingbats still rejects an empty tree',
    (tester) async {
      await pumpApp(tester, home: const SizedBox.shrink());

      final TestFailure failure = _failureFrom(
        () => expectNoDingbats(tester, screen: 'Nothing'),
      );
      expect(failure.message, contains('rendered no Text widgets'));
    },
  );

  // -------------------------------------------------------------------------
  // …and what the allowlist keeps green
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'the middle dot every step eyebrow draws is allowed',
    (tester) async {
      // The real widget, not a hand-typed string: `lumen_step_chrome.dart`
      // draws U+00B7 in all seven eyebrows, so an allowlist without it would
      // redden every existing onboarding screen.
      await pumpApp(
        tester,
        home: const Scaffold(
          body: LumenStepChrome(step: 5, totalSteps: 7, title: 'Goals'),
        ),
      );

      expect(find.textContaining('·'), findsOneWidget);
      expectNoDingbats(tester, screen: 'LumenStepChrome');
    },
  );

  testWidgetsWithSemantics(
    'the allowlist admits precomposed letters only, and says which mark it '
    'caught',
    (tester) async {
      // Control first: the precomposed form is admitted, so what follows is a
      // fact about the ENCODING and not about the letter.
      await pumpApp(tester, home: _text('A\u00F1adir'));
      expectNoDingbats(tester, screen: 'NFC');

      // The same word in NFD — `n` followed by U+0303 COMBINING TILDE. The rule
      // is per codepoint, so it fails, and it names the mark rather than the
      // letter. The fix for real copy is to normalise it, NOT to admit bare
      // combining marks: that would let every accented glyph through.
      await pumpApp(tester, home: _text('An\u0303adir'));
      final TestFailure failure = _failureFrom(() => expectNoDingbats(tester));
      expect(failure.message, contains('U+0303'));
    },
  );

  // -------------------------------------------------------------------------
  // expectLabeledField's contract
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'a plain Material field still appends its placeholder',
    (tester) async {
      // Why [expectLabeledField] asks for a PREFIX rather than an equality.
      // `LumenInputField` stopped appending its placeholder at P4b-T5d, so this
      // fixture is a bare Material field — the shape the matcher must still
      // accept, and the only remaining reason its contract is `startsWith`.
      await pumpApp(
        tester,
        home: Scaffold(
          body: Semantics(
            label: 'Name',
            child: const TextField(
              decoration: InputDecoration(hintText: 'Maya'),
            ),
          ),
        ),
      );

      // The premise, stated so the matcher below is not the only thing that
      // knows it: Flutter really does put the placeholder in the name here.
      expect(
        tester
            .getSemantics(find.byType(EditableText))
            .getSemanticsData()
            .label,
        'Name\nMaya',
      );

      expectLabeledField(tester, find.byType(TextField), 'Name');
    },
  );

  // -------------------------------------------------------------------------
  // What a finder means to these matchers
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'a finder inside a merged row resolves to the ROW, not to the widget named',
    (tester) async {
      await pumpApp(tester, home: _rowWithNestedButton());

      // `tester.getSemantics` walks up past every isMergedIntoParent ancestor,
      // so these two finders are the same node. That is what makes the matchers
      // assert about what is ANNOUNCED…
      expect(
        tester.getSemantics(find.text('Sleep quality')).id,
        tester.getSemantics(_rowFinder).id,
      );

      // …and it is also the trap the dartdocs warn about: this passes, and the
      // text it names is not the button. One assertion per ROW, stating the
      // whole announced name — never one per line.
      //
      // Only the id comparison above is framework-only. THIS line is ordinary
      // repo-dependent code and is killable: reverting `expectLabeledButton` to
      // read the node's own flags (mutation M1) reddens it with
      // `Expected a node flagged as a button for "Add"`.
      expectLabeledButton(tester, find.text('Sleep quality'), 'Add');
    },
  );

  testWidgetsWithSemantics('legitimate copy is allowed', (tester) async {
    const List<String> allowed = <String>[
      // es-ES letters and marks — R-04 permits English strings today, and
      // `localeProvider` already resolves es-ES.
      '¿Cuántos días? ¡Añádelo! ÁÉÍÓÚÜÑ',
      // Typographic punctuation, all of it already in shipped copy or one
      // paste away from it.
      'It’s ‘here’ “now” — or – later…',
      // Units and measure signs later phases need.
      '37.2° ±5 ×2 ≤ 40 ≥ 30 µg/dL μg/dL',
      // The password placeholder screen 2 draws.
      '••••••••',
    ];

    for (final String copy in allowed) {
      await pumpApp(tester, home: _text(copy));
      expectNoDingbats(tester, screen: 'Legitimate copy');
    }
  });
}
