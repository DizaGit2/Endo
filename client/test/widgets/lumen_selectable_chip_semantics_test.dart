// Accessibility tests for LumenSelectableChip (P4b-T19c).
//
// The house pattern this pins is `lumen_selectable_row.dart`'s: `MergeSemantics`
// over a `Semantics(button:, selected:, enabled:)` that adds the facts a merge
// cannot derive, with the announced NAME arriving from the child `Text` through
// the merge — never authored via `label:` + `excludeSemantics: true`, which is
// the obsolete pattern `cycle_setup_screen.dart`'s own `_Chip` still carries
// (left alone by controller ruling; see the widget's class doc). A test that
// would fail if someone reintroduced that pattern with no authored label is the
// point of the second test below.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';

import '../support/harness.dart';

const Key _chipKey = ValueKey<String>('chip');

Finder get _chip => find.byKey(_chipKey);

late int taps;

Future<void> _pumpChip(
  WidgetTester tester, {
  bool selected = false,
  bool enabled = true,
  String label = 'Bloating',
}) {
  taps = 0;
  return pumpApp(
    tester,
    home: Scaffold(
      body: LumenSelectableChip(
        key: _chipKey,
        label: label,
        selected: selected,
        enabled: enabled,
        onTap: () => taps++,
      ),
    ),
  );
}

SemanticsData _announced(WidgetTester tester) =>
    tester.getSemantics(_chip).getSemanticsData();

void main() {
  // -------------------------------------------------------------------------
  // What it announces
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('announces as a labelled button', (tester) async {
    await _pumpChip(tester, label: 'Bloating');

    expectLabeledButton(tester, _chip, 'Bloating', exactLabel: true);
  });

  testWidgetsWithSemantics(
    'the announced name is exactly the drawn label, arriving via the merge — '
    'a test that would fail if excludeSemantics: true reappeared with no '
    'authored label',
    (tester) async {
      await _pumpChip(tester, label: 'Cramping');

      expect(_announced(tester).label, 'Cramping');
    },
  );

  // -------------------------------------------------------------------------
  // Selected
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('announces its selected state', (tester) async {
    await _pumpChip(tester, selected: false);
    expect(_announced(tester).flagsCollection.isSelected, Tristate.isFalse);

    await _pumpChip(tester, selected: true);
    expect(_announced(tester).flagsCollection.isSelected, Tristate.isTrue);
  });

  // -------------------------------------------------------------------------
  // Enabled, and the action behind the announcement
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'an enabled chip offers a tap action and says it is enabled',
    (tester) async {
      await _pumpChip(tester);

      expect(_announced(tester).flagsCollection.isEnabled, Tristate.isTrue);
      expect(_announced(tester).hasAction(SemanticsAction.tap), isTrue);
    },
  );

  testWidgetsWithSemantics(
    'a disabled chip announces as DISABLED and offers no tap action',
    (tester) async {
      await _pumpChip(tester, enabled: false);

      expect(
        _announced(tester).flagsCollection.isEnabled,
        Tristate.isFalse,
        reason:
            'A chip that keeps isButton and merely loses its tap action is '
            '"looks like a button, cannot be activated, never says why".',
      );
      expect(_announced(tester).hasAction(SemanticsAction.tap), isFalse);
      // …and it still announces what it is: disabled is not silent.
      expect(_announced(tester).label, 'Bloating');
    },
  );

  testWidgetsWithSemantics(
    'the tap action assistive tech invokes runs the callback',
    (tester) async {
      await _pumpChip(tester);

      // Performing the SemanticsAction, not a pointer gesture: a chip whose
      // hit target works but whose semantics action was dropped stays green
      // under `tester.tap` and red here.
      final SemanticsNode node = tester.getSemantics(_chip);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();

      expect(taps, 1);
    },
  );

  testWidgetsWithSemantics('a disabled chip invokes nothing', (tester) async {
    await _pumpChip(tester, enabled: false);

    await tester.tap(_chip);
    await tester.pump();

    expect(taps, 0);
  });

  // -------------------------------------------------------------------------
  // House rules
  // -------------------------------------------------------------------------

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpChip(tester);

    expectNoDingbats(tester, screen: 'LumenSelectableChip');
  });
}
