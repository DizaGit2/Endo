// The period-event vocabulary (P4b-T16c) — the two label maps screen 11's
// Period section and its editor both read.
//
// What is worth pinning here is the ORDINAL translation. `flowIntensity` is
// 1-based on the wire, like `mood` and unlike `pain`, so a control built on a
// bare list index writes "Spotting" when the user picked "Light" — a
// fabricated value that looks completely real. The mapping is asserted in
// both directions, and the fallbacks are asserted to be honest rather than
// silent.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/cycle/presentation/period_vocabulary.dart';

void main() {
  group('kind labels', () {
    test('the three ratified codes map to their labels, in the backend\'s '
        'own declaration order', () {
      expect(kPeriodKindCodes, <String>[
        'period_start',
        'period_end',
        'spotting',
      ]);
      expect(periodKindLabel('period_start'), 'Period start');
      expect(periodKindLabel('period_end'), 'Period end');
      expect(periodKindLabel('spotting'), 'Spotting');
    });

    test('an unknown code renders the RAW code rather than vanishing — a row '
        'that exists must stay visible', () {
      expect(periodKindLabel('ovulation'), 'ovulation');
    });

    test('a null kind falls back to a neutral word, never to an empty row', () {
      expect(periodKindLabel(null), kPeriodKindUnknownLabel);
      expect(kPeriodKindUnknownLabel, isNotEmpty);
    });
  });

  group('flow labels', () {
    test('the wire ordinal 1..4 maps to the four PO-interim labels — '
        'Codes[value - 1], never Codes[index]', () {
      expect(flowLabel(1), 'Spotting');
      expect(flowLabel(2), 'Light');
      expect(flowLabel(3), 'Medium');
      expect(flowLabel(4), 'Heavy');
    });

    test('kFlowLabels is index-aligned to value - 1, and has exactly four '
        'members', () {
      expect(kFlowLabels, hasLength(4));
      for (var i = 0; i < kFlowLabels.length; i++) {
        expect(flowLabel(i + 1), kFlowLabels[i]);
      }
    });

    test('an out-of-range value renders the raw integer, never a clamped '
        'neighbour — a wrong level must not read as a real one', () {
      expect(flowLabel(0), '0');
      expect(flowLabel(5), '5');
    });
  });
}
