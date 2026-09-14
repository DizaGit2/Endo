// Tests for device_timezone.dart (D1 — PR #4 review, walk 2026-08-25, B-50).
//
// D-12 keys every day-bound row on `users.timezone`, and the client is the only
// party that knows the device's zone. Two things have to hold for that to be
// safe: the value sent is an id the server can resolve (a bad one is a 400
// keyed to a field screen 2 does not show), and asking the platform never
// throws — or hangs — into a registration or a cold start (the answer is a
// fallback, not a prerequisite).
//
// The platform is a mocked method channel here, in every shape it can answer:
// a bare id string (older platform code), a map (newer), junk, nothing, an
// error, and silence. Silence is the one that matters most: a channel with no
// handler never completes inside a widget test, and under `testWidgets`'s fake
// clock nothing but the read's own bounded wait can end it.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/time/device_timezone.dart';

const MethodChannel _channel = MethodChannel('flutter_timezone');

void _answer(WidgetTester tester, Future<Object?> Function(MethodCall) handler) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _channel,
    handler,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    ),
  );
}

void main() {
  group('usableTimezoneId', () {
    test('accepts IANA Area/Location ids as they are', () {
      for (final id in [
        'America/Mexico_City',
        'Europe/Madrid',
        'America/Argentina/Buenos_Aires',
        'America/Port-au-Prince',
        'Etc/GMT+5',
        'Pacific/Port_Moresby',
      ]) {
        expect(usableTimezoneId(id), id, reason: id);
      }
    });

    test('accepts the bare UTC the platform reports on some emulators', () {
      expect(usableTimezoneId('UTC'), 'UTC');
    });

    test('trims surrounding whitespace', () {
      expect(usableTimezoneId(' Europe/Madrid '), 'Europe/Madrid');
    });

    test('rejects abbreviations and offsets — what DateTime.timeZoneName '
        'gives, and what the server would answer 400 to', () {
      for (final raw in [
        'CST',
        'GMT',
        'GMT+1',
        'UTC+02:00',
        'Central Standard Time',
        'Europe',
        'Europe/',
        '/Madrid',
        'Europe Madrid',
        '',
        '   ',
      ]) {
        expect(usableTimezoneId(raw), isNull, reason: '"$raw"');
      }
    });

    test('rejects null', () {
      expect(usableTimezoneId(null), isNull);
    });

    test('rejects an id longer than the 64 characters the server accepts', () {
      final tooLong = '${'A' * 40}/${'B' * 30}';
      expect(tooLong.length, greaterThan(64), reason: 'premise');
      expect(usableTimezoneId(tooLong), isNull);
    });
  });

  group('readDeviceTimezone', () {
    testWidgets('returns the id the platform reports as a string', (
      tester,
    ) async {
      _answer(tester, (call) async {
        expect(call.method, 'getLocalTimezone');
        return 'America/Mexico_City';
      });

      expect(await readDeviceTimezone(), 'America/Mexico_City');
    });

    testWidgets('returns the id the platform reports as a map', (tester) async {
      _answer(tester, (_) async => <String, Object?>{
        'identifier': 'Europe/Madrid',
        'localizedName': 'Central European Standard Time',
        'locale': 'en',
      });

      expect(await readDeviceTimezone(), 'Europe/Madrid');
    });

    testWidgets('answers null when the platform reports something that is '
        'not an IANA id', (tester) async {
      _answer(tester, (_) async => 'CST');

      expect(await readDeviceTimezone(), isNull);
    });

    testWidgets('answers null, never throws, when the platform answers '
        'nothing', (tester) async {
      _answer(tester, (_) async => null);

      expect(await readDeviceTimezone(), isNull);
    });

    testWidgets('answers null, never throws, when the platform throws', (
      tester,
    ) async {
      _answer(
        tester,
        (_) async => throw PlatformException(code: 'unavailable'),
      );

      expect(await readDeviceTimezone(), isNull);
    });

    testWidgets('answers null within the bounded wait when the platform never '
        'answers — the shape of an unmocked channel, and of a hung engine',
        (tester) async {
      _answer(tester, (_) => Completer<Object?>().future);

      final pending = readDeviceTimezone();
      // Fake time: the bounded wait is a Timer, and nothing else here can
      // move the clock.
      await tester.pump(kDeviceTimezoneWait + const Duration(seconds: 1));

      expect(await pending, isNull);
    });
  });
}
