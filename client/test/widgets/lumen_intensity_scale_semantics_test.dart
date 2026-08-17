// Accessibility tests for LumenIntensityScale (P4b-T5, brief §3).
//
// The brief's requirement is specific: "a screen-reader user must be able to
// read and set the value. Give it a Semantics value and label, and make the
// increment/decrement affordance reachable without a drag gesture."
//
// That is two separate obligations and both are asserted here:
//   * READ — the container node carries the label ('Pain level') and a value
//     that distinguishes "not recorded" from "0".
//   * SET  — every stop is an individually labelled, activatable button (no
//     drag involved at all), AND the row offers increase/decrease so someone
//     navigating by node does not have to find one target out of eleven.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';

import '../support/harness.dart';

late List<int> reported;

Future<void> _pumpScale(
  WidgetTester tester, {
  required int? value,
  bool enabled = true,
}) {
  reported = <int>[];
  return pumpApp(
    tester,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LumenIntensityScale(
          value: value,
          enabled: enabled,
          semanticsLabel: 'Pain level',
          onChanged: reported.add,
        ),
      ),
    ),
  );
}

/// The scale's own container node (the one carrying the label).
SemanticsNode _scaleNode(WidgetTester tester) =>
    tester.getSemantics(find.byType(LumenIntensityScale));

SemanticsData _scaleData(WidgetTester tester) =>
    _scaleNode(tester).getSemanticsData();

/// Invokes [action] on the scale's node the way an assistive technology would.
///
/// Reached through the node's own [SemanticsOwner] rather than through
/// `tester.binding.pipelineOwner`, which is deprecated.
void _perform(WidgetTester tester, SemanticsAction action) {
  final node = _scaleNode(tester);
  node.owner!.performAction(node.id, action);
}

void main() {
  // -------------------------------------------------------------------------
  // Reading the value
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('announces what it measures', (tester) async {
    await _pumpScale(tester, value: 3);

    expect(_scaleData(tester).label, contains('Pain level'));
  });

  testWidgetsWithSemantics('announces the current value', (tester) async {
    await _pumpScale(tester, value: 3);

    expect(_scaleData(tester).value, '3 out of 10');
  });

  testWidgetsWithSemantics('announces 0 as a value, not as nothing', (
    tester,
  ) async {
    await _pumpScale(tester, value: 0);

    expect(_scaleData(tester).value, '0 out of 10');
  });

  testWidgetsWithSemantics('announces "not recorded" when nothing is logged', (
    tester,
  ) async {
    await _pumpScale(tester, value: null);

    expect(_scaleData(tester).value, 'Not recorded');
  });

  testWidgetsWithSemantics('the announced value follows the value it is given', (
    tester,
  ) async {
    // Pinning the update, not just one snapshot: a widget that hard-coded its
    // semantics value would pass any single assertion above.
    await _pumpScale(tester, value: null);
    expect(_scaleData(tester).value, 'Not recorded');

    await _pumpScale(tester, value: 0);
    expect(_scaleData(tester).value, '0 out of 10');

    await _pumpScale(tester, value: 10);
    expect(_scaleData(tester).value, '10 out of 10');
  });

  // -------------------------------------------------------------------------
  // Setting the value without a drag
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('every stop is a labelled, activatable button', (
    tester,
  ) async {
    await _pumpScale(tester, value: 3);

    for (var stop = 0; stop <= 10; stop++) {
      expectLabeledButton(
        tester,
        find.text('$stop'),
        '$stop',
        exactLabel: true,
      );
    }
  });

  testWidgetsWithSemantics('the current stop announces itself as selected', (
    tester,
  ) async {
    await _pumpScale(tester, value: 3);

    expect(
      tester.getSemantics(find.text('3')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(find.text('4')).flagsCollection.isSelected,
      Tristate.isFalse,
    );
  });

  // -------------------------------------------------------------------------
  // The disabled state
  // -------------------------------------------------------------------------
  //
  // T18 disables the scale while a write is in flight. Without an explicit
  // enabled flag the stops keep `isButton` and simply lose their tap action —
  // a screen-reader user swipes across eleven nodes announced as buttons,
  // double-taps do nothing, and nothing announces "dimmed". That is exactly
  // the failure `a11y_guard.dart`'s expectLabeledButton exists to catch.

  testWidgetsWithSemantics('an enabled stop announces as enabled', (
    tester,
  ) async {
    await _pumpScale(tester, value: 3);

    for (var stop = 0; stop <= 10; stop++) {
      final data = tester.getSemantics(find.text('$stop')).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }
  });

  testWidgetsWithSemantics(
    'a disabled stop announces as DISABLED, not as a dead button',
    (tester) async {
      await _pumpScale(tester, value: 3, enabled: false);

      for (var stop = 0; stop <= 10; stop++) {
        final data = tester.getSemantics(find.text('$stop')).getSemanticsData();

        expect(
          data.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason:
              'stop $stop is announced as a button with no tap action and no '
              'enabled state — "looks like a button, cannot be activated, '
              'never says why".',
        );
        expect(data.hasAction(SemanticsAction.tap), isFalse);
      }
    },
  );

  testWidgetsWithSemantics('a disabled scale offers no increase or decrease', (
    tester,
  ) async {
    await _pumpScale(tester, value: 3, enabled: false);
    final data = _scaleData(tester);

    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isFalse);
    // …and the value is still readable: disabled is not silent.
    expect(data.value, '3 out of 10');
  });

  testWidgetsWithSemantics('offers increase and decrease actions', (
    tester,
  ) async {
    await _pumpScale(tester, value: 3);
    final data = _scaleData(tester);

    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    expect(data.increasedValue, '4 out of 10');
    expect(data.decreasedValue, '2 out of 10');
  });

  testWidgetsWithSemantics('increase and decrease actually change the value', (
    tester,
  ) async {
    await _pumpScale(tester, value: 3);

    _perform(tester, SemanticsAction.increase);
    _perform(tester, SemanticsAction.decrease);
    await tester.pump();

    expect(reported, <int>[4, 2]);
  });

  testWidgetsWithSemantics('increase from "not recorded" selects 0', (
    tester,
  ) async {
    await _pumpScale(tester, value: null);

    expect(_scaleData(tester).increasedValue, '0 out of 10');
    // …and there is nothing below "no value", so decrease is not offered —
    // an action that announced a change it could not make would be a lie.
    expect(_scaleData(tester).hasAction(SemanticsAction.decrease), isFalse);
  });

  testWidgetsWithSemantics('neither action is offered past the bounds', (
    tester,
  ) async {
    await _pumpScale(tester, value: 10);
    expect(_scaleData(tester).hasAction(SemanticsAction.increase), isFalse);
    expect(_scaleData(tester).hasAction(SemanticsAction.decrease), isTrue);

    await _pumpScale(tester, value: 0);
    expect(_scaleData(tester).hasAction(SemanticsAction.increase), isTrue);
    expect(_scaleData(tester).hasAction(SemanticsAction.decrease), isFalse);
  });

  // -------------------------------------------------------------------------
  // House rules
  // -------------------------------------------------------------------------

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpScale(tester, value: 3);

    expectNoDingbats(tester, screen: 'LumenIntensityScale');
  });
}
