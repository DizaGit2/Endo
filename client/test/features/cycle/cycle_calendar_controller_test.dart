// CycleCalendarController — screen 10's state (P4b-T15).
//
// Screen 10 draws only what P4a genuinely supplies: the server's `today` and
// a sparse per-day dot. Most of what is worth pinning here is therefore not
// about rendering — it is about the THREE-WINDOW read the brief's §5
// requires (previous/current/next month, never one grid-shaped read, because
// `CycleRepository.getCalendarMonth` is month-bucketed and a write can only
// invalidate a month it can name), and about paging/refresh composing
// correctly with the cache layer T14 already built and tested: paging into an
// already-warm month must not re-hit the network, and refreshing after a
// write must re-read the month actually on screen — never silently snap the
// user back to today's month.
//
// The harness below therefore wires a REAL `CycleRepository` to a mocked
// `LumenApiApi` and a STATEFUL fake `CacheStore` (real in-memory freshness,
// not `emptyCacheStore()`'s always-miss stub) — the properties this file
// proves are emergent from composing the controller with the real cache
// mechanism, not something a mocked repository could show.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockCycleRepository extends Mock implements CycleRepository {}

/// A [MockCacheStore] backed by a real in-memory map — `isFresh`/`getJson`/
/// `putJson`/`invalidate` behave like the real `CacheStore` for the life of
/// one test. `emptyCacheStore()` (harness.dart) always misses, which is right
/// for most screen tests but cannot exercise "the second read of an unchanged
/// month is a cache hit", which is exactly what this file needs to prove.
MockCacheStore _realishCacheStore() {
  final data = <String, Map<String, dynamic>>{};
  final store = MockCacheStore();
  when(
    () => store.isFresh(any()),
  ).thenAnswer((i) => data.containsKey(i.positionalArguments[0] as String));
  when(
    () => store.getJson(any()),
  ).thenAnswer((i) => data[i.positionalArguments[0] as String]);
  when(() => store.putJson(any(), any(), ttl: any(named: 'ttl'))).thenAnswer((
    i,
  ) async {
    data[i.positionalArguments[0] as String] =
        i.positionalArguments[1] as Map<String, dynamic>;
  });
  when(() => store.invalidate(any())).thenAnswer((i) async {
    data.remove(i.positionalArguments[0] as String);
  });
  return store;
}

/// One assembled screen-10 world.
class _World {
  _World({Date? today, Failure? todayFailure})
    : api = MockLumenApiApi(),
      store = _realishCacheStore(),
      todayRepo = _MockServerTodayRepository() {
    if (todayFailure != null) {
      when(todayRepo.today).thenAnswer((_) async => throw todayFailure);
    } else {
      when(todayRepo.today).thenAnswer((_) async => today ?? Date(2026, 4, 20));
    }

    repo = CycleRepository(api: api, store: store);

    container = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[
        serverTodayRepositoryProvider.overrideWithValue(todayRepo),
        cycleRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    // cycleCalendarControllerProvider is autoDispose — a bare read disposes
    // it as it returns, so the deferred load would find `ref.mounted ==
    // false`. A subscription is what a screen's `ref.watch` does.
    container.listen(cycleCalendarControllerProvider, (_, _) {});
  }

  final MockLumenApiApi api;
  final MockCacheStore store;
  final _MockServerTodayRepository todayRepo;
  late final CycleRepository repo;
  late final ProviderContainer container;

  CycleCalendarController get notifier =>
      container.read(cycleCalendarControllerProvider.notifier);

  AsyncValue<CycleCalendarView> get state =>
      container.read(cycleCalendarControllerProvider);

  CycleCalendarView get view => state.value!;

  /// Lets a deferred/in-flight read run to completion.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Answers every `GET /cycle/calendar` call with a fixture selected by the
  /// requested window's month — `perMonth` is keyed by `DateTime(year,
  /// month)`. A month with no entry answers an empty (nothing-logged) month.
  ///
  /// `onCall` runs once per invocation, BEFORE the answer is built, so a test
  /// can count real network calls per month.
  void answerPerMonth(
    Map<DateTime, List<CycleCalendarDay>> perMonth, {
    Date? today,
    void Function(DateTime month)? onCall,
  }) {
    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((invocation) async {
      final from = invocation.namedArguments[#from] as Date;
      final month = DateTime(from.year, from.month);
      onCall?.call(month);
      return Response<CycleCalendarResponse>(
        requestOptions: RequestOptions(path: '/cycle/calendar'),
        statusCode: 200,
        data: cycleCalendarFixture(
          today: today,
          days: perMonth[month] ?? const <CycleCalendarDay>[],
        ),
      );
    });
  }

  /// As [answerPerMonth], but the window whose month is [failMonth] throws a
  /// connectivity failure instead of answering — with nothing cached yet,
  /// `cachedRead` turns that into [NetworkRequired].
  void answerWithOneFailure({required DateTime failMonth, Date? today}) {
    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((invocation) async {
      final from = invocation.namedArguments[#from] as Date;
      final month = DateTime(from.year, from.month);
      if (month == failMonth) {
        throw DioException(
          requestOptions: RequestOptions(path: '/cycle/calendar'),
          type: DioExceptionType.connectionError,
        );
      }
      return Response<CycleCalendarResponse>(
        requestOptions: RequestOptions(path: '/cycle/calendar'),
        statusCode: 200,
        data: cycleCalendarFixture(today: today),
      );
    });
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  // ---------------------------------------------------------------------------
  // The dot predicate — one test per disjunct, plus the two that matter most.
  // ---------------------------------------------------------------------------

  group('cycleCalendarDayHasMark — exactly the brief\'s predicate: '
      'pain != null || mood != null || hasNotes || eventCount > 0 || '
      'symptomCount > 0', () {
    test('pain != null marks the day', () {
      expect(cycleCalendarDayHasMark(cycleCalendarDayFixture(pain: 3)), isTrue);
    });

    test('D-08: pain: 0 marks the day — 0 is a real logged datum, not '
        'absence. Any falsiness test here would silently drop every '
        'pain-free day', () {
      expect(cycleCalendarDayHasMark(cycleCalendarDayFixture(pain: 0)), isTrue);
    });

    test('mood != null marks the day', () {
      expect(cycleCalendarDayHasMark(cycleCalendarDayFixture(mood: 1)), isTrue);
    });

    test('hasNotes marks the day (compared with == true, never forced)', () {
      expect(
        cycleCalendarDayHasMark(cycleCalendarDayFixture(hasNotes: true)),
        isTrue,
      );
    });

    test('eventCount > 0 marks the day', () {
      expect(
        cycleCalendarDayHasMark(cycleCalendarDayFixture(eventCount: 1)),
        isTrue,
      );
    });

    test('symptomCount > 0 marks the day', () {
      expect(
        cycleCalendarDayHasMark(cycleCalendarDayFixture(symptomCount: 1)),
        isTrue,
      );
    });

    test('a day with nothing logged — the fixture\'s own honest default — '
        'marks nothing: the negative control the six positives above need', () {
      expect(cycleCalendarDayHasMark(cycleCalendarDayFixture()), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // today comes from the response, never the device clock
  // ---------------------------------------------------------------------------

  group('today', () {
    test(
      'the visible month AND the ring date come from the sessionToday '
      'read, whatever it answers — not from any local notion of "now"',
      () async {
        final world = _World(today: Date(2031, 11, 3));
        world.answerPerMonth(const <DateTime, List<CycleCalendarDay>>{});

        await world.settle();

        expect(world.view.today, Date(2031, 11, 3));
        expect(world.view.visibleMonth, DateTime(2031, 11));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Three month reads, not one grid-shaped read
  // ---------------------------------------------------------------------------

  group('the three-window read', () {
    test('a displayed month issues exactly three requests, for the previous, '
        'the same, and the next calendar month', () async {
      final world = _World(today: Date(2026, 4, 20));
      final requestedMonths = <DateTime>[];
      world.answerPerMonth(
        const <DateTime, List<CycleCalendarDay>>{},
        onCall: requestedMonths.add,
      );

      await world.settle();

      expect(requestedMonths.toSet(), <DateTime>{
        DateTime(2026, 3),
        DateTime(2026, 4),
        DateTime(2026, 5),
      });
      expect(
        requestedMonths.length,
        3,
        reason: 'each of the three windows must be requested exactly once',
      );
    });

    test('a failure in any ONE of the three surfaces the error state, not a '
        'partial grid', () async {
      final world = _World(today: Date(2026, 4, 20))
        ..answerWithOneFailure(failMonth: DateTime(2026, 5));

      await world.settle();

      expect(
        world.state,
        isA<AsyncError<CycleCalendarView>>(),
        reason:
            'March and April both succeeded; a controller that surfaced '
            'their data anyway would be exactly the "5/6 correct, 1/6 '
            'silently absent" grid the brief refuses.',
      );
    });

    test('the merged view carries every month\'s sparse rows, keyed by date, '
        'and a date absent from every response has no entry at all', () async {
      final marked = cycleCalendarDayFixture(date: Date(2026, 3, 30), pain: 2);
      final world = _World(today: Date(2026, 4, 20));
      world.answerPerMonth(<DateTime, List<CycleCalendarDay>>{
        DateTime(2026, 3): <CycleCalendarDay>[marked],
      });

      await world.settle();

      expect(world.view.dayByDate[Date(2026, 3, 30)], same(marked));
      // Absent from every one of the three responses — must be absent from
      // the merged map too, never synthesised as a zero row.
      expect(world.view.dayByDate.containsKey(Date(2026, 4, 15)), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Paging
  // ---------------------------------------------------------------------------

  group('paging', () {
    test('paging from month N to N+1 issues only the ONE genuinely new read — '
        'N and N+1 are already cached', () async {
      final world = _World(today: Date(2026, 4, 20));
      final callsPerMonth = <DateTime, int>{};
      world.answerPerMonth(
        const <DateTime, List<CycleCalendarDay>>{},
        onCall: (month) =>
            callsPerMonth[month] = (callsPerMonth[month] ?? 0) + 1,
      );

      await world.settle();
      expect(callsPerMonth, <DateTime, int>{
        DateTime(2026, 3): 1,
        DateTime(2026, 4): 1,
        DateTime(2026, 5): 1,
      });

      await world.notifier.showNextMonth();
      await world.settle();

      expect(
        callsPerMonth,
        <DateTime, int>{
          DateTime(2026, 3): 1, // untouched by this page
          DateTime(2026, 4): 1, // already cached from the initial load
          DateTime(2026, 5): 1, // already cached from the initial load
          DateTime(2026, 6): 1, // the one genuinely new window
        },
        reason:
            'April and May must not be re-requested — the whole point of '
            'reading three windows up front is that paging into an '
            'already-warm month is instant.',
      );
      expect(world.view.visibleMonth, DateTime(2026, 5));
    });

    test('paging must never show a stale month\'s dots under a new month\'s '
        'title: the transition goes through loading, not through a '
        'part-updated view', () async {
      final world = _World(today: Date(2026, 4, 20));
      world.answerPerMonth(const <DateTime, List<CycleCalendarDay>>{});
      await world.settle();

      final states = <AsyncValue<CycleCalendarView>>[];
      world.container.listen(cycleCalendarControllerProvider, (_, next) {
        states.add(next);
      });

      await world.notifier.showNextMonth();

      // The FIRST state the page produces (before the read resolves) must
      // be loading — never a data value whose title has moved on while its
      // grid has not, or vice versa.
      expect(states.first, isA<AsyncLoading<CycleCalendarView>>());

      await world.settle();
      expect(world.state.value!.visibleMonth, DateTime(2026, 5));
    });

    test('paging backwards is unbounded — no artificial floor', () async {
      final world = _World(today: Date(2026, 1, 15));
      world.answerPerMonth(const <DateTime, List<CycleCalendarDay>>{});
      await world.settle();

      await world.notifier.showPreviousMonth();
      await world.settle();

      expect(world.view.visibleMonth, DateTime(2025, 12));
    });
  });

  // ---------------------------------------------------------------------------
  // refresh() — T16's call site
  // ---------------------------------------------------------------------------

  group('refresh', () {
    test('refresh() re-reads whatever month is on screen — even after paging — '
        'and re-fetches ONLY the month a write invalidated, leaving the other '
        'two cached', () async {
      final world = _World(today: Date(2026, 4, 20));
      final callsPerMonth = <DateTime, int>{};
      world.answerPerMonth(
        const <DateTime, List<CycleCalendarDay>>{},
        onCall: (month) =>
            callsPerMonth[month] = (callsPerMonth[month] ?? 0) + 1,
      );
      await world.settle();

      // Page forward once so the visible month (May) is NOT the month
      // `build()` would derive from `today` (April) — the case that tells
      // `refresh()` apart from `ref.invalidate(...)`.
      await world.notifier.showNextMonth();
      await world.settle();
      expect(world.view.visibleMonth, DateTime(2026, 5));

      // Simulate exactly what CycleRepository.logEvent/deleteEvent does on
      // a successful write to a day in May: CacheKeys.keysForDate
      // invalidates May's month bucket (T14).
      await world.store.invalidate(
        CacheKeys.cycleCalendarMonth(DateTime(2026, 5)),
      );

      await world.notifier.refresh();
      await world.settle();

      expect(
        world.view.visibleMonth,
        DateTime(2026, 5),
        reason:
            'refresh() must not reset paging back to today\'s month — that '
            'is exactly what ref.invalidate(...) would do instead, and is '
            'the reason this method exists rather than that call.',
      );
      expect(
        callsPerMonth[DateTime(2026, 5)],
        2,
        reason:
            'the invalidated month: one real network fetch on top of '
            'the original load',
      );
      expect(
        callsPerMonth[DateTime(2026, 4)],
        1,
        reason: 'untouched — still cached from the initial load',
      );
      expect(
        callsPerMonth[DateTime(2026, 6)],
        1,
        reason: 'untouched — still cached from paging forward',
      );
    });

    test('refresh() called while state.value is null (the settled-ERROR case, '
        'not merely "still loading") genuinely re-triggers a build — an '
        'empty null-branch body would leave the state stuck in AsyncError '
        'forever', () async {
      // fix-round-1, M-1: the ORIGINAL version of this test called
      // refresh() before the very first settle(), while build()'s own
      // read was still in flight — a state build() would reach on its
      // own regardless of what refresh()'s null-branch did, so it could
      // not distinguish "invalidateSelf() ran" from "the branch is
      // empty". Settling to a genuine AsyncError first removes that
      // ambiguity: nothing else will EVER move this state again (no
      // retry — `retry: (_, _) => null` — and no caller but this test),
      // so recovery can only be `refresh()`'s doing.
      final world = _World(todayFailure: const NetworkFailure());
      await world.settle();
      // A SECOND flush, not one. Measured, not assumed: with only one
      // settle() here, the re-stub below is silently ignored and this
      // test fails even against the CORRECT implementation. Cause:
      // `sessionTodayProvider`'s post-failure teardown
      // (`link.close()`, `server_today.dart`) makes the element eligible
      // for autoDispose, but eligible is not immediate — Riverpod
      // schedules the actual disposal rather than running it inline. A
      // second read arriving before that scheduled disposal fires hits
      // the SAME still-alive, already-rejected element and gets its
      // cached rejected Future straight back, never re-invoking
      // `create()` — so it never reaches the (by-then re-stubbed)
      // repository at all. One extra `pumpEventQueue()` here gives that
      // disposal a turn to actually run before the rest of the test
      // depends on a fresh one.
      await pumpEventQueue();
      expect(world.state, isA<AsyncError<CycleCalendarView>>());

      // Now let `today` succeed, and give the three-window read
      // somewhere to land.
      when(world.todayRepo.today).thenAnswer((_) async => Date(2026, 4, 20));
      world.answerPerMonth(const <DateTime, List<CycleCalendarDay>>{});

      await world.notifier.refresh();
      // Same reasoning as above: refresh()'s null-branch only calls
      // ref.invalidateSelf(), which SCHEDULES the rebuild rather than
      // running it inline; that rebuild then reads sessionTodayProvider
      // afresh, which is its own async hop. pumpEventQueue flushes the
      // whole chain rather than guessing how many ticks deep it is.
      await pumpEventQueue();

      expect(
        world.state,
        isA<AsyncData<CycleCalendarView>>(),
        reason:
            'an empty refresh() null-branch would leave this AsyncError '
            'forever — nothing else in this test ever re-reads today',
      );
      expect(world.view.visibleMonth, DateTime(2026, 4));
    });

    test('_generation IS reachable for refresh() vs refresh() (fix-round-1, '
        'M-5 — measured, contra the fix list\'s own characterisation): two '
        'overlapping refresh() calls where the FIRST-ISSUED resolves LAST '
        'must not let its stale result win', () async {
      // `refresh()`, unlike `_page`, does NOT write `state = loading()`
      // before its await — so a second call issued before the first
      // resolves still sees the OLD non-null `state.value` and proceeds
      // past the null-check too (measured directly at the repository
      // interface before this test was written: two overlapping
      // refresh() calls produced 3+3=6 REPOSITORY-level getCalendarMonth
      // calls beyond the initial build's 3, i.e. both bodies ran — the
      // cache layer's own in-flight de-dup would have hidden this if
      // counted at the HTTP-mock level instead, which is why this test
      // counts at the repository interface).
      final mockRepo = _MockCycleRepository();
      final todayRepo = _MockServerTodayRepository();
      when(todayRepo.today).thenAnswer((_) async => Date(2026, 4, 20));

      final unmarked = cycleCalendarFixture(today: Date(2026, 4, 20));
      final marked = cycleCalendarFixture(
        today: Date(2026, 4, 20),
        days: <CycleCalendarDay>[
          cycleCalendarDayFixture(date: Date(2026, 4, 5), eventCount: 1),
        ],
      );

      // Calls 1-3: build()'s own initial three-window read — instant,
      // unmarked. Calls 4-6: the FIRST refresh()'s three-window read —
      // gated, so it resolves only once `firstGate` completes. Calls
      // 7-9: the SECOND refresh()'s three-window read — instant, MARKED
      // (so the final state can be attributed to whichever call actually
      // won).
      final firstGate = Completer<void>();
      var callCount = 0;
      when(() => mockRepo.getCalendarMonth(any())).thenAnswer((_) async {
        callCount++;
        if (callCount <= 3) return Fresh<CycleCalendarResponse>(unmarked);
        if (callCount <= 6) {
          await firstGate.future;
          return Fresh<CycleCalendarResponse>(unmarked);
        }
        return Fresh<CycleCalendarResponse>(marked);
      });

      final container = ProviderContainer(
        retry: lumenRetry,
        overrides: <Override>[
          serverTodayRepositoryProvider.overrideWithValue(todayRepo),
          cycleRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);
      container.listen(cycleCalendarControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(cycleCalendarControllerProvider.notifier);
      // Issued in this order — first gets generation N, second gets
      // N+1 — but FIRST is the one gated to resolve last.
      final first = notifier.refresh();
      final second = notifier.refresh();

      await second;
      expect(
        container.read(cycleCalendarControllerProvider).value?.dayByDate,
        isNotEmpty,
        reason: 'the second (higher-generation) refresh must win first',
      );

      firstGate.complete();
      await first;

      expect(
        container.read(cycleCalendarControllerProvider).value?.dayByDate,
        isNotEmpty,
        reason:
            'the FIRST refresh resolving LAST must not overwrite the '
            'second (higher-generation) refresh\'s result with its own '
            'stale one — this is exactly what _generation exists to stop, '
            'and it is reachable, not dead code',
      );
    });
  });
}
