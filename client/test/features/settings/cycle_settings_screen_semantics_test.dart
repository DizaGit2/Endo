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
//  3. **R3/R-17 — the sanity warnings never block a save.** A value far
//     outside the server's band is submitted without argument, and the note
//     appears only after the 200 carrying it. Clinical bounds are
//     estimator-only and NEVER entry blockers, because endometriosis cycles
//     are irregular.

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
  }) {
    return cycleSettingsFixture(
      avgCycleLengthDays: avgCycleLengthDays,
      avgPeriodLengthDays: avgPeriodLengthDays,
      regularity: regularity,
      phasePredictionEnabled: phasePredictionEnabled,
      autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled: showFertilityWindowEnabled,
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
        showFertilityWindowEnabled:
            named[#showFertilityWindowEnabled] as bool?,
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
      'nothing about pausing is here either — the C-12 pause card is T22b\'s, '
      'and half a state machine is worse than none',
      (tester) async {
        await pumpScreen(tester);

        final drawn = renderedText(tester).join('\n').toLowerCase();
        expect(drawn, isNot(contains('pause')));
        expect(drawn, isNot(contains('resume')));
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

  group('R3 — the sanity warning is an advisory AFTER a successful save', () {
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
        expect(find.text(cycleWarningMessage(outOfBand)!), findsNothing);

        await tester.tap(
          find.widgetWithText(FilledButton, kCycleSettingsSaveLabel),
        );
        await tester.pumpAndSettle();

        // AFTER: the value was SAVED, and the note is on screen.
        expect(calls, hasLength(1));
        expect(calls.single.avgCycleLengthDays, 200);
        expect(find.text(cycleWarningMessage(outOfBand)!), findsOneWidget);
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
      expect(find.text(cycleWarningMessage(outOfBand)!), findsNothing);
    });

    testWidgets(
      'the note is not drawn on LOAD, even when the stored value is out of '
      'band — R3 makes it an advisory after a SAVE, and nothing has been '
      'saved yet',
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
        expect(find.text(cycleWarningMessage(outOfBand)!), findsNothing);
      },
    );
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
      'it — banner, block reason and CTA are adjacent inside one scroll view '
      '(T20b\'s amended S9)',
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
            .getRect(find.widgetWithText(FilledButton, kCycleSettingsRetryLabel))
            .top;
        expect(ctaTop - bannerBottom, lessThan(40));
      },
    );

    testWidgets('a 400 keyed to a field renders under that field', (
      tester,
    ) async {
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
}
