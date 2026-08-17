// Tests for LumenIntensityScale (P4b-T5, brief §3; decisions D-08 and R-12).
//
// TDD (RED first): this widget did not exist. Screens 9, 12 and 13 all need
// the NRS-11 control, and two decisions about it are the kind that get lost in
// a re-implementation:
//
//   * D-08 — ELEVEN stops, 0..10. Screen 9's mockup draws ten (0..9) and
//     `definitions.md:24` records that as a mockup artifact P4b corrects.
//   * R-12 — `0` is a real logged value meaning "none today"; `null` is "not
//     recorded". A caller must never be able to tell them apart by falsiness.
//     Sent to `POST /checkin/quick`, `pain: 0` OVERWRITES a stored 8; treated
//     as absent, it silently would not.
//
// The R-12 tests below are the ones that matter: they are written so that an
// implementation using `int` + a 0-means-unset convention, or one that reports
// the taps as `int?`, fails rather than passes quietly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Records every value the scale reports back. Deliberately typed `int` — a
/// widget that handed back `int?` would not compile against this list, which
/// is half the point of the R-12 assertions.
late List<int> reported;

Future<void> _pumpScale(
  WidgetTester tester, {
  required int? value,
  bool enabled = true,
  Brightness brightness = Brightness.light,
}) {
  reported = <int>[];
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LumenIntensityScale(
          value: value,
          enabled: enabled,
          semanticsLabel: 'Pain level',
          onChanged: reported.add,
        ),
      ),
    ),
  );
}

/// The painted box of the stop labelled [stop].
BoxDecoration _stopDecoration(WidgetTester tester, int stop) {
  final container = tester.widget<Container>(
    find.ancestor(
      of: find.text('$stop'),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

bool _isFilled(WidgetTester tester, int stop) =>
    _stopDecoration(tester, stop).color == lumenLight.accent;

void main() {
  // -------------------------------------------------------------------------
  // D-08 — eleven stops
  // -------------------------------------------------------------------------

  group('the scale is NRS-11', () {
    testWidgets('renders eleven stops, 0 through 10', (tester) async {
      await _pumpScale(tester, value: null);

      for (var stop = 0; stop <= 10; stop++) {
        expect(
          find.text('$stop'),
          findsOneWidget,
          reason: 'stop $stop should be on screen',
        );
      }
      // The mockup's row stops at 9. If this widget ever renders ten stops
      // again, the assertion above passes for 0..9 and this one fails.
      expect(find.text('10'), findsOneWidget);
      expect(LumenIntensityScale.stopCount, 11);
    });

    testWidgets('every one of the eleven stops is reachable by tap', (
      tester,
    ) async {
      await _pumpScale(tester, value: null);

      for (var stop = 0; stop <= 10; stop++) {
        await tester.tap(find.text('$stop'));
      }
      await tester.pump();

      expect(reported, <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    testWidgets('renders the two anchors and NOTHING between them', (
      tester,
    ) async {
      await _pumpScale(tester, value: 5);

      // An equality, not a "no severity words" blocklist: a blocklist only
      // fails for the words someone thought to ban, and "Moderate" is not the
      // only clinical inference available.
      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map(effectiveText)
          .toSet();
      expect(rendered, <String>{
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
        'None',
        'Worst',
      });
    });
  });

  // -------------------------------------------------------------------------
  // R-12 — 0 is a datum, null is the absence of one
  // -------------------------------------------------------------------------

  group('0 and null are different states', () {
    testWidgets('tapping 0 reports the integer 0, not null', (tester) async {
      await _pumpScale(tester, value: null);

      await tester.tap(find.text('0'));
      await tester.pump();

      expect(reported, hasLength(1));
      expect(reported.single, 0);
      expect(
        reported.single,
        isNotNull,
        reason: '"none today" is a logged value, not the absence of one.',
      );
    });

    testWidgets('value: 0 fills the first stop', (tester) async {
      await _pumpScale(tester, value: 0);

      expect(_isFilled(tester, 0), isTrue);
      for (var stop = 1; stop <= 10; stop++) {
        expect(_isFilled(tester, stop), isFalse);
      }
    });

    testWidgets('value: null fills NO stop — visibly unlike 0', (tester) async {
      await _pumpScale(tester, value: null);

      for (var stop = 0; stop <= 10; stop++) {
        expect(
          _isFilled(tester, stop),
          isFalse,
          reason:
              'nothing is recorded, so nothing may be shown as chosen — '
              'least of all 0, which would read as "you logged no pain".',
        );
      }
    });

    testWidgets('the two states announce differently', (tester) async {
      expect(LumenIntensityScale.describeValue(0), '0 out of 10');
      expect(LumenIntensityScale.describeValue(null), 'Not recorded');
      expect(
        LumenIntensityScale.describeValue(0),
        isNot(LumenIntensityScale.describeValue(null)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  group('selection', () {
    testWidgets('exactly the current value is filled', (tester) async {
      await _pumpScale(tester, value: 7);

      expect(_isFilled(tester, 7), isTrue);
      expect(_isFilled(tester, 6), isFalse);
      expect(_isFilled(tester, 8), isFalse);
    });

    testWidgets('a selected stop is accent-on-accent with a readable label', (
      tester,
    ) async {
      await _pumpScale(tester, value: 3);
      final decoration = _stopDecoration(tester, 3);
      final label = tester.widget<Text>(find.text('3')).style!;

      expect(decoration.color, lumenLight.accent);
      expect(decoration.border, Border.all(color: lumenLight.accent));
      expect(decoration.borderRadius, BorderRadius.circular(7));
      expect(label.fontWeight, FontWeight.w500);
      expect(
        label.color,
        lumenTheme(Brightness.light).colorScheme.onPrimary,
      );
    });

    testWidgets('an unselected stop is input-on-border, muted', (tester) async {
      await _pumpScale(tester, value: 3);
      final decoration = _stopDecoration(tester, 4);

      expect(decoration.color, lumenLight.input);
      expect(decoration.border, Border.all(color: lumenLight.border));
      expect(tester.widget<Text>(find.text('4')).style!.color, lumenLight.muted);
    });

    testWidgets('enabled: false ignores taps', (tester) async {
      await _pumpScale(tester, value: null, enabled: false);

      await tester.tap(find.text('5'));
      await tester.pump();

      expect(reported, isEmpty);
    });

    testWidgets('in dark mode the selected label is dark ink, not white', (
      tester,
    ) async {
      // The mockup hard-codes #FFFCF7 on the accent fill in both themes; in
      // dark that is near-white on light gold (~1.4:1).
      await _pumpScale(tester, value: 3, brightness: Brightness.dark);

      expect(
        _stopDecoration(tester, 3).color,
        lumenDark.accent,
      );
      expect(
        tester.widget<Text>(find.text('3')).style!.color,
        lumenTheme(Brightness.dark).colorScheme.onPrimary,
      );
    });
  });
}
