// Tests for LumenErrorRetry — the collapse of a widget that existed twice,
// verbatim, in two different layers (P4b-T5).
//
// TDD (RED first). `profile_screen.dart`'s `_ErrorBody` and
// `app_router.dart`'s `_GateUnavailableBody` were the same twenty lines:
// Center > Padding(24) > Column(min) > a liveRegion message > 16 > an outlined
// "Try again". P4b-T1 wrote the second one deliberately as a verbatim copy,
// with a comment saying T5 would collapse it. This is that collapse.
//
// Two of the tests below mount the real call sites, because every other
// assertion here would still pass if the shared widget shipped ALONGSIDE the
// two private copies rather than replacing them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';

import '../support/harness.dart';

// What this surface ANNOUNCES is asserted in
// `lumen_error_retry_semantics_test.dart`, which the widget registry requires.
// The live-region assertion moved there rather than being duplicated.

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pumpBody(
  WidgetTester tester, {
  String message = 'Something went wrong. Please try again.',
  VoidCallback? onRetry,
  Brightness brightness = Brightness.light,
}) {
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: LumenErrorRetry(message: message, onRetry: onRetry ?? () {}),
    ),
  );
}

/// A controller whose build() throws a [Failure] — the shape production
/// throws.
///
/// It used to throw a plain `StateError`, because riverpod's `defaultRetry`
/// skips `error is Error` but retries a `Failure`, and a retried build sits in
/// `AsyncLoading(retrying: true)` — which `AsyncValue.when` routes to
/// `loading`, so the error body would never have rendered. P4b-T26 moved that
/// decision to `lumenRetry` at the container, which is what lets this throw
/// what `MeRepository` throws.
class _ErrorProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async {
    throw const TlsFailure();
  }
}

void main() {
  // -------------------------------------------------------------------------
  // The widget
  // -------------------------------------------------------------------------

  testWidgets('renders the message it was given under a "Try again"', (
    tester,
  ) async {
    await _pumpBody(tester, message: 'Nope.');

    expect(find.text('Nope.'), findsOneWidget);
    // The label is a constant, not a parameter: both call sites say exactly
    // this, and a surface that needs different wording composes
    // LumenRetryButton directly instead.
    expect(find.text(LumenErrorRetry.retryLabel), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('tapping retry runs the callback', (tester) async {
    var retries = 0;
    await _pumpBody(tester, onRetry: () => retries++);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(retries, 1);
  });

  testWidgets('reuses the promoted retry button rather than a bare one', (
    tester,
  ) async {
    await _pumpBody(tester);

    expect(find.byType(LumenRetryButton), findsOneWidget);
  });

  testWidgets('the message is muted at 14, centred, with 24 of padding', (
    tester,
  ) async {
    await _pumpBody(tester, message: 'Broken.');
    final text = tester.widget<Text>(find.text('Broken.'));

    expect(text.style!.color, lumenLight.muted);
    expect(text.style!.fontSize, 14);
    expect(text.textAlign, TextAlign.center);

    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(LumenErrorRetry),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(padding.padding, const EdgeInsets.all(24));
  });

  testWidgets('takes its colours from the dark palette in dark mode', (
    tester,
  ) async {
    await _pumpBody(tester, message: 'Broken.', brightness: Brightness.dark);

    expect(
      tester.widget<Text>(find.text('Broken.')).style!.color,
      lumenDark.muted,
    );
  });

  // -------------------------------------------------------------------------
  // Both former copies are really gone
  // -------------------------------------------------------------------------

  testWidgets('screen 31\'s error state renders the shared widget', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const ProfileScreen(),
      overrides: [
        ...lumenOverrides(),
        profileControllerProvider.overrideWith(_ErrorProfileController.new),
      ],
    );

    expect(find.byType(LumenErrorRetry), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  // The splash's gate-unavailable surface is the other former copy; it is
  // asserted in `test/core/router/splash_gate_test.dart`, which already owns
  // the app-level harness that surface needs.
}
