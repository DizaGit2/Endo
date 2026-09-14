// Finishing onboarding, through the whole shell (P4b-T13).
//
// Screen 7 is the last step and the only screen that can END the flow, so this
// file drives the real `OnboardingShellScreen` — the chrome, the step switch,
// the flow controller and the step controllers — rather than one step body in
// isolation. Three things need that much of the app to be true statements:
//
//   1. **The two CTAs are two REQUEST SEQUENCES.** "Allow & finish" writes the
//      four preference rows and then completes; "Not now" completes and writes
//      nothing at all. The fake server below is stateful and applies each
//      endpoint's own rule, so the closing assertion of each test is about WHAT
//      THE SERVER ENDS UP HOLDING rather than about what the client sent.
//
//      This is where the D-02 skip earns a test of its own. The server's
//      completion backfill is guarded by
//      `if (!await db.UserNotificationPrefs.AnyAsync(...))`
//      (`OnboardingStepsService.cs:1091-1105`), so a "skip" implemented as an
//      empty POST would store four rows with every flag `false`, suppress the
//      backfill, and leave the user MUTED where the seed would have given them
//      `daily_checkin` and `phase_shift`. `_Server` reproduces exactly that, so
//      the wrong implementation fails on the stored rows and not merely on a
//      `verifyNever`.
//
//   2. **The completion 409 becomes an actionable route.** A premature finish
//      answers `code: onboarding_incomplete` with `missingSteps: ["cycle"]`.
//      The user has to end up ON screen 3, with the server's message visible —
//      and the banner belongs to the SHELL, so only a shell-mounted test can
//      see it. An unrecognised step code must degrade to "stay put and say
//      why".
//
//   3. **Screen 7 inherits T8b's data-loss path.** It is a FULL REPLACE step
//      with a back affordance, like screens 5 and 6, so a stale prefill here is
//      the next request's body rather than a stale view.
//
// Controls are located by KEY or TYPE throughout (the T5c rule).

import 'dart:async';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/notification_prefs_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/notifications_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/notifications_screen.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// The fake server
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

/// The rows the server holds, and the rules `POST /onboarding/notifications`
/// and `POST /onboarding/complete` apply to them.
///
/// Deliberately stateful, and deliberately modelled on the ABSENCE of rows: the
/// difference between skipping this step and posting an empty set is invisible
/// in a mock that echoes its request, and it is the whole subject of this file.
class _Server {
  _Server({this.completeConflict});

  /// The four rows, or null when the user has never answered — which is a
  /// DIFFERENT state from four rows that are all `false`.
  Map<String, bool>? notifications;

  /// What `POST /onboarding/complete` refuses with, or null when it succeeds.
  final ConflictFailure? completeConflict;

  bool completed = false;
  int completeCalls = 0;

  /// `GET /onboarding/state` — every step answered but the last, so the resume
  /// lands on screen 7.
  OnboardingStateResponse get state => onboardingStateFixture(
    cycleProvided: true,
    baselineProvided: true,
    goalsProvided: true,
    hormonesProvided: true,
    notificationsProvided: notifications != null,
    lastPeriodStart: Date(2026, 4, 1),
    notifications: notifications,
  );

  /// `POST /onboarding/notifications` — FULL REPLACE: the server writes a row
  /// for EVERY category and sets `Enabled` from membership of [codes]
  /// (`OnboardingStepsService.cs:556-573`).
  NotificationPrefsResponse saveNotifications(List<String> codes) {
    notifications = <String, bool>{
      for (final String code in kSeededNotifications.keys)
        code: codes.contains(code),
    };
    return notificationPrefsResponseFixture(notifications);
  }

  /// `POST /onboarding/complete` — stamps the account and materialises the seed
  /// for any preference set the user never answered.
  ///
  /// The backfill's guard is the load-bearing line: it fires only when there is
  /// NO row (`OnboardingStepsService.cs:1091`), so a step that posted an empty
  /// set has already spent it.
  OnboardingCompleteResponse complete() {
    completeCalls += 1;
    if (completeConflict != null) throw completeConflict!;
    if (!completed) {
      notifications ??= Map<String, bool>.of(kSeededNotifications);
      completed = true;
    }
    return onboardingCompleteFixture();
  }
}

// ---------------------------------------------------------------------------
// The world
// ---------------------------------------------------------------------------

/// The whole onboarding shell over [server], with only the repositories faked.
class _World {
  _World(this.server) {
    when(
      onboarding.getState,
    ).thenAnswer((_) async => Fresh<OnboardingStateResponse>(server.state));

    answerNotificationsSave();

    when(onboarding.complete).thenAnswer((_) async => server.complete());

    // Screen 6's write. The only way back INTO step 7 from step 6 is that
    // screen's own Continue, and the back-navigation test walks it — nothing
    // here asserts on hormone rows.
    when(
      () => onboarding.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) async => hormonePrefsResponseFixture());

    // Screen 3's two reads — needed because the 409 test routes the user there.
    when(settings.getSettings).thenAnswer(
      (_) async => Fresh<CycleSettingsResponse>(cycleSettingsFixture()),
    );
    when(today.today).thenAnswer((_) async => Date(2026, 4, 20));

    overrides = <Override>[
      ...lumenOverrides(),
      deviceLocaleProvider.overrideWithValue('es-ES'),
      onboardingRepositoryProvider.overrideWithValue(onboarding),
      cycleSettingsRepositoryProvider.overrideWithValue(settings),
      serverTodayRepositoryProvider.overrideWithValue(today),
    ];
  }

  final _Server server;
  final _MockOnboardingRepository onboarding = _MockOnboardingRepository();
  final _MockCycleSettingsRepository settings = _MockCycleSettingsRepository();
  final _MockServerTodayRepository today = _MockServerTodayRepository();
  late final List<Override> overrides;

  /// The array every `POST /onboarding/notifications` carried, in order.
  final List<List<String>> notificationSaves = <List<String>>[];

  late ProviderContainer container;

  void answerNotificationsSave() {
    when(
      () => onboarding.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((Invocation call) async {
      final List<String> codes = call.namedArguments[#codes] as List<String>;
      notificationSaves.add(codes);
      return server.saveNotifications(codes);
    });
  }

  Completer<NotificationPrefsResponse>? _held;
  List<String>? _heldCodes;

  /// Holds the next `POST /onboarding/notifications` OPEN, so the step can be
  /// left while the request is still in flight.
  ///
  /// An ordinary gesture rather than a contrived one: the shell's back
  /// affordance is NOT gated on `submitting`
  /// (`onboarding_shell_screen.dart:100,126`) — only the rows and the two CTAs
  /// are.
  void holdNotificationsSave() {
    when(
      () => onboarding.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((Invocation call) {
      _heldCodes = call.namedArguments[#codes] as List<String>;
      notificationSaves.add(_heldCodes!);
      return (_held = Completer<NotificationPrefsResponse>()).future;
    });
  }

  /// Lets the held write land — the server stores it now, exactly as it would
  /// have done had the user stayed on the step.
  void releaseNotificationsSave() {
    _held!.complete(server.saveNotifications(_heldCodes!));
    answerNotificationsSave();
  }

  Future<void> pump(WidgetTester tester) async {
    container = await pumpApp(
      tester,
      home: const OnboardingShellScreen(),
      overrides: overrides,
      // The shell and every step body draw an INDETERMINATE spinner while their
      // reads are open, and an indeterminate spinner never settles. The frames
      // are driven by hand instead.
      settle: false,
    );
    await _settle(tester);
  }

  OnboardingStep get step =>
      container.read(onboardingFlowControllerProvider).value!.step;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// The SHELL's back affordance. Screen 3 draws its own `Icons.chevron_left` for
/// the previous month, so the icon alone does not identify this control;
/// 'Back' is `MaterialLocalizations.backButtonTooltip`.
final Finder _shellBack = find.byWidgetPredicate(
  (Widget widget) =>
      widget is Icon &&
      widget.icon == Icons.chevron_left &&
      widget.semanticLabel == 'Back',
  description: "the shell's back affordance",
);

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(_shellBack);
  await _settle(tester);
}

Future<void> _tapAllow(WidgetTester tester) async {
  await tester.tap(find.byKey(kNotificationsAllowKey));
  await _settle(tester);
}

Future<void> _tapSkip(WidgetTester tester) async {
  await tester.tap(find.byKey(kNotificationsSkipKey));
  await _settle(tester);
}

/// Whether the category row for [code] announces itself as enabled.
bool _categoryEnabled(WidgetTester tester, String code) =>
    tester
        .getSemantics(find.byKey(notificationRowKey(code)))
        .getSemanticsData()
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

/// Every category, muted — the shape `user_notification_prefs` ends up in after
/// an empty POST, and the state a skip must NOT produce.
const Map<String, bool> _allMuted = <String, bool>{
  'daily_checkin': false,
  'phase_shift': false,
  'period_prediction': false,
  'medication_reminders': false,
};

void main() {
  setUpAll(() {
    registerFallbackValue(const <String>['daily_checkin']);
  });

  // -------------------------------------------------------------------------
  // The two request sequences
  // -------------------------------------------------------------------------

  testWidgets('"Not now" completes and leaves the SERVER to seed the '
      'preferences', (tester) async {
    final server = _Server();
    final world = _World(server);
    await world.pump(tester);

    // Premise: the flow resumed on step 7 and the server holds NO preference
    // row — the state the whole assertion below depends on.
    expect(world.step, OnboardingStep.notifications);
    expect(server.notifications, isNull);

    await _tapSkip(tester);

    // No preference write at all: D-02's skip means not calling the step
    // endpoint (`ARCHITECTURE.md` §C.1).
    expect(world.notificationSaves, isEmpty);
    expect(server.completeCalls, 1);
    expect(server.completed, isTrue);

    // …and the server's own backfill gave the user the seed. THIS is the
    // assertion an empty POST would fail: it would have written four `false`
    // rows first, and the backfill's `AnyAsync` guard would then have done
    // nothing.
    expect(server.notifications, kSeededNotifications);
    expect(server.notifications, isNot(_allMuted));
  });

  testWidgets('"Allow & finish" writes the four rows and THEN completes', (
    tester,
  ) async {
    final server = _Server();
    final world = _World(server);
    await world.pump(tester);

    // Premise: the seed is what the screen shows, and it is what the user is
    // about to change.
    expect(_categoryEnabled(tester, 'daily_checkin'), isTrue);
    expect(_categoryEnabled(tester, 'period_prediction'), isFalse);

    await tester.tap(find.byKey(notificationRowKey('daily_checkin')));
    await tester.tap(find.byKey(notificationRowKey('period_prediction')));
    await tester.pump();

    await _tapAllow(tester);

    expect(world.notificationSaves, <List<String>>[
      <String>['phase_shift', 'period_prediction'],
    ]);
    expect(server.completeCalls, 1);

    // The user's answer, stored — and NOT the seed, which is what the
    // completion would have written had the step been skipped. The two paths
    // end in different rows, which is why they are two sequences.
    expect(server.notifications, <String, bool>{
      'daily_checkin': false,
      'phase_shift': true,
      'period_prediction': true,
      'medication_reminders': false,
    });
    expect(server.notifications, isNot(kSeededNotifications));
  });

  testWidgets('"Allow & finish" with everything muted stores the muted set, '
      'not the seed', (tester) async {
    // The positive control for the skip test above, at the level of stored
    // rows: an empty preference set IS reachable, it IS different from
    // skipping, and it is what a "skip" implemented as an empty POST would
    // silently give a user who declined.
    final server = _Server();
    final world = _World(server);
    await world.pump(tester);

    await tester.tap(find.byKey(notificationRowKey('daily_checkin')));
    await tester.tap(find.byKey(notificationRowKey('phase_shift')));
    await tester.pump();

    await _tapAllow(tester);

    expect(world.notificationSaves, <List<String>>[<String>[]]);
    expect(server.notifications, _allMuted);
    expect(server.completeCalls, 1);
    // …and the completion did NOT overwrite it with the seed: the backfill only
    // fires where there is no row.
    expect(server.notifications, isNot(kSeededNotifications));
  });

  // -------------------------------------------------------------------------
  // The completion 409
  // -------------------------------------------------------------------------

  testWidgets('a 409 naming `cycle` lands the user on screen 3 with the '
      'server\'s message', (tester) async {
    final server = _Server(
      completeConflict: const ConflictFailure(
        message:
            'Onboarding cannot be completed until the required steps are '
            'answered.',
        code: 'onboarding_incomplete',
        missingSteps: <String>['cycle'],
      ),
    );
    final world = _World(server);
    await world.pump(tester);

    // Premise: the user is on step 7 and screen 3's heading is not on screen.
    expect(world.step, OnboardingStep.notifications);
    expect(find.text('When did your last period start?'), findsNothing);

    await _tapSkip(tester);

    // A conflict the user cannot act on is a dead button. The named step is
    // where they end up, and the server's own words travel with them — rendered
    // by the SHELL, because a step change would take a step-owned banner off
    // screen with it.
    expect(world.step, OnboardingStep.cycle);
    expect(find.byType(NotificationsScreen), findsNothing);
    expect(find.byType(LumenErrorBanner), findsOneWidget);
    expect(
      find.text(
        'Onboarding cannot be completed until the required steps are answered.',
      ),
      findsOneWidget,
    );
    expectLiveRegionAt(
      tester,
      find.byType(LumenErrorBanner),
      describedAs: 'the completion banner',
    );

    // …and the gate stayed shut: nothing was completed, so the router must not
    // let the user out of the flow.
    expect(
      world.container.read(onboardingStatusProvider),
      isNot(OnboardingStatus.completed),
    );
  });

  testWidgets('a 409 naming a step this build does not know leaves the user '
      'on screen 7, with the message', (tester) async {
    // `missingSteps` is append-only on the server. Sending someone to a guessed
    // screen on the strength of a code this build has never seen is worse than
    // showing them the message.
    final server = _Server(
      completeConflict: const ConflictFailure(
        message: 'Onboarding cannot be completed yet.',
        code: 'onboarding_incomplete',
        missingSteps: <String>['identity_verification'],
      ),
    );
    final world = _World(server);
    await world.pump(tester);

    await _tapSkip(tester);

    expect(world.step, OnboardingStep.notifications);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Onboarding cannot be completed yet.'), findsOneWidget);

    // The control: the SAME path with a recognised code does move the user, so
    // "stayed put" is about the unknown step and not about routing that never
    // worked. Proven at the seam the routing reads.
    expect(OnboardingStep.fromWireName('identity_verification'), isNull);
    expect(OnboardingStep.fromWireName('cycle'), OnboardingStep.cycle);

    // …and both CTAs are live again, which is what makes the message
    // actionable: a repeat completion answers 200 with the original timestamp,
    // never a second 409.
    expect(
      tester.widget<FilledButton>(find.byKey(kNotificationsAllowKey)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TextButton>(find.byKey(kNotificationsSkipKey)).onPressed,
      isNotNull,
    );
  });

  // -------------------------------------------------------------------------
  // T8b — screen 7 is a FULL REPLACE step with a back affordance
  // -------------------------------------------------------------------------

  testWidgets('screen 7 — coming back shows the categories the server STORED, '
      'and finishing again does not write the pre-save set over them', (
    tester,
  ) async {
    // The completion can fail — a 409, or a network drop — leaving the user on
    // a step they have already written. `autoDispose` then rebuilds the step
    // controller from `OnboardingFlow.state`, and on a FULL REPLACE endpoint a
    // stale prefill is not a stale view: it is the next request's body.
    final server = _Server();
    final world = _World(server);
    await world.pump(tester);

    expect(world.step, OnboardingStep.notifications);
    final NotificationsController left = world.container.read(
      notificationsControllerProvider.notifier,
    );

    // The user's real answer: mute the two the seed had on, keep nothing.
    await tester.tap(find.byKey(notificationRowKey('daily_checkin')));
    await tester.tap(find.byKey(notificationRowKey('phase_shift')));
    await tester.pump();

    await _tapAllow(tester);

    // Premise: the write landed, so what follows is about coming BACK rather
    // than about a save that never happened.
    expect(world.notificationSaves, <List<String>>[<String>[]]);
    expect(server.notifications, _allMuted);

    await _tapBack(tester);
    expect(world.step, OnboardingStep.hormones);
    await tester.tap(find.byType(FilledButton)); // screen 6's Continue
    await _settle(tester);
    expect(world.step, OnboardingStep.notifications);

    // The premise the whole test rests on: `autoDispose` disposed the
    // controller on the way out, so this is a fresh one seeded from the flow —
    // not the settled form the save left behind.
    expect(
      identical(
        world.container.read(notificationsControllerProvider.notifier),
        left,
      ),
      isFalse,
      reason:
          'leaving the step must dispose its autoDispose controller — this '
          'test is about what the REBUILT one seeds from',
    );

    // What the user sees is what the server holds.
    for (final String code in kSeededNotifications.keys) {
      expect(_categoryEnabled(tester, code), isFalse);
    }

    // …and finishing again re-posts the WHOLE set, so a prefill that had
    // reverted would write the seed back on.
    await _tapAllow(tester);
    expect(world.notificationSaves, <List<String>>[<String>[], <String>[]]);
    expect(server.notifications, _allMuted);
  });

  testWidgets('screen 7 — leaving the step while the save is IN FLIGHT still '
      'records what the server stored', (tester) async {
    // The same silent loss in a narrower window, and reachable with no back
    // door: the shell's back affordance is NOT gated on `submitting`
    // (`onboarding_shell_screen.dart:100,126`), so Back during a save is an
    // ordinary gesture. It disposes the step controller, and the 200 then lands
    // on a dead one. A refresh written BEHIND that disposal gate never runs;
    // the user walks back into step 7 to finish, the rows re-seed pre-save, and
    // the next "Allow & finish" full-replaces their answer away. That is why
    // the record is taken before the gate and the flow notifier is read before
    // the await (T8b).
    final server = _Server();
    final world = _World(server);
    await world.pump(tester);

    expect(world.step, OnboardingStep.notifications);
    await tester.tap(find.byKey(notificationRowKey('daily_checkin')));
    await tester.tap(find.byKey(notificationRowKey('phase_shift')));
    await tester.pump();

    final NotificationsController left = world.container.read(
      notificationsControllerProvider.notifier,
    );

    world.holdNotificationsSave();
    await tester.tap(find.byKey(kNotificationsAllowKey));
    await tester.pump();

    // Premise: the request is genuinely open. Without this the Back below would
    // be an ordinary back-navigation and this test would duplicate the one
    // above it.
    expect(
      world.container.read(notificationsControllerProvider).submitting,
      isTrue,
    );

    // Back, mid-flight. This is what disposes the controller the response is
    // about to land on.
    await _tapBack(tester);
    expect(world.step, OnboardingStep.hormones);

    world.releaseNotificationsSave();
    await _settle(tester);

    // Premise: the write DID land — the server holds the user's real answer, so
    // anything the client shows from here on is either that or a lie.
    expect(server.notifications, _allMuted);

    // Forward again, the way the user reaches step 7 at all.
    await tester.tap(find.byType(FilledButton)); // screen 6's Continue
    await _settle(tester);
    expect(world.step, OnboardingStep.notifications);
    expect(
      identical(
        world.container.read(notificationsControllerProvider.notifier),
        left,
      ),
      isFalse,
      reason:
          'the mid-flight Back must have disposed the step controller — this '
          'test is about what the REBUILT one seeds from',
    );

    for (final String code in kSeededNotifications.keys) {
      expect(_categoryEnabled(tester, code), isFalse);
    }

    // …and finishing does not full-replace the stored answer away.
    await _tapAllow(tester);
    expect(world.notificationSaves, <List<String>>[<String>[], <String>[]]);
    expect(server.notifications, _allMuted);
  });
}
