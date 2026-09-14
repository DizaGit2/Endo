// Tests for LumenSectionLabel (P4b-T5b).
//
// The oldest of the shared widgets and, until this task, the only one with no
// test of its own — covered incidentally through the screens that render it,
// which means a token drift here would have been reported as three unrelated
// screen goldens moving.
//
// CSS equivalent (the design system's section tags):
//   `text-transform: uppercase; letter-spacing: 1px; color: var(--sg);
//    font-size: 10-11px; font-weight: 500`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// Pumps the label, passing `fontSize`/`letterSpacing` ONLY when the caller
/// gave them.
///
/// The distinction is the whole point of the defaults test: passing 10.0/1.0
/// explicitly asserts that the widget honours its arguments, which is a
/// different claim from "the default is 10.0" and stays green when the default
/// changes.
Future<void> _pumpLabel(
  WidgetTester tester, {
  String text = 'App lock',
  double? fontSize,
  double? letterSpacing,
  Brightness brightness = Brightness.light,
}) => pumpApp(
  tester,
  brightness: brightness,
  home: Scaffold(
    body: fontSize == null && letterSpacing == null
        ? LumenSectionLabel(text)
        : LumenSectionLabel(
            text,
            fontSize: fontSize ?? 10.0,
            letterSpacing: letterSpacing ?? 1.0,
          ),
  ),
);

TextStyle _style(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(LumenSectionLabel),
        matching: find.byType(Text),
      ),
    )
    .style!;

void main() {
  testWidgets('uppercases the text it is given', (tester) async {
    await _pumpLabel(tester, text: 'Data and privacy');

    expect(find.text('DATA AND PRIVACY'), findsOneWidget);
    expect(find.text('Data and privacy'), findsNothing);
  });

  testWidgets('is sage, w500, 10/1.0 by default', (tester) async {
    // No fontSize, no letterSpacing: the constructor's own defaults are the
    // subject here.
    await _pumpLabel(tester);
    final style = _style(tester);

    expect(style.color, lumenLight.sage);
    expect(style.fontWeight, FontWeight.w500);
    expect(style.fontSize, 10);
    expect(style.letterSpacing, 1.0);
  });

  testWidgets('takes the size and spacing it is given', (tester) async {
    // The dashboard band uses 11/1.5; settings uses the default. Both are call
    // sites in the tree, so both are pinned.
    await _pumpLabel(tester, fontSize: 11, letterSpacing: 1.5);
    final style = _style(tester);

    expect(style.fontSize, 11);
    expect(style.letterSpacing, 1.5);
  });

  testWidgets('takes its colour from the dark palette in dark mode', (
    tester,
  ) async {
    await _pumpLabel(tester, brightness: Brightness.dark);

    expect(_style(tester).color, lumenDark.sage);
  });
}
