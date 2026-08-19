import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// ServerTodayRepository
// ---------------------------------------------------------------------------

/// The user's current day, **as the server computes it** (D-12).
///
/// ## Why this exists at all
///
/// D-12 puts every day-boundary decision on the server and says the client
/// must not re-derive "today" from its own clock: the boundary depends on
/// `users.timezone`, which the device may disagree with, and a device-derived
/// day would file health data under the wrong date. The guard in
/// `test/core/locale/formatting_guard_test.dart` enforces the negative half: a
/// `DateTime.now()` anywhere under `lib/` fails the build unless it carries a
/// line-level waiver, and that test pins the whole waiver list at two entries,
/// neither of them a cycle date. This class is the positive half — the answer
/// to "then where does today come from".
///
/// ## Why it reads the calendar endpoint
///
/// `GET /cycle/calendar` is the one route that reports it: its response carries
/// `today` and `timezone`, and with **no** `from`/`to` the server answers for
/// the caller's current month, derived from `UserDayInfo.Today` and, in that
/// method's own words, *"rather than from any UTC date"*
/// (`backend/src/Lumen.Api/Cycle/CycleCalendarService.cs:68-79`). The route is
/// gated on authentication alone (`CycleEndpoints.cs:174`), so a user who has
/// not finished onboarding reaches it.
///
/// That it is the *sanctioned* source rather than a workaround is recorded in
/// `.superpowers/sdd/lumen-build/survey/phase-carryover.md:946` — *"`GET
/// /cycle/calendar` returns `today` + `timezone`; use the server's `today`"* —
/// and in that survey's D-12 row
/// (`survey/decisions-and-vocabularies.md:30`).
///
/// **Do not look for this rule in `docs/ARCHITECTURE.md` §A.** Its D-12 row is
/// about the SERVER-side day-boundary helper (`IUserDayResolver`) and says
/// nothing about where a client gets today; an earlier version of this comment
/// attributed the sentence above to it, and it is not there.
///
/// Everything else in that response — the day rows, the phase envelope — is
/// dropped here. The **windowed** calendar read, its month-bucketed cache entry
/// and the phase-unavailable state belong to screen 10 and are not this
/// class's business.
///
/// ## Why it is not READ from cache
///
/// `CacheKeys`' whole policy rests on one property: *every key is derivable
/// from a date*. A request whose purpose is to **learn** the date has no date
/// to key on, and a fixed key would go stale across the one boundary it exists
/// to observe — midnight. So [today] always attempts the network and never
/// SERVES a cached value in its place: a caller that cannot reach the network
/// gets a [Failure] rather than yesterday.
///
/// **P4b-T14 considered, and declined, write-only cache warming.** A
/// windowless response *is* the user's current month, so the row it carries
/// could legitimately be filed under `CacheKeys.cycleCalendarMonth(today)`
/// even though nothing here would ever read it back. Taking that would mean
/// injecting `CacheStore` into this class for a write with no corresponding
/// read here, to save one round trip on the FIRST calendar view of the
/// current month only — not worth a second writer of that key for a class
/// whose whole job is staying a plain online read. **"Not cached" was
/// therefore the wrong claim to make about this file on its own once T14
/// shipped `CycleRepository.getCalendarMonth`**: that method's ordinary
/// windowed read files its response under the very same
/// `CacheKeys.cycleCalendarMonth(today)` key when a screen is showing the
/// current month, so the key this call corresponds to CAN be found in the
/// cache — just never by way of this class. "Not read from cache" is the
/// claim that stays true.
class ServerTodayRepository {
  const ServerTodayRepository({
    required LumenApiApi api,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api; // ignore: prefer_initializing_formals

  final LumenApiApi _api;

  /// The caller's own current day.
  ///
  /// Throws a typed [Failure]: [NetworkFailure] offline, [ServerFailure] when
  /// the response names no day at all. It never answers a guess — a screen that
  /// cannot learn today renders without it (screen 3 keeps its calendar closed
  /// rather than opening it on a month nobody chose).
  Future<Date> today() async {
    try {
      // No window on purpose. Supplying one would mean already knowing a date,
      // which is the question being asked; and any date invented to fill it
      // would be the device clock under another name.
      final response = await _api.cycleCalendarGet();
      final today = response.data?.today;
      if (today == null) {
        throw const ServerFailure('The server did not report the current day.');
      }
      return today;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [ServerTodayRepository] wired to the shared API client.
final serverTodayRepositoryProvider = Provider<ServerTodayRepository>((ref) {
  return ServerTodayRepository(api: ref.watch(lumenApiProvider));
});

// ---------------------------------------------------------------------------
// sessionTodayProvider — one round trip for "today", shared for the session
// ---------------------------------------------------------------------------

/// The app's own answer to "what day is it", shared across every dated screen
/// that reads through it, so a cold start does not re-issue
/// `GET /cycle/calendar` once per screen mount, forever, on mobile
/// (P4b-T14's brief). **Screens 3 and 4 read through it too**
/// (`CycleSetupController._readToday`, `BaselineController._readToday` —
/// fix round 1 / M-1): they shipped calling [serverTodayRepositoryProvider]
/// directly, which left the brief's *"screens 3, 4, 10, 11 and 14 share one
/// round trip"* unmet for the two screens already built. That omission was
/// only cosmetic while C-1 (below) was still open — a call site that read
/// this provider on `.autoDispose` before the disposal race was fixed would
/// have broken in production while its own tests, using instant mocks,
/// stayed green — so the switch was made only after C-1 was closed.
///
/// **Declared `.autoDispose`, not the plain non-`autoDispose` `FutureProvider`
/// the brief names — a deliberate, measured deviation, kept because the
/// literal shape cannot satisfy the brief's OWN adjacent requirement** ("any
/// memoising layer must not cache a failure"). [ServerTodayRepository.today]
/// never answers a guess: it throws a typed [Failure] rather than serving a
/// stale day. Three shapes were tried on top of that promise and measured —
/// with a throwaway `ProviderContainer` harness, not the shipped suite, since
/// what is under test is Riverpod 3.3.2's own machinery — before this one:
///
/// 1. **A plain non-`autoDispose` `FutureProvider<Date>`.** Once `create()`
///    throws, its `AsyncError` IS the provider's state, permanently: reading
///    an already-built provider is a cache lookup, not a re-invocation of
///    `create()`. A user offline for one screen would find `today`
///    unreachable for the rest of the app's life, even minutes later with
///    connectivity back. That is exactly the cached failure the brief warns
///    against.
/// 2. **The same, plus `ref.invalidateSelf()` in the `catch` block before
///    rethrowing** — the obvious-looking fix, to schedule a rebuild so the
///    NEXT read retries. Measured and rejected: `invalidateSelf` does not
///    wait for a next reader to ask — it schedules a refresh on the
///    container's own scheduler unconditionally, and with the repository's
///    failure path being fast, the provider re-entered `create()` **four
///    times before the very first caller's own `await` had a chance to
///    run**, with no caller involved and nothing bounding it. Against a real
///    `Dio` call rather than a synchronous throw this is not a tight loop,
///    but it is an unbounded background retry with no backoff, hammering the
///    server (or draining battery) for as long as the network stays down and
///    long after the screen that triggered it is gone — worse than what it
///    replaced, not better.
/// 3. **Leaving Riverpod's OWN default retry active** (exponential backoff,
///    up to 10 attempts, `ProviderContainer.defaultRetry`). Measured: while a
///    retry is pending the provider's state is `AsyncLoading` carrying the
///    error (`retrying: true`), not `AsyncError`, and `.future` does not
///    settle — an awaiting screen hangs for the whole backoff window (tens of
///    seconds) before the typed failure ever surfaces. A screen that hangs
///    instead of being told promptly that today is unknown is "answering a
///    guess" by omission: it shows nothing rather than the honest unknown
///    state screen 3 already knows how to render.
/// 4. **`ref.keepAlive()` called AFTER the `await` (this file's own first
///    shipped version, caught in review, fix round 1 / C-1).** Looks
///    equivalent to the shape below at a glance — it is not. With
///    `.autoDispose` and no live listener, a one-off
///    `container.read(sessionTodayProvider.future)` closes its temporary
///    subscription immediately, which schedules disposal on a
///    `Timer(Duration.zero)` (`ProviderElement.mayNeedDispose`,
///    `riverpod-3.3.2/lib/src/core/element.dart:1196-1204`). Against an
///    INSTANT mock (`(_) async => value`, resolving on a microtask) the
///    `await` above resumes before that timer ever fires, so every test in
///    this file passed. Measured against a repository with a real ~30 ms
///    delay: the timer fires first, the element is disposed while the
///    `await` is still pending, and when the network call resolves —
///    **successfully** — `ref.keepAlive()` hits `_throwIfInvalidUsage()`
///    (`lib/src/core/ref.dart:253-254` → `232-242`) and throws
///    `UnmountedRefException`. Two one-shot reads against that slow
///    repository both threw, with the repository called TWICE — the exact
///    inverse of both halves of this provider's job. It held only under a
///    live `ref.watch`, which never drops its subscription mid-flight — the
///    dartdoc's own worked example below used to point callers at
///    exactly the access pattern that broke.
///
/// **What ships:** the [Ref.keepAlive] link is taken SYNCHRONOUSLY, as the
/// first statement in `create()` — before the only `await` in this function,
/// so the element is provably still alive (its own `mount()` is what is
/// currently running) and the call cannot fail. `retry: (_, __) => null`
/// still opts out of (3). On success the link is simply never closed, so the
/// value stays pinned for the rest of the app session exactly as a plain
/// non-`autoDispose` provider would. On failure the `catch` closes the link
/// explicitly — un-pinning it — before rethrowing, so the element goes back
/// to being an ordinary unwatched `autoDispose` element eligible for teardown
/// like any other, and the NEXT genuine read gets a fresh `create()` and a
/// fresh network attempt. Measured against the same slow (~30 ms) repository
/// this time: two one-shot reads of a slow SUCCESS both succeed with
/// `today()` called once; a slow FAILURE reaches the caller as the typed
/// `Failure` with no self-storm (call count holds across a 60 ms idle
/// window); a later read after recovery retries and then pins; a rejection
/// settles in ~12 ms, not tens of seconds. `session_today_test.dart` pins all
/// of this with real async gaps in its stubs, not the instant ones that let
/// the bug ship the first time.
///
/// A caller reads this exactly as it would [ServerTodayRepository.today]
/// directly: catch the typed [Failure] and render without today. Retrying
/// after a shown failure is the same `ref.invalidate` + re-read gesture every
/// other error/retry surface in this app already uses
/// (`LumenErrorRetry` and `expectRetryReissuesOneRequest`, P4b-T9) — this
/// provider adds no bespoke retry affordance of its own.
final sessionTodayProvider = FutureProvider.autoDispose<Date>((ref) async {
  // Taken FIRST, synchronously, before the only `await` below — the element
  // is guaranteed alive here (its own `mount()` is what is executing), so
  // this call cannot itself race a disposal. Taking it AFTER the await was
  // the C-1 bug: see mechanism (4) above.
  final link = ref.keepAlive();
  try {
    return await ref.watch(serverTodayRepositoryProvider).today();
  } catch (_) {
    // A failure is NOT pinned — release the link so this element goes back
    // to ordinary autoDispose teardown, then let the typed Failure through.
    link.close();
    rethrow;
  }
}, retry: (retryCount, error) => null);
