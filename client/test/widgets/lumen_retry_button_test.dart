// Tests for LumenRetryButton — the promoted `_RetryButton` (P4b-T5).
//
// TDD (RED first): `_RetryButton` was private to `profile_screen.dart`, and
// P4b-T1 then lifted its styling verbatim into `app_router.dart` as an inline
// `OutlinedButton` on the splash's gate-unavailable surface. Two copies of a
// secondary affordance is already one too many with thirteen screens to go.
//
// It stays a dumb StatelessWidget with no Riverpod dependency: `ref.invalidate`
// belongs at the call site, which is what lets the same button serve the
// profile controller, the onboarding-status controller and whatever P4b's
// screens invalidate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';

import '../support/harness.dart';

Future<void> _pumpButton(
  WidgetTester tester, {
  String label = 'Try again',
  Brightness brightness = Brightness.light,
}) {
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: Center(
        child: LumenRetryButton(label: label, onPressed: () {}),
      ),
    ),
  );
}

ButtonStyle _style(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!;

void main() {
  testWidgets('renders the label it was given', (tester) async {
    await _pumpButton(tester, label: 'Retry');

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a tap runs the callback exactly once', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      home: Scaffold(
        body: Center(
          child: LumenRetryButton(
            label: 'Try again',
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgetsWithSemantics('announces as a labelled, activatable button', (
    tester,
  ) async {
    await _pumpButton(tester);

    expectLabeledButton(
      tester,
      find.text('Try again'),
      'Try again',
      exactLabel: true,
    );
  });

  testWidgets('is an outlined secondary affordance in accent on border', (
    tester,
  ) async {
    await _pumpButton(tester);
    final style = _style(tester);

    expect(style.foregroundColor!.resolve(<WidgetState>{}), lumenLight.accent);
    expect(
      style.side!.resolve(<WidgetState>{})!.color,
      lumenLight.border,
    );
  });

  testWidgets('keeps the shipped geometry: radius 14, 24/10 padding, 13/w500', (
    tester,
  ) async {
    await _pumpButton(tester);
    final style = _style(tester);

    expect(
      style.shape!.resolve(<WidgetState>{}),
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    expect(
      style.padding!.resolve(<WidgetState>{}),
      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    );
    final text = style.textStyle!.resolve(<WidgetState>{})!;
    expect(text.fontSize, 13);
    expect(text.fontWeight, FontWeight.w500);
  });

  testWidgets('takes its colours from the dark palette in dark mode', (
    tester,
  ) async {
    await _pumpButton(tester, brightness: Brightness.dark);
    final style = _style(tester);

    expect(style.foregroundColor!.resolve(<WidgetState>{}), lumenDark.accent);
    expect(style.side!.resolve(<WidgetState>{})!.color, lumenDark.border);
  });
}
