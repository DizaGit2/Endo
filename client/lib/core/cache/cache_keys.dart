// ---------------------------------------------------------------------------
// CacheKeys — the one place P4b builds a cache key (ruling R-05)
// ---------------------------------------------------------------------------
//
// [CacheStore] offers exact-key `invalidate(key)` and nothing else: no key
// enumeration, no prefix invalidation. That is sufficient — but only if a write
// to a date can NAME every key that date can appear in. This file is what makes
// that true.
//
// The property the whole policy rests on:
//
//     EVERY key is derivable from a date.
//
// Concretely, the calendar read is MONTH-BUCKETED: callers ask for a month, not
// an arbitrary window. Free-form `?from=…&to=…` windows would break the
// property — two overlapping windows both covering 14 June would live under two
// different keys, and a write to 14 June could not enumerate them without a
// prefix scan. Bucketing collapses that set to exactly one key per month, so
// `POST /checkin/quick` on 14 June invalidates precisely:
//
//     GET:/cycle/day/2026-06-14
//     GET:/symptoms?day=2026-06-14
//     GET:/cycle/calendar?month=2026-06
//
// …which is what [keysForDate] returns. Deliberately, `invalidatePrefix` is NOT
// added to [CacheStore]: month-bucketing is what makes it unnecessary, and
// shipping both would be two mechanisms for one job.
//
// Over-invalidation is safe (the next read re-fetches); under-invalidation is a
// stale-UI bug. [keysForDate] therefore returns all three date-derived keys
// rather than trying to guess which reads a particular write moved.

// ---------------------------------------------------------------------------
// Month window
// ---------------------------------------------------------------------------

/// The inclusive `[from, to]` day range a month bucket stands for.
///
/// A calendar read must request exactly this window for the month it is keyed
/// under — otherwise the cached body would not match the key it is filed at.
typedef MonthWindow = ({DateTime from, DateTime to});

// ---------------------------------------------------------------------------
// CacheKeys
// ---------------------------------------------------------------------------

/// The complete cache-key policy for the client.
///
/// Nothing else may build a cache-key string: repositories import these
/// functions so that a write and a read can never disagree about spelling.
///
/// All date parameters take a [DateTime] and read only its civil `year`,
/// `month` and `day` — the time-of-day component and the UTC flag are ignored,
/// so two callers holding different clock times on the same day share a key.
/// A caller holding the generated API [Date] type converts with
/// `date.toDateTime()`.
abstract final class CacheKeys {
  // ── TTL ──────────────────────────────────────────────────────────────────

  /// The TTL every P4b read is cached with.
  ///
  /// `GET:/me` shipped at 5 minutes in P3b and keeps it; the P4b reads match it
  /// rather than inventing a second freshness horizon for the same data.
  static const ttl = Duration(minutes: 5);

  // ── Static keys ──────────────────────────────────────────────────────────

  /// `GET /me` — the profile read. Pre-existing; the string is unchanged.
  static const profile = 'GET:/me';

  /// `GET /settings/cycle` — cycle settings.
  static const cycleSettings = 'GET:/settings/cycle';

  /// `GET /onboarding/state` — the onboarding resume read.
  static const onboardingState = 'GET:/onboarding/state';

  // ── Date-derived keys ────────────────────────────────────────────────────

  /// `GET /cycle/calendar` for the month containing [date].
  ///
  /// Month-bucketed on purpose — see the file header.
  static String cycleCalendarMonth(DateTime date) =>
      'GET:/cycle/calendar?month=${_yyyyMM(date)}';

  /// `GET /cycle/day/{date}` — one day's log.
  static String cycleDay(DateTime date) => 'GET:/cycle/day/${_yyyyMMdd(date)}';

  /// `GET /symptoms?day={date}` — one day's symptoms.
  static String symptomsDay(DateTime date) =>
      'GET:/symptoms?day=${_yyyyMMdd(date)}';

  // ── Invalidation ─────────────────────────────────────────────────────────

  /// Every key whose cached body can contain data for [date].
  ///
  /// Pass straight to `cachedWrite(invalidateKeys: …)` after any write that
  /// touches a dated record:
  ///
  /// ```dart
  /// return cachedWrite(
  ///   store: _store,
  ///   write: () async => _api.checkinQuickPost(…),
  ///   invalidateKeys: CacheKeys.keysForDate(day),
  /// );
  /// ```
  static List<String> keysForDate(DateTime date) => <String>[
        cycleDay(date),
        symptomsDay(date),
        cycleCalendarMonth(date),
      ];

  /// The inclusive day window the calendar read for [date]'s month must ask for.
  ///
  /// Both ends bucket to the same key as [date], by construction.
  static MonthWindow monthWindow(DateTime date) => (
        from: DateTime(date.year, date.month),
        // Day 0 of the following month is the last day of this one — correct
        // for 30/31-day months and for both kinds of February. `DateTime`
        // normalises month 13 into January of the next year, so December needs
        // no special case.
        to: DateTime(date.year, date.month + 1, 0),
      );

  // ── Formatting ───────────────────────────────────────────────────────────

  static String _yyyyMM(DateTime date) =>
      '${_pad4(date.year)}-${_pad2(date.month)}';

  static String _yyyyMMdd(DateTime date) =>
      '${_yyyyMM(date)}-${_pad2(date.day)}';

  static String _pad2(int value) => value.toString().padLeft(2, '0');

  static String _pad4(int value) => value.toString().padLeft(4, '0');
}
