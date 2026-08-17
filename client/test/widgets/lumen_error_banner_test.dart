// Tests for LumenErrorBanner — the promoted `_ErrorBanner` (P4b-T5).
//
// TDD (RED first): this was private to `account_screen.dart`. Every P4b write
// screen (3-7, 9, 11, 12, 13, 32) surfaces a failed write the same way, so the
// banner — and, more importantly, its `liveRegion` semantics — has to be one
// widget rather than thirteen near-copies, one of which will forget the
// liveRegion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';

import '../support/harness.dart';

Future<void> _pumpBanner(
  WidgetTester tester, {
  String message = 'A server error occurred. Please try again later.',
  Brightness brightness = Brightness.light,
}) {
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(body: LumenErrorBanner(message: message)),
  );
}

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(LumenErrorBanner),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('renders the message it was given', (tester) async {
    await _pumpBanner(tester, message: 'That email is already registered.');

    expect(find.text('That email is already registered.'), findsOneWidget);
  });

  testWidgetsWithSemantics('announces itself as a live region', (tester) async {
    // The single most load-bearing assertion here: a banner that appears after
    // a failed write and is NOT a live region is silent for a screen-reader
    // user until they happen to swipe onto it.
    await _pumpBanner(tester, message: 'Could not save your changes.');

    expectLiveRegion(tester, 'Could not save your changes.');
  });

  testWidgets('sits on accent-soft with a 30%-accent hairline, radius 12', (
    tester,
  ) async {
    await _pumpBanner(tester);
    final decoration = _decoration(tester);

    expect(decoration.color, lumenLight.accentSoft);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(
      decoration.border,
      Border.all(color: lumenLight.accent.withValues(alpha: 0.3)),
    );
  });

  testWidgets('pads 14 horizontal / 12 vertical and fills the width', (
    tester,
  ) async {
    await _pumpBanner(tester);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(LumenErrorBanner),
        matching: find.byType(Container),
      ),
    );

    expect(
      container.padding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
    expect(container.constraints?.maxWidth, double.infinity);
  });

  testWidgets('the message is accent, 13/w400, 1.4 line height', (tester) async {
    await _pumpBanner(tester, message: 'Something failed.');
    final style = tester.widget<Text>(find.text('Something failed.')).style!;

    expect(style.color, lumenLight.accent);
    expect(style.fontSize, 13);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.height, 1.4);
  });

  testWidgets('takes its colours from the dark palette in dark mode', (
    tester,
  ) async {
    await _pumpBanner(tester, message: 'Dark.', brightness: Brightness.dark);

    expect(_decoration(tester).color, lumenDark.accentSoft);
    expect(
      tester.widget<Text>(find.text('Dark.')).style!.color,
      lumenDark.accent,
    );
  });
}
