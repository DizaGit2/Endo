// Tests for Routes.parseCycleDayDate / Routes.cycleDayPath (P4b-T16).
//
// TDD (RED first). The brief's sharp edge: `/cycle/day/2026-02-31` MATCHES
// go_router's `:date` pattern — the matcher cannot see that Dart's `DateTime`
// constructor SILENTLY ROLLS `DateTime(2026, 2, 31)` to March 3rd. This parser
// is the only place that can catch it, so it must round-trip-verify rather
// than trust the constructor.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/router/routes.dart';

void main() {
  group('Routes.parseCycleDayDate — the round trip', () {
    test('a well-formed date parses to local midnight', () {
      expect(Routes.parseCycleDayDate('2026-04-07'), DateTime(2026, 4, 7));
    });

    test('REJECTS 2026-02-31 rather than rolling it to March 3rd — the '
        'brief\'s named sharp edge', () {
      expect(Routes.parseCycleDayDate('2026-02-31'), isNull);
    });

    test('rejects a non-existent April 31st (30-day month)', () {
      expect(Routes.parseCycleDayDate('2026-04-31'), isNull);
    });

    test('accepts the real leap day and rejects it one year later', () {
      expect(Routes.parseCycleDayDate('2028-02-29'), DateTime(2028, 2, 29));
      expect(Routes.parseCycleDayDate('2029-02-29'), isNull);
    });

    test('rejects a month outside 1-12', () {
      expect(Routes.parseCycleDayDate('2026-13-01'), isNull);
      expect(Routes.parseCycleDayDate('2026-00-01'), isNull);
    });

    test('rejects an unpadded month or day', () {
      expect(Routes.parseCycleDayDate('2026-4-07'), isNull);
      expect(Routes.parseCycleDayDate('2026-04-7'), isNull);
    });

    test('rejects garbage and empty input', () {
      expect(Routes.parseCycleDayDate('banana'), isNull);
      expect(Routes.parseCycleDayDate(''), isNull);
      expect(Routes.parseCycleDayDate(null), isNull);
    });

    test('is anchored — a valid date followed by extra text is rejected', () {
      expect(Routes.parseCycleDayDate('2026-04-07/extra'), isNull);
      expect(Routes.parseCycleDayDate('x2026-04-07'), isNull);
    });
  });

  group('Routes.cycleDayPath', () {
    test('builds /cycle/day/yyyy-MM-dd, zero-padded', () {
      expect(
        Routes.cycleDayPath(DateTime(2026, 4, 7)),
        '/cycle/day/2026-04-07',
      );
    });

    test('zero-pads a single-digit month and day', () {
      expect(
        Routes.cycleDayPath(DateTime(2026, 1, 5)),
        '/cycle/day/2026-01-05',
      );
    });

    test('round-trips through parseCycleDayDate', () {
      final date = DateTime(2026, 4, 7);
      final path = Routes.cycleDayPath(date);
      final segment = path.substring('${Routes.cycle}/day/'.length);
      expect(Routes.parseCycleDayDate(segment), date);
    });
  });
}
