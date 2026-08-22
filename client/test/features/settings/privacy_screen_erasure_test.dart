// Screen 36's danger zone — `DELETE /me`, wired (P4b-T22c).
//
// TDD (RED first): the "Delete all data" row had NO `onTap` at all, and was
// documented in this directory as visual-only. `DELETE /me` worked end to end
// on the server and no user could reach it.
//
// The four properties this file exists to pin, in the order they can go wrong:
//
//  1. **Declining writes nothing.** Asserted as "the API was never called",
//     not as "the dialog closed" — a dialog that closes and posts anyway looks
//     identical from the outside.
//  2. **Accepting writes exactly ONCE.** P4b-T21b's lesson: a test that only
//     asserts "no exception" is green over a duplicate write. So the call
//     COUNT is asserted, including for the double-tap-while-in-flight path,
//     which would be a duplicate enqueue on the server's side of the contract.
//  3. **A 202 is an ACCEPTANCE, not a completion.** The server answers before
//     the erasure has run. No string this screen shows may say the data is
//     gone — asserted twice: over the authored constants themselves (which
//     survives any change to the tree) and over every string rendered after
//     the 202.
//  4. **A refused request is never silent, and THIS SCREEN changes nothing
//     of its own.** No session ends here, no local data is thrown away here,
//     and the user is told. What the layers BELOW do on a refusal is a
//     different question, answered in the note above the `refused` group.
//
// **The layer this file observes.** The API fake is a `MockLumenApiApi` in
// EVERY test here, the whole-app one at the bottom included — above Dio,
// above `AuthInterceptor`, so NOTHING in this file observes the interceptor.
// What the bottom test adds is the real `LumenApp`, router and redirect, not
// a lower fake. These are therefore assertions about the SCREEN, plus one
// about where the app puts the user afterwards. Where that differs from what
// the app does, the difference is stated rather than papered over: see the
// note above the `refused` group, which walks all three refusals.
//
// The ROUTE and the entry affordance live in
// `test/core/router/privacy_route_test.dart`, and are not re-asserted here.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// API answers
// ---------------------------------------------------------------------------

/// The real answer: `202 Accepted`, no body. The job is ENQUEUED, not run.
ApiAnswer<void> _accepted() => (_) async {
  return Response<void>(
    requestOptions: RequestOptions(path: '/me'),
    statusCode: 202,
  );
};

/// A `badResponse` at [code] — 401 and 503 have no archetype of their own.
ApiAnswer<void> _status(int code) => (_) async {
  final options = RequestOptions(path: '/me');
  throw DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<void>(requestOptions: options, statusCode: code),
  );
};

Response<void> _acceptedResponse() => Response<void>(
  requestOptions: RequestOptions(path: '/me'),
  statusCode: 202,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

typedef _Harness = ({
  ProviderContainer container,
  MockLumenApiApi api,
  MockTokenStore tokenStore,
  MockCacheStore cacheStore,
});

Future<_Harness> _pumpPrivacy(
  WidgetTester tester, {
  required ApiAnswer<void> answer,
}) async {
  final api = MockLumenApiApi();
  when(() => api.meDelete()).thenAnswer(answer);
  final tokenStore = emptyTokenStore();
  final cacheStore = emptyCacheStore();

  final container = await pumpApp(
    tester,
    home: const PrivacyScreen(),
    overrides: lumenOverrides(
      api: api,
      cacheStore: cacheStore,
      tokenStore: tokenStore,
    ),
  );
  return (
    container: container,
    api: api,
    tokenStore: tokenStore,
    cacheStore: cacheStore,
  );
}

/// Opens the confirmation and takes the destructive choice.
///
/// [settle] is false for the in-flight tests: the row shows an indeterminate
/// progress indicator while the request is out, and `pumpAndSettle` never
/// returns on one of those.
Future<void> _confirmDelete(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.text(kPrivacyDeleteRowLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(kPrivacyDeleteConfirmLabel));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Enough frames for the dialog's ~150 ms exit transition to finish and
    // the route to be removed, but NOT `pumpAndSettle` — the row shows an
    // indeterminate progress indicator while the request is out, and settle
    // never arrives on one of those.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }
}

// ---------------------------------------------------------------------------
// "Has it happened yet?" — the claims this screen must never make
// ---------------------------------------------------------------------------

/// Words that assert the erasure has ALREADY happened.
///
/// `DELETE /me` answers `202`: the job is enqueued and nothing has been erased
/// when the client hears back. Any of these on screen after that would be a
/// completion claim the API has not made — and on this surface, a compliance
/// statement.
final List<RegExp> kCompletionClaims = <RegExp>[
  RegExp(r'\bdeleted\b', caseSensitive: false),
  RegExp(r'\berased\b', caseSensitive: false),
  RegExp(r'\bremoved\b', caseSensitive: false),
  RegExp(r'\bwiped\b', caseSensitive: false),
  RegExp(r'\bgone\b', caseSensitive: false),
];

/// Words that characterise what SURVIVES an erasure, or how permanent it is.
///
/// P4a's STATUS records three open L-05/L-06 blockers, and two of them falsify
/// the obvious wording: "erased data remains encrypted and unreadable" is no
/// longer true of plaintext health data, and the backup horizon is UNBOUNDED
/// (§G's nightly `pg_dump` has no expiry). So a sentence about backups,
/// encryption or irreversibility is a legal claim, not merely imprecise copy.
///
/// **Applied to the AUTHORED strings, not to the whole tree**, and that scope
/// is deliberate: screen 36 already ships a DATA row reading "Encryption
/// status / AES-256", which is pre-existing P3b copy the plan explicitly says
/// P4b must flag rather than rewrite (the *"Known, accepted, still-open at
/// phase exit"* paragraph in P4b's phase entry — R-23: named, not cited by
/// line, because a plan edit moves it). **The PO reviewed that row and the
/// warrant canary on 2026-08-22 and ruled both KEEP, risk accepted, routed to
/// the L-05/L-06 legal pass.** So the scope stands for a second reason now: it
/// is not this test's call. This task must not ADD such a claim; it is not
/// licensed to remove the ones already there.
final List<RegExp> kLegalCharacterisations = <RegExp>[
  RegExp('permanent', caseSensitive: false),
  RegExp('irreversib', caseSensitive: false),
  RegExp('cannot be undone', caseSensitive: false),
  RegExp('backup', caseSensitive: false),
  RegExp('encrypt', caseSensitive: false),
  RegExp(r'\bunreadable\b', caseSensitive: false),
];

void _expectNoMatch(
  String text,
  List<RegExp> patterns, {
  required String describedAs,
  required String why,
}) {
  for (final pattern in patterns) {
    expect(
      pattern.hasMatch(text),
      isFalse,
      reason: '$describedAs matches /${pattern.pattern}/ — "$text". $why',
    );
  }
}

void _expectMakesNoCompletionClaim(String text, {required String describedAs}) {
  _expectNoMatch(
    text,
    kCompletionClaims,
    describedAs: describedAs,
    why: 'A 202 says the request was ACCEPTED, never that the erasure has run.',
  );
}

/// Every string the tree is currently rendering, `Text` and `Text.rich` alike.
List<String> _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

// ---------------------------------------------------------------------------
// The whole app, for the landing assertion
// ---------------------------------------------------------------------------

class _SettledProfile extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async =>
      Fresh(meResponseFixture(id: 'user-1'));

  @override
  Future<void> saveDisplayName(String name) async {}
}

class _SettledOnboarding extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.cycle, state: onboardingStateFixture()),
  );
}

class _SettledDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(
    DashboardView(
      today: DateTime(2026, 4, 20),
      displayName: 'Maya',
      todayPain: null,
      todayMood: null,
      yesterdayPain: null,
      phaseUnavailableReason: null,
    ),
  );
}

/// Pumps the REAL [LumenApp] — the real router, the real redirect, the real
/// `authStatusProvider` and the REAL [MeRepository] — which is the only
/// harness that can answer "where does the app land when the session ends?".
///
/// [MeRepository] is deliberately NOT mocked here (unlike `r19_navigation_
/// test.dart`, whose subject is navigation): this test's subject is the write,
/// so the whole path from the row to `meDelete` has to be the production one.
/// The onboarding gate's `/me` read therefore also goes through it, which is
/// why `meGet` is stubbed.
///
/// settle: false — the splash spinner animates forever while the gate's read
/// is in flight, so a handful of manual frames stand in for it (r19's shape).
Future<MockLumenApiApi> _pumpRealApp(WidgetTester tester) async {
  final api = MockLumenApiApi();
  when(() => api.meDelete()).thenAnswer(_accepted());
  when(() => api.meGet()).thenAnswer(
    apiSuccess(meResponseFixture(id: 'user-1', onboardingCompleted: true)),
  );

  await pumpLumenApp(
    tester,
    settle: false,
    overrides: [
      ...lumenOverrides(
        api: api,
        cacheStore: emptyCacheStore(),
        tokenStore: emptyTokenStore(),
      ),
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      dashboardControllerProvider.overrideWith(_SettledDashboard.new),
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
      profileControllerProvider.overrideWith(_SettledProfile.new),
    ],
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return api;
}

void main() {
  // -------------------------------------------------------------------------
  // The confirmation
  // -------------------------------------------------------------------------

  group('the confirmation', () {
    testWidgets(
      'the danger-zone row opens it, and opening it alone writes nothing',
      (tester) async {
        final h = await _pumpPrivacy(tester, answer: _accepted());

        await tester.tap(find.text(kPrivacyDeleteRowLabel));
        await tester.pumpAndSettle();

        expect(find.text(kPrivacyDeleteConfirmTitle), findsOneWidget);
        expect(find.text(kPrivacyDeleteConfirmBody), findsOneWidget);
        expect(find.text(kPrivacyDeleteConfirmLabel), findsOneWidget);
        expect(find.text(kPrivacyDeleteCancelLabel), findsOneWidget);
        verifyNever(() => h.api.meDelete());
      },
    );

    testWidgets('the dismissal comes FIRST and is the autofocused choice — the '
        'destructive one is not what a stray activation takes', (tester) async {
      await _pumpPrivacy(tester, answer: _accepted());

      await tester.tap(find.text(kPrivacyDeleteRowLabel));
      await tester.pumpAndSettle();

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      final actions = dialog.actions!;
      expect(
        ((actions.first as TextButton).child! as Text).data,
        kPrivacyDeleteCancelLabel,
      );
      expect((actions.first as TextButton).autofocus, isTrue);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, kPrivacyDeleteConfirmLabel),
            )
            .autofocus,
        isFalse,
      );
    });

    testWidgets('Cancel writes NOTHING — the API is never called', (
      tester,
    ) async {
      final h = await _pumpPrivacy(tester, answer: _accepted());

      await tester.tap(find.text(kPrivacyDeleteRowLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kPrivacyDeleteCancelLabel));
      await tester.pumpAndSettle();

      expect(find.text(kPrivacyDeleteConfirmTitle), findsNothing);
      verifyNever(() => h.api.meDelete());
      expect(h.container.read(authStatusProvider), AuthStatus.authenticated);
    });

    testWidgets(
      'a barrier tap writes NOTHING either — a dismissal that pops null is '
      'not consent',
      (tester) async {
        final h = await _pumpPrivacy(tester, answer: _accepted());

        await tester.tap(find.text(kPrivacyDeleteRowLabel));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.text(kPrivacyDeleteConfirmTitle), findsNothing);
        verifyNever(() => h.api.meDelete());
        expect(h.container.read(authStatusProvider), AuthStatus.authenticated);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Accepting
  // -------------------------------------------------------------------------

  group('accepting', () {
    testWidgets('calls DELETE /me exactly ONCE', (tester) async {
      final h = await _pumpPrivacy(tester, answer: _accepted());

      await _confirmDelete(tester);

      verify(() => h.api.meDelete()).called(1);
    });

    testWidgets(
      'a second tap while the request is IN FLIGHT issues no second request',
      (tester) async {
        final release = Completer<Response<void>>();
        var calls = 0;
        final h = await _pumpPrivacy(
          tester,
          answer: (_) {
            calls++;
            return release.future;
          },
        );

        await _confirmDelete(tester, settle: false);
        expect(calls, 1);

        // The row must refuse the second attempt outright. Tapping it and then
        // looking for the dialog is the falsifiable form: without the guard the
        // confirmation opens again and a second confirm posts again.
        await tester.tap(
          find.text(kPrivacyDeleteRowLabel),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(find.text(kPrivacyDeleteConfirmTitle), findsNothing);
        expect(calls, 1);

        release.complete(_acceptedResponse());
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(
          h.container.read(authStatusProvider),
          AuthStatus.unauthenticated,
        );
      },
    );

    testWidgetsWithSemantics(
      'while the request is in flight the row says so — its semantics node '
      'declares itself DISABLED with no tap action, and it shows a spinner '
      'instead of the chevron',
      (tester) async {
        final release = Completer<Response<void>>();
        await _pumpPrivacy(tester, answer: (_) => release.future);

        await _confirmDelete(tester, settle: false);

        final data = tester
            .getSemantics(find.text(kPrivacyDeleteRowLabel))
            .getSemanticsData();
        expect(
          data.flagsCollection.isButton,
          isTrue,
          reason: 'It is still the same control, just not usable right now.',
        );
        expect(
          data.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason:
              'A node that keeps isButton, offers no tap action and still '
              'claims to be enabled is "looks like a button, cannot be '
              'activated, never says why".',
        );
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsNothing);

        release.complete(_acceptedResponse());
        await tester.pumpAndSettle();
      },
    );

    // -----------------------------------------------------------------------
    // The in-flight ANNOUNCEMENT (P4b-T22c fix round, review I2)
    // -----------------------------------------------------------------------
    //
    // The test above pins that the row stops claiming to be usable. That is
    // not the same as telling anyone what is happening: "Delete all data,
    // button, disabled" is also what a permanently dead control sounds like,
    // and the sighted user meanwhile gets a spinner. The wait can run to 15 s
    // (`dioProvider`'s connect timeout) after confirming an ACCOUNT DELETION.
    //
    // The house rule is one `semanticsLabel` per new spinner. This spinner has
    // none on purpose: `_DeleteAllDataRow`'s `Semantics(excludeSemantics:
    // true)` drops its subtree, so a label there would announce to nobody. The
    // state is carried on the row's own node instead. These two assertions are
    // what stop that from being a story told only in a dartdoc.
    //
    // What the harness itself sees is the node's `label` and its live-region
    // flag. That the platform then SPEAKS the new name unprompted is the SDK
    // contract for that flag (quoted at the assertion), inferred here rather
    // than observed: no assistive technology runs in a widget test.

    testWidgetsWithSemantics(
      'while the request is in flight the row ANNOUNCES it — the accessible '
      'name becomes the busy one, EXACTLY, and the node carries the '
      'live-region flag that makes the platforms speak it without focus '
      '(SDK contract, inferred: no screen reader runs in a widget test)',
      (tester) async {
        final release = Completer<Response<void>>();
        await _pumpPrivacy(tester, answer: (_) => release.future);

        // Before: the ordinary name, and NOT a live region — a row that is
        // permanently live re-announces itself on every unrelated rebuild.
        final before = tester
            .getSemantics(find.text(kPrivacyDeleteRowLabel))
            .getSemanticsData();
        expect(before.label, kPrivacyDeleteRowLabel);
        expect(before.flagsCollection.isLiveRegion, isFalse);

        await _confirmDelete(tester, settle: false);

        final busy = tester
            .getSemantics(find.text(kPrivacyDeleteRowLabel))
            .getSemanticsData();
        expect(
          busy.label,
          kPrivacyDeleteRowBusyLabel,
          reason:
              'EXACT, not `contains`. Exactness is what keeps the subtree '
              'exclusion honest: if a spinner semanticsLabel ever did leak '
              'into this node it would change the announced name, and this '
              'assertion is what notices instead of the name being quietly '
              'stolen.',
        );
        expect(
          busy.label,
          contains(kPrivacyDeleteRowLabel),
          reason:
              'WCAG 2.5.3 Label in Name: the accessible name must still '
              'contain the words a sighted user reads, or voice control '
              'loses the control.',
        );
        expect(
          busy.flagsCollection.isLiveRegion,
          isTrue,
          reason:
              'What is asserted is the FLAG. The audible consequence is an '
              'inference from the SDK contract, not something this harness '
              'observes: `SemanticsConfiguration.liveRegion` documents that '
              '"On Android and iOS, live region causes a polite announcement '
              'to be generated automatically, even if the widget does not '
              'have accessibility focus." Without the flag the new name is '
              'only reached by a user who happens to swipe back onto a '
              'control they just activated.',
        );

        release.complete(_acceptedResponse());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'THIS SCREEN moves nothing about the session until the 202 has '
      'arrived — its own sign-out does not race the request. (Below this '
      'fake the session can end before any 202 does: a proactive refresh of '
      'a near-expiry token signs the user out and the DELETE is never sent '
      '— see the note above the `refused` group.)',
      (tester) async {
        final release = Completer<Response<void>>();
        final h = await _pumpPrivacy(tester, answer: (_) => release.future);

        await _confirmDelete(tester, settle: false);

        // In flight: the request is out, and THIS SCREEN has moved nothing
        // about the session — `authStatusProvider` and the token store are
        // what this harness can see, and neither has moved.
        verify(() => h.api.meDelete()).called(1);
        verifyNever(() => h.tokenStore.clear());
        expect(h.container.read(authStatusProvider), AuthStatus.authenticated);
        expect(find.text(kPrivacyErasureRequestedMessage), findsNothing);

        release.complete(_acceptedResponse());
        await tester.pumpAndSettle();

        verify(() => h.tokenStore.clear()).called(1);
        expect(
          h.container.read(authStatusProvider),
          AuthStatus.unauthenticated,
        );
      },
    );

    testWidgetsWithSemantics(
      'the session ends and the user is told the request was RECEIVED',
      (tester) async {
        final h = await _pumpPrivacy(tester, answer: _accepted());

        await _confirmDelete(tester);

        expect(
          h.container.read(authStatusProvider),
          AuthStatus.unauthenticated,
        );
        verify(() => h.tokenStore.clear()).called(1);
        expectLiveRegion(tester, kPrivacyErasureRequestedMessage);
      },
    );

    testWidgets(
      'NO string on screen after the 202 claims the deletion has happened',
      (tester) async {
        await _pumpPrivacy(tester, answer: _accepted());

        await _confirmDelete(tester);

        final rendered = _renderedText(tester);
        expect(rendered, contains(kPrivacyErasureRequestedMessage));
        for (final text in rendered) {
          _expectMakesNoCompletionClaim(
            text,
            describedAs: 'A string on screen',
          );
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // The authored copy itself — a pin that survives any change to the tree
  // -------------------------------------------------------------------------

  group('the authored copy', () {
    test('no erasure string claims completion, or characterises backups, '
        'encryption or irreversibility', () {
      const authored = <String, String>{
        'kPrivacyDeleteConfirmTitle': kPrivacyDeleteConfirmTitle,
        'kPrivacyDeleteConfirmBody': kPrivacyDeleteConfirmBody,
        'kPrivacyErasureRequestedMessage': kPrivacyErasureRequestedMessage,
        'kPrivacyErasureFailedMessage': kPrivacyErasureFailedMessage,
        // Never rendered as text — it is the row's accessible NAME while the
        // request is out. It is authored copy all the same, and a screen
        // reader is exactly the wrong audience to make an unchecked claim to.
        'kPrivacyDeleteRowBusyLabel': kPrivacyDeleteRowBusyLabel,
      };
      authored.forEach((name, text) {
        _expectMakesNoCompletionClaim(text, describedAs: name);
        _expectNoMatch(
          text,
          kLegalCharacterisations,
          describedAs: name,
          why:
              'P4a has three OPEN L-05/L-06 blockers; two of them falsify '
              'exactly this kind of sentence. Describe what the action does '
              'and stop there.',
        );
      });
    });
  });

  // -------------------------------------------------------------------------
  // Refused
  // -------------------------------------------------------------------------
  //
  // **What this harness can see, and what it cannot.** The fake is a
  // `MockLumenApiApi` — ABOVE Dio. These tests therefore observe THE SCREEN
  // and nothing underneath it. That scope is exactly right for the properties
  // the screen owes: on a refusal it must tell the user, must not end the
  // session ITSELF, and must not throw local data away ITSELF. It is not wide
  // enough to say what the APP does — and on ALL THREE refusals the app can
  // do something else. So every name below carries the scope it can back up.
  //
  // **Branch by branch, where the app parts company with the screen.** Each
  // step below was re-read at source in `auth_interceptor.dart`,
  // `dio_provider.dart` and `auth_controller.dart`:
  //
  //   * **A 401 never reaches this code untouched.** `onError` intercepts it
  //     and attempts a refresh:
  //       - refresh fails, or no refresh token is stored → `_performRefresh`
  //         clears the token store and calls `onAuthLost`. **The session
  //         ends.** This is the likely branch for `DELETE /me`.
  //       - refresh succeeds → the request is retried once, marked; a second
  //         401 is forwarded untouched and the session survives, which is the
  //         only case that matches the test below.
  //   * **No connectivity and a 503 can end the session BEFORE the DELETE is
  //     ever sent** — they are not the safe cases with the 401 as the lone
  //     exception; they are the same case reached by a different trigger.
  //     `onRequest` refreshes PROACTIVELY whenever the stored access token
  //     has `_kProactiveRefreshThreshold` (30 s) of life left OR LESS — the
  //     code is `remaining <= threshold`, so a token that expired hours ago
  //     takes the same branch, not only one inside a 30 s window. Offline
  //     that refresh cannot reach the token endpoint at all; against a backend
  //     that is 5xx-ing `/me`, the token endpoint may be down with it. Either
  //     way `_performRefresh` clears the tokens, calls `onAuthLost` and
  //     throws, and `onRequest` REJECTS the request — so the user is signed
  //     out and `meDelete` never leaves the device. The branch is reached
  //     whenever the access token is within 30 s of expiry, at it, or past
  //     it — which is not a rare state.
  //   * **`onAuthLost` also throws local data away.** `dioProvider` wires it
  //     to `authStatusProvider.notifier.logout()`, and
  //     `AuthController.logout()` ends the OIDC session, clears the
  //     `TokenStore` AND runs `cacheStoreProvider.purge()` before going
  //     `unauthenticated`. So on every branch above the local cache IS purged
  //     — which is why the purge test below is named for this screen and not
  //     for the app.
  //
  // In each of those cases the user is left looking at
  // `kPrivacyErasureFailedMessage` — *"please try again"* — on the way to
  // Welcome, where there is nothing to try again with.
  //
  // **The production behaviour is pinned where it lives** and is not restated
  // here: `auth_interceptor_test.dart`'s *"refresh throws → clear() called,
  // onAuthLost invoked, DioException thrown"* and
  // `dio_provider_test.dart`'s *"401 with a failing refresh clears tokens and
  // drives authStatusProvider to unauthenticated"*.
  //
  // (Nothing about the screen changes as a result: it must not end a session
  // it cannot reason about, and a 401 on `DELETE /me` is ambiguous to it —
  // the same call disables the Keycloak identity, so a 401 can equally mean
  // "an earlier attempt already succeeded". Filed for the phase's STATUS: the
  // retry advice is misleading on EVERY sign-out branch, not just the 401,
  // and correcting it is a copy change on an L-05/L-06-gated string, not an
  // implementer's call.)

  group('refused', () {
    /// The refusal cases, each with the scope its assertions ACTUALLY have —
    /// spliced into the test name so the name cannot outrun the harness.
    final refusals = <String, ({ApiAnswer<void> Function() answer, String scope})>{
      'no connectivity': (
        answer: () => apiNetworkFailure<void>(path: '/me'),
        scope:
            'and THIS SCREEN signs nobody out — offline, a proactive refresh '
            'of a near-expiry token ends the session one layer below this '
            'fake, before the DELETE is even sent; see the note above the '
            'group',
      ),
      'a 401': (
        answer: () => _status(401),
        scope:
            'and THIS SCREEN signs nobody out — in production the session '
            'usually ends anyway, one layer below this fake; see the note '
            'above the group',
      ),
      'a 503': (
        answer: () => _status(503),
        scope:
            'and THIS SCREEN signs nobody out — if the token endpoint is down '
            'with the API, that same proactive refresh ends the session one '
            'layer below this fake; see the note above the group',
      ),
    };

    refusals.forEach((name, refusal) {
      final answer = refusal.answer;
      testWidgetsWithSemantics(
        '$name: the user is told, ${refusal.scope}',
        (tester) async {
          final h = await _pumpPrivacy(tester, answer: answer());

          await _confirmDelete(tester);

          expectLiveRegion(tester, kPrivacyErasureFailedMessage);
          expect(find.text(kPrivacyErasureRequestedMessage), findsNothing);
          expect(
            h.container.read(authStatusProvider),
            AuthStatus.authenticated,
          );
          verifyNever(() => h.tokenStore.clear());
        },
      );

      // Scoped to the screen on purpose. On every branch where `onAuthLost`
      // fires — the 401's failed refresh, and the proactive refresh behind
      // the other two (see the note above the group) — production `logout()`
      // runs `cacheStoreProvider.purge()`, so "nothing local is thrown away"
      // would be false of the APP. What the screen owes, and all this harness
      // can see, is that the screen purges nothing of its own on a refusal.
      testWidgets('$name: THIS SCREEN throws nothing local away', (
        tester,
      ) async {
        final h = await _pumpPrivacy(tester, answer: answer());

        await _confirmDelete(tester);

        verifyNever(() => h.cacheStore.purge());
      });

      testWidgetsWithSemantics(
        '$name: the row is live again — the SCREEN leaves a retry available '
        '(whether the app still has a session to retry with is decided '
        'below this harness; see the note above the group)',
        (tester) async {
          await _pumpPrivacy(tester, answer: answer());

          await _confirmDelete(tester);

          expectLabeledButton(
            tester,
            find.text(kPrivacyDeleteRowLabel),
            kPrivacyDeleteRowLabel,
          );
        },
      );
    });
  });

  // -------------------------------------------------------------------------
  // The whole app — where does an accepted erasure land the user?
  // -------------------------------------------------------------------------

  group('the whole app', () {
    testWidgets(
      'More -> Privacy & security -> Delete all data -> Delete lands the app '
      'on the unauthenticated welcome screen, with the request-received '
      'message still on screen',
      (tester) async {
        final api = await _pumpRealApp(tester);

        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kPrivacyScreenTitle));
        await tester.pumpAndSettle();
        expect(find.byType(PrivacyScreen), findsOneWidget);

        await _confirmDelete(tester);

        verify(() => api.meDelete()).called(1);
        expect(find.byType(PrivacyScreen), findsNothing);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(find.text(kPrivacyErasureRequestedMessage), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The route is NOT re-asserted here — on purpose
  // -------------------------------------------------------------------------
  //
  // What stood here was `expect(Routes.privacy, isNotEmpty)`, named "screen 36
  // has a route at all (the whole point of T22c)". It asserted that one `const
  // String` is non-empty: no router, no `lumenRoutes()`, no redirect, so no
  // change to the route table could redden it. This task's own mutation m6 —
  // delete the `routes:` child from the More branch, i.e. exactly "screen 36
  // has no route" — turned FIVE tests red, and this was not one of them.
  //
  // Deleted rather than renamed: the property is owned, and pinned by running
  // the router, in `test/core/router/privacy_route_test.dart` — the path
  // constant asserted by EXACT value against `Routes.more` (which subsumes
  // non-empty), and a deep link to `/more/privacy` pumped through
  // `lumenRoutes()` and the production redirect, expecting screen 36 and NOT
  // the dashboard. That deep-link test is one of m6's five.
}
