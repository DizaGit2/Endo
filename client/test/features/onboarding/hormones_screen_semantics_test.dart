// Semantics + behaviour for screen 6 (P4b-T12).
//
// Four things on this screen are correctness rather than polish:
//
//   * the list it draws is the SERVER's. `POST /onboarding/hormones` and
//     `GET /onboarding/state` both answer the complete vocabulary in frozen
//     order with a boolean per code, and the screen renders that — so the
//     fixtures below hand it a list that contradicts the D-14 all-ON seed, in
//     an order the client would not have produced, and assert it followed the
//     wire;
//   * Continue writes a FULL REPLACE. A code left out of the array is stored as
//     DESELECTED (`OnboardingStepsService.cs:448-464`), so an untouched-but-
//     charted hormone has to travel or the user's earlier answer is discarded;
//   * charting NOTHING is a valid answer. This endpoint has no minimum — the
//     server keys `value is required` on a NULL and nothing else
//     (`OnboardingStepsService.cs:435-436`) — so screen 5's inert Continue is
//     deliberately absent here, and the empty case is asserted as a SUCCESS;
//   * the wire codes and the drawn labels are different strings.
//     `estradiol` is drawn "Estrogen" and `glp1` "GLP-1" (B16). The labels are
//     i18n source strings; a label on the array is a 400.
//
// One element of the row needs a test rather than a golden: the PILL TOGGLE's
// OFF appearance. The goldens pin the mockup's all-ON form, and every other
// assertion about "is this on" reads the ROW's semantics, so both of the pill's
// two conditional lines could be hard-coded to their ON value with the whole
// suite green - shipping a screen whose row fill says OFF while the pill beside
// it says ON. Proven: before `the pill toggle draws ON and OFF differently`
// existed, both mutations SURVIVED with ZERO reds across all 335 tests here.
//
// Controls are located by KEY or TYPE throughout (`hormoneRowKey`,
// `find.byType(FilledButton)`), never by what they announce — the T5c rule:
// `find.bySemanticsLabel` appears only inside assertions ABOUT what is
// announced, so a semantics change elsewhere cannot redden a test by failing
// inside `tester.tap`.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/hormone_prefs_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/hormone_palette.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/hormones_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/hormones_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 6 carrying [hormones] as its resume read.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.hormones);

  final Map<String, bool>? hormones;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.hormones,
      state: onboardingStateFixture(cycleProvided: true, hormones: hormones),
    ),
  );
}

class _Harness {
  _Harness({Map<String, bool>? hormones}) {
    overrides = <Override>[
      ...lumenOverrides(),
      onboardingFlowControllerProvider.overrideWith(
        () => _SettledFlow(hormones),
      ),
      onboardingRepositoryProvider.overrideWithValue(repo),
    ];
  }

  final _MockOnboardingRepository repo = _MockOnboardingRepository();
  late final List<Override> overrides;

  void answerSave([HormonePrefsResponse? body]) {
    when(
      () => repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) async => body ?? hormonePrefsResponseFixture());
  }

  void rejectSave(Failure failure) {
    when(
      () => repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) async => throw failure);
  }

  /// Holds the save open so the in-flight surface can be asserted on.
  Completer<HormonePrefsResponse> holdSave() {
    final completer = Completer<HormonePrefsResponse>();
    when(
      () => repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) => completer.future);
    return completer;
  }

  /// The array the repository was actually handed. Captured ONCE per call —
  /// `verify` consumes the recorded invocation.
  List<String> get postedCodes =>
      verify(
            () => repo.saveHormones(codes: captureAny(named: 'codes')),
          ).captured.last
          as List<String>;

  void verifyNoSave() =>
      verifyNever(() => repo.saveHormones(codes: any(named: 'codes')));

  /// The frame the shell puts around a step body — [onboardingStepHost], built
  /// out of the shell's own insets and its own step slot, so this file drives
  /// screen 6 under the constraints it actually ships under.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool settle = true,
    Brightness brightness = Brightness.light,
  }) async {
    final container = await pumpApp(
      tester,
      home: onboardingStepHost(const HormonesScreen()),
      overrides: overrides,
      brightness: brightness,
      settle: settle,
    );
    // The flow is autoDispose and the SHELL is what watches it in the app;
    // this file mounts the step body alone, so without a subscription the
    // `ref.read(...notifier)` inside the advance would build it, move it and
    // watch it disposed in the same turn.
    container.listen(onboardingFlowControllerProvider, (_, _) {});
    return container;
  }
}

/// One hormone row, by its stable handle.
Finder _row(String code) => find.byKey(hormoneRowKey(code));

/// One hormone's colour swatch, by its stable handle.
Finder _swatch(String code) => find.byKey(hormoneSwatchKey(code));

/// The swatch's drawn fill.
Color _swatchColor(WidgetTester tester, String code) {
  final Container box = tester.widget<Container>(_swatch(code));
  return (box.decoration! as BoxDecoration).color!;
}

/// One hormone's pill toggle, by its stable handle.
Finder _pill(String code) => find.byKey(hormoneTogglePillKey(code));

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

/// The colour the heading is actually drawn in - the probe that says which
/// theme the tree is in.
Color _headingInk(WidgetTester tester) =>
    tester.widget<Text>(find.text('Which to chart?')).style!.color!;

/// Whether the node at [finder] announces itself as selected.
bool _isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

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
  setUpAll(() => registerFallbackValue(const <String>['estradiol']));

  // -------------------------------------------------------------------------
  // What it says
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('it renders the mockup\'s copy and no dingbats', (
    tester,
  ) async {
    await _Harness().pump(tester);

    expect(find.text('Which to chart?'), findsOneWidget);
    expect(
      find.text('Defaults shown. Tweak now or in settings.'),
      findsOneWidget,
    );
    expect(find.text('Estrogen'), findsOneWidget);
    expect(find.text('Progesterone'), findsOneWidget);
    expect(find.text('LH'), findsOneWidget);
    expect(find.text('FSH'), findsOneWidget);
    expect(find.text('Testosterone'), findsOneWidget);
    expect(find.text('Cortisol'), findsOneWidget);
    expect(find.text('GLP-1'), findsOneWidget);
    // The five categories, on the rows the mockup puts them on.
    expect(find.text('Sex'), findsNWidgets(2));
    expect(find.text('Pituitary'), findsNWidgets(2));
    expect(find.text('Androgen'), findsOneWidget);
    expect(find.text('Stress'), findsOneWidget);
    expect(find.text('Metabolic'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // Screen 6's mockup draws `‹` (U+2039) and `☾`; both belong to the shell's
    // chrome or to the mockup's theme toggle, and neither may reach a `Text`
    // here. Since P4b-T5d this matcher fails on ANY codepoint above U+007F
    // that is not allowlisted, so it covers glyphs nobody has thought of.
    expectNoDingbats(tester, screen: 'Screen 6');
  });

  testWidgetsWithSemantics(
    'screen 33\'s display units are not on this screen',
    (tester) async {
      await _Harness().pump(tester);

      // Screen 6 shows name, category and toggle only. The units belong to
      // screen 33 and rest on the clinician-UNSIGNED C-07 whitelist
      // (`HormoneCatalog.cs:14-19`), so drawing one here would ship an unsigned
      // clinical value.
      for (final String unit in const <String>[
        'pg/mL',
        'ng/mL',
        'mIU/mL',
        'ng/dL',
        'pmol/L',
      ]) {
        expect(find.textContaining(unit), findsNothing);
      }
      // The control: the parts that DO belong are drawn, so the absences above
      // are about the units rather than about a screen that rendered nothing.
      expect(find.text('Estrogen'), findsOneWidget);
      expect(find.text('Sex'), findsNWidgets(2));
    },
  );

  testWidgetsWithSemantics('the heading is a header', (tester) async {
    await _Harness().pump(tester);

    expect(
      tester
          .getSemantics(find.text('Which to chart?'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    // The control: the subhead beside it is ordinary prose, not a second
    // landmark for a screen reader to stop on.
    expect(
      tester
          .getSemantics(find.text('Defaults shown. Tweak now or in settings.'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isFalse,
    );
  });

  // -------------------------------------------------------------------------
  // Codes on the wire, labels on the screen
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('the wire codes are never drawn and the labels are '
      'never sent', (tester) async {
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    // The two members whose code and label differ (B16). The label is what the
    // user reads…
    expect(find.text('Estrogen'), findsOneWidget);
    expect(find.text('GLP-1'), findsOneWidget);
    // …and the code is never drawn as copy.
    expect(find.textContaining('estradiol'), findsNothing);
    expect(find.textContaining('glp1'), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final List<String> posted = harness.postedCodes;
    // …while the wire carries the opposite pair.
    expect(posted, contains('estradiol'));
    expect(posted, contains('glp1'));
    expect(posted, isNot(contains('Estrogen')));
    expect(posted, isNot(contains('GLP-1')));
    // The positive control that makes the four rows above discriminating: the
    // code and the label really are different strings for these two members.
    // Without it they would all pass for a screen that drew the code.
    expect(HormoneOption.estradiol.label, isNot('estradiol'));
    expect(HormoneOption.glp1.label, isNot('glp1'));
  });

  // -------------------------------------------------------------------------
  // The list is the server's
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('what is drawn as charted comes from the RESPONSE, '
      'not from the D-14 seed', (tester) async {
    // A stored answer that contradicts the seed on every code.
    await _Harness(
      hormones: const <String, bool>{
        'estradiol': false,
        'progesterone': false,
        'lh': true,
        'fsh': false,
        'testosterone': false,
        'cortisol': false,
        'glp1': false,
      },
    ).pump(tester);

    expect(_isSelected(tester, _row('lh')), isTrue);

    // The positive control: the seed this build holds is all seven ON, so a
    // screen that drew the seed would have every one of these the other way
    // round.
    expect(HormoneOption.estradiol.defaultCharted, isTrue);
    expect(_isSelected(tester, _row('estradiol')), isFalse);
    expect(_isSelected(tester, _row('progesterone')), isFalse);
    expect(_isSelected(tester, _row('glp1')), isFalse);
  });

  testWidgetsWithSemantics('the rows are drawn in the RESPONSE\'s order', (
    tester,
  ) async {
    // Deliberately not the frozen order: the point is to prove the screen
    // renders the order it was sent rather than one it holds itself.
    const scrambled = <String, bool>{
      'glp1': true,
      'estradiol': false,
      'cortisol': true,
      'lh': false,
      'fsh': true,
      'testosterone': false,
      'progesterone': true,
    };
    await _Harness(hormones: scrambled).pump(tester);

    expect(
      _drawnOrder(tester, scrambled.keys.toList()),
      scrambled.keys.toList(),
    );

    // Positive control: that order is NOT the client's own, so the row above
    // cannot pass for a screen that ignored the wire.
    expect(
      scrambled.keys.toList(),
      isNot(HormoneOption.values.map((HormoneOption o) => o.wireName).toList()),
    );
  });

  testWidgetsWithSemantics('a code with no copy is not drawn, and is still '
      'carried into the write', (tester) async {
    // The vocabulary is append-only on the server. There is no label, no
    // category and no swatch for a code this build has never seen, and
    // inventing one from the wire code would be authoring copy — but on a FULL
    // REPLACE endpoint, dropping it from the array stores the user's answer as
    // a deselection.
    final harness = _Harness(
      hormones: const <String, bool>{
        'estradiol': true,
        'shbg': true,
        'glp1': false,
      },
    )..answerSave();
    await harness.pump(tester);

    expect(_row('shbg'), findsNothing);
    expect(find.textContaining('shbg'), findsNothing);
    // The control: a code this build DOES know is drawn, so the absence above
    // is a fact about the unknown one rather than about a list that never
    // rendered.
    expect(_row('estradiol'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(harness.postedCodes, <String>['estradiol', 'shbg']);
  });

  // -------------------------------------------------------------------------
  // The row
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a row is an activatable toggle named by its '
      'hormone and its category', (tester) async {
    await _Harness().pump(tester);

    // Premise: this is the state before the tap, so what changes below is the
    // tap's doing. All seven start ON (D-14).
    expect(_isSelected(tester, _row('cortisol')), isTrue);
    expect(_isSelected(tester, _row('glp1')), isTrue);

    await tester.tap(_row('cortisol'));
    await tester.pump();

    expect(_isSelected(tester, _row('cortisol')), isFalse);
    // …and its neighbour is untouched: this is a multi-select, not a radio
    // group.
    expect(_isSelected(tester, _row('glp1')), isTrue);

    expectLabeledButton(tester, _row('cortisol'), 'Cortisol');

    // It flips back — a toggle that only ever turned things off would satisfy
    // every row above.
    await tester.tap(_row('cortisol'));
    await tester.pump();
    expect(_isSelected(tester, _row('cortisol')), isTrue);
  });

  testWidgetsWithSemantics('the row announces its name and category, and the '
      'swatch and toggle are silent', (tester) async {
    await _Harness().pump(tester);

    // An equality, not two containments: the row is a `MergeSemantics`, so its
    // announced name IS the rendered copy joined by the framework's own line
    // break. A containment pair would not notice the swatch or the pill toggle
    // starting to announce themselves, and neither has anything to say — the
    // colour is decoration and the pill is the selected state, which is already
    // carried as `SemanticsFlag.isSelected`.
    expect(
      tester.getSemantics(_row('estradiol')).getSemanticsData().label,
      'Estrogen\nSex',
    );
    expect(
      tester.getSemantics(_row('glp1')).getSemanticsData().label,
      'GLP-1\nMetabolic',
    );
  });

  testWidgetsWithSemantics('the swatch is the hormone\'s hard-coded colour '
      '(light theme)', (tester) async {
    await _Harness().pump(tester);

    expect(_swatchColor(tester, 'estradiol'), HormonePalette.estrogen);
    expect(_swatchColor(tester, 'lh'), HormonePalette.lh);
    expect(_swatchColor(tester, 'glp1'), HormonePalette.glp1);

    // The control that makes this half of the pair mean something: the tree
    // really is in the LIGHT theme, and the two themes' ink tokens differ - so
    // the dark test below is not photographing the same tree twice.
    expect(_headingInk(tester), _tokens(Brightness.light).ink);
    expect(_tokens(Brightness.light).ink, isNot(_tokens(Brightness.dark).ink));
  });

  testWidgetsWithSemantics('...and the SAME colour in dark, because the swatch '
      'does not theme-switch', (tester) async {
    await _Harness().pump(tester, brightness: Brightness.dark);

    // A hormone keeps its identity colour in both themes (`CLAUDE.md`,
    // `HormoneCatalog.cs:63-66`). These are the same three constants the light
    // test asserts, unchanged.
    expect(_swatchColor(tester, 'estradiol'), HormonePalette.estrogen);
    expect(_swatchColor(tester, 'lh'), HormonePalette.lh);
    expect(_swatchColor(tester, 'glp1'), HormonePalette.glp1);

    // The control: everything else on the screen DID switch.
    expect(_headingInk(tester), _tokens(Brightness.dark).ink);
  });

  testWidgetsWithSemantics('the pill toggle draws ON and OFF differently', (
    tester,
  ) async {
    // A MIXED state, deliberately. The goldens pin the mockup's all-ON form and
    // every other "is this charted" assertion reads the ROW's semantics, so the
    // OFF pill is the one appearance on this row that nothing else covers.
    // Hard-coding either of the pill's two conditional lines to its ON value
    // would leave the row's own fill - which IS covered - saying OFF while the
    // pill beside it said ON: two contradictory affordances on one control.
    await _Harness(
      hormones: const <String, bool>{'estradiol': true, 'progesterone': false},
    ).pump(tester);

    final LumenColors c = _tokens(Brightness.light);

    // ON: the mockup's `.r.on .tgl` - accent fill, knob at `left:14px`.
    expect(_pillColor(tester, 'estradiol'), c.accent);
    expect(_pillKnob(tester, 'estradiol'), Alignment.centerRight);

    // OFF: the mockup's bare `.tgl` - border fill, knob at `left:2px`.
    expect(_pillColor(tester, 'progesterone'), c.border);
    expect(_pillKnob(tester, 'progesterone'), Alignment.centerLeft);

    // The controls. Both states are read from ONE mount of ONE screen, so no
    // single hard-coded value can satisfy both halves - and these two say the
    // pair really is a pair rather than one value written twice.
    expect(c.accent, isNot(c.border));
    expect(Alignment.centerRight, isNot(Alignment.centerLeft));

    // ...and the pill agrees with the row it sits in. That agreement is the
    // thing this test exists to keep true: the row's state is announced, the
    // pill's is only drawn, and a screen reader and a sighted user must not be
    // told opposite things.
    expect(_isSelected(tester, _row('estradiol')), isTrue);
    expect(_isSelected(tester, _row('progesterone')), isFalse);
  });

  // -------------------------------------------------------------------------
  // Continue — the FULL REPLACE
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('Continue posts the COMPLETE charted set, never a '
      'diff', (tester) async {
    final harness = _Harness(
      hormones: const <String, bool>{
        'estradiol': true,
        'progesterone': true,
        'lh': false,
        'fsh': false,
        'testosterone': false,
        'cortisol': false,
        'glp1': false,
      },
    )..answerSave();
    final container = await harness.pump(tester);

    await tester.tap(_row('lh')); // off -> on
    await tester.pump();
    await tester.tap(_row('estradiol')); // on  -> off
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final List<String> posted = harness.postedCodes;
    // The whole test is the middle element. `progesterone` was not touched on
    // this visit — a screen that sent the diff would post `['lh']`, and the
    // server's FULL REPLACE would then store `progesterone` as DESELECTED.
    // That is the silent discard.
    expect(posted, <String>['progesterone', 'lh']);
    // …and the deselected code is absent rather than sent as `false`: on this
    // wire shape, absence IS the deselection.
    expect(posted, isNot(contains('estradiol')));

    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.notifications,
    );
  });

  testWidgetsWithSemantics('an untouched screen still posts the whole set', (
    tester,
  ) async {
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(harness.postedCodes, kSeededHormones.keys.toList());
  });

  // -------------------------------------------------------------------------
  // Charting nothing is a valid answer — NOT screen 5's min-1 rule
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('with nothing charted Continue is still live, and '
      'it posts an empty array', (tester) async {
    final harness = _Harness()
      ..answerSave(
        hormonePrefsResponseFixture(const <String, bool>{
          'estradiol': false,
          'progesterone': false,
          'lh': false,
          'fsh': false,
          'testosterone': false,
          'cortisol': false,
          'glp1': false,
        }),
      );
    final container = await harness.pump(tester);

    for (final String code in kSeededHormones.keys) {
      await tester.tap(_row(code));
      await tester.pump();
    }

    // Premise: every row really is off, so what follows is about the empty
    // answer rather than about a screen that never seeded.
    for (final String code in kSeededHormones.keys) {
      expect(_isSelected(tester, _row(code)), isFalse);
    }

    // Screen 5 would be inert here and would draw `select at least one goal`.
    // Screen 6 has no minimum, so the button stays a named, activatable
    // control and there is no sentence explaining a rule that does not exist.
    expectLabeledButton(
      tester,
      find.byType(FilledButton),
      'Continue',
      exactLabel: true,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('at least one'), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(harness.postedCodes, isEmpty);
    // A SUCCESS: the step advances and nothing is held as a failure.
    expect(find.byType(LumenErrorBanner), findsNothing);
    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.notifications,
    );
  });

  // -------------------------------------------------------------------------
  // States
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a rejection is announced and names the field', (
    tester,
  ) async {
    final harness = _Harness()
      ..rejectSave(
        const ValidationFailure(
          message: 'The request contained invalid data.',
          fields: <String, List<String>>{
            'chartedHormones[0]': <String>['value is not an allowed value'],
          },
        ),
      );
    await harness.pump(tester);

    // Control: no banner before the attempt. "No banner" is also the state of a
    // screen that never renders one.
    expect(find.byType(LumenErrorBanner), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    expectLiveRegionAt(
      tester,
      find.byType(LumenErrorBanner),
      describedAs: 'the failure banner',
    );
    // The server's own words. There is no per-field slot on this screen: the
    // rejection can only be about a member of the array, and the array is the
    // whole list of rows.
    expect(find.text('The request contained invalid data.'), findsOneWidget);
  });

  testWidgetsWithSemantics('an offline save says so and leaves the answers '
      'alone', (tester) async {
    final harness = _Harness()..rejectSave(const NetworkFailure());
    final container = await harness.pump(tester);

    await tester.tap(_row('cortisol'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    // The user's answer survives the failure — there is nothing to re-enter,
    // and Continue is live again.
    expect(_isSelected(tester, _row('cortisol')), isFalse);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    // …and the flow stayed put.
    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.hormones,
    );
  });

  testWidgetsWithSemantics('the save reports itself while it is in flight', (
    tester,
  ) async {
    final harness = _Harness();
    final gate = harness.holdSave();
    await harness.pump(tester);

    // Control: no spinner before the attempt.
    expect(
      find.byWidgetPredicate((Widget w) => w is ProgressIndicator),
      findsNothing,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expectLabeledSpinner(tester, 'Loading');

    // …and a row stops offering a toggle that the response would discard.
    expect(_isSelected(tester, _row('cortisol')), isTrue);
    await tester.tap(_row('cortisol'));
    await tester.pump();
    expect(_isSelected(tester, _row('cortisol')), isTrue);

    gate.complete(hormonePrefsResponseFixture());
    await tester.pumpAndSettle();
  });
}
