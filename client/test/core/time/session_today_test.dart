// sessionTodayProvider — one round trip for "today", shared for the session
// (P4b-T14, fix round 1 / C-1).
//
// This provider sits directly on top of `ServerTodayRepository.today()`
// (`server_today_test.dart` covers that class on its own) and adds exactly
// one thing: memoisation, so screens 10, 11, 14 and a dated dashboard do not
// each re-issue `GET /cycle/calendar` on every mount. The interesting
// behaviour is entirely at the memoisation boundary — a SUCCESS must be
// pinned for the rest of the session, a FAILURE must not be, and neither may
// leave a caller hanging instead of seeing the typed rejection promptly. The
// file header on `server_today.dart` records the four mechanisms that were
// tried and measured before the shipped one — the fourth (`ref.keepAlive()`
// taken AFTER the `await`) is this file's fix-round-1 lesson: EVERY stub
// below used to resolve/throw on a microtask, with no real async gap, which
// is exactly what let a successful read that throws in production ship with
// a fully green suite. Every stub that stands in for the repository's
// network call now goes through [_slow], a real `Future.delayed`, so the
// disposal race C-1 was about actually has a window to occur in.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:mocktail/mocktail.dart';

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

/// A real async gap — `Future.delayed`, never a microtask — standing in for
/// the network round trip `ServerTodayRepository.today()` actually makes.
///
/// The whole point: a `Future` that resolves via `(_) async => value` settles
/// on a microtask, and `Timer(Duration.zero)` (what `autoDispose` schedules
/// its teardown with) fires only AFTER the current microtask queue drains —
/// so an instant stub's `await` always wins the race against disposal,
/// whether or not the provider is coded to survive it. A stub with a real
/// delay lets the timer fire FIRST, which is what a live network call does
/// on every request. `delay` defaults to 30 ms, the figure the review used.
Future<T> Function(Invocation) _slow<T>(
  T Function() value, {
  Duration delay = const Duration(milliseconds: 30),
}) {
  return (_) => Future<T>.delayed(delay, value);
}

/// Same shape, but the delayed future REJECTS rather than resolves.
Future<T> Function(Invocation) _slowFailure<T>(
  Object error, {
  Duration delay = const Duration(milliseconds: 30),
}) {
  return (_) => Future<T>.delayed(delay, () => throw error);
}

void main() {
  late _MockServerTodayRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _MockServerTodayRepository();
    container = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[
        serverTodayRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
  });

  test(
    'it answers what the repository said, through a real async gap',
    () async {
      when(repo.today).thenAnswer(_slow(() => Date(2026, 4, 20)));

      final result = await container.read(sessionTodayProvider.future);

      expect(result, Date(2026, 4, 20));
    },
  );

  test('C-1: a SLOW success survives TWO one-shot reads — both succeed, and '
      'the repository is called exactly once (this is the exact shape the '
      'review measured throwing twice against the pre-fix provider)', () async {
    when(repo.today).thenAnswer(_slow(() => Date(2026, 4, 20)));

    final first = await container.read(sessionTodayProvider.future);
    final second = await container.read(sessionTodayProvider.future);

    expect(first, Date(2026, 4, 20));
    expect(second, Date(2026, 4, 20));
    verify(repo.today).called(1);
  });

  test('a success is pinned for the session — a LATER read, after the value '
      'has had time to be torn down if it were not pinned, does not re-hit '
      'the repository', () async {
    when(repo.today).thenAnswer(_slow(() => Date(2026, 4, 20)));

    final first = await container.read(sessionTodayProvider.future);
    // Let any scheduled teardown run — a one-off `.read()` holds no
    // persistent subscription, so if the value were not pinned this is
    // exactly the gap `ref.keepAlive()` must close.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final second = await container.read(sessionTodayProvider.future);

    expect(first, Date(2026, 4, 20));
    expect(second, Date(2026, 4, 20));
    verify(repo.today).called(1);
  });

  test('a live listener (ref.watch / container.listen) never drops its '
      'subscription mid-flight, so a slow success resolves normally — this '
      'access pattern worked even on the pre-fix provider; it is the '
      'one-shot `.read(...future)` pattern that did not', () async {
    when(repo.today).thenAnswer(_slow(() => Date(2026, 4, 20)));

    final states = <AsyncValue<Date>>[];
    final sub = container.listen(
      sessionTodayProvider,
      (previous, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(sub.close);

    final result = await container.read(sessionTodayProvider.future);

    expect(result, Date(2026, 4, 20));
    expect(states.last.value, Date(2026, 4, 20));
    verify(repo.today).called(1);
  });

  test('a rejection reaches the CURRENT caller as the typed Failure — never a '
      'guess — even through a real async gap', () async {
    when(repo.today).thenAnswer(_slowFailure<Date>(const NetworkFailure()));

    await expectLater(
      container.read(sessionTodayProvider.future),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('a SLOW rejection is NOT cached — a LATER read gets a fresh attempt, '
      'and does not silently keep retrying on its own in between', () async {
    when(repo.today).thenAnswer(_slowFailure<Date>(const NetworkFailure()));

    await expectLater(
      container.read(sessionTodayProvider.future),
      throwsA(isA<NetworkFailure>()),
    );
    // Consume the first call so the checkpoints below count only what
    // happens from here — mocktail's `called()` is cumulative since the
    // last verification, not since the previous line.
    verify(repo.today).called(1);

    // No storm: nothing re-invokes the repository on its own while nobody
    // is asking. This is the property the eager-`invalidateSelf` mechanism
    // (recorded, and rejected, in `server_today.dart`'s dartdoc) could not
    // hold — it kept re-firing with no caller involved.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    verifyNever(repo.today);

    // The network recovers. A LATER read — a retry tap, a different dated
    // screen mounting — must get a FRESH attempt, not a replay of the
    // failure above. Brought in-contract per fix round 1, corrected in
    // round 2. Neither `expectLater(..., completion(...))` nor a bare
    // `try/catch + fail()` is sanctioned: `completion(...)` never catches a
    // REJECTION at all (`_Completes.matchAsync` in
    // package:matcher/src/expect/future_matchers.dart does
    // `item.then((value) async {...})` with no `onError` arm — the rejected
    // future, the exact shape a regression here produces, is simply never
    // handed to matcher's own failure formatter; this is NOT the
    // zone-unhandled-error path, since `await expectLater(...)` awaits the
    // chain and that `await` rethrows the rejection directly into this
    // test's own body). `fail()` alone gets `isFailure: true` but skips the
    // formatter too, so it carries no `Expected:`/`Actual:` block. None of
    // this makes `completion(...)` useless — it still fails a wrong VALUE.
    // The gap is narrow: it does not convert a REJECTION into a
    // `TestFailure`.
    //
    // The sanctioned shape: capture the rejection with `.then(onError:)` so
    // nothing ever rejects the awaited future, then assert on the captured
    // value with a real matcher.
    when(repo.today).thenAnswer(_slow(() => Date(2026, 5, 1)));
    await expectLater(
      container
          .read(sessionTodayProvider.future)
          .then<Object?>((value) => value, onError: (Object e) => e),
      completion(Date(2026, 5, 1)),
      reason: 'a later read after recovery must succeed',
    );
    verify(repo.today).called(1);
  });

  test('a THIRD read after the retry succeeds does not hit the repository '
      'again — the recovered value is pinned exactly like a first-attempt '
      'success', () async {
    when(repo.today).thenAnswer(_slowFailure<Date>(const NetworkFailure()));
    await expectLater(
      container.read(sessionTodayProvider.future),
      throwsA(isA<NetworkFailure>()),
    );
    verify(repo.today).called(1);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    when(repo.today).thenAnswer(_slow(() => Date(2026, 5, 1)));
    // Brought in-contract per fix round 1, corrected in round 2 — see the
    // note above on why `completion(...)` alone does not do this (it never
    // catches a rejection, regardless of the surrounding `expectLater`) and
    // why `fail()` alone is not sanctioned either (no `Expected:`/`Actual:`
    // block). Capture-then-assert is the shape that gets both.
    await expectLater(
      container
          .read(sessionTodayProvider.future)
          .then<Object?>((value) => value, onError: (Object e) => e),
      completion(Date(2026, 5, 1)),
      reason: 'the retry read must succeed',
    );
    verify(repo.today).called(1);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final third = await container.read(sessionTodayProvider.future);

    expect(third, Date(2026, 5, 1));
    verifyNever(repo.today);
  });

  test('a rejection settles PROMPTLY (well under the request\'s own delay '
      'compounded) rather than hanging through Riverpod\'s own default retry '
      'backoff', () async {
    when(repo.today).thenAnswer(_slowFailure<Date>(const NetworkFailure()));

    // Riverpod's own default retry (exponential backoff, up to 10
    // attempts) leaves `.future` unsettled — AsyncLoading(retrying: true)
    // — for tens of seconds. `retry: (_, __) => null` on the provider
    // opts out of it; this bounded timeout is what would catch a
    // regression of that opt-out (`server_today.dart`'s dartdoc records
    // the measurement that found the hang in the first place).
    await expectLater(
      container.read(sessionTodayProvider.future),
      throwsA(isA<NetworkFailure>()),
    ).timeout(const Duration(seconds: 2));
  });
}
