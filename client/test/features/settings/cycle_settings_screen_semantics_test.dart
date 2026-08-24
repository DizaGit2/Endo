// Screen 32 — cycle settings (P4b-T22a): what it renders, what it refuses to
// render, and what a tap actually puts on the wire.
//
// Driven through the REAL controller over a mock repository, so every
// assertion below crosses the whole stack the user does: widget → controller →
// repository call. A screen test that stubs the controller can prove the CTA
// is disabled and prove nothing at all about whether a request went out.
//
// Three properties this file exists for, each of which has been broken
// somewhere in this phase before:
//
//  1. **R5 — the dropped row and the dropped footer are ASSERTED ABSENT.**
//     T22c pinned screen 36's cut App-lock strings the same way, and the
//     reason is the same: copy that was removed for a reason drifts back in
//     silently unless a test argues with it.
//  2. **R4 — the block is a disabled control PLUS a rendered reason PLUS no
//     request.** All three, because the first two can be true while the third
//     is false (a second code path that submits) and the third can be true for
//     the wrong reason (a dead button with no explanation).
//  3. **R3/R-17 — the sanity warnings never block a save, and they render on
//     LOAD as well as after one.** A value far outside the server's band is
//     submitted without argument. Clinical bounds are estimator-only and NEVER
//     entry blockers, because endometriosis cycles are irregular. The
//     load half arrived in T22a's fix round 1: the server computes the codes
//     on the GET so this screen can show the hint on arrival, and without that
//     the hint could never reach a user whose value went out of band in an
//     earlier session.
//  4. **The message zone is PINNED** — advisory, banner, block reason and CTA
//     sit outside the scroll view, screen 12's shape since T20b's fix round 1.
//     Asserted structurally (no `Scrollable` ancestor) rather than only by a
//     golden, because a golden of a screen that does not scroll yet cannot
//     tell the two layouts apart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart'
    show cycleWarningMessage;
import 'package:lumen/features/settings/application/cycle_settings_controller.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

/// One `updateSettings` call's touched flags and values, flattened.
typedef _SaveCall = ({
  int? avgCycleLengthDays,
  int? avgPeriodLengthDays,
  String? regularity,
  bool? phasePredictionEnabled,
  bool? autoDetectPeriodStartEnabled,
  bool? showFertilityWindowEnabled,
  bool touchedAvgCycleLengthDays,
  bool touchedAvgPeriodLengthDays,
  bool touchedRegularity,
  bool touchedPhasePredictionEnabled,
  bool touchedAutoDetectPeriodStartEnabled,
  bool touchedShowFertilityWindowEnabled,
});

void main() {
  late _MockCycleSettingsRepository repo;
  late List<_SaveCall> calls;

  CycleSettingsResponse stored({
    int? avgCycleLengthDays = 29,
    int? avgPeriodLengthDays = 5,
    String? regularity = 'somewhat',
    bool? phasePredictionEnabled = true,
    bool? autoDetectPeriodStartEnabled = true,
    bool? showFertilityWindowEnabled = false,
    List<String>? warnings = const <String>[],
    // The pause triple (P4b-T22b), supplied INDEPENDENTLY: the pair
    // `(trackingPaused: false, pauseReason: 'pregnancy')` is a resumed user,
    // which the server produces by design and which R2 exists for.
    bool? trackingPaused = false,
    String? pauseReason,
  }) {
    return cycleSettingsFixture(
      avgCycleLengthDays: avgCycleLengthDays,
      avgPeriodLengthDays: avgPeriodLengthDays,
      regularity: regularity,
      phasePredictionEnabled: phasePredictionEnabled,
      autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled: showFertilityWindowEnabled,
      trackingPaused: trackingPaused,
      pauseReason: pauseReason,
      phasesUnavailable:
          (trackingPaused ?? false) || !(phasePredictionEnabled ?? false),
      warnings: warnings,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
  }

  /// Matches ANY `updateSettings` call — used both to stub and to
  /// `verifyNever`, so the two can never disagree about what "a save" is.
  Future<CycleSettingsResponse> anyUpdate() => repo.updateSettings(
    avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
    avgPeriodLengthDays: any(named: 'avgPeriodLengthDays'),
    regularity: any(named: 'regularity'),
    phasePredictionEnabled: any(named: 'phasePredictionEnabled'),
    autoDetectPeriodStartEnabled: any(named: 'autoDetectPeriodStartEnabled'),
    showFertilityWindowEnabled: any(named: 'showFertilityWindowEnabled'),
    touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
    touchedAvgPeriodLengthDays: any(named: 'touchedAvgPeriodLengthDays'),
    touchedRegularity: any(named: 'touchedRegularity'),
    touchedPhasePredictionEnabled: any(named: 'touchedPhasePredictionEnabled'),
    touchedAutoDetectPeriodStartEnabled: any(
      named: 'touchedAutoDetectPeriodStartEnabled',
    ),
    touchedShowFertilityWindowEnabled: any(
      named: 'touchedShowFertilityWindowEnabled',
    ),
  );

  void stubSave({CycleSettingsResponse? body, Object? throws}) {
    when(anyUpdate).thenAnswer((invocation) async {
      final named = invocation.namedArguments;
      calls.add((
        avgCycleLengthDays: named[#avgCycleLengthDays] as int?,
        avgPeriodLengthDays: named[#avgPeriodLengthDays] as int?,
        regularity: named[#regularity] as String?,
        phasePredictionEnabled: named[#phasePredictionEnabled] as bool?,
        autoDetectPeriodStartEnabled:
            named[#autoDetectPeriodStartEnabled] as bool?,
        showFertilityWindowEnabled: named[#showFertilityWindowEnabled] as bool?,
        touchedAvgCycleLengthDays: named[#touchedAvgCycleLengthDays] as bool,
        touchedAvgPeriodLengthDays: named[#touchedAvgPeriodLengthDays] as bool,
        touchedRegularity: named[#touchedRegularity] as bool,
        touchedPhasePredictionEnabled:
            named[#touchedPhasePredictionEnabled] as bool,
        touchedAutoDetectPeriodStartEnabled:
            named[#touchedAutoDetectPeriodStartEnabled] as bool,
        touchedShowFertilityWindowEnabled:
            named[#touchedShowFertilityWindowEnabled] as bool,
      ));
      if (throws != null) throw throws;
      return body ?? stored();
    });
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    CacheResult<CycleSettingsResponse>? read,
  }) async {
    when(
      () => repo.getSettings(),
    ).thenAnswer((_) async => read ?? Fresh(stored()));
    await pumpApp(
      tester,
      home: const CycleSettingsScreen(),
      overrides: <Override>[
        ...lumenOverrides(cacheStore: emptyCacheStore()),
        cycleSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// Every string the tree currently DRAWS.
  ///
  /// Read off `RichText` rather than `find.byType(Text)`: the latter matches
  /// `runtimeType == Text` only, so a `Text.rich` or a bare `RichText` would be
  /// invisible to it — and these are absence assertions, where a blind spot
  /// reads as a pass.
  ///
  /// `includeSemanticsLabels: false` for the same reason, and it is the hole
  /// T22c booked against its own copy of this helper: `toPlainText()`'s default
  /// substitutes a span's `semanticsLabel` for its text, so a cut string drawn
  /// inside a labelled span would be replaced by the label and missed.
  List<String> renderedText(WidgetTester tester) {
    return tester
        .widgetList<RichText>(find.byType(RichText))
        .map(
          (w) => w.text.toPlainText(
            includeSemanticsLabels: false,
            includePlaceholders: false,
          ),
        )
        .toList();
  }

  setUp(() {
    repo = _MockCycleSettingsRepository();
    calls = <_SaveCall>[];
    stubSave();
  });

  // ── R5: what is NOT here ──────────────────────────────────────────────────

  group('R5 — the dropped row and the dropped footer', () {
    testWidgets(
      'the DISPLAY section and its `First day of week` row are gone — R-10: '
      'there is no first-day-of-week column anywhere on the P4a surface, and '
      'R-04 already derives the week from the locale, so the row could only '
      'ever be a promise with a date attached',
      (tester) async {
        await pumpScreen(tester);

        expect(find.text('First day of week'), findsNothing);
        expect(find.text('Display'), findsNothing);
        expect(find.text('DISPLAY'), findsNothing);
        expect(find.text('Monday'), findsNothing);
      },
    );

    testWidgets(
      'the retrain footer is gone — R-16: the phase engine is deterministic '
      'C# rules, so there is no model and nothing retrains, and the "3 '
      'cycles" figure also contradicts the 6-cycle window',
      (tester) async {
        await pumpScreen(tester);

        final drawn = renderedText(tester).join('\n').toLowerCase();
        expect(drawn, isNot(contains('retrain')));
        expect(drawn, isNot(contains('3 logged cycles')));
      },
    );

    testWidgets(
      'the pause card IS here now — this assertion was T22a\'s tripwire that '
      'nothing about pausing had shipped yet, and P4b-T22b inverts it rather '
      'than deleting it, so the two halves of screen 32 stay pinned to each '
      'other (T21b did the same to screen 12\'s body-map tripwire)',
      (tester) async {
        await pumpScreen(tester);

        final drawn = renderedText(tester).join('\n').toLowerCase();
        expect(drawn, contains('pause'));
      },
    );
  });

  // ── the drawn glyphs ──────────────────────────────────────────────────────

  group('no dingbats', () {
    testWidgets(
      'the chevron and sparkle glyphs the mockup draws are real Icons, not '
      'characters — a codepoint above U+007F that a screen reader would try '
      'to pronounce is a rule this screen inherits, not a new one',
      (tester) async {
        await pumpScreen(tester);
        expectNoDingbats(tester, screen: 'CycleSettingsScreen');
      },
    );

    testWidgets(
      'and the advisory the mockup drew a sparkle beside carries none either',
      (tester) async {
        stubSave(
          body: stored(
            avgCycleLengthDays: 200,
            warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
          ),
        );
        await pumpScreen(tester);

        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();

        expectNoDingbats(tester, screen: 'CycleSettingsScreen');
      },
    );
  });

  // ── what IS here ──────────────────────────────────────────────────────────

  group('the pattern rows', () {
    testWidgets('both lengths render with their unit and a chevron', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text(kCycleSettingsAvgCycleLabel), findsOneWidget);
      expect(find.text(kCycleSettingsAvgPeriodLabel), findsOneWidget);
      expect(find.text('29 days'), findsOneWidget);
      expect(find.text('5 days'), findsOneWidget);
    });

    testWidgets(
      'a period length of 1 is `1 day`, not `1 days` — the row is a control '
      'name, and a plural on a singular value reads as a bug',
      (tester) async {
        await pumpScreen(tester, read: Fresh(stored(avgPeriodLengthDays: 1)));

        expect(find.text('1 day'), findsOneWidget);
      },
    );

    testWidgets(
      'an UNSET period length says so rather than showing a number nobody '
      'entered — onboarding never collects this field, so null is the '
      'ordinary state of a freshly-onboarded account',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(stored(avgPeriodLengthDays: null)),
        );

        expect(find.text(kCycleSettingsNotSetValue), findsOneWidget);
      },
    );

    testWidgetsWithSemantics('each length row is a real, named button', (
      tester,
    ) async {
      await pumpScreen(tester);

      // The row MERGES its label and its value, so the announced name is
      // both — which is the point: "Avg cycle length" alone would not tell a
      // screen-reader user what the control currently holds.
      expectLabeledButton(
        tester,
        find.bySemanticsLabel(RegExp(kCycleSettingsAvgCycleLabel)),
        '$kCycleSettingsAvgCycleLabel\n29 days',
        exactLabel: true,
      );
    });
  });

  group('R2 — the only surface that can set the period length', () {
    testWidgets(
      'opening the period-length editor on an UNSET row, typing a number and '
      'saving puts that number on the wire. If this path does not work, '
      'nothing in the app can ever set `avgPeriodLengthDays`.',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(stored(avgPeriodLengthDays: null)),
        );

        await tester.tap(find.text(kCycleSettingsAvgPeriodLabel));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '6');
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsEditSaveLabel));
        await tester.pumpAndSettle();

        expect(find.text('6 days'), findsOneWidget);

        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();

        expect(calls, hasLength(1));
        expect(calls.single.avgPeriodLengthDays, 6);
        expect(calls.single.touchedAvgPeriodLengthDays, isTrue);
        // …and nothing else was asserted, though every other value was on
        // screen the whole time.
        expect(calls.single.touchedAvgCycleLengthDays, isFalse);
        expect(calls.single.touchedRegularity, isFalse);
        expect(calls.single.avgCycleLengthDays, 29);
      },
    );

    testWidgets(
      'the editor\'s Save is inert while the box is empty — this endpoint has '
      'no clear, so an empty box must not become a gesture the server cannot '
      'honour',
      (tester) async {
        await pumpScreen(tester);

        await tester.tap(find.text(kCycleSettingsAvgPeriodLabel));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();

        final save = tester.widget<TextButton>(
          find.widgetWithText(TextButton, kCycleSettingsEditSaveLabel),
        );
        expect(save.onPressed, isNull);
      },
    );

    testWidgets('cancelling the editor changes nothing at all', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsAvgCycleLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '44');
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsEditCancelLabel));
      await tester.pumpAndSettle();

      expect(find.text('29 days'), findsOneWidget);
      expect(find.text('44 days'), findsNothing);
      expect(
        find.text(kCycleSettingsNothingChangedMessage),
        findsOneWidget,
        reason: 'a cancelled edit must not mark the field touched',
      );
    });
  });

  // ── R4: the block ─────────────────────────────────────────────────────────

  group('R4 — nothing touched, nothing sent', () {
    testWidgets(
      'the CTA is disabled, the REASON is rendered beside it, and no request '
      'is issued — all three, because the endpoint answers an all-absent body '
      'with a 400 keyed `request` and a disabled button alone proves nothing '
      'about a second code path',
      (tester) async {
        await pumpScreen(tester);

        final cta = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
        );
        expect(cta.onPressed, isNull);
        expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);

        await tester.tap(
          find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
        );
        await tester.pumpAndSettle();

        verifyNever(anyUpdate);
        expect(calls, isEmpty);
      },
    );

    testWidgets('one toggle is enough to unblock it, and the reason goes', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsFertilityLabel));
      await tester.pumpAndSettle();

      expect(find.text(kCycleSettingsNothingChangedMessage), findsNothing);
      final cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
      );
      expect(cta.onPressed, isNotNull);
    });
  });

  // ── the toggles and the chips ─────────────────────────────────────────────

  group('the prediction preferences', () {
    testWidgetsWithSemantics(
      'each toggle row announces itself as a selected/unselected button — the '
      'pill is decoration and says nothing of its own',
      (tester) async {
        await pumpScreen(tester);

        expectLabeledButton(
          tester,
          find.bySemanticsLabel(kCycleSettingsPhasePredictionLabel),
          kCycleSettingsPhasePredictionLabel,
        );
      },
    );

    testWidgets('flipping one sends exactly that one, as `false`', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsPhasePredictionLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      expect(calls.single.phasePredictionEnabled, isFalse);
      expect(calls.single.touchedPhasePredictionEnabled, isTrue);
      expect(calls.single.touchedAutoDetectPeriodStartEnabled, isFalse);
      expect(calls.single.touchedShowFertilityWindowEnabled, isFalse);
    });
  });

  group('regularity', () {
    testWidgets(
      'the SELECTED chip offers no tap action — this endpoint cannot un-set a '
      'regularity, so a deselect gesture would be one the server could not '
      'honour',
      (tester) async {
        await pumpScreen(tester);

        final selected = tester
            .widgetList<LumenSelectableChip>(find.byType(LumenSelectableChip))
            .where((chip) => chip.selected)
            .toList();
        expect(selected, hasLength(1));
        expect(selected.single.label, 'Somewhat');
        expect(selected.single.onTap, isNull);
      },
    );

    testWidgets('picking another chip sends its WIRE code, not its label', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Irregular'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      expect(calls.single.regularity, 'irregular');
      expect(calls.single.touchedRegularity, isTrue);
    });
  });

  // ── R3 / R-17: the advisory ───────────────────────────────────────────────

  group('R3 — the sanity warning is an advisory, and never a blocker', () {
    const outOfBand = 'avg_cycle_length_out_of_sanity_band';

    testWidgets(
      'a value the server will warn about does NOT block the save: the CTA is '
      'live, the request goes out, and only then does the note appear. '
      'R-17 is a PO ruling — clinical bounds are estimator-only and never '
      'entry blockers, because endometriosis cycles are irregular.',
      (tester) async {
        stubSave(
          body: stored(
            avgCycleLengthDays: 200,
            warnings: const <String>[outOfBand],
          ),
        );
        await pumpScreen(tester);

        await tester.tap(find.text(kCycleSettingsAvgCycleLabel));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '200');
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsEditSaveLabel));
        await tester.pumpAndSettle();

        // BEFORE the save: submittable, and no note yet.
        final cta = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
        );
        expect(cta.onPressed, isNotNull);
        expect(
          find.text(cycleSettingsWarningMessage(outOfBand)!),
          findsNothing,
        );

        await tester.tap(
          find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
        );
        await tester.pumpAndSettle();

        // AFTER: the value was SAVED, and the note is on screen.
        expect(calls, hasLength(1));
        expect(calls.single.avgCycleLengthDays, 200);
        expect(
          find.text(cycleSettingsWarningMessage(outOfBand)!),
          findsOneWidget,
        );
      },
    );

    testWidgets('a clean 200 renders no advisory at all', (tester) async {
      stubSave(body: stored(warnings: const <String>[]));
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsFertilityLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(find.text(cycleSettingsWarningMessage(outOfBand)!), findsNothing);
    });

    testWidgets(
      'the note IS drawn on LOAD when the stored value is out of band — the '
      'server computes the codes on the GET for exactly this, and a value '
      'typed in an earlier session has no other way of ever being mentioned',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(
            stored(
              avgCycleLengthDays: 200,
              warnings: const <String>[outOfBand],
            ),
          ),
        );

        expect(find.text('200 days'), findsOneWidget);
        expect(
          find.text(cycleSettingsWarningMessage(outOfBand)!),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a hint on LOAD still blocks NOTHING: the only reason Save is disabled '
      'on arrival is that nothing has been touched, and one edit makes the '
      'CTA live and puts the request on the wire (R-17)',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(
            stored(
              avgCycleLengthDays: 200,
              warnings: const <String>[outOfBand],
            ),
          ),
        );

        // The block that IS in force names the empty body, not the number.
        expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
              )
              .onPressed,
          isNull,
        );

        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
              )
              .onPressed,
          isNotNull,
        );

        await tester.tap(
          find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
        );
        await tester.pumpAndSettle();

        expect(calls, hasLength(1));
      },
    );

    testWidgets(
      'the hint is DROPPED when the user changes a value — it describes what '
      'the server stores, not what is on screen',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(
            stored(
              avgCycleLengthDays: 200,
              warnings: const <String>[outOfBand],
            ),
          ),
        );
        expect(
          find.text(cycleSettingsWarningMessage(outOfBand)!),
          findsOneWidget,
        );

        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();

        expect(
          find.text(cycleSettingsWarningMessage(outOfBand)!),
          findsNothing,
        );
      },
    );

    test('screen 32 says what screen 3 says, minus the save acknowledgement — '
        'the two copies are duplicated on purpose and this is what stops them '
        'drifting into describing the same server behaviour differently', () {
      for (final code in <String>[
        'avg_cycle_length_out_of_sanity_band',
        'avg_period_length_out_of_sanity_band',
      ]) {
        expect(
          cycleSettingsWarningMessage(code),
          cycleWarningMessage(code)!.replaceFirst('Saved. ', ''),
          reason:
              'screen 3 only ever shows the hint in the moment after a '
              'save, so `Saved.` is true there. Screen 32 shows it on load '
              'too, where it would be a statement about something the user '
              'did not just do.',
        );
        // And the prefix really was there to remove — otherwise the
        // assertion above would pass on two identical strings.
        expect(cycleWarningMessage(code), startsWith('Saved. '));
      }
    });

    test('an unknown code has nothing to say, on both surfaces', () {
      expect(cycleSettingsWarningMessage('some_code_from_p6'), isNull);
    });
  });

  // ── R6: the designed failure ──────────────────────────────────────────────

  group('R6 — a failed save', () {
    testWidgets(
      'keeps every answer on screen and relabels the CTA — leaving would '
      'discard the edit silently',
      (tester) async {
        stubSave(throws: const NetworkFailure('offline'));
        await pumpScreen(tester);

        await tester.tap(find.text('Irregular'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();

        expect(find.byType(LumenErrorBanner), findsOneWidget);
        expect(find.text(kCycleSettingsRetryLabel), findsOneWidget);
        expect(find.text(kCycleSettingsSaveLabel), findsNothing);

        // The answers survived: the Irregular chip is still the selected one
        // and the fertility row is still on.
        final selected = tester
            .widgetList<LumenSelectableChip>(find.byType(LumenSelectableChip))
            .where((chip) => chip.selected)
            .single;
        expect(selected.label, 'Irregular');
      },
    );

    testWidgets(
      'the failure message does not scroll away from the control that caused '
      'it — banner, block reason and CTA are adjacent, and pinned together '
      'BELOW the scroll view (T20b\'s amended S9). This is the geometric '
      'half; the structural half is the "message zone is PINNED" group, '
      'because `getRect` reports OFF-SCREEN rectangles and would stay green '
      'on a banner that had scrolled away.',
      (tester) async {
        stubSave(throws: const NetworkFailure('offline'));
        await pumpScreen(tester);

        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();

        final bannerBottom = tester
            .getRect(find.byType(LumenErrorBanner))
            .bottom;
        final ctaTop = tester
            .getRect(
              find.widgetWithText(FilledButton, kCycleSettingsRetryLabel),
            )
            .top;
        expect(ctaTop - bannerBottom, lessThan(40));
      },
    );

    testWidgets('a 400 keyed to a field renders under that field — the ONE '
        'message class that stays with the scrolling content, because it '
        'names a row rather than the button', (tester) async {
      stubSave(
        throws: const ValidationFailure(
          fields: <String, List<String>>{
            'avgCycleLengthDays': <String>['value must be between 1 and 32767'],
          },
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsAvgCycleLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '99999');
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsEditSaveLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      expect(find.text('value must be between 1 and 32767'), findsOneWidget);
    });

    testWidgets('the retry re-issues EXACTLY ONE request', (tester) async {
      final log = ApiCallLog();
      when(anyUpdate).thenAnswer((_) async {
        log.record();
        throw const NetworkFailure('offline');
      });
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsFertilityLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      await expectRetryReissuesOneRequest(
        tester,
        requestCount: () => log.calls,
        label: kCycleSettingsRetryLabel,
      );
    });
  });

  // ── the pinned message zone ───────────────────────────────────────────────

  group('the message zone is PINNED, outside the scroll view', () {
    // **Structural, not geometric, and not a golden.** T22a shipped the
    // banner, the block reason and the CTA inside the `SingleChildScrollView`
    // and pinned their adjacency with `getRect` — which reports OFF-SCREEN
    // rectangles, so it stays green on a screen that has begun to scroll. The
    // goldens cannot tell the two layouts apart either while
    // `maxScrollExtent` is 0.0, which it is today at 390x844. T22b adds a
    // pause card to this screen; the day the content exceeds the viewport,
    // only an assertion about the TREE catches a banner that has floated away.
    // (T20b's review made the same point about a pinned footer proven by a
    // golden alone.)

    /// The probe the assertions below rely on, exercised against something
    /// that really is inside the scroll view — otherwise a `findsNothing`
    /// could just be a finder pair that never matches anything.
    void expectProbeCanSeeAScrollAncestor(WidgetTester tester) {
      expect(
        find.byType(SingleChildScrollView),
        findsOneWidget,
        reason: 'the FORM still scrolls; only the message zone does not',
      );
      expect(
        find.ancestor(
          of: find.text(kCycleSettingsAvgCycleLabel),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    }

    testWidgets('the failure banner has no Scrollable ancestor', (
      tester,
    ) async {
      stubSave(throws: const NetworkFailure('offline'));
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsFertilityLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      expect(find.byType(LumenErrorBanner), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(LumenErrorBanner),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason:
            'the user is AT the CTA when a failure arrives — that is the '
            'control they just pressed — and the announcement has to stay '
            'next to the retry control that answers it (T20b amended S9 to '
            'say so; this screen converges on it)',
      );
      expectProbeCanSeeAScrollAncestor(tester);
    });

    testWidgets('the block reason and the CTA have no Scrollable ancestor', (
      tester,
    ) async {
      await pumpScreen(tester);

      // A freshly-opened form is blocked, so both are on screen at once.
      expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(LumenFieldMessage),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason:
            'a block reason that scrolls away leaves a disabled button with '
            'no explanation — S7, and the same class of message as the banner',
      );
      expect(
        find.ancestor(
          of: find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expectProbeCanSeeAScrollAncestor(tester);
    });

    testWidgets('the advisory has no Scrollable ancestor either — it renders '
        'on LOAD, when the user is at the TOP of the page, and after a save, '
        'when they are at the bottom; pinning is the only placement that is '
        'on screen for both', (tester) async {
      await pumpScreen(
        tester,
        read: Fresh(
          stored(
            avgCycleLengthDays: 200,
            warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
          ),
        ),
      );

      final advisory = find.text(
        cycleSettingsWarningMessage('avg_cycle_length_out_of_sanity_band')!,
      );
      expect(advisory, findsOneWidget);
      expect(
        find.ancestor(of: advisory, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expectProbeCanSeeAScrollAncestor(tester);
    });

    testWidgets('a field-keyed 400 stays WITH its row, inside the scroll '
        'view — it names a row, not the button, and the pin is about the '
        'message zone rather than about every message', (tester) async {
      stubSave(
        throws: const ValidationFailure(
          fields: <String, List<String>>{
            'avgCycleLengthDays': <String>['value must be between 1 and 32767'],
          },
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.text(kCycleSettingsAvgCycleLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '99999');
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsEditSaveLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCycleSettingsSaveLabel));
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('value must be between 1 and 32767'),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });
  });

  // ── after a successful save ───────────────────────────────────────────────

  group('after a successful save', () {
    testWidgets(
      'the CTA blocks again with its reason, and a second tap issues no '
      'second request — the 200 became the new seed with nothing marked '
      'touched, so there is nothing left to assert back at the endpoint',
      (tester) async {
        await pumpScreen(tester);

        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();
        expect(calls, hasLength(1));

        expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);
        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();

        expect(calls, hasLength(1));
      },
    );
  });

  // ── the C-12 pause sub-flow (P4b-T22b) ────────────────────────────────────
  //
  // Everything below is driven through the real controller and asserted at the
  // repository call, so "the card looks right" and "the right request went
  // out" are never confused for each other.
  //
  // The two rulings that decide the shape of this group:
  //
  //  * **R2** — the card's state is `trackingPaused`. A resumed user's
  //    response still carries their last `pauseReason`, on purpose, so every
  //    case here supplies the two independently and one of them is the pair a
  //    `pauseReason != null` gate would render as "paused forever".
  //  * **R1** — resume is unconditional for every one of the five reasons,
  //    pregnancy included. The resume cases are parameterised over the whole
  //    vocabulary, and each asserts that no dialog appeared.

  group('the pause card', () {
    late List<String> pauseCalls;
    late int resumeCalls;

    void stubPause({CycleSettingsResponse? body, Object? throws}) {
      when(() => repo.pauseTracking(reason: any(named: 'reason'))).thenAnswer((
        invocation,
      ) async {
        final reason = invocation.namedArguments[#reason] as String;
        pauseCalls.add(reason);
        if (throws != null) throw throws;
        return body ?? stored(trackingPaused: true, pauseReason: reason);
      });
    }

    void stubResume({CycleSettingsResponse? body, Object? throws}) {
      when(repo.resumeTracking).thenAnswer((_) async {
        resumeCalls++;
        if (throws != null) throw throws;
        return body ?? stored(trackingPaused: false, pauseReason: 'pregnancy');
      });
    }

    setUp(() {
      pauseCalls = <String>[];
      resumeCalls = 0;
      stubPause();
      stubResume();
    });

    /// Taps one reason chip, scrolling it into view first.
    ///
    /// The pause card is the LAST thing in the scroll view and the form now
    /// genuinely scrolls at 390x844 — which is the whole reason R5 moved the
    /// sub-flow's CTA out of it. A bare `tap` on a chip below the fold warns
    /// "finder missed" and does nothing, so the gesture has to reach the
    /// widget the same way a user's would.
    Future<void> tapReasonChip(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    /// The five reason chips currently drawn, by label. The regularity row
    /// uses the same widget, so counting `LumenSelectableChip` alone would
    /// answer three when the pause card draws none.
    List<String> reasonChipLabels(WidgetTester tester) {
      return CyclePauseReason.values
          .map((r) => r.label)
          .where(
            (label) => find
                .widgetWithText(LumenSelectableChip, label)
                .evaluate()
                .isNotEmpty,
          )
          .toList();
    }

    /// R4 — every drawn string that mentions a C-12 reason IS that reason's
    /// bare label. A sentence saying what a reason means is C-12's clinician's
    /// to write; C-12 is PO-interim with the sign-off still pending.
    ///
    /// `other` is deliberately not among the words: it is an ordinary English
    /// word that would match copy having nothing to do with the vocabulary,
    /// and a check that fires on the wrong thing gets deleted rather than
    /// heeded.
    void expectNoReasonProse(WidgetTester tester) {
      const words = <String, String>{
        'pregnan': 'Pregnancy',
        'hormonal': 'Hormonal suppression',
        'surgic': 'Surgical',
        'menopaus': 'Menopause',
      };
      for (final drawn in renderedText(tester)) {
        for (final entry in words.entries) {
          if (!drawn.toLowerCase().contains(entry.key)) continue;
          expect(
            drawn,
            entry.value,
            reason:
                'a sentence that explains a C-12 reason is the clinician\'s '
                'to write, not this screen\'s',
          );
        }
      }
    }

    // -- the vocabulary ------------------------------------------------------

    testWidgets(
      'the five C-12 codes are exactly the five the server accepts, and all '
      'five are drawn as chips — the labels are the codes humanised and '
      'nothing more (R4: the reasons are a vocabulary, not a diagnosis)',
      (tester) async {
        expect(
          CyclePauseReason.values.map((r) => r.wireName).toList(),
          <String>[
            'pregnancy',
            'hormonal_suppression',
            'surgical',
            'menopause',
            'other',
          ],
        );

        await pumpScreen(tester);

        for (final reason in CyclePauseReason.values) {
          expect(
            find.widgetWithText(LumenSelectableChip, reason.label),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'R4 — no copy on this screen says anything about what a reason MEANS. '
      'C-12 is PO-interim and clinician-UNSIGNED, so every drawn string that '
      'mentions one of these words is that reason\'s bare label and nothing '
      'longer',
      (tester) async {
        await pumpScreen(tester);
        expectNoReasonProse(tester);
      },
    );

    testWidgets('R4 — and none while PAUSED either', (tester) async {
      await pumpScreen(
        tester,
        read: Fresh(stored(trackingPaused: true, pauseReason: 'pregnancy')),
      );
      expectNoReasonProse(tester);
    });

    // -- R2: the flag is the state ------------------------------------------

    testWidgets(
      'R2 — a RESUMED user renders as NOT paused, though their response still '
      'carries their last reason. This is the state a `pauseReason != null` '
      'gate would draw as paused forever, with a Resume button they had '
      'already used',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(stored(trackingPaused: false, pauseReason: 'pregnancy')),
        );

        expect(find.text(kCycleSettingsTrackingActiveValue), findsOneWidget);
        expect(find.text(kCycleSettingsTrackingPausedValue), findsNothing);
        expect(
          find.widgetWithText(OutlinedButton, kCycleSettingsPauseLabel),
          findsOneWidget,
        );
        expect(find.text(kCycleSettingsResumeLabel), findsNothing);

        // …and the remembered reason is doing the one job the server keeps it
        // for: the chip opens pre-selected, so the CTA is live immediately.
        final chip = tester.widget<LumenSelectableChip>(
          find.widgetWithText(
            LumenSelectableChip,
            CyclePauseReason.pregnancy.label,
          ),
        );
        expect(chip.selected, isTrue);
        expect(find.text(kCycleSettingsChooseReasonMessage), findsNothing);
      },
    );

    testWidgets('a PAUSED user renders paused, with the reason and no chips', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        read: Fresh(stored(trackingPaused: true, pauseReason: 'surgical')),
      );

      expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);
      expect(find.text(kCycleSettingsTrackingActiveValue), findsNothing);
      expect(find.text(CyclePauseReason.surgical.label), findsOneWidget);
      // …but NOT as a chip: while paused the reason is a read-only row, and
      // re-picking one is a gesture this task deliberately does not ship.
      expect(reasonChipLabels(tester), isEmpty);
      expect(
        find.widgetWithText(OutlinedButton, kCycleSettingsResumeLabel),
        findsOneWidget,
      );
    });

    testWidgets(
      'a stored reason this build has never seen draws no reason row at all, '
      'and never the raw wire code — the C-12 vocabulary is append-only on '
      'the server, so a sixth member WILL reach a build that predates it',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(stored(trackingPaused: true, pauseReason: 'lactational')),
        );

        expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);
        expect(renderedText(tester).join('\n'), isNot(contains('lactational')));
        expect(
          find.widgetWithText(OutlinedButton, kCycleSettingsResumeLabel),
          findsOneWidget,
          reason: 'and they can still resume out of it',
        );
      },
    );

    // -- R1: five in, five out ----------------------------------------------

    for (final reason in CyclePauseReason.values) {
      testWidgets(
        'tapping ${reason.label} then Pause sends `${reason.wireName}`',
        (tester) async {
          await pumpScreen(tester);

          await tapReasonChip(tester, reason.label);
          await tester.tap(find.text(kCycleSettingsPauseLabel));
          await tester.pumpAndSettle();

          expect(pauseCalls, <String>[reason.wireName]);
          expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);
        },
      );

      testWidgets(
        'Resume works from `${reason.wireName}` with NO confirmation and no '
        'second question — R1: there is no reason a user cannot resume from',
        (tester) async {
          stubResume(
            body: stored(trackingPaused: false, pauseReason: reason.wireName),
          );
          await pumpScreen(
            tester,
            read: Fresh(
              stored(trackingPaused: true, pauseReason: reason.wireName),
            ),
          );

          await tester.tap(find.text(kCycleSettingsResumeLabel));
          // ONE pump, before settling: a confirmation would be on screen here.
          await tester.pump();
          expect(
            find.byType(AlertDialog),
            findsNothing,
            reason: 'nothing may stand between the user and resuming',
          );
          await tester.pumpAndSettle();

          expect(resumeCalls, 1);
          expect(find.text(kCycleSettingsTrackingActiveValue), findsOneWidget);
        },
      );
    }

    testWidgets(
      'R2 end to end — after resuming, the reason is STILL SET and the screen '
      'still reads active. The chip comes back pre-selected, which is the '
      'whole reason the server keeps it',
      (tester) async {
        stubResume(
          body: stored(trackingPaused: false, pauseReason: 'pregnancy'),
        );
        await pumpScreen(
          tester,
          read: Fresh(stored(trackingPaused: true, pauseReason: 'pregnancy')),
        );

        await tester.tap(find.text(kCycleSettingsResumeLabel));
        await tester.pumpAndSettle();

        expect(find.text(kCycleSettingsTrackingActiveValue), findsOneWidget);
        expect(find.text(kCycleSettingsResumeLabel), findsNothing);
        final chip = tester.widget<LumenSelectableChip>(
          find.widgetWithText(
            LumenSelectableChip,
            CyclePauseReason.pregnancy.label,
          ),
        );
        expect(chip.selected, isTrue);
      },
    );

    // -- the block, and its independence from the save's ---------------------

    testWidgets(
      'with no reason ever chosen the pause CTA is DISABLED, its reason is '
      'rendered, and no request goes out — all three, because the first two '
      'can be true while a second code path still submits',
      (tester) async {
        await pumpScreen(tester);

        expect(find.text(kCycleSettingsChooseReasonMessage), findsOneWidget);
        final cta = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, kCycleSettingsPauseLabel),
        );
        expect(cta.onPressed, isNull);

        await tester.tap(
          find.widgetWithText(OutlinedButton, kCycleSettingsPauseLabel),
        );
        await tester.pumpAndSettle();
        expect(pauseCalls, isEmpty);
      },
    );

    testWidgets(
      'the empty-body block belongs to the SAVE alone — a freshly opened '
      'screen can pause without touching a single setting. `Validate`\'s '
      'emptiness test spans all nine members, so a pause-only body names a '
      'field and is a legal request',
      (tester) async {
        await pumpScreen(
          tester,
          read: Fresh(stored(trackingPaused: false, pauseReason: 'menopause')),
        );

        expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
              )
              .onPressed,
          isNull,
        );

        await tester.tap(find.text(kCycleSettingsPauseLabel));
        await tester.pumpAndSettle();

        expect(pauseCalls, <String>['menopause']);
        verifyNever(anyUpdate);
      },
    );

    // -- R5: the sub-flow's message zone is pinned too ----------------------

    testWidgets(
      'R5 — the pause banner, its block reason and its CTA all sit OUTSIDE '
      'the scroll view, exactly where T22a put the save trio. The pause card '
      'is precisely the content that made this matter',
      (tester) async {
        stubPause(throws: const NetworkFailure('offline'));
        await pumpScreen(tester);

        // Blocked first: the CTA and its reason, with the form scrolling.
        expect(find.text(kCycleSettingsChooseReasonMessage), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text(kCycleSettingsChooseReasonMessage),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.widgetWithText(OutlinedButton, kCycleSettingsPauseLabel),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );

        // The positive control: the chips the CTA acts on DO scroll, so the
        // `findsNothing`s above are about placement rather than a finder pair
        // that never matches anything.
        expect(
          find.ancestor(
            of: find.text(CyclePauseReason.other.label),
            matching: find.byType(Scrollable),
          ),
          findsWidgets,
        );

        await tapReasonChip(tester, CyclePauseReason.other.label);
        await tester.tap(find.text(kCycleSettingsPauseLabel));
        await tester.pumpAndSettle();

        expect(find.byType(LumenErrorBanner), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(LumenErrorBanner),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.text(CyclePauseReason.other.label),
            matching: find.byType(Scrollable),
          ),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'a failed pause relabels ITS OWN control to Try again — the save CTA is '
      'untouched — and the retry re-issues exactly one request',
      (tester) async {
        final log = ApiCallLog();
        when(() => repo.pauseTracking(reason: any(named: 'reason'))).thenAnswer(
          (_) async {
            log.record();
            throw const NetworkFailure('offline');
          },
        );
        await pumpScreen(tester);

        await tapReasonChip(tester, CyclePauseReason.surgical.label);
        await tester.tap(find.text(kCycleSettingsPauseLabel));
        await tester.pumpAndSettle();

        expect(find.text(kCycleSettingsSaveLabel), findsOneWidget);
        await expectRetryReissuesOneRequest(
          tester,
          requestCount: () => log.calls,
          label: kCycleSettingsRetryLabel,
        );
      },
    );

    testWidgets(
      'the two CTAs never both read Try again — starting either attempt '
      'clears the other\'s banner, so `findRetryAffordance` can always name '
      'one control and a screen reader hears one',
      (tester) async {
        stubSave(throws: const NetworkFailure('offline'));
        stubPause(throws: const ServerFailure('boom'));
        // Seeded with a REMEMBERED reason, so the pause needs no chip tap.
        // Tapping one would go through the controller's `_write`, which clears
        // the settings failure by itself — and the test would then pass
        // whether or not the pause path clears anything (T22b mutation m8,
        // caught at the controller layer and closed in both places).
        await pumpScreen(
          tester,
          read: Fresh(stored(trackingPaused: false, pauseReason: 'menopause')),
        );

        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kCycleSettingsSaveLabel));
        await tester.pumpAndSettle();
        expect(findRetryAffordance(), findsOneWidget);
        expect(find.byType(LumenErrorBanner), findsOneWidget);

        await tester.tap(find.text(kCycleSettingsPauseLabel));
        await tester.pumpAndSettle();

        expect(findRetryAffordance(), findsOneWidget);
        expect(find.byType(LumenErrorBanner), findsOneWidget);
      },
    );

    testWidgets(
      'while a pause is in flight the pause control shows a spinner and BOTH '
      'CTAs go inert, along with the chips — the controller refuses either '
      'write while the other runs, so a live control here would be one whose '
      'activation silently does nothing',
      (tester) async {
        // The save CTA's half of this was measured unpinned: gating it on
        // `form.submitting` alone left the suite green (T22b mutation m23),
        // because the controller refuses the overlapping save anyway and no
        // screen test looked at the button.
        final gate = Completer<CycleSettingsResponse>();
        when(
          () => repo.pauseTracking(reason: any(named: 'reason')),
        ).thenAnswer((_) => gate.future);
        await pumpScreen(
          tester,
          read: Fresh(stored(trackingPaused: false, pauseReason: 'menopause')),
        );

        // Touched first, so the save CTA is live BEFORE the pause starts and
        // its disabling can only come from the in-flight gate.
        await tester.tap(find.text(kCycleSettingsFertilityLabel));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
              )
              .onPressed,
          isNotNull,
        );

        await tester.tap(find.text(kCycleSettingsPauseLabel));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(OutlinedButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull,
        );
        expect(
          tester
              .widgetList<LumenSelectableChip>(find.byType(LumenSelectableChip))
              .every((chip) => !chip.enabled),
          isTrue,
        );

        gate.complete(stored(trackingPaused: true, pauseReason: 'menopause'));
        await tester.pumpAndSettle();
        expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);
      },
    );

    testWidgets('no dingbats with the chips drawn', (tester) async {
      await pumpScreen(tester);
      expectNoDingbats(tester, screen: 'CycleSettingsScreen');
    });

    testWidgets('no dingbats while paused', (tester) async {
      await pumpScreen(
        tester,
        read: Fresh(stored(trackingPaused: true, pauseReason: 'menopause')),
      );
      expectNoDingbats(tester, screen: 'CycleSettingsScreen');
    });
  });
}
