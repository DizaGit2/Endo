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
/// ## Why it is not cached
///
/// `CacheKeys`' whole policy rests on one property: *every key is derivable
/// from a date*. A request whose purpose is to **learn** the date has no date
/// to key on, and a fixed key would go stale across the one boundary it exists
/// to observe — midnight. So this is a plain online read, and a caller that
/// cannot reach the network gets a [Failure] rather than yesterday.
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
