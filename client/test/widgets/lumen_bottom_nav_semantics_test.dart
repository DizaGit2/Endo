// Accessibility tests for LumenBottomNav (P4b-T5b).
//
// The bar is the chrome on every tab, so it is the control a screen-reader user
// meets most often. Three properties, each of which a plausible implementation
// breaks silently:
//
//   * every destination announces its name AND a tap action — a nav bar whose
//     items are decorative text is a dead end;
//   * the selected destination announces as SELECTED, which is the only way a
//     screen reader conveys "you are here" (the accent colour is not available
//     to it);
//   * the labels are real text, so `expectNoDingbats` applies.
//
// It is the second widget declared in `lumen_scaffold.dart` and it owns this
// file: the registry's unit is the widget, so `LumenScaffold`'s coverage does
// not stand in for it.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../support/harness.dart';

const _tabs = <String>['Home', 'Cycle', 'Hormones', 'Body', 'More'];

Future<List<int>> _pumpNav(WidgetTester tester, {int currentIndex = 0}) async {
  final selected = <int>[];
  await pumpApp(
    tester,
    home: Scaffold(
      body: const SizedBox.shrink(),
      bottomNavigationBar: LumenBottomNav(
        currentIndex: currentIndex,
        onDestinationSelected: selected.add,
      ),
    ),
  );
  return selected;
}

void main() {
  testWidgetsWithSemantics('every destination is named and activatable', (
    tester,
  ) async {
    await _pumpNav(tester);

    for (final tab in _tabs) {
      expectLabeledButton(tester, find.text(tab), tab);
    }
  });

  testWidgetsWithSemantics('the current destination announces as selected, '
      'and only it', (tester) async {
    await _pumpNav(tester, currentIndex: 2);

    for (var i = 0; i < _tabs.length; i++) {
      final data = tester.getSemantics(find.text(_tabs[i])).getSemanticsData();
      // `isSelected` is a Tristate, not a bool: comparing it against the
      // `isTrue` MATCHER passes for every value it can hold, which is an
      // assertion that cannot fail.
      expect(
        data.flagsCollection.isSelected,
        i == 2 ? Tristate.isTrue : isNot(Tristate.isTrue),
        reason:
            '${_tabs[i]} announced selected=${data.flagsCollection.isSelected} '
            'while the bar was on ${_tabs[2]}. "You are here" reaches a screen '
            'reader through this flag and nothing else — the accent colour '
            'does not.',
      );
    }
  });

  testWidgetsWithSemantics('activating a destination from the semantics tree '
      'switches tab', (tester) async {
    // What a screen reader's double-tap does. `expectLabeledButton` proves the
    // action is advertised; this proves the advertisement is wired.
    final selected = await _pumpNav(tester, currentIndex: 0);

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();

    expect(selected, <int>[3]);
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpNav(tester);

    expectNoDingbats(tester, screen: 'LumenBottomNav');
  });
}
