// ---------------------------------------------------------------------------
// CacheKeys — the P4b cache-key policy (ruling R-05)
// ---------------------------------------------------------------------------
//
// The property under test is the one that makes exact-key invalidation
// sufficient: EVERY key is derivable from a date, so a write to date D can name
// exactly the keys it invalidates. A test here is only meaningful if it would
// go red for a plausible mistake, so each one names the mistake it catches:
//
//   • unpadded month/day components      ('2026-1'  vs '2026-01')
//   • an arbitrary (from,to) window key  (two windows covering D would not
//                                         share a key, so a write could not
//                                         name them)
//   • a month bucket computed by day arithmetic (30-day months, leap Februarys)

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/cache/cache_keys.dart';

void main() {
  // -------------------------------------------------------------------------
  // Constant keys — the P4b policy table, verbatim
  // -------------------------------------------------------------------------

  group('CacheKeys — constant keys', () {
    test('match the policy table exactly', () {
      expect(CacheKeys.profile, 'GET:/me');
      expect(CacheKeys.cycleSettings, 'GET:/settings/cycle');
      expect(CacheKeys.onboardingState, 'GET:/onboarding/state');
    });

    test('the policy TTL is 5 minutes', () {
      expect(CacheKeys.ttl, const Duration(minutes: 5));
    });
  });

  // -------------------------------------------------------------------------
  // Day keys
  // -------------------------------------------------------------------------

  group('CacheKeys — day keys', () {
    test('cycleDay is GET:/cycle/day/yyyy-MM-dd', () {
      expect(CacheKeys.cycleDay(DateTime(2026, 6, 14)), 'GET:/cycle/day/2026-06-14');
    });

    test('symptomsDay is GET:/symptoms?day=yyyy-MM-dd', () {
      expect(CacheKeys.symptomsDay(DateTime(2026, 6, 14)), 'GET:/symptoms?day=2026-06-14');
    });

    test('single-digit month and day are zero-padded', () {
      // Catches string interpolation without padLeft: '2026-1-5'.
      expect(CacheKeys.cycleDay(DateTime(2026, 1, 5)), 'GET:/cycle/day/2026-01-05');
      expect(CacheKeys.symptomsDay(DateTime(2026, 1, 5)), 'GET:/symptoms?day=2026-01-05');
    });

    test('the time-of-day component of a DateTime is ignored', () {
      // Two reads of the same civil day must hit the same key, whatever clock
      // time the caller happened to hold.
      expect(
        CacheKeys.cycleDay(DateTime(2026, 6, 14, 23, 59, 59)),
        CacheKeys.cycleDay(DateTime(2026, 6, 14, 0, 0, 0)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Month bucketing — the property that makes exact-key invalidate enough
  // -------------------------------------------------------------------------

  group('CacheKeys — the calendar key is month-bucketed', () {
    test('is GET:/cycle/calendar?month=yyyy-MM', () {
      expect(
        CacheKeys.cycleCalendarMonth(DateTime(2026, 6, 14)),
        'GET:/cycle/calendar?month=2026-06',
      );
    });

    test('every day of a month buckets to the SAME key', () {
      // This is the whole point: a free-form (from,to) window key would give a
      // different key per caller, and a write to D could not name them.
      final january = CacheKeys.cycleCalendarMonth(DateTime(2026, 1, 1));
      for (var day = 1; day <= 31; day++) {
        expect(
          CacheKeys.cycleCalendarMonth(DateTime(2026, 1, day)),
          january,
          reason: 'day $day of 2026-01 must share the January bucket',
        );
      }
    });

    test('adjacent months do NOT share a bucket', () {
      // Catches a bucket computed by day arithmetic (e.g. "start + 30 days").
      expect(
        CacheKeys.cycleCalendarMonth(DateTime(2026, 1, 31)),
        isNot(CacheKeys.cycleCalendarMonth(DateTime(2026, 2, 1))),
      );
      expect(
        CacheKeys.cycleCalendarMonth(DateTime(2026, 12, 31)),
        isNot(CacheKeys.cycleCalendarMonth(DateTime(2027, 1, 1))),
      );
    });

    test('the month component is zero-padded', () {
      expect(
        CacheKeys.cycleCalendarMonth(DateTime(2026, 9, 30)),
        'GET:/cycle/calendar?month=2026-09',
      );
    });
  });

  // -------------------------------------------------------------------------
  // keysForDate — what a write to date D invalidates
  // -------------------------------------------------------------------------

  group('CacheKeys.keysForDate — a write to D names exactly its keys', () {
    test('returns that day\'s two reads plus D\'s month bucket', () {
      expect(
        CacheKeys.keysForDate(DateTime(2026, 6, 14)),
        <String>[
          'GET:/cycle/day/2026-06-14',
          'GET:/symptoms?day=2026-06-14',
          'GET:/cycle/calendar?month=2026-06',
        ],
      );
    });

    test('the 1st of a month', () {
      expect(
        CacheKeys.keysForDate(DateTime(2026, 3, 1)),
        <String>[
          'GET:/cycle/day/2026-03-01',
          'GET:/symptoms?day=2026-03-01',
          'GET:/cycle/calendar?month=2026-03',
        ],
      );
    });

    test('the 31st of a month', () {
      expect(
        CacheKeys.keysForDate(DateTime(2026, 3, 31)),
        <String>[
          'GET:/cycle/day/2026-03-31',
          'GET:/symptoms?day=2026-03-31',
          'GET:/cycle/calendar?month=2026-03',
        ],
      );
    });

    test('a leap-day February', () {
      expect(
        CacheKeys.keysForDate(DateTime(2024, 2, 29)),
        <String>[
          'GET:/cycle/day/2024-02-29',
          'GET:/symptoms?day=2024-02-29',
          'GET:/cycle/calendar?month=2024-02',
        ],
      );
    });

    test('every returned key is one the policy can also build directly', () {
      // No key may be minted here that a read cannot ask for — otherwise a
      // write would invalidate a key nothing reads.
      final d = DateTime(2026, 7, 4);
      expect(CacheKeys.keysForDate(d), <String>[
        CacheKeys.cycleDay(d),
        CacheKeys.symptomsDay(d),
        CacheKeys.cycleCalendarMonth(d),
      ]);
    });
  });

  // -------------------------------------------------------------------------
  // monthWindow — the window a month-bucketed calendar read must request
  // -------------------------------------------------------------------------

  group('CacheKeys.monthWindow — the (from,to) a bucket stands for', () {
    test('covers the whole month for a 31-day month', () {
      final w = CacheKeys.monthWindow(DateTime(2026, 1, 17));
      expect(w.from, DateTime(2026, 1, 1));
      expect(w.to, DateTime(2026, 1, 31));
    });

    test('a 30-day month ends on the 30th', () {
      final w = CacheKeys.monthWindow(DateTime(2026, 4, 17));
      expect(w.to, DateTime(2026, 4, 30));
    });

    test('a common-year February ends on the 28th', () {
      final w = CacheKeys.monthWindow(DateTime(2026, 2, 17));
      expect(w.to, DateTime(2026, 2, 28));
    });

    test('a leap-year February ends on the 29th', () {
      // Catches a hard-coded 28, and a `DateTime(y, m, 28 + 1)` style guess.
      final w = CacheKeys.monthWindow(DateTime(2024, 2, 17));
      expect(w.to, DateTime(2024, 2, 29));
    });

    test('December does not roll into the next year', () {
      // Catches DateTime(year, month + 1, 0) written as DateTime(year, 13, 0)
      // without relying on Dart's normalisation — and any hand-rolled variant
      // that forgets the rollover.
      final w = CacheKeys.monthWindow(DateTime(2026, 12, 5));
      expect(w.from, DateTime(2026, 12, 1));
      expect(w.to, DateTime(2026, 12, 31));
    });

    test('the window and the key agree: both ends bucket to the same key', () {
      final d = DateTime(2024, 2, 17);
      final w = CacheKeys.monthWindow(d);
      expect(CacheKeys.cycleCalendarMonth(w.from), CacheKeys.cycleCalendarMonth(d));
      expect(CacheKeys.cycleCalendarMonth(w.to), CacheKeys.cycleCalendarMonth(d));
    });
  });
}
