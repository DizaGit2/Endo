// Timezone probe for the `TZ=Europe/Madrid` CI step (P4b-T17b).
//
// WHY THIS EXISTS. Three tests in P4b are timezone-sensitive and cannot be
// proved on the repo's primary dev machine: it is UTC−6 (Mexico Central, no
// DST since 2022) and **Dart on Windows ignores the POSIX `TZ` variable
// entirely** — a probe there still reports `-6:00` with `TZ=Europe/Madrid`
// set. The CI step re-runs those tests on `ubuntu-latest`, where Dart
// resolves local time through the C library and does read `TZ`.
//
// The hazard that makes this file necessary: if `TZ` is ignored on the runner
// too, the step still passes — and a step that silently proves nothing is a
// false green wearing a CI badge. So the step asserts the precondition it
// depends on BEFORE running the tests, and fails loudly when it does not
// hold. It never asserts anything about the tests themselves.
//
// Usage: `dart run tool/tz_probe.dart` from the `client/` directory, with
// `TZ` set. Exit 0 when the local zone is Madrid's (UTC+1 in winter, UTC+2 in
// summer), exit 1 otherwise — including on this repo's own dev machine, which
// is the intended and useful negative result.

import 'dart:io';

/// Europe/Madrid: CET (+60) in winter, CEST (+120) in summer. Both are
/// accepted, so the probe does not rot on the last Sunday in March.
const Set<int> madridOffsetsInMinutes = <int>{60, 120};

void main() {
  final now = DateTime.now();
  final offsetMinutes = now.timeZoneOffset.inMinutes;
  stdout.writeln(
    'TZ=${Platform.environment['TZ'] ?? '<unset>'} — Dart reports '
    'zone "${now.timeZoneName}", offset $offsetMinutes min',
  );

  if (madridOffsetsInMinutes.contains(offsetMinutes)) {
    stdout.writeln(
      'Local time resolves through TZ. The timezone-sensitive tests that '
      'follow are running on a positive-offset, DST-observing zone.',
    );
    return;
  }

  stderr.writeln(
    'ERROR: TZ was NOT honoured by the Dart VM (expected a Europe/Madrid '
    'offset of ${madridOffsetsInMinutes.join(' or ')} minutes, got '
    '$offsetMinutes).\n'
    'The timezone-sensitive tests in this step would run on the runner\'s '
    'own zone and prove nothing. Fix the step or delete it — do not let it '
    'stay green.',
  );
  exit(1);
}
