// NotificationsController — screen 7's answers, and the two ways to finish
// (P4b-T13).
//
// This is the last onboarding step and the first screen that can END the flow,
// so its two CTAs are not two paths to one request. They are two different
// REQUEST SEQUENCES, and D-02 is what makes the difference matter:
//
//   * "Allow & finish" → `POST /onboarding/notifications` (FULL REPLACE of all
//     four rows) and then `POST /onboarding/complete`;
//   * "Not now"        → `POST /onboarding/complete` **only**, writing no
//     preference row at all.
//
// **A skip that posted an empty preference set would be wrong, and silently
// so.** `SaveNotificationPrefsAsync` writes a row for EVERY category and sets
// `Enabled` from membership of the array (`OnboardingStepsService.cs:556-573`
// through `StagePreferenceRows` at `:1172-1192`), so `enabledCategories: []`
// stores four rows with every flag `false`. `CompleteAsync` then leaves them
// alone, because its backfill is guarded by
// `if (!await db.UserNotificationPrefs.AnyAsync(...))`
// (`OnboardingStepsService.cs:1091-1105`). The user who tapped "Not now" would
// end up with everything muted instead of the ON / ON / OFF / OFF seed
// completion would otherwise have materialised — and nothing on any screen
// would ever say so.
//
// So `Not now writes no preference row at all` is asserted as a request
// sequence, with the empty POST as its positive control in the same file: the
// two states are reachable, they are different, and only the `verifyNever`
// tells them apart.
//
// CONTROLLER SHAPE. `build()` awaits nothing — the category list came with the
// shell's resume read — so this is a plain `Notifier<NotificationsForm>` with a
// synchronous `build()`, the rule's empty-build case taken to its root. Every
// test that mutates settles the flow first.

import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/notification_category_selection.dart';
import 'package:lumen/api/model/notification_prefs_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/push/push_token_source.dart';
import 'package:lumen/features/onboarding/application/notifications_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 7 carrying [notifications] as its resume
/// read.
///
/// Only `build()` is overridden: `complete()` is the REAL one, so every
/// assertion below about the completion is about the shipped code path.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.notifications);

  final Map<String, bool>? notifications;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.notifications,
      state: onboardingStateFixture(
        cycleProvided: true,
        baselineProvided: true,
        goalsProvided: true,
        hormonesProvided: true,
        notifications: notifications,
      ),
    ),
  );
}

/// A [PushTokenSource] answering [token], counting how often it was asked.
class _Source implements PushTokenSource {
  _Source([this.token]);

  final PushToken? token;
  int reads = 0;

  @override
  Future<PushToken?> read() async {
    reads += 1;
    return token;
  }
}

class _Harness {
  _Harness({Map<String, bool>? notifications, PushTokenSource? source})
    : source = source ?? _Source() {
    container = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[
        authStatusProvider.overrideWith(
          () => FakeAuthController(AuthStatus.unauthenticated),
        ),
        onboardingRepositoryProvider.overrideWithValue(repo),
        onboardingFlowControllerProvider.overrideWith(
          () => _SettledFlow(notifications),
        ),
        pushTokenSourceProvider.overrideWithValue(this.source),
      ],
    );
    addTearDown(container.dispose);
    // Both are autoDispose; a bare `read` would tear them down again the moment
    // it returned. A screen's `ref.watch` is what keeps them alive in
    // production, and these subscriptions are that.
    container.listen(onboardingFlowControllerProvider, (_, _) {});
    container.listen(notificationsControllerProvider, (_, _) {});

    when(repo.complete).thenAnswer((_) async => onboardingCompleteFixture());
  }

  final _MockOnboardingRepository repo = _MockOnboardingRepository();
  final PushTokenSource source;
  late final ProviderContainer container;

  NotificationsForm get form => container.read(notificationsControllerProvider);

  NotificationsController get controller =>
      container.read(notificationsControllerProvider.notifier);

  OnboardingFlow get flow =>
      container.read(onboardingFlowControllerProvider).value!;

  void answerSave([NotificationPrefsResponse? body]) {
    when(
      () => repo.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((_) async => body ?? notificationPrefsResponseFixture());
  }

  void rejectSave(Failure failure) {
    when(
      () => repo.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((_) async => throw failure);
  }

  Completer<NotificationPrefsResponse> holdSave() {
    final completer = Completer<NotificationPrefsResponse>();
    when(
      () => repo.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((_) => completer.future);
    return completer;
  }

  /// Everything the repository was handed on its LAST call.
  ///
  /// One `verify` for all three arguments, and read into a local by every
  /// caller: `verify` CONSUMES the recorded invocation, so a test that asked
  /// twice would be told there were no calls at all — a failure that looks
  /// exactly like the code never having posted.
  ({List<String> codes, String? pushToken, String? platform}) get posted {
    final List<dynamic> captured = verify(
      () => repo.saveNotifications(
        codes: captureAny(named: 'codes'),
        pushToken: captureAny(named: 'pushToken'),
        platform: captureAny(named: 'platform'),
      ),
    ).captured;
    return (
      codes: captured[captured.length - 3] as List<String>,
      pushToken: captured[captured.length - 2] as String?,
      platform: captured.last as String?,
    );
  }

  void verifyNoSave() => verifyNever(
    () => repo.saveNotifications(
      codes: any(named: 'codes'),
      pushToken: any(named: 'pushToken'),
      platform: any(named: 'platform'),
    ),
  );
}

/// The codes the form currently holds ON, in the form's own order.
List<String> _enabled(NotificationsForm form) => form.enabledCodes;

void main() {
  setUpAll(() {
    registerFallbackValue(const <String>['daily_checkin']);
  });

  // -------------------------------------------------------------------------
  // The list is the server's
  // -------------------------------------------------------------------------

  test('the categories come from the RESPONSE, not from the ratified seed', () {
    // A stored answer that contradicts the seed on every code.
    final harness = _Harness(
      notifications: const <String, bool>{
        'daily_checkin': false,
        'phase_shift': false,
        'period_prediction': true,
        'medication_reminders': true,
      },
    );

    expect(_enabled(harness.form), <String>[
      'period_prediction',
      'medication_reminders',
    ]);

    // The positive control: the seed this build holds is the OPPOSITE pair, so
    // a form that drew the seed could not have produced the row above.
    expect(NotificationOption.dailyCheckin.defaultEnabled, isTrue);
    expect(NotificationOption.periodPrediction.defaultEnabled, isFalse);
  });

  test('with no list on the wire it falls back to the ON/ON/OFF/OFF seed', () {
    // Null is "the wire carried no list" — a truncated body, or the P3b-era
    // cache, which predates this member entirely. It is the one case the
    // ratified table is a source of truth for, and the fallback is the same
    // per-code seed `ReadNotificationPrefsAsync` applies
    // (`OnboardingStepsService.cs:640-655`).
    final harness = _Harness();

    // The whole list, as values: the four codes in the frozen order, each with
    // its own seed flag. An equality over `NotificationChoice` rather than two
    // projections, so a row that arrived with the right code and the wrong flag
    // cannot slip between them.
    expect(harness.form.categories, const <NotificationChoice>[
      NotificationChoice(code: 'daily_checkin', enabled: true),
      NotificationChoice(code: 'phase_shift', enabled: true),
      NotificationChoice(code: 'period_prediction', enabled: false),
      NotificationChoice(code: 'medication_reminders', enabled: false),
    ]);
    expect(_enabled(harness.form), <String>['daily_checkin', 'phase_shift']);

    // The control that makes the row above discriminating: the seed VARIES by
    // code on this step, unlike screen 6's, so "all on" and "all off" are both
    // wrong answers and neither could pass it.
    expect(
      NotificationOption.values.map((o) => o.defaultEnabled).toList(),
      <bool>[true, true, false, false],
    );
  });

  test('an EMPTY list on the wire is not the same input as no list', () {
    // `[]` off this endpoint is a form with NO rows — a screen that draws
    // nothing — while null is the seed. The two must not collapse.
    final harness = _Harness(notifications: const <String, bool>{});

    expect(harness.form.categories, isEmpty);
    // The control: the same harness with a null list is four rows.
    expect(_Harness().form.categories, hasLength(4));
  });

  test('a row whose flag is NULL falls back to the per-code seed', () {
    // The server declares `enabled` non-nullable and always sends it, but every
    // generated property is `T?` (§C.0.2), so a null here is a TRUNCATED body
    // rather than an answer — and the honest reading of a truncated body is the
    // same seed an unanswered step gets.
    final harness = _Harness(notifications: <String, bool>{});
    // Built by hand: the fixture cannot express a null flag, and this is the
    // shape the assertion is about.
    final NotificationsForm form =
        NotificationsForm.fromWire(<NotificationCategorySelection>[
          NotificationCategorySelection((b) => b..code = 'daily_checkin'),
          NotificationCategorySelection((b) => b..code = 'period_prediction'),
          NotificationCategorySelection((b) => b..code = 'weekly_digest'),
          NotificationCategorySelection((b) => b..enabled = true),
        ]);

    expect(form.categories, const <NotificationChoice>[
      // Known codes take their own seed — which DIFFERS between these two, so
      // neither `true` nor `false` alone could satisfy the pair.
      NotificationChoice(code: 'daily_checkin', enabled: true),
      NotificationChoice(code: 'period_prediction', enabled: false),
      // A code this build has never seen has no seed to apply. `false` is the
      // safe direction: it silences a notification this build could not have
      // described rather than sending one the user never agreed to.
      NotificationChoice(code: 'weekly_digest', enabled: false),
      // …and the row naming NOTHING is dropped: it can be neither drawn nor
      // sent. Its absence is why this list has three entries and the input had
      // four.
    ]);

    // The control: the harness above proves an EMPTY wire list is a form with
    // no rows, so the three rows here came from the input rather than from a
    // fallback that ignores it.
    expect(harness.form.categories, isEmpty);
  });

  test('the order is the RESPONSE\'s order, not a client-side one', () {
    const scrambled = <String, bool>{
      'medication_reminders': true,
      'daily_checkin': false,
      'period_prediction': true,
      'phase_shift': false,
    };
    final harness = _Harness(notifications: scrambled);

    expect(
      harness.form.categories.map((c) => c.code).toList(),
      scrambled.keys.toList(),
    );
    // Positive control: that order is NOT the frozen one, so the row above
    // cannot pass for a form that ignored the wire.
    expect(
      scrambled.keys.toList(),
      isNot(NotificationOption.values.map((o) => o.wireName).toList()),
    );
  });

  test('a code this build has no copy for is CARRIED, never dropped', () async {
    // The vocabulary is append-only on the server. There is no label and no
    // sub-copy for a code this build has never seen — inventing one from the
    // wire code would be authoring copy — but on a FULL REPLACE endpoint,
    // dropping it from the array stores the user's answer as a deselection.
    final harness = _Harness(
      notifications: const <String, bool>{
        'daily_checkin': true,
        'weekly_digest': true,
        'phase_shift': false,
      },
    )..answerSave();

    expect(
      harness.form.categories.map((c) => c.code),
      contains('weekly_digest'),
    );
    expect(
      harness.form.drawable.map((c) => c.code),
      isNot(contains('weekly_digest')),
    );
    // The control: a code this build DOES know is drawable, so the absence
    // above is about the unknown one rather than about an empty list.
    expect(harness.form.drawable.map((c) => c.code), contains('daily_checkin'));

    await harness.controller.allowAndFinish();

    expect(harness.posted.codes, <String>['daily_checkin', 'weekly_digest']);
  });

  // -------------------------------------------------------------------------
  // Answering
  // -------------------------------------------------------------------------

  test('toggling flips exactly one code and leaves the rest standing', () {
    final harness = _Harness();

    // Premise: the state before the toggle, so what changes is the toggle's
    // doing.
    expect(_enabled(harness.form), <String>['daily_checkin', 'phase_shift']);

    harness.controller.toggle('period_prediction');
    expect(_enabled(harness.form), <String>[
      'daily_checkin',
      'phase_shift',
      'period_prediction',
    ]);

    harness.controller.toggle('daily_checkin');
    expect(_enabled(harness.form), <String>[
      'phase_shift',
      'period_prediction',
    ]);

    // It flips back — a toggle that only ever turned things on would satisfy
    // the first row.
    harness.controller.toggle('period_prediction');
    expect(_enabled(harness.form), <String>['phase_shift']);
  });

  // -------------------------------------------------------------------------
  // "Allow & finish" — save, THEN complete
  // -------------------------------------------------------------------------

  test('Allow & finish posts the COMPLETE enabled set, never a diff', () async {
    final harness = _Harness(
      notifications: const <String, bool>{
        'daily_checkin': true,
        'phase_shift': true,
        'period_prediction': false,
        'medication_reminders': false,
      },
    )..answerSave();

    harness.controller.toggle('period_prediction'); // off -> on
    harness.controller.toggle('daily_checkin'); // on  -> off

    await harness.controller.allowAndFinish();

    // The whole test is the first element. `phase_shift` was not touched on
    // this visit — a controller that sent the diff would post
    // `['period_prediction']`, and the server's FULL REPLACE would then store
    // `phase_shift` as DESELECTED. That is the silent discard.
    final List<String> posted = harness.posted.codes;
    expect(posted, <String>['phase_shift', 'period_prediction']);
    // ...and the deselected code is absent rather than sent as `false`: on this
    // wire shape, absence IS the deselection.
    expect(posted, isNot(contains('daily_checkin')));
  });

  test('an untouched screen still posts the whole set', () async {
    final harness = _Harness()..answerSave();

    await harness.controller.allowAndFinish();

    expect(harness.posted.codes, <String>['daily_checkin', 'phase_shift']);
  });

  test('the array carries WIRE CODES, never the display labels', () async {
    final harness = _Harness()..answerSave();

    await harness.controller.allowAndFinish();

    final List<String> posted = harness.posted.codes;
    expect(posted, contains('phase_shift'));
    expect(posted, isNot(contains('Phase shift')));
    // The positive control: the code and the label really are different
    // strings, so the pair above discriminates. `phase_shift` is SINGULAR —
    // screen 7's plural "Phase shifts" is display drift and
    // `HormoneCatalog.NotificationCategories` is the authority
    // (`HormoneCatalog.cs:85-108`).
    expect(NotificationOption.phaseShift.label, 'Phase shift');
    expect(NotificationOption.phaseShift.label, isNot('phase_shift'));
    expect(NotificationOption.phaseShift.label, isNot('Phase shifts'));
  });

  test('it saves and THEN completes, in that order', () async {
    final harness = _Harness()..answerSave();

    await harness.controller.allowAndFinish();

    verifyInOrder(<void Function()>[
      () => harness.repo.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
      harness.repo.complete,
    ]);
  });

  test('the empty answer is a POST, not a skip', () async {
    // Muting everything is a real answer this endpoint stores — the server keys
    // `value is required` on a NULL and on nothing else
    // (`OnboardingStepsService.cs:515-517`). It is the POSITIVE CONTROL for the
    // "Not now" test below: an empty preference set IS reachable, it IS
    // different from skipping, and only a `verifyNever` on the save tells the
    // two apart.
    final harness = _Harness()
      ..answerSave(
        notificationPrefsResponseFixture(const <String, bool>{
          'daily_checkin': false,
          'phase_shift': false,
          'period_prediction': false,
          'medication_reminders': false,
        }),
      );

    harness.controller.toggle('daily_checkin');
    harness.controller.toggle('phase_shift');
    expect(_enabled(harness.form), isEmpty);

    await harness.controller.allowAndFinish();

    expect(harness.posted.codes, isEmpty);
    verify(harness.repo.complete).called(1);
  });

  // -------------------------------------------------------------------------
  // "Not now" — D-02's skip: NO preference row at all
  // -------------------------------------------------------------------------

  test('Not now completes and writes NO preference row', () async {
    final harness = _Harness()..answerSave();

    await harness.controller.notNow();

    // The whole of D-02's "skip" on this step. NOT an empty post: an empty post
    // stores four rows with every flag false and then SUPPRESSES the
    // completion backfill, whose guard is
    // `if (!await db.UserNotificationPrefs.AnyAsync(...))`
    // (`OnboardingStepsService.cs:1091`). The user who declined would be
    // silenced instead of getting the ON / ON / OFF / OFF seed.
    harness.verifyNoSave();
    verify(harness.repo.complete).called(1);

    // The control that makes `verifyNoSave` mean something: the save IS stubbed
    // and the SAME harness does post when the other CTA is used. Without this,
    // "no save" would also be true of a repository nobody had wired.
    await harness.controller.allowAndFinish();
    expect(harness.posted.codes, <String>['daily_checkin', 'phase_shift']);
  });

  test('Not now does not consult the push token source either', () async {
    // Skipping means not calling the step endpoint at all, so there is nothing
    // for a token to travel on. Asking for one would also be the moment a real
    // P9a source raised the OS permission prompt — on the CTA whose entire
    // meaning is "not now".
    final source = _Source(
      const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
    );
    final harness = _Harness(source: source)..answerSave();

    await harness.controller.notNow();

    expect(source.reads, 0);
    // The control: the other CTA does ask, so zero is a fact about "Not now"
    // rather than about a seam nobody wired.
    await harness.controller.allowAndFinish();
    expect(source.reads, 1);
  });

  // -------------------------------------------------------------------------
  // The push pair (R-09)
  // -------------------------------------------------------------------------

  test('with no token nothing about a device reaches the request', () async {
    // P4b's shipped `PushTokenSource` answers null, so this is the path screen
    // 7 actually takes today: the categories-only request, whose
    // `deviceRegistered: false` is a documented normal outcome.
    final source = _Source();
    final harness = _Harness(source: source)..answerSave();

    await harness.controller.allowAndFinish();

    final sent = harness.posted;
    expect(sent.pushToken, isNull);
    expect(sent.platform, isNull);
    // The control: the source WAS consulted, so the nulls above are its answer
    // rather than a code path that skipped it.
    expect(source.reads, 1);
  });

  test('a token travels WHOLE, as a pair', () async {
    final harness = _Harness(
      source: _Source(
        const PushToken(token: 'apns-xyz', platform: PushPlatform.ios),
      ),
    )..answerSave();

    await harness.controller.allowAndFinish();

    final sent = harness.posted;
    expect(sent.pushToken, 'apns-xyz');
    expect(sent.platform, 'ios');
  });

  test('a BLANK half is dropped, and does not cost the user their answer', () async {
    // FCM's `getToken()` can answer an empty string while a `deleteToken()` is
    // in flight, so this is a shape a real P9a source hands over rather than a
    // theoretical one.
    //
    // Unnormalised it is strictly WORSE than a source that throws: the blank
    // token reaches the repository, the server's own blank-is-absent rule makes
    // it HALF a pair, the all-or-nothing guard throws an ArgumentError, and
    // `allowAndFinish`'s `catch (_)` renders it as an UnknownFailure banner —
    // so four preference rows go unsaved and onboarding never completes, over a
    // messaging fault with nothing to do with the categories.
    final harness = _Harness(
      source: _Source(
        const PushToken(token: '  ', platform: PushPlatform.android),
      ),
    )..answerSave();

    await harness.controller.allowAndFinish();

    // The headline consequence FIRST, and deliberately so: unnormalised, this
    // is where the user lands — a banner, no rows saved, onboarding unfinished.
    // Asserting it before the request shape also keeps the failure a MATCHER
    // failure (`Expected: null`), where reading `harness.posted` first would
    // fail inside mocktail's `verify` with "no matching calls", which names no
    // expectation and so cannot positively identify a mutation kill.
    expect(harness.form.failure, isNull);
    expect(harness.form.submitting, isFalse);

    final sent = harness.posted;
    // The categories travelled...
    expect(sent.codes, <String>['daily_checkin', 'phase_shift']);
    // ...and the unusable pair did not, on either half.
    expect(sent.pushToken, isNull);
    expect(sent.platform, isNull);
    // ...and the flow FINISHED, which is the whole point.
    verify(harness.repo.complete).called(1);
  });

  test('a blank platform is dropped too, and the pair still travels whole '
      'when both halves are real', () async {
    // The other half of the same rule, plus the positive control the pair of
    // tests rests on: a source of the SAME shape whose halves are non-blank
    // DOES send both, so the nulls above are about the blank and not about a
    // seam that never travels.
    final blank = _Harness(
      source: _Source(const PushToken(token: 'fcm-abc', platform: '')),
    )..answerSave();
    await blank.controller.allowAndFinish();
    final dropped = blank.posted;
    expect(dropped.pushToken, isNull);
    expect(dropped.platform, isNull);
    expect(dropped.codes, <String>['daily_checkin', 'phase_shift']);

    final usable = _Harness(
      source: _Source(
        const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
      ),
    )..answerSave();
    await usable.controller.allowAndFinish();
    final ok = usable.posted;
    expect(ok.pushToken, 'fcm-abc');
    expect(ok.platform, 'android');
  });

  test(
    'a token source that throws does not cost the user their answer',
    () async {
      // P9a's source talks to FCM/APNs and can throw. The categories are what the
      // step is FOR, and D-19's scheduler reads them; losing them because a
      // messaging SDK failed would be the tail wagging the dog.
      final harness = _Harness(source: _ThrowingSource())..answerSave();

      await harness.controller.allowAndFinish();

      final sent = harness.posted;
      expect(sent.codes, <String>['daily_checkin', 'phase_shift']);
      expect(sent.pushToken, isNull);
      expect(sent.platform, isNull);
      verify(harness.repo.complete).called(1);
    },
  );

  // -------------------------------------------------------------------------
  // Failure
  // -------------------------------------------------------------------------

  test('a rejected save does NOT complete the flow', () async {
    final harness = _Harness()..rejectSave(const NetworkFailure());

    await harness.controller.allowAndFinish();

    // Premise + assertion: the failure is held, and the second request never
    // went out. Completing after a failed save would stamp
    // `onboarding_completed_at` and materialise the SEED, quietly discarding
    // the answer the user was told had failed.
    expect(harness.form.failure, isA<NetworkFailure>());
    verifyNever(harness.repo.complete);
    // ...and the CTA is live again.
    expect(harness.form.submitting, isFalse);
  });

  test('a rejection does not survive the next attempt', () async {
    final harness = _Harness()..rejectSave(const NetworkFailure());

    await harness.controller.allowAndFinish();
    expect(harness.form.failure, isNotNull);

    harness.answerSave();
    await harness.controller.allowAndFinish();

    expect(harness.form.failure, isNull);
    verify(harness.repo.complete).called(1);
  });

  test('answering again drops what the last attempt said', () async {
    final harness = _Harness()..rejectSave(const NetworkFailure());

    await harness.controller.allowAndFinish();
    expect(harness.form.failure, isNotNull);

    harness.controller.toggle('period_prediction');

    expect(harness.form.failure, isNull);
  });

  test('an unclassifiable error still settles the button', () async {
    // `cachedWrite` invalidates its keys UNGUARDED after a successful write, so
    // a concurrent logout purge closing the Hive box throws here — AFTER the
    // rows landed. Left unhandled it would be a spinner that never stops and a
    // banner that never appears. It is also the stored-but-reported-failure
    // arm (T8b invariant 2): the rows may be on the server while the flow keeps
    // the pre-save list.
    final harness = _Harness();
    when(
      () => harness.repo.saveNotifications(
        codes: any(named: 'codes'),
        pushToken: any(named: 'pushToken'),
        platform: any(named: 'platform'),
      ),
    ).thenAnswer((_) async => throw StateError('box closed'));

    await harness.controller.allowAndFinish();

    expect(harness.form.failure, isA<UnknownFailure>());
    expect(harness.form.submitting, isFalse);
    verifyNever(harness.repo.complete);
  });

  test(
    'a second press while one is in flight issues no second request',
    () async {
      final harness = _Harness();
      final gate = harness.holdSave();

      final Future<void> first = harness.controller.allowAndFinish();
      expect(harness.form.submitting, isTrue);

      await harness.controller.allowAndFinish();
      await harness.controller.notNow();

      gate.complete(notificationPrefsResponseFixture());
      await first;

      verify(
        () => harness.repo.saveNotifications(
          codes: any(named: 'codes'),
          pushToken: any(named: 'pushToken'),
          platform: any(named: 'platform'),
        ),
      ).called(1);
      verify(harness.repo.complete).called(1);
    },
  );

  test(
    'a toggle in flight is refused, because the response would discard it',
    () async {
      final harness = _Harness();
      final gate = harness.holdSave();

      final Future<void> pending = harness.controller.allowAndFinish();
      // Premise: the request is genuinely open.
      expect(harness.form.submitting, isTrue);

      harness.controller.toggle('period_prediction');
      expect(_enabled(harness.form), <String>['daily_checkin', 'phase_shift']);

      gate.complete(notificationPrefsResponseFixture());
      await pending;

      // The control: with the request settled, the same toggle IS accepted.
      harness.controller.toggle('period_prediction');
      expect(_enabled(harness.form), <String>[
        'daily_checkin',
        'phase_shift',
        'period_prediction',
      ]);
    },
  );

  // -------------------------------------------------------------------------
  // T8b's invariants
  // -------------------------------------------------------------------------

  test('a successful save refreshes the FLOW, so a rebuilt controller seeds '
      'from what the server stored', () async {
    final harness = _Harness()
      ..answerSave(
        notificationPrefsResponseFixture(const <String, bool>{
          'daily_checkin': false,
          'phase_shift': false,
          'period_prediction': true,
          'medication_reminders': false,
        }),
      );

    // Premise: the flow's copy of `GET /onboarding/state` is the PRE-save one.
    expect(harness.flow.state.notifications, isNull);

    await harness.controller.allowAndFinish();

    final BuiltList<NotificationCategorySelection>? recorded =
        harness.flow.state.notifications;
    expect(recorded, isNotNull);
    expect(
      <String, bool>{for (final c in recorded!) c.code!: c.enabled!},
      <String, bool>{
        'daily_checkin': false,
        'phase_shift': false,
        'period_prediction': true,
        'medication_reminders': false,
      },
    );
    // ...and nothing else on the flow moved. `notificationsProvided` is the
    // RESUME read's answer, never the current one (T8b invariant 1).
    expect(harness.flow.state.notificationsProvided, isFalse);
  });

  test('a TRUNCATED 200 does not repaint the answer with the seed', () async {
    // The write succeeded and the body is malformed — a contract violation, and
    // a different fact from "this user has never answered". Only the second
    // wants the seed, so `fromWire(null)`'s fallback must not be reachable from
    // the write path: what the server holds is what this screen just posted.
    //
    // Left unseparated, the user's just-muted rows repaint ON / ON / OFF / OFF
    // and the flow RECORDS that, so the next full replace writes a set they
    // never chose.
    final harness = _Harness()
      ..answerSave(
        NotificationPrefsResponse((b) => b..deviceRegistered = false),
      );

    harness.controller.toggle('daily_checkin');
    harness.controller.toggle('phase_shift');
    // Premise: the answer being posted is the empty one, and it is the OPPOSITE
    // of the seed on the two codes the seed turns on.
    expect(_enabled(harness.form), isEmpty);

    await harness.controller.allowAndFinish();

    // The form still shows the user's answer...
    expect(harness.form.categories, const <NotificationChoice>[
      NotificationChoice(code: 'daily_checkin', enabled: false),
      NotificationChoice(code: 'phase_shift', enabled: false),
      NotificationChoice(code: 'period_prediction', enabled: false),
      NotificationChoice(code: 'medication_reminders', enabled: false),
    ]);

    // ...and so does the FLOW, so a rebuilt controller seeds from it rather
    // than from the seed. Recording `null` here would have been the same
    // repaint, one navigation later.
    final BuiltList<NotificationCategorySelection>? recorded =
        harness.flow.state.notifications;
    expect(recorded, isNotNull);
    expect(
      <String, bool>{for (final c in recorded!) c.code!: c.enabled!},
      <String, bool>{
        'daily_checkin': false,
        'phase_shift': false,
        'period_prediction': false,
        'medication_reminders': false,
      },
    );

    // The positive control that makes every row above discriminating: the seed
    // this build would have fallen back to really does differ, on exactly the
    // two codes the test muted. Without it a form that HAD repainted could
    // satisfy the shape of these assertions.
    expect(NotificationsForm.fromWire(null).enabledCodes, <String>[
      'daily_checkin',
      'phase_shift',
    ]);
  });

  test('a save that lands after the FLOW is gone records nothing and throws '
      'nothing', () async {
    // The shell's back affordance is not gated on `submitting`, so Back
    // mid-save is an ordinary gesture; the flow reference is therefore read
    // BEFORE the await and the record is taken BEFORE this controller's own
    // mounted gate. What this test adds is the other end: when the FLOW itself
    // is gone, `_recordSaved` returns rather than throwing on `state =`.
    final harness = _Harness();
    final gate = harness.holdSave();

    final Future<void> pending = harness.controller.allowAndFinish();
    harness.container.dispose();

    gate.complete(notificationPrefsResponseFixture());
    await expectLater(pending, completes);
  });
}

class _ThrowingSource implements PushTokenSource {
  @override
  Future<PushToken?> read() async => throw StateError('no messaging service');
}
