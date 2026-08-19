// Tests for LumenSelectableRow — the promoted `_GoalTile`/`_StatusOption`
// (P4b-T5d).
//
// The two originals differed only in padding and corner radius, so those are
// the parameters, and everything a caller could have drifted on — the fill, the
// outline, the full-width box, the opaque hit behaviour — is not. What this
// file pins is that the shared row still draws each shipped screen's geometry
// exactly, because a promotion that re-spaced two live screens is not a
// refactor.
//
// What it ANNOUNCES is asserted in `lumen_selectable_row_semantics_test.dart`,
// which the widget registry requires.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

import '../support/harness.dart';

const Key _rowKey = ValueKey<String>('row');

Finder get _row => find.byKey(_rowKey);

late int taps;

Future<void> _pumpRow(
  WidgetTester tester, {
  bool selected = false,
  bool enabled = true,
  EdgeInsetsGeometry? padding,
  double? borderRadius,
  Brightness brightness = Brightness.light,
}) {
  taps = 0;
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: LumenSelectableRow(
        key: _rowKey,
        selected: selected,
        enabled: enabled,
        onTap: () => taps++,
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: borderRadius ?? 12,
        child: const Text('Manage symptoms'),
      ),
    ),
  );
}

/// The row's own box — the first [Container] under it, which is the one this
/// widget builds.
Container _box(WidgetTester tester) => tester.widget<Container>(
  find.descendant(of: _row, matching: find.byType(Container)).first,
);

BoxDecoration _decoration(WidgetTester tester) =>
    _box(tester).decoration! as BoxDecoration;

void main() {
  testWidgets('draws the child it was given', (tester) async {
    await _pumpRow(tester);

    expect(
      find.descendant(of: _row, matching: find.text('Manage symptoms')),
      findsOneWidget,
    );
  });

  testWidgets('a tap runs the callback exactly once', (tester) async {
    await _pumpRow(tester);

    await tester.tap(_row);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a disabled row ignores taps', (tester) async {
    // The control is the test above: the same tap on the same handle runs the
    // callback when the row is enabled, so "0" here is the disabling and not a
    // tap that missed.
    await _pumpRow(tester, enabled: false);

    await tester.tap(_row);
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('takes the accent pair when selected and the quiet pair when '
      'not', (tester) async {
    await _pumpRow(tester);
    expect(_decoration(tester).color, lumenLight.input);
    expect(
      (_decoration(tester).border! as Border).top.color,
      lumenLight.border,
    );

    await _pumpRow(tester, selected: true);
    expect(_decoration(tester).color, lumenLight.accentSoft);
    expect(
      (_decoration(tester).border! as Border).top.color,
      lumenLight.accent,
    );
  });

  testWidgets('takes its colours from the dark palette in dark mode', (
    tester,
  ) async {
    await _pumpRow(tester, selected: true, brightness: Brightness.dark);

    expect(_decoration(tester).color, lumenDark.accentSoft);
    expect((_decoration(tester).border! as Border).top.color, lumenDark.accent);
  });

  testWidgets('keeps screen 5\'s geometry: 14/12 padding, radius 12', (
    tester,
  ) async {
    await _pumpRow(tester);

    expect(
      _box(tester).padding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
    expect(
      _decoration(tester).borderRadius,
      BorderRadius.circular(12),
    );
  });

  testWidgets('keeps screen 4\'s tighter geometry when it asks for it: 12/11 '
      'padding, radius 10', (tester) async {
    await _pumpRow(
      tester,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      borderRadius: 10,
    );

    expect(
      _box(tester).padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    );
    expect(_decoration(tester).borderRadius, BorderRadius.circular(10));
  });

  testWidgets('spans the width it is given', (tester) async {
    await _pumpRow(tester);

    // `width: double.infinity` on the box, so a row in a column of rows lines
    // up with its neighbours whatever it contains.
    expect(
      tester.getSize(_row).width,
      tester.getSize(find.byType(Scaffold)).width,
    );
  });
}
