// ---------------------------------------------------------------------------
// lumen_wire_test.dart — P4b-T6
// ---------------------------------------------------------------------------
//
// The display side is locale-driven (D-05); the WIRE side never is. These tests
// take the same two values a user sees formatted — a weight and a date — and
// assert that what leaves the client is ISO-8601 and period-separated, by
// encoding a real `SaveBaselineRequest` through the real generated serializer
// rather than by inspecting a helper's return value.
//
// The two field-level facts that do not survive codegen (ARCHITECTURE §C.0.2)
// are pinned here too:
//   * `weightKg` — the backend REJECTS more than one decimal, it never rounds;
//   * `diagnosedOn` — a `String?` of exact form `yyyy-MM`, hand-parsed, because
//     `DateTime.parse('2026-08')` throws.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/save_baseline_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/formatters/lumen_wire.dart';

/// Encodes [request] exactly as dio does before it hits the socket.
String _wire(SaveBaselineRequest request) => json.encode(
      standardSerializers.serializeWith(SaveBaselineRequest.serializer, request),
    );

void main() {
  // -------------------------------------------------------------------------
  // weightKg — round to one decimal BEFORE serialising (§C.0.2)
  // -------------------------------------------------------------------------

  group('LumenWire.weightKg', () {
    test('rounds a two-decimal entry to one decimal', () {
      expect(LumenWire.weightKg(60.35), 60.4);
    });

    test('rounds a computed value that is not exactly representable', () {
      // The real defect this rule exists for: an lbs→kg conversion or a slider
      // step. `0.1 + 0.2` prints as 0.30000000000000004, which is a 400.
      expect(0.1 + 0.2, isNot(0.3)); // the trap is real, not hypothetical
      expect(LumenWire.weightKg(0.1 + 0.2), 0.3);
    });

    test('leaves an already-valid one-decimal value alone', () {
      expect(LumenWire.weightKg(60.4), 60.4);
      expect(LumenWire.weightKg(72), 72.0);
    });

    test('rounds half away from zero, so 60.05 does not silently truncate', () {
      expect(LumenWire.weightKg(60.05), 60.1);
    });

    test('the SERIALISED payload carries the rounded value', () {
      final request = SaveBaselineRequest(
        (b) => b..weightKg = LumenWire.weightKg(60.35),
      );
      expect(_wire(request), '{"weightKg":60.4}');
    });

    test('without the rounding the payload would carry too much precision', () {
      // This is the defect, stated as an assertion so nobody has to take the
      // comment's word for it: the raw double reaches the wire with two
      // decimals (a 400), and the computed one with seventeen.
      expect(
        _wire(SaveBaselineRequest((b) => b..weightKg = 60.35)),
        '{"weightKg":60.35}',
      );
      expect(
        _wire(SaveBaselineRequest((b) => b..weightKg = 0.1 + 0.2)),
        '{"weightKg":0.30000000000000004}',
      );
    });
  });

  // -------------------------------------------------------------------------
  // diagnosedOn — `yyyy-MM`, hand-parsed (§C.0.2)
  // -------------------------------------------------------------------------

  group('LumenWire.parseDiagnosedOn', () {
    test('parses "2026-08" to that month', () {
      final parsed = LumenWire.parseDiagnosedOn('2026-08');
      expect(parsed, DateTime(2026, 8));
      expect(parsed!.day, 1, reason: 'month precision anchors on the 1st');
    });

    test('DateTime.parse cannot do this — which is why the helper exists', () {
      expect(() => DateTime.parse('2026-08'), throwsFormatException);
    });

    test('rejects a full date', () {
      expect(LumenWire.parseDiagnosedOn('2026-08-01'), isNull);
    });

    test('rejects unpadded, unseparated, empty and null input', () {
      expect(LumenWire.parseDiagnosedOn('2026-8'), isNull);
      expect(LumenWire.parseDiagnosedOn('202608'), isNull);
      expect(LumenWire.parseDiagnosedOn(''), isNull);
      expect(LumenWire.parseDiagnosedOn(null), isNull);
      expect(LumenWire.parseDiagnosedOn('august 2026'), isNull);
    });

    test('rejects a month outside 1–12 instead of rolling it over', () {
      // DateTime(2026, 13) is a legal Dart value meaning January 2027. Reading
      // a server "2026-13" as January 2027 would be worse than showing nothing.
      expect(LumenWire.parseDiagnosedOn('2026-13'), isNull);
      expect(LumenWire.parseDiagnosedOn('2026-00'), isNull);
    });
  });

  group('LumenWire.diagnosedOn', () {
    test('formats a month as the exact wire form', () {
      expect(LumenWire.diagnosedOn(2026, 8), '2026-08');
      expect(LumenWire.diagnosedOn(2026, 12), '2026-12');
    });

    test('round-trips through the parser', () {
      const wire = '2026-08';
      final parsed = LumenWire.parseDiagnosedOn(wire)!;
      expect(LumenWire.diagnosedOn(parsed.year, parsed.month), wire);
    });

    test('the SERIALISED payload carries the month string, not a date', () {
      final request = SaveBaselineRequest(
        (b) => b..diagnosedOn = LumenWire.diagnosedOn(2026, 8),
      );
      expect(_wire(request), '{"diagnosedOn":"2026-08"}');
    });
  });

  // -------------------------------------------------------------------------
  // The round trip: what the user SEES is not what goes on the wire
  // -------------------------------------------------------------------------

  group('display formatting never reaches the wire', () {
    const locale = 'es_ES'; // the primary locale (D-03), the worst case

    test('a comma decimal and a day-first date are display-only', () {
      final dob = DateTime(2026, 3, 7);

      // What the user sees under es-ES.
      expect(LumenFormats.mass(60.35, locale), '60,4 kg');
      expect(LumenFormats.date(dob, locale), '7/3/2026');

      // What leaves the client for the same two values.
      final request = SaveBaselineRequest(
        (b) => b
          ..weightKg = LumenWire.weightKg(60.35)
          ..dob = dob.toDate()
          ..diagnosedOn = LumenWire.diagnosedOn(2026, 8),
      );
      final wire = _wire(request);

      expect(wire, contains('"weightKg":60.4'));
      expect(wire, contains('"dob":"2026-03-07"'));
      expect(wire, contains('"diagnosedOn":"2026-08"'));

      // …and nothing locale-shaped survived into it. The regex is the general
      // form of the defect: JSON separates fields with commas, so the thing to
      // forbid is a comma BETWEEN DIGITS — a decimal comma — anywhere at all.
      expect(wire, isNot(contains('60,4')));
      expect(wire, isNot(contains('7/3/2026')));
      expect(wire, isNot(matches(RegExp(r'\d,\d'))));
    });
  });
}
