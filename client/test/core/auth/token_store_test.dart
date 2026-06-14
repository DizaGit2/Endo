import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage storage;
  late TokenStore tokenStore;

  setUp(() {
    storage = MockFlutterSecureStorage();
    tokenStore = TokenStore(storage: storage);
  });

  // ---------------------------------------------------------------------------
  // saveTokens
  // ---------------------------------------------------------------------------
  group('TokenStore.saveTokens', () {
    test('writes all four keys with expected values', () async {
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) async {});

      final expiry = DateTime.utc(2026, 6, 14, 12, 0, 0);
      await tokenStore.saveTokens(
        accessToken: 'access-abc',
        refreshToken: 'refresh-xyz',
        idToken: 'id-tok',
        accessTokenExpiry: expiry,
      );

      verify(
        () => storage.write(key: 'access_token', value: 'access-abc'),
      ).called(1);
      verify(
        () => storage.write(key: 'refresh_token', value: 'refresh-xyz'),
      ).called(1);
      verify(
        () => storage.write(key: 'id_token', value: 'id-tok'),
      ).called(1);
      verify(
        () => storage.write(
          key: 'access_token_expiry',
          value: expiry.toUtc().toIso8601String(),
        ),
      ).called(1);
    });

    test('expiry round-trips through ISO-8601 UTC string', () async {
      String? capturedExpiry;
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((invocation) async {
        final k = invocation.namedArguments[const Symbol('key')] as String;
        final v = invocation.namedArguments[const Symbol('value')] as String;
        if (k == 'access_token_expiry') capturedExpiry = v;
      });

      final expiry = DateTime.utc(2026, 6, 14, 12, 30, 45);
      await tokenStore.saveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        idToken: 'i',
        accessTokenExpiry: expiry,
      );

      expect(capturedExpiry, isNotNull);
      final parsed = DateTime.parse(capturedExpiry!);
      expect(parsed.isUtc, isTrue);
      expect(parsed, expiry);
    });
  });

  // ---------------------------------------------------------------------------
  // readAccessToken / readRefreshToken / readIdToken
  // ---------------------------------------------------------------------------
  group('TokenStore.readAccessToken', () {
    test('returns stored value', () async {
      when(
        () => storage.read(key: 'access_token'),
      ).thenAnswer((_) async => 'access-abc');

      expect(await tokenStore.readAccessToken(), 'access-abc');
    });

    test('returns null when absent', () async {
      when(
        () => storage.read(key: 'access_token'),
      ).thenAnswer((_) async => null);

      expect(await tokenStore.readAccessToken(), isNull);
    });
  });

  group('TokenStore.readRefreshToken', () {
    test('returns stored value', () async {
      when(
        () => storage.read(key: 'refresh_token'),
      ).thenAnswer((_) async => 'refresh-xyz');

      expect(await tokenStore.readRefreshToken(), 'refresh-xyz');
    });

    test('returns null when absent', () async {
      when(
        () => storage.read(key: 'refresh_token'),
      ).thenAnswer((_) async => null);

      expect(await tokenStore.readRefreshToken(), isNull);
    });
  });

  group('TokenStore.readIdToken', () {
    test('returns stored value', () async {
      when(
        () => storage.read(key: 'id_token'),
      ).thenAnswer((_) async => 'id-tok');

      expect(await tokenStore.readIdToken(), 'id-tok');
    });

    test('returns null when absent', () async {
      when(
        () => storage.read(key: 'id_token'),
      ).thenAnswer((_) async => null);

      expect(await tokenStore.readIdToken(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // readAccessTokenExpiry
  // ---------------------------------------------------------------------------
  group('TokenStore.readAccessTokenExpiry', () {
    test('parses a stored ISO string to the correct UTC DateTime', () async {
      final expiry = DateTime.utc(2026, 6, 14, 12, 0, 0);
      when(
        () => storage.read(key: 'access_token_expiry'),
      ).thenAnswer((_) async => expiry.toIso8601String());

      final result = await tokenStore.readAccessTokenExpiry();

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result, expiry);
    });

    test('returns null when absent', () async {
      when(
        () => storage.read(key: 'access_token_expiry'),
      ).thenAnswer((_) async => null);

      expect(await tokenStore.readAccessTokenExpiry(), isNull);
    });

    test('returns null when stored value is garbage', () async {
      when(
        () => storage.read(key: 'access_token_expiry'),
      ).thenAnswer((_) async => 'not-a-date');

      expect(await tokenStore.readAccessTokenExpiry(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // hasValidSession
  // ---------------------------------------------------------------------------
  group('TokenStore.hasValidSession', () {
    test('true when a refresh token exists', () async {
      when(
        () => storage.read(key: 'refresh_token'),
      ).thenAnswer((_) async => 'refresh-xyz');

      expect(await tokenStore.hasValidSession(), isTrue);
    });

    test('false when refresh token is null (absent)', () async {
      when(
        () => storage.read(key: 'refresh_token'),
      ).thenAnswer((_) async => null);

      expect(await tokenStore.hasValidSession(), isFalse);
    });

    test('false when refresh token is empty string', () async {
      when(
        () => storage.read(key: 'refresh_token'),
      ).thenAnswer((_) async => '');

      expect(await tokenStore.hasValidSession(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // clear
  // ---------------------------------------------------------------------------
  group('TokenStore.clear', () {
    test('deletes exactly the four token keys (not deleteAll)', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await tokenStore.clear();

      verify(() => storage.delete(key: 'access_token')).called(1);
      verify(() => storage.delete(key: 'refresh_token')).called(1);
      verify(() => storage.delete(key: 'id_token')).called(1);
      verify(() => storage.delete(key: 'access_token_expiry')).called(1);
      verifyNever(() => storage.deleteAll());
      verifyNoMoreInteractions(storage);
    });
  });
}
