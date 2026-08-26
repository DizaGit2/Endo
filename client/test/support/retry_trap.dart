// ---------------------------------------------------------------------------
// retry_trap.dart — "the error state is designed, not accidental" (P4b-T3)
// ---------------------------------------------------------------------------
//
// A screen that renders an error message and nothing else has stranded the
// user: the only way out is to leave the route and come back, and on an
// `autoDispose` controller that is not discoverable. P4b's exit criteria
// therefore require a DESIGNED error/retry state on every screen that writes.
//
// The trap asserts all three halves of that, because each has been broken
// separately in this codebase before:
//   1. the error state offers a retry affordance at all;
//   2. it is a real button with an accessible name (a bare GestureDetector
//      under `Semantics(excludeSemantics: true)` is not);
//   3. tapping it re-issues EXACTLY ONE request — not zero (a dead button),
//      not two (a rebuild that also re-fires, which on a write endpoint means
//      a duplicated log entry).
//
//   final log = ApiCallLog();
//   when(() => api.symptomsPost(…)).thenAnswer(
//     apiScript([apiNetworkFailure(), apiSuccess(…)], log: log),
//   );
//   …
//   await expectRetryReissuesOneRequest(tester, requestCount: () => log.calls);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y_guard.dart';

/// The retry labels the design system ships. `Try again` belongs to the
/// generic error body, `Retry` to the offline / NetworkRequired body.
const kRetryLabels = <String>['Try again', 'Retry'];

/// Finds the retry affordance by its visible label.
///
/// Deliberately located by text rather than by widget type: T5 moves the
/// retry button into `shared/widgets/`, and a helper that names the private
/// type would break on that move.
Finder findRetryAffordance({String? label}) {
  if (label != null) return find.text(label);
  return find.byWidgetPredicate(
    (Widget w) => w is Text && w.data != null && kRetryLabels.contains(w.data),
    description: 'a retry affordance labelled one of $kRetryLabels',
  );
}

/// Asserts the currently-rendered error state offers a working retry, and that
/// using it re-issues exactly one request.
///
/// [requestCount] reads however the test counts requests — `() => log.calls`
/// for an [ApiCallLog], or a plain closure over a counter for a faked
/// controller. It is sampled before and after the tap, so a screen that
/// already issued requests during setup is fine.
///
/// Pass [label] to pin which of [kRetryLabels] is expected; leave it off to
/// accept either.
///
/// Set [settle] to false when the post-retry tree contains an indeterminate
/// spinner (settle would never arrive) and pump the frames yourself after.
Future<void> expectRetryReissuesOneRequest(
  WidgetTester tester, {
  required int Function() requestCount,
  String? label,
  bool checkSemantics = true,
  bool settle = true,
}) async {
  final retry = findRetryAffordance(label: label);

  expect(
    retry,
    findsOneWidget,
    reason:
        'The error state offers no retry affordance. An error message with no '
        'way forward strands the user: on an autoDispose controller the only '
        'recovery is leaving the route and coming back, which nothing on '
        'screen tells them to do.',
  );

  if (checkSemantics) {
    // Scoped to this assertion: the caller may or may not have the semantics
    // tree on, and a handle left open here would fail the test with "A
    // SemanticsHandle was active" instead of whatever actually broke.
    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      final Text text = tester.widget<Text>(retry);
      expectLabeledButton(tester, retry, text.data!);
    } finally {
      handle.dispose();
    }
  }

  final before = requestCount();

  await tester.tap(retry);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }

  expect(
    requestCount() - before,
    1,
    reason:
        'Tapping retry issued ${requestCount() - before} request(s), expected '
        'exactly 1. Zero means the affordance is decorative; more than one '
        'means a rebuild is re-firing it, which on a write endpoint duplicates '
        "the user's data.",
  );
}
