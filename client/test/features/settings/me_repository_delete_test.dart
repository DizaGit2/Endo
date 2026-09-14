// `MeRepository.deleteMe()` — the client half of `DELETE /me` (P4b-T22c).
//
// TDD (RED first): `deleteMe` did not exist when this file was written, so the
// whole file failed to compile — the loudest red available.
//
// Two properties this file exists to pin, neither of which any other test
// covers:
//
//  * **exactly one request per call.** The endpoint enqueues a background job;
//    a duplicated request is a duplicated enqueue on the server's side of the
//    contract, and P4b-T21b's lesson is that "it did not throw" is green over a
//    duplicate write. So the count is asserted, not the absence of an
//    exception.
//  * **an accepted erasure clears the WHOLE cache box, not a key list.** Every
//    other write in this app names the keys it invalidates
//    (`CacheKeys.keysForDate`, `CacheKeys.profile`); this one cannot, because
//    the date-derived keys (R-05) are an unbounded set. The store is therefore
//    driven for real (a temp-dir Hive box, as `me_repository_write_test.dart`
//    does) rather than mocked, so "everything is gone" is observed rather than
//    asserted about a mock.
//
// The failure cases pin the opposite: nothing is cleared, because the client
// does not know the server wrote anything. See `deleteMe`'s own dartdoc for
// why the ambiguous (network / 5xx) case deliberately does NOT clear either.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockLumenApiApi extends Mock implements LumenApiApi {}

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A 202 with no body — exactly what `DELETE /me` answers.
Response<void> _accepted() => Response<void>(
  requestOptions: RequestOptions(path: '/me'),
  statusCode: 202,
);

DioException _networkError() => DioException(
  requestOptions: RequestOptions(path: '/me'),
  type: DioExceptionType.connectionError,
);

DioException _status(int code) {
  final options = RequestOptions(path: '/me');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<void>(requestOptions: options, statusCode: code),
  );
}

Future<CacheStore> _buildStore(Directory dir) async {
  final storage = _MockFlutterSecureStorage();
  when(
    () => storage.read(key: any(named: 'key')),
  ).thenAnswer((_) async => null);
  when(
    () => storage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((_) async {});
  return initHive(
    path: dir.path,
    storage: storage,
    clock: () => DateTime.utc(2026, 6, 14, 12, 0, 0),
  );
}

/// Two keys from opposite ends of the key policy: the constant profile key and
/// a date-derived one. A key-list invalidation could name the first; only a
/// whole-box clear reaches both.
const _profileKey = CacheKeys.profile;
final _dayKey = CacheKeys.cycleDay(DateTime(2026, 6, 14));

void main() {
  late Directory tempDir;
  late _MockLumenApiApi api;
  late CacheStore store;
  late MeRepository repo;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('me_repository_delete_test_');
    api = _MockLumenApiApi();
    store = await _buildStore(tempDir);
    repo = MeRepository(api: api, store: store);

    await store.putJson(_profileKey, <String, dynamic>{'id': 'user-1'});
    await store.putJson(_dayKey, <String, dynamic>{'pain': 4});
  });

  tearDown(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('deleteMe — accepted', () {
    test('issues exactly ONE DELETE /me', () async {
      when(() => api.meDelete()).thenAnswer((_) async => _accepted());

      await repo.deleteMe();

      verify(() => api.meDelete()).called(1);
    });

    test('clears the whole cache box — the constant key AND a date-derived '
        'one', () async {
      when(() => api.meDelete()).thenAnswer((_) async => _accepted());
      expect(store.getJson(_profileKey), isNotNull, reason: 'precondition');
      expect(store.getJson(_dayKey), isNotNull, reason: 'precondition');

      await repo.deleteMe();

      expect(store.getJson(_profileKey), isNull);
      expect(store.getJson(_dayKey), isNull);
    });
  });

  group('deleteMe — refused', () {
    test('a connectivity failure throws NetworkFailure and clears '
        'NOTHING', () async {
      when(() => api.meDelete()).thenThrow(_networkError());

      await expectLater(repo.deleteMe(), throwsA(isA<NetworkFailure>()));

      expect(store.getJson(_profileKey), isNotNull);
      expect(store.getJson(_dayKey), isNotNull);
    });

    test('a 401 throws AuthFailure and clears NOTHING', () async {
      when(() => api.meDelete()).thenThrow(_status(401));

      await expectLater(repo.deleteMe(), throwsA(isA<AuthFailure>()));

      expect(store.getJson(_profileKey), isNotNull);
      expect(store.getJson(_dayKey), isNotNull);
    });

    test('a 503 throws ServerFailure and clears NOTHING — the ambiguous '
        'case is deliberately NOT treated as an erasure', () async {
      when(() => api.meDelete()).thenThrow(_status(503));

      await expectLater(repo.deleteMe(), throwsA(isA<ServerFailure>()));

      expect(store.getJson(_profileKey), isNotNull);
      expect(store.getJson(_dayKey), isNotNull);
    });

    test('a refused request is still issued exactly once — no retry hides '
        'inside the repository', () async {
      when(() => api.meDelete()).thenThrow(_networkError());

      await expectLater(repo.deleteMe(), throwsA(isA<Failure>()));

      verify(() => api.meDelete()).called(1);
    });
  });
}
