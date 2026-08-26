// Tests for LumenFieldLabel (P4b-T5c).
//
// Promoted from the `_FieldLabel` that existed twice: verbatim in
// `cycle_setup_screen.dart` (screen 3), and with an added `announce` flag in
// `baseline_screen.dart` (screen 4). The promoted widget carries the flag, so
// screen 3's call sites keep the always-announced behaviour they had (the
// flag's default) and screen 4's keep theirs.
//
// CSS equivalent (the mockups' `.lb`):
//   `text-transform: uppercase; letter-spacing: .5px; color: var(--mut);
//    font-size: 11px; font-weight: 500`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';

import '../support/harness.dart';

/// Pumps the label, passing `announce` ONLY when the caller gave it.
///
/// The distinction is the point of the defaults test: passing `announce: true`
/// explicitly asserts the widget honours its argument, which is a different
/// claim from "the default announces" — and screen 3's call sites depend on
/// the default, not on the argument.
Future<void> _pumpLabel(
  WidgetTester tester, {
  String text = 'Average cycle length',
  bool? announce,
  Brightness brightness = Brightness.light,
}) => pumpApp(
  tester,
  brightness: brightness,
  home: Scaffold(
    body: announce == null
        ? LumenFieldLabel(text)
        : LumenFieldLabel(text, announce: announce),
  ),
);

TextStyle _style(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(LumenFieldLabel),
        matching: find.byType(Text),
      ),
    )
    .style!;

void main() {
  testWidgets('uppercases the text it is given', (tester) async {
    await _pumpLabel(tester, text: 'Date of birth');

    // The first assertion is the control for the second: "the sentence case is
    // not drawn" is also true of a screen that drew nothing at all.
    expect(find.text('DATE OF BIRTH'), findsOneWidget);
    expect(find.text('Date of birth'), findsNothing);
  });

  testWidgets('is muted, w500, 11/0.5', (tester) async {
    await _pumpLabel(tester);
    final style = _style(tester);

    expect(style.color, lumenLight.muted);
    expect(style.fontWeight, FontWeight.w500);
    expect(style.fontSize, 11);
    expect(style.letterSpacing, 0.5);
  });

  testWidgets('takes its colour from the dark palette in dark mode', (
    tester,
  ) async {
    // Trip-wire on the premise: if the two palettes ever agree on `muted`,
    // this test passes without discriminating anything and should be deleted
    // rather than trusted.
    expect(lumenDark.muted, isNot(lumenLight.muted));

    await _pumpLabel(tester, brightness: Brightness.dark);

    expect(_style(tester).color, lumenDark.muted);
  });

  testWidgets('draws the same visible run whether or not it announces', (
    tester,
  ) async {
    // The reconciliation, stated as a test: `announce` changes what a screen
    // reader gets and NOTHING about what is painted. Screen 3 and screen 4
    // draw their labels identically and always did.
    await _pumpLabel(tester, text: 'Height', announce: false);
    final silentStyle = _style(tester);
    final silentSize = tester.getSize(find.text('HEIGHT'));

    // Presence is not visibility: a zero-width run, or one painted at zero
    // alpha, satisfies `find.text` and paints nothing.
    expect(find.text('HEIGHT'), findsOneWidget);
    expect(silentSize.width, greaterThan(0));
    expect(silentSize.height, greaterThan(0));
    expect(silentStyle.color!.a, 1.0);

    await _pumpLabel(tester, text: 'Height', announce: true);

    expect(_style(tester), silentStyle);
    expect(tester.getSize(find.text('HEIGHT')), silentSize);
  });
}
