// Tests for LumenFieldMessage (P4b-T5c).
//
// Promoted from the `_FieldMessage` that existed BYTE-IDENTICALLY in
// `cycle_setup_screen.dart` (screen 3) and `baseline_screen.dart` (screen 4).
//
// It carries one field's rejection in the SERVER's own words: the backdate
// floor is `users.created_at - 2 years` and no endpoint returns `created_at`,
// so a client-side paraphrase could not be written even if we wanted one.
// Everything here therefore guards against the message being transformed on
// the way to the screen.
//
// CSS equivalent: `color: var(--ac); font-size: 12px; line-height: 1.4`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';

import '../support/harness.dart';

const _message = 'date is before the earliest allowed date';

Future<void> _pumpMessage(
  WidgetTester tester, {
  String message = _message,
  Brightness brightness = Brightness.light,
}) => pumpApp(
  tester,
  brightness: brightness,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: LumenFieldMessage(message),
    ),
  ),
);

TextStyle _style(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(LumenFieldMessage),
        matching: find.byType(Text),
      ),
    )
    .style!;

void main() {
  testWidgets('renders the message unchanged', (tester) async {
    await _pumpMessage(tester);

    expect(find.text(_message), findsOneWidget);
    // The sibling widget in this promotion, LumenFieldLabel, uppercases what
    // it is given. This one must not: the string is the server's, and the
    // first assertion is the control that says the message was rendered at
    // all.
    expect(find.text(_message.toUpperCase()), findsNothing);

    // Presence is not visibility: a zero-height run, or one painted at zero
    // alpha, satisfies `find.text` and paints nothing.
    final size = tester.getSize(find.text(_message));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    expect(_style(tester).color!.a, 1.0);
  });

  testWidgets('is accent-coloured, 12/1.4', (tester) async {
    await _pumpMessage(tester);
    final style = _style(tester);

    expect(style.color, lumenLight.accent);
    expect(style.fontSize, 12);
    expect(style.height, 1.4);
  });

  testWidgets('takes its colour from the dark palette in dark mode', (
    tester,
  ) async {
    // Trip-wire on the premise: if the two palettes ever agree on `accent`,
    // this test discriminates nothing and should be deleted rather than
    // trusted.
    expect(lumenDark.accent, isNot(lumenLight.accent));

    await _pumpMessage(tester, brightness: Brightness.dark);

    expect(_style(tester).color, lumenDark.accent);
  });
}
