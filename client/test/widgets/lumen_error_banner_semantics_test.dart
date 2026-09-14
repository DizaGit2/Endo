// Accessibility tests for LumenErrorBanner (P4b-T5b).
//
// The banner's decoration is the least important thing about it. What it exists
// to carry is `Semantics(liveRegion: true)`: it appears AFTER a failed write, at
// a moment when the user's attention is on the button they just pressed, and a
// banner that is not a live region says nothing at all until they happen to
// swipe onto it.
//
// The live-region assertion moved here from `lumen_error_banner_test.dart` when
// the widget registry started requiring a semantics test — moved, not copied,
// so there is one place that owns it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';

import '../support/harness.dart';

Future<void> _pumpBanner(
  WidgetTester tester, {
  String message = 'Could not save your changes.',
}) => pumpApp(
  tester,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: LumenErrorBanner(message: message),
    ),
  ),
);

void main() {
  testWidgetsWithSemantics('announces itself as a live region', (tester) async {
    await _pumpBanner(tester);

    expectLiveRegion(tester, 'Could not save your changes.');
  });

  testWidgetsWithSemantics('announces the message once, not twice', (
    tester,
  ) async {
    // The banner is one Text inside one Semantics; a decoration that wrapped
    // the message in a second labelled node would have a screen reader read
    // the failure twice in a row.
    await _pumpBanner(tester, message: 'That email is already registered.');

    expect(
      find.bySemanticsLabel('That email is already registered.'),
      findsOneWidget,
    );
  });

  testWidgetsWithSemantics('is not announced as a button', (tester) async {
    // Nothing is wired to the banner: it is a statement, not an affordance.
    // The retry lives beside it (LumenRetryButton) or replaces the surface
    // (LumenErrorRetry).
    await _pumpBanner(tester);

    expectNotAButton(tester, find.byType(LumenErrorBanner));
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpBanner(tester);

    expectNoDingbats(tester, screen: 'LumenErrorBanner');
  });
}
