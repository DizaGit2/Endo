// ServerToday — where "today" comes from (P4b-T9).
//
// D-12: every day-boundary decision is the server's, and the client must not
// re-derive today from its own clock. `GET /cycle/calendar` is the endpoint
// that answers it (`ARCHITECTURE.md §A` D-12; the phase carry-over states it
// flatly: *"`GET /cycle/calendar` returns `today` + `timezone`; use the
// server's `today`"*), and with no window it answers for the USER's current
// month — `CycleCalendarService.GetCalendarAsync` derives that month from
// `UserDayInfo.Today` rather than from any UTC date.
//
// Screen 3 needs it for two things and nothing else: which month its calendar
// opens on, and which days are in the future. Both are the server's answer or
// they are absent — there is no device-clock fallback anywhere in `lib/`.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

void main() {
  late MockLumenApiApi api;
  late ServerTodayRepository repo;

  setUp(() {
    api = MockLumenApiApi();
    repo = ServerTodayRepository(api: api);
  });

  test(
    'it asks for no window, so the server answers for the USER\'s month',
    () async {
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(apiSuccess(cycleCalendarFixture()));

      await repo.today();

      // Both bounds absent is the whole request: a client that had a date to put
      // in `from` would not need to ask this question, and any date it invented
      // would be the device clock by another name.
      final captured = verify(
        () => api.cycleCalendarGet(
          from: captureAny(named: 'from'),
          to: captureAny(named: 'to'),
        ),
      ).captured;
      expect(captured, <Object?>[null, null]);
    },
  );

  test('it answers what the server said, not a constant', () async {
    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(apiSuccess(cycleCalendarFixture(today: Date(2026, 4, 20))));

    expect(await repo.today(), Date(2026, 4, 20));

    // Positive control: one date is satisfied by any implementation that
    // returns a constant — including one that returns the device's own day on
    // the machine that happens to run the suite. Two different answers from
    // two different responses is the property worth having.
    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(apiSuccess(cycleCalendarFixture(today: Date(2025, 12, 31))));

    expect(await repo.today(), Date(2025, 12, 31));
  });

  test('a response that names no day is a typed failure, not a null', () async {
    // Two distinct server faults reach the same place: no body at all, and a
    // body whose `today` is null (every generated property is `T?`, §C.0.2).
    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (_) async => Response<CycleCalendarResponse>(
        requestOptions: RequestOptions(path: '/cycle/calendar'),
        statusCode: 200,
      ),
    );
    await expectLater(repo.today(), throwsA(isA<ServerFailure>()));

    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      apiSuccess(CycleCalendarResponse((b) => b..timezone = 'Europe/Madrid')),
    );
    await expectLater(repo.today(), throwsA(isA<ServerFailure>()));
  });

  test(
    'an offline read is a typed NetworkFailure, never a DioException',
    () async {
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(apiNetworkFailure<CycleCalendarResponse>());

      // A repository that forgot to map throws the raw `DioException`, which is
      // a different type — so this assertion discriminates on its own and needs
      // no control.
      await expectLater(repo.today(), throwsA(isA<NetworkFailure>()));
    },
  );
}
