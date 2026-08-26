// Accessibility tests for LumenSelectableRow (P4b-T5d).
//
// This row is the promotion of `goals_screen.dart`'s `_GoalTile` and
// `baseline_screen.dart`'s `_StatusOption`, and it is the widget whose SHAPE
// changed in the promotion: both originals wrapped their content in
// `Semantics(label: …, excludeSemantics: true)` because `expectLabeledButton`
// read a node's OWN label and could not see a merged one. That matcher defect
// is fixed in the same task, so the row now merges — and the properties below
// are what the merge has to deliver:
//
//   * ONE node, named by what the row actually draws, byte-identical to the
//     string the two call sites used to author by hand;
//   * the button, selected and enabled facts a merge cannot derive;
//   * a tap action assistive tech can invoke — not just a pointer target;
//   * and a descendant added later is ANNOUNCED rather than silently dropped,
//     which is the property `excludeSemantics: true` could not offer.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

import '../support/harness.dart';

const Key _rowKey = ValueKey<String>('row');

Finder get _row => find.byKey(_rowKey);

late int taps;

/// A two-line row, the shape screen 5 draws: a title over a sub-description.
Future<void> _pumpRow(
  WidgetTester tester, {
  bool? selected = false,
  bool enabled = true,
  List<Widget> extra = const <Widget>[],
}) {
  taps = 0;
  return pumpApp(
    tester,
    home: Scaffold(
      body: LumenSelectableRow(
        key: _rowKey,
        selected: selected,
        enabled: enabled,
        onTap: () => taps++,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Manage symptoms'),
            const Text('Find pain & flare patterns'),
            ...extra,
          ],
        ),
      ),
    ),
  );
}

SemanticsData _announced(WidgetTester tester) =>
    tester.getSemantics(_row).getSemanticsData();

void main() {
  // -------------------------------------------------------------------------
  // What it announces
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('announces as ONE labelled button', (tester) async {
    await _pumpRow(tester);

    // The name is an equality, not a containment: what this row must not do is
    // announce its two lines as two stops, and a containment check cannot tell
    // the difference.
    expectLabeledButton(
      tester,
      _row,
      'Manage symptoms\nFind pain & flare patterns',
      exactLabel: true,
    );
  });

  testWidgetsWithSemantics(
    'the announced name is byte-identical to the string the call sites used to '
    'author',
    (tester) async {
      await _pumpRow(tester);

      // Screen 5 wrote `'${option.title}\n${option.description}'` by hand under
      // `excludeSemantics: true`. The framework joins sibling labels with the
      // same line break, so the promotion changed no announced string — this
      // is the assertion that says so, in the form the old code wrote it.
      const String title = 'Manage symptoms';
      const String description = 'Find pain & flare patterns';
      expect(_announced(tester).label, '$title\n$description');
    },
  );

  testWidgetsWithSemantics(
    'a descendant added later is announced, not dropped',
    (tester) async {
      // Premise / control: without the badge the row announces two lines.
      await _pumpRow(tester);
      expect(_announced(tester).label, isNot(contains('3 logged')));

      await _pumpRow(tester, extra: const <Widget>[Text('3 logged')]);

      // Under `excludeSemantics: true` this string would be nowhere in the
      // semantics tree and nothing would have failed. That is the whole reason
      // the workaround did not survive the matcher fix.
      expect(
        _announced(tester).label,
        'Manage symptoms\nFind pain & flare patterns\n3 logged',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Selected
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('announces its selected state', (tester) async {
    // The control first: an unselected row announces NOT selected — not the
    // absence of the flag, which is what a row that never set it would give.
    await _pumpRow(tester);
    expect(_announced(tester).flagsCollection.isSelected, Tristate.isFalse);

    await _pumpRow(tester, selected: true);
    expect(_announced(tester).flagsCollection.isSelected, Tristate.isTrue);
  });

  testWidgetsWithSemantics(
    'selected: null OMITS the selected flag entirely — fix round 1, M-3: a '
    'pure launcher with no selection concept must not announce "not '
    'selected" (the bug the dashboard\'s Mood tile shipped with)',
    (tester) async {
      await _pumpRow(tester, selected: null);

      expect(
        _announced(tester).flagsCollection.isSelected,
        Tristate.none,
        reason:
            'Semantics(selected: null) never calls '
            '`config.isSelected = …` at all (measured against the Flutter '
            'SDK, rendering/object.dart: `if (_properties.selected != '
            'null)`), so the flag is not merely false — it is ABSENT, and '
            'a screen reader says nothing about selection rather than '
            '"not selected".',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Enabled, and the action behind the announcement
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('an enabled row offers a tap action and says it is '
      'enabled', (tester) async {
    await _pumpRow(tester);

    expect(_announced(tester).flagsCollection.isEnabled, Tristate.isTrue);
    expect(_announced(tester).hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgetsWithSemantics(
    'a disabled row announces as DISABLED, not as a dead button',
    (tester) async {
      await _pumpRow(tester, enabled: false);

      expect(
        _announced(tester).flagsCollection.isEnabled,
        Tristate.isFalse,
        reason:
            'A row that keeps isButton and merely loses its tap action is '
            '"looks like a button, cannot be activated, never says why".',
      );
      expect(_announced(tester).hasAction(SemanticsAction.tap), isFalse);
      // …and it still announces what it is: disabled is not silent.
      expect(
        _announced(tester).label,
        'Manage symptoms\nFind pain & flare patterns',
      );
    },
  );

  testWidgetsWithSemantics(
    'the tap action assistive tech invokes runs the callback',
    (tester) async {
      await _pumpRow(tester);

      // Performing the SemanticsAction, not a pointer gesture: a row whose hit
      // target works but whose semantics action was dropped stays green under
      // `tester.tap` and red here. Reached through the node's own owner, and
      // through the row's stable KEY rather than through what it announces.
      final SemanticsNode node = tester.getSemantics(_row);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();

      expect(taps, 1);
    },
  );

  testWidgetsWithSemantics('a disabled row invokes nothing', (tester) async {
    await _pumpRow(tester, enabled: false);

    await tester.tap(_row);
    await tester.pump();

    expect(taps, 0);
  });

  // -------------------------------------------------------------------------
  // House rules
  // -------------------------------------------------------------------------

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpRow(tester);

    expectNoDingbats(tester, screen: 'LumenSelectableRow');
  });
}
