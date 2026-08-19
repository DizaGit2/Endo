// Semantics + behaviour for screen 7 (P4b-T13).
//
// Five things on this screen are correctness rather than polish:
//
//   * the list it draws is the SERVER's. `POST /onboarding/notifications` and
//     `GET /onboarding/state` both answer the complete vocabulary in frozen
//     order with a boolean per code, and the screen renders that — so the
//     fixtures below hand it a list that contradicts the seed on every code, in
//     an order the client would not have produced, and assert it followed the
//     wire;
//   * "Allow & finish" writes a FULL REPLACE. A code left out of the array is
//     stored as DESELECTED (`OnboardingStepsService.cs:556-573`), so an
//     untouched-but-enabled category has to travel or the user's earlier answer
//     is discarded;
//   * "Not now" is a DIFFERENT REQUEST SEQUENCE, not the same one with an empty
//     array. D-02's skip means not calling the step endpoint at all, and the
//     empty post is asserted in the same file as its positive control;
//   * `phase_shift` is SINGULAR. The mockup draws "Phase shifts";
//     `HormoneCatalog.NotificationCategories` says the canonical label is
//     "Phase shift" and calls the plural the drift (`HormoneCatalog.cs:97-108`),
//     so the plural must not be on screen;
//   * quiet hours and the DAILY / CYCLE EVENTS grouping belong to settings
//     screen 34 and must not appear here.
//
// One element of the row needs a test rather than a golden: the PILL TOGGLE's
// OFF appearance. The goldens pin the seed's ON/ON/OFF/OFF form, but every
// other assertion about "is this on" reads the ROW's semantics, so both of the
// pill's conditional lines could be hard-coded and the screen would ship a row
// whose fill says OFF beside a pill that says ON.
//
// Controls are located by KEY or TYPE throughout, never by what they announce
// (the T5c rule): `find.bySemanticsLabel` appears only inside assertions ABOUT
// what is announced, so a semantics change elsewhere cannot redden a test by
// failing inside `tester.tap`.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/notification_prefs_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/notifications_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/notifications_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 7 carrying [notifications] as its resume
/// read. `complete()` is the REAL one.
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

class _Harness {
  _Harness({Map<String, bool>? notifications}) {
    overrides = <Override>[
      ...lumenOverrides(),
      onboardingFlowControllerProvider.overrideWith(
        () => _SettledFlow(notifications),
      ),
      onboardingRepositoryProvider.overrideWithValue(repo),
    ];
    when(repo.complete).thenAnswer((_) async => onboardingCompleteFixture());
  }

  final _MockOnboardingRepository repo = _MockOnboardingRepository();
  late final List<Override> overrides;

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

  void rejectComplete(Failure failure) {
    when(repo.complete).thenAnswer((_) async => throw failure);
  }

  /// Holds `POST /onboarding/complete` open so the skip's own in-flight surface
  /// can be asserted on.
  Completer<OnboardingCompleteResponse> holdComplete() {
    final completer = Completer<OnboardingCompleteResponse>();
    when(repo.complete).thenAnswer((_) => completer.future);
    return completer;
  }

  /// Holds the save open so the in-flight surface can be asserted on.
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

  /// The array the repository was handed. Captured ONCE per call — `verify`
  /// consumes the recorded invocation.
  List<String> get postedCodes =>
      verify(
            () => repo.saveNotifications(
              codes: captureAny(named: 'codes'),
              pushToken: any(named: 'pushToken'),
              platform: any(named: 'platform'),
            ),
          ).captured.last
          as List<String>;

  void verifyNoSave() => verifyNever(
    () => repo.saveNotifications(
      codes: any(named: 'codes'),
      pushToken: any(named: 'pushToken'),
      platform: any(named: 'platform'),
    ),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool settle = true,
    Brightness brightness = Brightness.light,
  }) async {
    final container = await pumpApp(
      tester,
      home: onboardingStepHost(const NotificationsScreen()),
      overrides: overrides,
      brightness: brightness,
      settle: settle,
    );
    // The flow is autoDispose and the SHELL is what watches it in the app; this
    // file mounts the step body alone, so without a subscription the
    // `ref.read(...notifier)` inside the completion would build it, use it and
    // watch it disposed in the same turn.
    container.listen(onboardingFlowControllerProvider, (_, _) {});
    return container;
  }
}

/// One category row, by its stable handle.
Finder _row(String code) => find.byKey(notificationRowKey(code));

/// One category's pill toggle, by its stable handle.
Finder _pill(String code) => find.byKey(notificationTogglePillKey(code));

Finder get _allow => find.byKey(kNotificationsAllowKey);
Finder get _skip => find.byKey(kNotificationsSkipKey);

/// The pill's drawn fill.
Color _pillColor(WidgetTester tester, String code) {
  final Container box = tester.widget<Container>(_pill(code));
  return (box.decoration! as BoxDecoration).color!;
}

/// Which end of the pill its knob sits at.
AlignmentGeometry _pillKnob(WidgetTester tester, String code) => tester
    .widget<Align>(
      find.descendant(of: _pill(code), matching: find.byType(Align)),
    )
    .alignment;

/// The token set the real app theme resolves for [brightness].
LumenColors _tokens(Brightness brightness) =>
    lumenTheme(brightness).extension<LumenColors>()!;

/// Whether the node at [finder] announces itself as selected.
bool _isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

/// Every string this screen renders, top to bottom-ish.
List<String> _allText(WidgetTester tester) => <String>[
  for (final Text text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data case final String data) data,
];

/// The codes whose rows are drawn, top to bottom.
List<String> _drawnOrder(WidgetTester tester, List<String> candidates) {
  final drawn = <String>[
    for (final String code in candidates)
      if (_row(code).evaluate().isNotEmpty) code,
  ];
  drawn.sort(
    (String a, String b) =>
        tester.getTopLeft(_row(a)).dy.compareTo(tester.getTopLeft(_row(b)).dy),
  );
  return drawn;
}

void main() {
  setUpAll(() => registerFallbackValue(const <String>['daily_checkin']));

  // -------------------------------------------------------------------------
  // What it says
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('it renders the mockup\'s copy and no dingbats', (
    tester,
  ) async {
    await _Harness().pump(tester);

    expect(find.text('Stay in tune'), findsOneWidget);
    expect(find.text('Soft nudges only. Mute anytime.'), findsOneWidget);
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('Log symptoms each evening'), findsOneWidget);
    expect(find.text('Phase shift'), findsOneWidget);
    expect(find.text('When you enter a new phase'), findsOneWidget);
    expect(find.text('Period prediction'), findsOneWidget);
    expect(find.text('Two days before your period'), findsOneWidget);
    expect(find.text('Medication reminders'), findsOneWidget);
    expect(find.text('Once you log a treatment'), findsOneWidget);
    expect(find.text('Allow & finish'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    // The mockup draws `‹`, `☾` and the `◐` inside its `.bell` circle. The
    // first two belong to the shell's chrome or the mockup's theme toggle; the
    // third is decoration and ships as an `Icon` (the P3c rule). Since
    // P4b-T5d this matcher fails on ANY codepoint above U+007F that is not
    // allowlisted, so it covers glyphs nobody has thought of.
    expectNoDingbats(tester, screen: 'Screen 7');
  });

  testWidgetsWithSemantics('the plural "Phase shifts" is not on screen', (
    tester,
  ) async {
    await _Harness().pump(tester);

    // The one place this screen departs from its own mockup, and it is not a
    // judgement call: `HormoneCatalog.NotificationCategories.Labels` says
    // `phase_shift` is "Phase shift", singular, and names screen 7's plural as
    // the drift (`HormoneCatalog.cs:85-108`; B16; `definitions.md:740`).
    expect(find.text('Phase shifts'), findsNothing);
    // The control: the singular IS drawn, so the absence above is about the
    // plural rather than about a row that never rendered.
    expect(find.text('Phase shift'), findsOneWidget);
  });

  testWidgetsWithSemantics('it renders EXACTLY the sourced copy and nothing '
      'else', (tester) async {
    await _Harness().pump(tester);

    // An exact set, not a series of containments. R-10 ships these preferences
    // knowing P4b dispatches no notification at all, deliberately and without
    // an explanatory note — so the risk this screen carries is INVENTED copy
    // about when notifications will start ("coming soon", "not yet active"),
    // and only an exhaustive assertion can see a sentence nobody predicted.
    //
    // Every string below is the mockup's or `definitions.md`'s
    // (`Screens/screen_07_notifications.html`, `definitions.md:110-114,739-742`)
    // except the four category labels, which are the backend catalogue's.
    expect(
      _allText(tester)..sort(),
      <String>[
        'Allow & finish',
        'Daily check-in',
        'Log symptoms each evening',
        'Medication reminders',
        'Not now',
        'Once you log a treatment',
        'Period prediction',
        'Phase shift',
        'Soft nudges only. Mute anytime.',
        'Stay in tune',
        'Two days before your period',
        'When you enter a new phase',
      ]..sort(),
    );
  });

  testWidgetsWithSemantics('screen 34\'s quiet hours and grouping are not on '
      'this screen', (tester) async {
    await _Harness().pump(tester);

    // `definitions.md:757`: grouping is "part of settings layout, not a
    // property of the category", and the quiet-hours window row is not a toggle
    // category at all. Neither belongs to onboarding, which is a single
    // ungrouped list.
    for (final String absent in const <String>[
      'Quiet',
      'DAILY',
      'CYCLE EVENTS',
      '8:00 PM',
      '2 days before',
      '2 active',
    ]) {
      expect(find.textContaining(absent), findsNothing);
    }
    // The control: the parts that DO belong are drawn, so the absences above
    // are about screen 34's material rather than about a screen that rendered
    // nothing.
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('Two days before your period'), findsOneWidget);
  });

  testWidgetsWithSemantics('the heading is a header', (tester) async {
    await _Harness().pump(tester);

    expect(
      tester
          .getSemantics(find.text('Stay in tune'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    // The control: the subtitle beside it is ordinary prose, not a second
    // landmark for a screen reader to stop on.
    expect(
      tester
          .getSemantics(find.text('Soft nudges only. Mute anytime.'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isFalse,
    );
  });

  // -------------------------------------------------------------------------
  // The list is the server's
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('what is drawn as enabled comes from the RESPONSE, '
      'not from the seed', (tester) async {
    // A stored answer that contradicts the seed on every code.
    await _Harness(
      notifications: const <String, bool>{
        'daily_checkin': false,
        'phase_shift': false,
        'period_prediction': true,
        'medication_reminders': true,
      },
    ).pump(tester);

    expect(_isSelected(tester, _row('period_prediction')), isTrue);
    expect(_isSelected(tester, _row('medication_reminders')), isTrue);

    // The positive control: the seed this build holds is the OPPOSITE pair, so
    // a screen that drew the seed would have every one of these the other way
    // round.
    expect(NotificationOption.dailyCheckin.defaultEnabled, isTrue);
    expect(NotificationOption.periodPrediction.defaultEnabled, isFalse);
    expect(_isSelected(tester, _row('daily_checkin')), isFalse);
    expect(_isSelected(tester, _row('phase_shift')), isFalse);
  });

  testWidgetsWithSemantics('the rows are drawn in the RESPONSE\'s order', (
    tester,
  ) async {
    // Deliberately not the frozen order: the point is to prove the screen
    // renders the order it was sent rather than one it holds itself.
    const scrambled = <String, bool>{
      'medication_reminders': true,
      'daily_checkin': false,
      'period_prediction': true,
      'phase_shift': false,
    };
    await _Harness(notifications: scrambled).pump(tester);

    expect(
      _drawnOrder(tester, scrambled.keys.toList()),
      scrambled.keys.toList(),
    );
    // Positive control: that order is NOT the client's own, so the row above
    // cannot pass for a screen that ignored the wire.
    expect(
      scrambled.keys.toList(),
      isNot(
        NotificationOption.values
            .map((NotificationOption o) => o.wireName)
            .toList(),
      ),
    );
  });

  testWidgetsWithSemantics('a code with no copy is not drawn, and is still '
      'carried into the write', (tester) async {
    // The vocabulary is append-only on the server. There is no label and no
    // sub-copy for a code this build has never seen, and inventing one from the
    // wire code would be authoring copy — but on a FULL REPLACE endpoint,
    // dropping it from the array stores the user's answer as a deselection.
    final harness = _Harness(
      notifications: const <String, bool>{
        'daily_checkin': true,
        'weekly_digest': true,
        'phase_shift': false,
      },
    )..answerSave();
    await harness.pump(tester);

    expect(_row('weekly_digest'), findsNothing);
    expect(find.textContaining('weekly_digest'), findsNothing);
    // The control: a code this build DOES know is drawn, so the absence above
    // is a fact about the unknown one rather than about a list that never
    // rendered.
    expect(_row('daily_checkin'), findsOneWidget);

    await tester.tap(_allow);
    await tester.pumpAndSettle();

    expect(harness.postedCodes, <String>['daily_checkin', 'weekly_digest']);
  });

  // -------------------------------------------------------------------------
  // The row
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a row is an activatable toggle named by its '
      'category and its sub-copy', (tester) async {
    await _Harness().pump(tester);

    // Premise: the state before the tap, so what changes below is the tap's
    // doing. The seed is ON / ON / OFF / OFF.
    expect(_isSelected(tester, _row('daily_checkin')), isTrue);
    expect(_isSelected(tester, _row('period_prediction')), isFalse);

    await tester.tap(_row('daily_checkin'));
    await tester.pump();

    expect(_isSelected(tester, _row('daily_checkin')), isFalse);
    // …and its neighbour is untouched: this is a multi-select, not a radio
    // group.
    expect(_isSelected(tester, _row('phase_shift')), isTrue);

    expectLabeledButton(tester, _row('daily_checkin'), 'Daily check-in');

    // It flips back — a toggle that only ever turned things off would satisfy
    // every row above.
    await tester.tap(_row('daily_checkin'));
    await tester.pump();
    expect(_isSelected(tester, _row('daily_checkin')), isTrue);
  });

  testWidgetsWithSemantics('the row announces its name and its sub-copy, and '
      'the toggle is silent', (tester) async {
    await _Harness().pump(tester);

    // An equality, not two containments: the row is a `MergeSemantics`, so its
    // announced name IS the rendered copy joined by the framework's own line
    // break. A containment pair would not notice the pill toggle starting to
    // announce itself, and it has nothing to say — it draws the selected state,
    // which is already carried as `SemanticsFlag.isSelected`.
    expect(
      tester.getSemantics(_row('daily_checkin')).getSemanticsData().label,
      'Daily check-in\nLog symptoms each evening',
    );
    expect(
      tester.getSemantics(_row('phase_shift')).getSemanticsData().label,
      'Phase shift\nWhen you enter a new phase',
    );
  });

  testWidgetsWithSemantics('the pill toggle draws ON and OFF differently', (
    tester,
  ) async {
    // The goldens pin the seed's form and every other "is this enabled"
    // assertion reads the ROW's semantics, so the pill's two conditional lines
    // are the one appearance on this row that nothing else covers. Hard-coding
    // either to its ON value would leave the row's own fill — which IS covered
    // — saying OFF while the pill beside it said ON.
    await _Harness().pump(tester);

    final LumenColors c = _tokens(Brightness.light);

    // ON: the mockup's `.n.on .tgl` — accent fill, knob at `left:14px`.
    expect(_pillColor(tester, 'daily_checkin'), c.accent);
    expect(_pillKnob(tester, 'daily_checkin'), Alignment.centerRight);

    // OFF: the mockup's bare `.tgl` — border fill, knob at `left:2px`.
    expect(_pillColor(tester, 'period_prediction'), c.border);
    expect(_pillKnob(tester, 'period_prediction'), Alignment.centerLeft);

    // The controls. Both states are read from ONE mount of ONE screen, so no
    // single hard-coded value can satisfy both halves — and these two say the
    // pair really is a pair rather than one value written twice.
    expect(c.accent, isNot(c.border));
    expect(Alignment.centerRight, isNot(Alignment.centerLeft));

    // …and the pill agrees with the row it sits in. That agreement is the thing
    // this test exists to keep true: the row's state is announced, the pill's is
    // only drawn, and a screen reader and a sighted user must not be told
    // opposite things.
    expect(_isSelected(tester, _row('daily_checkin')), isTrue);
    expect(_isSelected(tester, _row('period_prediction')), isFalse);
  });

  // -------------------------------------------------------------------------
  // "Allow & finish" — FULL REPLACE, then complete
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('Allow & finish posts the COMPLETE enabled set, '
      'then completes', (tester) async {
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    await tester.tap(_row('period_prediction')); // off -> on
    await tester.pump();
    await tester.tap(_row('daily_checkin')); // on  -> off
    await tester.pump();

    await tester.tap(_allow);
    await tester.pumpAndSettle();

    final List<String> posted = harness.postedCodes;
    // The whole test is the first element. `phase_shift` was not touched on
    // this visit — a screen that sent the diff would post
    // `['period_prediction']`, and the server's FULL REPLACE would then store
    // `phase_shift` as DESELECTED. That is the silent discard.
    expect(posted, <String>['phase_shift', 'period_prediction']);
    expect(posted, isNot(contains('daily_checkin')));

    verify(harness.repo.complete).called(1);
  });

  testWidgetsWithSemantics('with nothing enabled the CTA is still live, and it '
      'posts an empty array', (tester) async {
    // Muting everything is a real answer this endpoint stores: the server keys
    // `value is required` on a NULL and on nothing else. There is no minimum,
    // so screen 5's inert Continue is deliberately absent here — and this is the
    // POSITIVE CONTROL for the "Not now" test below, which asserts the same
    // user intention produces NO request at all.
    final harness = _Harness()
      ..answerSave(
        notificationPrefsResponseFixture(const <String, bool>{
          'daily_checkin': false,
          'phase_shift': false,
          'period_prediction': false,
          'medication_reminders': false,
        }),
      );
    await harness.pump(tester);

    await tester.tap(_row('daily_checkin'));
    await tester.tap(_row('phase_shift'));
    await tester.pump();

    // Premise: every row really is off, so what follows is about the empty
    // answer rather than about a screen that never seeded.
    for (final String code in kSeededNotifications.keys) {
      expect(_isSelected(tester, _row(code)), isFalse);
    }

    expectLabeledButton(tester, _allow, 'Allow & finish', exactLabel: true);
    expect(tester.widget<FilledButton>(_allow).onPressed, isNotNull);
    expect(find.textContaining('at least one'), findsNothing);

    await tester.tap(_allow);
    await tester.pumpAndSettle();

    expect(harness.postedCodes, isEmpty);
    expect(find.byType(LumenErrorBanner), findsNothing);
    verify(harness.repo.complete).called(1);
  });

  // -------------------------------------------------------------------------
  // "Not now" — D-02's skip
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('Not now completes and writes NO preference row', (
    tester,
  ) async {
    final harness = _Harness()..answerSave();
    final container = await harness.pump(tester);

    expectLabeledButton(tester, _skip, 'Not now', exactLabel: true);

    await tester.tap(_skip);
    await tester.pumpAndSettle();

    // The two CTAs are two request sequences. An empty post is NOT a skip: it
    // stores four rows with every flag false and then suppresses the completion
    // backfill (`OnboardingStepsService.cs:1091`), leaving a user who declined
    // silenced instead of seeded ON / ON / OFF / OFF.
    harness.verifyNoSave();
    verify(harness.repo.complete).called(1);

    // The control that makes `verifyNoSave` mean something: the save IS stubbed,
    // and the OTHER CTA on the same screen does post. Without it "no save"
    // would also be true of a repository nobody had wired.
    await tester.tap(_allow);
    await tester.pumpAndSettle();
    expect(harness.postedCodes, <String>['daily_checkin', 'phase_shift']);

    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.notifications,
    );
  });

  // -------------------------------------------------------------------------
  // The completion 409 — screen 7 is its first real consumer
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a 409 naming a missing step sends the user to '
      'that step', (tester) async {
    final harness = _Harness()
      ..answerSave()
      ..rejectComplete(
        const ConflictFailure(
          message: 'Onboarding cannot be completed yet.',
          code: 'onboarding_incomplete',
          missingSteps: <String>['cycle'],
        ),
      );
    final container = await harness.pump(tester);

    // Premise: the flow is on step 7, so the move below is the 409's doing.
    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.notifications,
    );

    await tester.tap(_allow);
    await tester.pumpAndSettle();

    // A conflict the user cannot act on is a dead button. The named step
    // becomes the step the shell shows, and the server's own message travels
    // with them — the shell renders it, which is why there is no banner on this
    // body.
    final OnboardingFlow flow = container
        .read(onboardingFlowControllerProvider)
        .value!;
    expect(flow.step, OnboardingStep.cycle);
    expect(flow.failure, isA<ConflictFailure>());
    expect(flow.failure!.message, 'Onboarding cannot be completed yet.');

    // …and the categories WERE saved before the completion was refused, so the
    // user does not lose the answer they gave on the way past.
    expect(harness.postedCodes, <String>['daily_checkin', 'phase_shift']);
  });

  testWidgetsWithSemantics('a 409 naming a step this build does not know '
      'leaves the user where they are', (tester) async {
    // `missingSteps` is append-only on the server. Sending someone to a guessed
    // screen on the strength of a code this build has never seen is worse than
    // showing them the message, so an unrecognised step degrades to "stay put,
    // and say why".
    final harness = _Harness()
      ..rejectComplete(
        const ConflictFailure(
          message: 'Onboarding cannot be completed yet.',
          code: 'onboarding_incomplete',
          missingSteps: <String>['identity_verification'],
        ),
      );
    final container = await harness.pump(tester);

    await tester.tap(_skip);
    await tester.pumpAndSettle();

    final OnboardingFlow flow = container
        .read(onboardingFlowControllerProvider)
        .value!;
    expect(flow.step, OnboardingStep.notifications);
    expect(flow.failure, isA<ConflictFailure>());
    // The control: the recognised code on the same path DOES move the user, so
    // "stayed put" is a fact about the unknown step rather than about routing
    // that never worked.
    expect(OnboardingStep.fromWireName('identity_verification'), isNull);
    expect(OnboardingStep.fromWireName('cycle'), OnboardingStep.cycle);

    // …and both CTAs are live again: a retry is safe, because a repeat
    // completion answers 200 with the original timestamp, never a second 409.
    expect(tester.widget<FilledButton>(_allow).onPressed, isNotNull);
    expect(tester.widget<TextButton>(_skip).onPressed, isNotNull);
  });

  // -------------------------------------------------------------------------
  // States
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a rejected save is announced and does not finish '
      'the flow', (tester) async {
    final harness = _Harness()
      ..rejectSave(
        const ValidationFailure(
          message: 'The request contained invalid data.',
          fields: <String, List<String>>{
            'enabledCategories[0]': <String>[
              'value is not one of the allowed values',
            ],
          },
        ),
      );
    await harness.pump(tester);

    // Control: no banner before the attempt. "No banner" is also the state of a
    // screen that never renders one.
    expect(find.byType(LumenErrorBanner), findsNothing);

    await tester.tap(_allow);
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    expectLiveRegionAt(
      tester,
      find.byType(LumenErrorBanner),
      describedAs: 'the failure banner',
    );
    expect(find.text('The request contained invalid data.'), findsOneWidget);

    // Completing after a rejected save would stamp `onboarding_completed_at`
    // and materialise the SEED, quietly replacing the answer the user was just
    // told had failed.
    verifyNever(harness.repo.complete);
  });

  testWidgetsWithSemantics('an offline save says so and leaves the answers '
      'alone', (tester) async {
    final harness = _Harness()..rejectSave(const NetworkFailure());
    await harness.pump(tester);

    await tester.tap(_row('period_prediction'));
    await tester.pump();
    await tester.tap(_allow);
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    // The user's answer survives the failure — there is nothing to re-enter,
    // and both CTAs are live again.
    expect(_isSelected(tester, _row('period_prediction')), isTrue);
    expect(tester.widget<FilledButton>(_allow).onPressed, isNotNull);
    expect(tester.widget<TextButton>(_skip).onPressed, isNotNull);
  });

  testWidgetsWithSemantics('the save reports itself while it is in flight, and '
      'the skip stands down', (tester) async {
    final harness = _Harness();
    final gate = harness.holdSave();
    await harness.pump(tester);

    // Control: no spinner before the attempt.
    expect(
      find.byWidgetPredicate((Widget w) => w is ProgressIndicator),
      findsNothing,
    );

    await tester.tap(_allow);
    await tester.pump();

    expectLabeledSpinner(tester, 'Loading');

    // The other CTA is not a second way out of a request already in flight:
    // "Not now" would complete the flow while the save it is racing decides
    // what the server holds.
    expect(tester.widget<TextButton>(_skip).onPressed, isNull);

    // …and a row stops offering a toggle that the response would discard.
    expect(_isSelected(tester, _row('period_prediction')), isFalse);
    await tester.tap(_row('period_prediction'));
    await tester.pump();
    expect(_isSelected(tester, _row('period_prediction')), isFalse);

    gate.complete(notificationPrefsResponseFixture());
    await tester.pumpAndSettle();
  });

  testWidgetsWithSemantics('the SKIP reports itself while it is in flight, and '
      'the primary stands down', (tester) async {
    // "Not now" is a request too — `POST /onboarding/complete` — so it owns an
    // in-flight surface of its own. Without one the user taps a control that
    // appears to do nothing while the account is being stamped, and the primary
    // beside it would still offer to write preferences into a completion
    // already under way.
    final harness = _Harness();
    final gate = harness.holdComplete();
    await harness.pump(tester);

    // Control: no spinner before the attempt.
    expect(
      find.byWidgetPredicate((Widget w) => w is ProgressIndicator),
      findsNothing,
    );

    await tester.tap(_skip);
    await tester.pump();

    expectLabeledSpinner(tester, 'Loading');
    expect(tester.widget<FilledButton>(_allow).onPressed, isNull);

    gate.complete(onboardingCompleteFixture());
    await tester.pumpAndSettle();

    // …and it settles: both CTAs are live again once the request lands.
    expect(tester.widget<FilledButton>(_allow).onPressed, isNotNull);
    expect(tester.widget<TextButton>(_skip).onPressed, isNotNull);
  });
}
