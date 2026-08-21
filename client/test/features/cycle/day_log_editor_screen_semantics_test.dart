// The day-log editor as a WIDGET (P4b-T16b) — semantics, controls, and the
// two gestures this surface deliberately does NOT offer.
//
// The controller's own state machine is pinned in
// `application/day_log_editor_controller_test.dart`. What this file pins is
// the half a controller test structurally cannot see:
//
//  * the pain scale is built `allowClear: false` and the mood chips refuse a
//    deselect, so the endpoint's "no clear" is enforced at the CONTROL, not
//    only hoped for;
//  * the note box is SEEDED from the stored note, once, and seeding does not
//    mark it touched — the S-1 wipe shape, made unreachable;
//  * a failure keeps every answer on screen and puts its message directly
//    above the button that failed;
//  * the CTA is disabled with a visible reason rather than round-tripping a
//    request the server can only reject.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/application/day_log_editor_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/day_log_editor_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockCycleRepository extends Mock implements CycleRepository {}

/// What one `logDay` call actually carried.
typedef _DayCall = ({
  int? pain,
  int? mood,
  String? notes,
  bool touchedPain,
  bool touchedMood,
  bool touchedNotes,
});

/// Shows the sheet only once the day view has settled — screen 11's own gate
/// (the affordance lives in the `data` arm of `view.when`).
class _SettledDayHost extends ConsumerWidget {
  const _SettledDayHost({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dayDetailControllerProvider(date));
    if (!view.hasValue) return const SizedBox.shrink();
    return LumenBottomSheet(child: DayLogEditorScreen(date: date));
  }
}

class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

void main() {
  final date = DateTime(2026, 4, 7);
  late _MockCycleRepository repo;

  /// Every `logDay` call the sheet has made, in order.
  ///
  /// Recorded from the invocation rather than read back through mocktail's
  /// `captureAny`: the captured list is ordered by mocktail's own argument
  /// iteration, not by the order the matchers are written, which makes a
  /// positional read of it quietly wrong.
  late List<_DayCall> writes;

  setUp(() {
    repo = _MockCycleRepository();
    writes = <_DayCall>[];
  });

  void stubLogDay({Object? throws, CycleDayLogResponse? body}) {
    when(
      () => repo.logDay(
        date: any(named: 'date'),
        pain: any(named: 'pain'),
        mood: any(named: 'mood'),
        notes: any(named: 'notes'),
        touchedPain: any(named: 'touchedPain'),
        touchedMood: any(named: 'touchedMood'),
        touchedNotes: any(named: 'touchedNotes'),
      ),
    ).thenAnswer((invocation) async {
      writes.add((
        pain: invocation.namedArguments[#pain] as int?,
        mood: invocation.namedArguments[#mood] as int?,
        notes: invocation.namedArguments[#notes] as String?,
        touchedPain: invocation.namedArguments[#touchedPain] as bool,
        touchedMood: invocation.namedArguments[#touchedMood] as bool,
        touchedNotes: invocation.namedArguments[#touchedNotes] as bool,
      ));
      if (throws != null) throw throws;
      return body ?? cycleDayLogFixture();
    });
  }

  /// Mounts the sheet the way screen 11 does: over a day view that has
  /// ALREADY SETTLED.
  ///
  /// The gate is not test scaffolding — it is the production shape. Screen
  /// 11's affordance lives inside `_Body`, which only exists in the `data`
  /// arm, so the editor can never be opened over a loading or failed read.
  /// Mounting the sheet against an unsettled day view here would seed an
  /// empty form from a day that in fact has a log, which is a state the app
  /// cannot reach.
  Future<void> pumpSheet(
    WidgetTester tester, {
    CycleDayLogResponse? log,
  }) async {
    await pumpApp(
      tester,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: _SettledDayHost(date: date),
        ),
      ),
      overrides: [
        cycleRepositoryProvider.overrideWithValue(repo),
        dayDetailControllerProvider(date).overrideWith(
          () => _SettledDayDetail(
            DayDetailView(
              events: const [],
              date: date,
              log: log,
              symptoms: const [],
              symptomsTotal: 0,
            ),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // Chrome and copy
  // ---------------------------------------------------------------------------

  group('the sheet', () {
    testWidgetsWithSemantics('renders no dingbats', (tester) async {
      await pumpSheet(
        tester,
        log: cycleDayLogFixture(pain: 3, mood: 2, notes: 'A note.'),
      );

      expectNoDingbats(tester, screen: 'DayLogEditorScreen');
    });

    testWidgetsWithSemantics(
      'names the DAY it writes, and offers no control that could change it',
      (tester) async {
        await pumpSheet(tester);

        expect(find.text('April 7'), findsOneWidget);
        // No date picker, no calendar, no editable date: the day is the
        // route's path parameter and this endpoint has no move operation, so
        // a control that appeared to change it could only be a lie.
        expect(find.byIcon(Icons.calendar_today), findsNothing);
        expect(find.byIcon(Icons.edit_calendar), findsNothing);
        expect(find.byType(CalendarDatePicker), findsNothing);
        expect(
          find.text('April 7'),
          isNot(
            find.ancestor(
              of: find.text('April 7'),
              matching: find.byType(TextField),
            ),
          ),
        );
        // Exactly ONE text field on this sheet, and it is the note box.
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).maxLines,
          5,
          reason: 'the multiline note box, not a date input',
        );
      },
    );

    testWidgetsWithSemantics(
      'states the MERGE rule where the user can read it before typing',
      (tester) async {
        await pumpSheet(tester);

        expect(find.text(kDayLogEditorMergeNote), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Seeding
  // ---------------------------------------------------------------------------

  group('the form opens on what is already stored', () {
    testWidgetsWithSemantics('the note box is seeded from the stored note', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        log: cycleDayLogFixture(pain: 3, mood: 2, notes: 'stored note'),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'stored note',
      );
    });

    testWidgetsWithSemantics(
      'S-1 — a seeded, never-edited note is NOT sent: saving after touching '
      'only pain leaves touchedNotes false',
      (tester) async {
        stubLogDay();
        await pumpSheet(
          tester,
          log: cycleDayLogFixture(pain: 3, mood: 2, notes: 'stored note'),
        );

        await tester.tap(find.text('7'));
        await tester.pump();
        await tester.tap(find.text(kDayLogEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(writes, hasLength(1));
        expect(
          writes.single.notes,
          'stored note',
          reason:
              'the VALUE reaches the repository — it is the FLAG that stops '
              'it reaching the wire, and asserting null here would test the '
              'wrong layer',
        );
        expect(writes.single.touchedPain, isTrue, reason: 'pain was tapped');
        expect(
          writes.single.touchedNotes,
          isFalse,
          reason:
              'the note was displayed, never edited — showing a value must '
              'not become asserting it',
        );
      },
    );

    testWidgetsWithSemantics('an unlogged day opens with an empty note box '
        'and no selected stop', (tester) async {
      await pumpSheet(tester, log: null);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(
        tester.widget<LumenIntensityScale>(find.byType(LumenIntensityScale)).value,
        isNull,
      );
    });

    testWidgetsWithSemantics('a stored pain of 0 seeds the scale at 0, not at '
        '"not recorded" (D-08)', (tester) async {
      await pumpSheet(tester, log: cycleDayLogFixture(pain: 0, mood: null));

      expect(
        tester.widget<LumenIntensityScale>(find.byType(LumenIntensityScale)).value,
        0,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // The two gestures this surface refuses
  // ---------------------------------------------------------------------------

  group('nothing here pretends a value can be un-logged', () {
    testWidgetsWithSemantics(
      'the pain scale is built with allowClear: false',
      (tester) async {
        await pumpSheet(tester, log: cycleDayLogFixture(pain: 4));

        expect(
          tester
              .widget<LumenIntensityScale>(find.byType(LumenIntensityScale))
              .allowClear,
          isFalse,
          reason:
              'POST /cycle/day/{date} merges and the serializer omits nulls, '
              'so a cleared pain would simply not be sent and the stored '
              'value would come straight back',
        );
      },
    );

    testWidgetsWithSemantics(
      'tapping the selected stop leaves the value alone — the scale does not '
      'go blank and the CTA does not become enabled',
      (tester) async {
        await pumpSheet(tester, log: cycleDayLogFixture(pain: 4, mood: null));

        await tester.tap(find.text('4'));
        await tester.pump();

        expect(
          tester
              .widget<LumenIntensityScale>(find.byType(LumenIntensityScale))
              .value,
          4,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
          reason: 'nothing changed, so there is nothing to save',
        );
      },
    );

    testWidgetsWithSemantics(
      'tapping the SELECTED mood chip is a no-op — it does not deselect and '
      'does not enable the CTA',
      (tester) async {
        await pumpSheet(tester, log: cycleDayLogFixture(pain: null, mood: 3));

        await tester.tap(find.text('Steady'));
        await tester.pump();

        expect(find.text(kDayLogNothingChangedMessage), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      },
    );

    testWidgetsWithSemantics(
      'I-1 — the SELECTED mood chip offers NO tap action, exactly like the '
      'selected pain stop beside it, while the other chips still do',
      (tester) async {
        await pumpSheet(tester, log: cycleDayLogFixture(pain: 4, mood: 3));

        final SemanticsData chosen = tester
            .getSemantics(find.text('Steady'))
            .getSemanticsData();
        expect(
          chosen.hasAction(SemanticsAction.tap),
          isFalse,
          reason:
              'mood cannot be un-logged on this endpoint, so activating this '
              'chip can do nothing — and a control that cannot act must not '
              'announce itself as one that can',
        );
        expect(chosen.flagsCollection.isEnabled, Tristate.isFalse);
        expect(chosen.flagsCollection.isSelected, Tristate.isTrue);

        final SemanticsData other = tester
            .getSemantics(find.text('Bright'))
            .getSemanticsData();
        expect(other.hasAction(SemanticsAction.tap), isTrue);
        expect(other.flagsCollection.isEnabled, Tristate.isTrue);

        // The comparison that failed before fix round 1: the two controls on
        // this ONE sheet now report a refused gesture the same way.
        expect(
          tester
              .getSemantics(find.text('4'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'the allowClear: false stop, for comparison',
        );
      },
    );

    testWidgetsWithSemantics('picking a DIFFERENT mood chip does select it, '
        'and sends the WIRE ordinal, never the list index', (tester) async {
      stubLogDay();
      await pumpSheet(tester, log: null);

      // 'Bright' is the fourth label — wire ordinal 4, list index 3.
      await tester.tap(find.text('Bright'));
      await tester.pump();
      await tester.tap(find.text(kDayLogEditorSaveLabel));
      await tester.pumpAndSettle();

      expect(writes.single.mood, 4);
      expect(writes.single.touchedMood, isTrue);
      expect(
        writes.single.touchedPain,
        isFalse,
        reason: 'the pain scale was never touched on this day',
      );
    });

    testWidgetsWithSemantics(
      'there is no "clear", "remove" or "delete" affordance anywhere on the '
      'sheet',
      (tester) async {
        await pumpSheet(
          tester,
          log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'a note'),
        );

        expect(find.textContaining('Clear'), findsNothing);
        expect(find.textContaining('Remove'), findsNothing);
        expect(find.textContaining('Delete'), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The blocked save (M-7)
  // ---------------------------------------------------------------------------

  group('the CTA', () {
    testWidgetsWithSemantics(
      'opens disabled, with the reason visible beside it',
      (tester) async {
        await pumpSheet(tester, log: cycleDayLogFixture(pain: 4, mood: 2));

        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.text(kDayLogNothingChangedMessage), findsOneWidget);
        expect(find.byType(LumenFieldMessage), findsOneWidget);
      },
    );

    testWidgetsWithSemantics(
      'M-7 — clearing a prefilled note and nothing else keeps the CTA '
      'disabled and shows the reason inline: no request is made',
      (tester) async {
        stubLogDay();
        await pumpSheet(
          tester,
          log: cycleDayLogFixture(pain: null, mood: null, notes: 'a note'),
        );

        await tester.enterText(find.byType(TextField), '');
        await tester.pump();

        expect(find.text(kDayLogEmptyChangeMessage), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(writes, isEmpty);
      },
    );

    testWidgetsWithSemantics('enables as soon as pain 0 is chosen — 0 is a '
        'real answer, never falsiness-tested away', (tester) async {
      await pumpSheet(tester, log: null);

      await tester.tap(find.text('0'));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(find.byType(LumenFieldMessage), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Failure and retry (R9)
  // ---------------------------------------------------------------------------

  group('a failed save', () {
    testWidgetsWithSemantics(
      'keeps every answer on screen, relabels the CTA and puts the message '
      'directly above it — the sheet is never rebuilt or cleared',
      (tester) async {
        stubLogDay(throws: const NetworkFailure());
        await pumpSheet(tester, log: cycleDayLogFixture(pain: 4, mood: 2));

        await tester.tap(find.text('7'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'typed this');
        await tester.pump();
        await tester.tap(find.text(kDayLogEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(find.byType(LumenErrorBanner), findsOneWidget);
        expect(find.text(const NetworkFailure().message), findsOneWidget);
        expect(find.text(kDayLogEditorRetryLabel), findsOneWidget);
        expect(
          tester
              .widget<LumenIntensityScale>(find.byType(LumenIntensityScale))
              .value,
          7,
          reason: 'the answer survives the failure',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'typed this',
        );
        expect(find.text('Steady'), findsOneWidget);

        // T20b's amended S9: the message and the control that produced it are
        // in the same scrollable, adjacent, so the banner cannot scroll away
        // from the retry.
        final bannerY = tester.getBottomLeft(find.byType(LumenErrorBanner)).dy;
        final ctaY = tester.getTopLeft(find.byType(FilledButton)).dy;
        expect(
          ctaY - bannerY,
          lessThan(40),
          reason:
              'the failure message must stay next to the button that failed',
        );
      },
    );

    testWidgetsWithSemantics(
      'the retry is a real button and re-issues exactly one request',
      (tester) async {
        stubLogDay(throws: const NetworkFailure());
        await pumpSheet(tester, log: null);

        await tester.tap(find.text('7'));
        await tester.pump();
        await tester.tap(find.text(kDayLogEditorSaveLabel));
        await tester.pumpAndSettle();

        await expectRetryReissuesOneRequest(
          tester,
          requestCount: () => writes.length,
          label: kDayLogEditorRetryLabel,
        );
      },
    );

    testWidgetsWithSemantics(
      'a 400 keyed `request` renders the server\'s cross-field sentence, not '
      'generic copy',
      (tester) async {
        stubLogDay(
          throws: const ValidationFailure(
            fields: {
              'request': ['at least one of pain, mood or notes is required'],
            },
          ),
        );
        await pumpSheet(tester, log: null);

        await tester.tap(find.text('7'));
        await tester.pump();
        await tester.tap(find.text(kDayLogEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(
          find.text('at least one of pain, mood or notes is required'),
          findsOneWidget,
        );
      },
    );

    testWidgetsWithSemantics(
      'a 400 keyed `date` — the future-day rule, whose key is a ROUTE '
      'parameter with no field on this sheet — is promoted into the banner '
      'rather than dropped',
      (tester) async {
        stubLogDay(
          throws: const ValidationFailure(
            fields: {
              'date': ['date must not be in the future'],
            },
          ),
        );
        await pumpSheet(tester, log: null);

        await tester.tap(find.text('7'));
        await tester.pump();
        await tester.tap(find.text(kDayLogEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(find.text('date must not be in the future'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // In flight
  // ---------------------------------------------------------------------------

  group('while the write is in flight', () {
    testWidgetsWithSemantics(
      'every control is frozen and the sheet refuses to be dismissed',
      (tester) async {
        when(
          () => repo.logDay(
            date: any(named: 'date'),
            pain: any(named: 'pain'),
            mood: any(named: 'mood'),
            notes: any(named: 'notes'),
            touchedPain: any(named: 'touchedPain'),
            touchedMood: any(named: 'touchedMood'),
            touchedNotes: any(named: 'touchedNotes'),
          ),
        ).thenAnswer((_) => Future<CycleDayLogResponse>.delayed(
          const Duration(seconds: 1),
          cycleDayLogFixture,
        ));

        await pumpSheet(tester, log: null);
        await tester.tap(find.text('7'));
        await tester.pump();
        await tester.tap(find.text(kDayLogEditorSaveLabel));
        await tester.pump();

        expect(
          tester
              .widget<LumenIntensityScale>(find.byType(LumenIntensityScale))
              .enabled,
          isFalse,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        final popScope = tester
            .widgetList<PopScope<dynamic>>(find.byType(PopScope<dynamic>))
            .single;
        expect(
          popScope.canPop,
          isFalse,
          reason:
              'the scrim tap and the system back gesture both consult this '
              'freshly; abandoning a committed write leaves every open '
              'screen showing pre-write data',
        );

        await tester.pumpAndSettle(const Duration(seconds: 2));
      },
    );
  });
}
