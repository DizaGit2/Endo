// Tests for LumenBottomNav's theming (P4b-T5, brief §1b).
//
// TDD (RED first). `LumenBottomNav` was a bare Material 3 `NavigationBar`, so
// every colour on it came from `ColorScheme` derivations rather than from the
// design tokens: an M3-derived `secondaryContainer` indicator, an
// `onSurfaceVariant` unselected icon, a tinted `surfaceContainer` background
// and an elevation shadow. That was invisible while the widget had no
// production caller; P4b-T2 mounted it in the shell, so it is now the chrome on
// every tab.
//
// The mockups (screens 8, 10, 11) draw the bar as:
//
//     .nav{ margin-top:auto; display:flex; border-top:1px solid var(--bd);
//           padding-top:8px; }
//     .nb { flex:1; text-align:center; font-size:9px; color:var(--mut); }
//     .nb.on{ color:var(--ac); font-weight:500; }
//
// i.e. surface, a hairline top border on `--bd`, muted items, accent for the
// selected one — and no shadow, no tint, no derived container colour.
//
// Every assertion below names one of those. The `selected` ones are what a
// `ColorScheme` default cannot satisfy by accident: `secondaryContainer` and
// `onSurfaceVariant` are not equal to any Lumen token.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pumpNav(
  WidgetTester tester, {
  int currentIndex = 0,
  Brightness brightness = Brightness.light,
}) {
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: const SizedBox.shrink(),
      bottomNavigationBar: LumenBottomNav(currentIndex: currentIndex),
    ),
  );
}

/// The effective [NavigationBarThemeData] the bar renders under — whatever the
/// widget did to get it there.
NavigationBarThemeData _navTheme(WidgetTester tester) {
  final context = tester.element(find.byType(NavigationBar));
  return NavigationBarTheme.of(context);
}

TextStyle _labelStyle(WidgetTester tester, {required bool selected}) =>
    _navTheme(tester).labelTextStyle!.resolve(<WidgetState>{
      if (selected) WidgetState.selected,
    })!;

IconThemeData _iconTheme(WidgetTester tester, {required bool selected}) =>
    _navTheme(tester).iconTheme!.resolve(<WidgetState>{
      if (selected) WidgetState.selected,
    })!;

/// The bar's own painted surface + hairline, read off the box the widget wraps
/// the [NavigationBar] in.
BoxDecoration _barDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(LumenBottomNav),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

void main() {
  // -------------------------------------------------------------------------
  // Item colours — the mockups' `.nb` / `.nb.on`
  // -------------------------------------------------------------------------

  group('light theme', () {
    testWidgets('the selected item is accent; the rest are muted', (
      tester,
    ) async {
      await _pumpNav(tester);

      expect(_labelStyle(tester, selected: true).color, lumenLight.accent);
      expect(_labelStyle(tester, selected: false).color, lumenLight.muted);
      expect(_iconTheme(tester, selected: true).color, lumenLight.accent);
      expect(_iconTheme(tester, selected: false).color, lumenLight.muted);
    });

    testWidgets('the selected label is w500 and the rest are w400', (
      tester,
    ) async {
      await _pumpNav(tester);

      expect(_labelStyle(tester, selected: true).fontWeight, FontWeight.w500);
      expect(_labelStyle(tester, selected: false).fontWeight, FontWeight.w400);
    });

    testWidgets('the selection indicator is accent-soft', (tester) async {
      await _pumpNav(tester);

      // Not `ColorScheme.secondaryContainer`, which is what an unthemed M3
      // NavigationBar uses and which is not a Lumen token at all.
      expect(_navTheme(tester).indicatorColor, lumenLight.accentSoft);
    });

    testWidgets('the bar sits on the surface behind a border hairline', (
      tester,
    ) async {
      await _pumpNav(tester);
      final decoration = _barDecoration(tester);

      expect(decoration.color, lumenLight.surface);
      expect(
        decoration.border,
        Border(top: BorderSide(color: lumenLight.border)),
      );
    });

    testWidgets('nothing tints or shadows the bar', (tester) async {
      await _pumpNav(tester);
      final theme = _navTheme(tester);

      // M3 defaults would paint a surface tint and an elevation shadow over
      // the flat treatment the mockups draw.
      expect(theme.elevation, 0);
      expect(theme.surfaceTintColor, Colors.transparent);
      expect(theme.shadowColor, Colors.transparent);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).backgroundColor,
        Colors.transparent,
        reason:
            'The bar paints its own surface + hairline, so the NavigationBar '
            'must not paint a second one over the border.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Dark theme — the tokens are read, not hard-coded
  // -------------------------------------------------------------------------

  group('dark theme', () {
    testWidgets('takes every colour from the dark palette', (tester) async {
      await _pumpNav(tester, brightness: Brightness.dark);

      expect(_labelStyle(tester, selected: true).color, lumenDark.accent);
      expect(_labelStyle(tester, selected: false).color, lumenDark.muted);
      expect(_iconTheme(tester, selected: true).color, lumenDark.accent);
      expect(_navTheme(tester).indicatorColor, lumenDark.accentSoft);
      expect(_barDecoration(tester).color, lumenDark.surface);
      expect(
        _barDecoration(tester).border,
        Border(top: BorderSide(color: lumenDark.border)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Still a navigation bar
  // -------------------------------------------------------------------------

  testWidgets('labels stay visible on every destination, selected or not', (
    tester,
  ) async {
    await _pumpNav(tester, currentIndex: 2);

    for (final label in const ['Home', 'Cycle', 'Hormones', 'Body', 'More']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('theming did not change which destination is selected', (
    tester,
  ) async {
    await _pumpNav(tester, currentIndex: 3);

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });

  testWidgets('a tap still reaches onDestinationSelected', (tester) async {
    var selected = -1;
    await pumpApp(
      tester,
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: LumenBottomNav(
          currentIndex: 0,
          onDestinationSelected: (index) => selected = index,
        ),
      ),
    );

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();

    expect(selected, 3);
  });
}
