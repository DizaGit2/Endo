// Accessibility tests for LumenScaffold (P4b-T5b).
//
// The scaffold is chrome, so its a11y contract is about what it must NOT do to
// the content it wraps. It applies a background colour, an optional padding and
// an optional bottom bar; every one of those is a plausible place to lose the
// body's semantics (a `Padding` is harmless, an `ExcludeSemantics` or an
// `IgnorePointer` around the body would not be, and both are one careless edit
// away).
//
// The heading assertion is the positive one: an `appBar` title is what
// heading-navigation lands on, and thirteen screens are about to pass one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../support/harness.dart';

Future<void> _pumpScaffold(
  WidgetTester tester, {
  bool withAppBar = true,
  bool withNav = true,
  EdgeInsets? padding = const EdgeInsets.all(16),
}) => pumpApp(
  tester,
  home: LumenScaffold(
    // Not 'Cycle': that is also a nav destination label, and a finder that
    // matches two nodes is a finder that proves nothing about either.
    appBar: withAppBar ? AppBar(title: const Text('Lumen')) : null,
    bottomNavigationBar: withNav ? const LumenBottomNav(currentIndex: 1) : null,
    padding: padding,
    body: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('Cycle day 14'), Text('Log today')],
    ),
  ),
);

void main() {
  testWidgetsWithSemantics('the body it wraps is still announced', (
    tester,
  ) async {
    await _pumpScaffold(tester);

    expect(find.bySemanticsLabel('Cycle day 14'), findsOneWidget);
    expect(find.bySemanticsLabel('Log today'), findsOneWidget);
  });

  testWidgetsWithSemantics('padding does not cost the body its semantics', (
    tester,
  ) async {
    // The padded and unpadded trees must announce identically: padding is
    // layout, not meaning.
    await _pumpScaffold(tester, padding: null);
    expect(find.bySemanticsLabel('Cycle day 14'), findsOneWidget);

    await _pumpScaffold(tester, padding: const EdgeInsets.all(24));
    expect(find.bySemanticsLabel('Cycle day 14'), findsOneWidget);
  });

  testWidgetsWithSemantics('the app bar title announces as a header', (
    tester,
  ) async {
    await _pumpScaffold(tester);

    expect(
      tester.getSemantics(find.text('Lumen')).flagsCollection.isHeader,
      isTrue,
      reason:
          'The title is what a heading-navigation gesture lands on. A title '
          'rendered into the body instead of the appBar loses that.',
    );
  });

  testWidgetsWithSemantics('the chrome invents no affordance of its own', (
    tester,
  ) async {
    // With no app bar and no nav, a scaffold wrapping two Texts must offer
    // nothing tappable — the buttons a screen has are the ones it wrote.
    await _pumpScaffold(tester, withAppBar: false, withNav: false);

    expectNoButtons(
      tester,
      reason:
          'LumenScaffold added a button to a body that has none. Chrome must '
          'not create affordances.',
    );
  });

  testWidgetsWithSemantics('the bottom nav it is given keeps its own '
      'destinations', (tester) async {
    // The nav is passed through, not re-wrapped: if the scaffold buried it in
    // an ExcludeSemantics, every tab would vanish from the reading order while
    // still being visible.
    await _pumpScaffold(tester);

    for (final tab in const ['Home', 'Cycle', 'Hormones', 'Body', 'More']) {
      // Named AND activatable: a destination that survives as text but loses
      // its tap action is a tab a screen-reader user cannot switch to.
      expectLabeledButton(tester, find.text(tab), tab);
    }
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpScaffold(tester);

    expectNoDingbats(tester, screen: 'LumenScaffold');
  });
}
