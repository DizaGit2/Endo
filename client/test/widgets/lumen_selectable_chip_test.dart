// Tests for LumenSelectableChip — screen 12's selectable chip geometry
// (P4b-T19c).
//
// This chip is NOT a promotion of either private `_Chip`: the survey found
// `day_detail_screen.dart`'s `_Chip` is a different, read-only widget with no
// tap at all, and `cycle_setup_screen.dart`'s `_Chip` is selectable but at a
// different radius, font size, unselected text colour and with a weight
// change on select — belongs to a shipped screen and is left alone by
// controller ruling. See `lumen_selectable_chip.dart`'s class doc for the
// full comparison. What this file pins is screen 12's OWN measured geometry
// and its own three-token colour pair, asserted against `lumenLight`/
// `lumenDark` rather than hard-coded hex, exactly as `lumen_selectable_row_
// test.dart` does for its widget.
//
// What it ANNOUNCES is asserted in `lumen_selectable_chip_semantics_test.dart`,
// which the widget registry requires.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
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
  Brightness brightness = Brightness.light,
}) {
  taps = 0;
  return pumpApp(
    tester,
    brightness: brightness,
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

/// The chip's own box — the first [Container] under it, which is the one this
/// widget builds.
Container _box(WidgetTester tester) => tester.widget<Container>(
  find.descendant(of: _chip, matching: find.byType(Container)).first,
);

BoxDecoration _decoration(WidgetTester tester) =>
    _box(tester).decoration! as BoxDecoration;

TextStyle _labelStyle(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _chip, matching: find.byType(Text)))
    .style!;

void main() {
  // -------------------------------------------------------------------------
  // Content and taps
  // -------------------------------------------------------------------------

  testWidgets('draws the label it is given, unaltered — no case transform', (
    tester,
  ) async {
    // Mixed-case on purpose: a widget that sentence-cased or upper-cased this
    // would fail here, and that transform belongs to the row above the
    // chips (T20's, via LumenFieldLabel), never to the chip's own text.
    await _pumpChip(tester, label: 'lower Case Label');

    expect(
      find.descendant(of: _chip, matching: find.text('lower Case Label')),
      findsOneWidget,
    );
  });

  testWidgets('a tap runs the callback exactly once', (tester) async {
    await _pumpChip(tester);

    await tester.tap(_chip);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a disabled chip ignores taps', (tester) async {
    // The control is the test above: the same tap on the same handle runs
    // the callback when the chip is enabled, so "0" here is the disabling
    // and not a tap that missed.
    await _pumpChip(tester, enabled: false);

    await tester.tap(_chip);
    await tester.pump();

    expect(taps, 0);
  });

  // -------------------------------------------------------------------------
  // Geometry — screen_12_symptom_form.html, measured
  // -------------------------------------------------------------------------

  group('geometry — screen 12\'s measured chip', () {
    testWidgets('padding is 6 vertical / 10 horizontal, radius 14', (
      tester,
    ) async {
      await _pumpChip(tester);

      expect(
        _box(tester).padding,
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      );
      expect(_decoration(tester).borderRadius, BorderRadius.circular(14));
    });

    testWidgets('the label is drawn at 11px in both selection states', (
      tester,
    ) async {
      await _pumpChip(tester, selected: false);
      expect(_labelStyle(tester).fontSize, 11);

      await _pumpChip(tester, selected: true);
      expect(_labelStyle(tester).fontSize, 11);
    });

    testWidgets(
      'selection changes no font weight — the mockup applies none, unlike '
      'cycle_setup_screen.dart\'s chip',
      (tester) async {
        await _pumpChip(tester, selected: false);
        final unselectedWeight = _labelStyle(tester).fontWeight;

        await _pumpChip(tester, selected: true);
        final selectedWeight = _labelStyle(tester).fontWeight;

        expect(selectedWeight, unselectedWeight);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Colour tokens (light) — selection changes ONLY these three
  // -------------------------------------------------------------------------

  group('colour tokens (light)', () {
    testWidgets(
      'unselected: input fill, border outline, MUTED text — not ink',
      (tester) async {
        await _pumpChip(tester);

        expect(_decoration(tester).color, lumenLight.input);
        expect(
          (_decoration(tester).border! as Border).top.color,
          lumenLight.border,
        );
        expect(_labelStyle(tester).color, lumenLight.muted);
      },
    );

    testWidgets('selected: accentSoft fill, accent outline, accent text', (
      tester,
    ) async {
      await _pumpChip(tester, selected: true);

      expect(_decoration(tester).color, lumenLight.accentSoft);
      expect(
        (_decoration(tester).border! as Border).top.color,
        lumenLight.accent,
      );
      expect(_labelStyle(tester).color, lumenLight.accent);
    });
  });

  // -------------------------------------------------------------------------
  // Colour tokens (dark) — the tokens must actually be read from the theme
  // -------------------------------------------------------------------------

  group('colour tokens (dark)', () {
    testWidgets('unselected takes the dark palette', (tester) async {
      await _pumpChip(tester, brightness: Brightness.dark);

      expect(_decoration(tester).color, lumenDark.input);
      expect(
        (_decoration(tester).border! as Border).top.color,
        lumenDark.border,
      );
      expect(_labelStyle(tester).color, lumenDark.muted);
    });

    testWidgets('selected takes the dark palette', (tester) async {
      await _pumpChip(tester, selected: true, brightness: Brightness.dark);

      expect(_decoration(tester).color, lumenDark.accentSoft);
      expect(
        (_decoration(tester).border! as Border).top.color,
        lumenDark.accent,
      );
      expect(_labelStyle(tester).color, lumenDark.accent);
    });
  });
}
