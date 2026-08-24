// ---------------------------------------------------------------------------
// CycleSettingsController — screen 32's cycle settings (P4b-T22a)
// ---------------------------------------------------------------------------
//
// The read and the write behind screen 32: `GET /settings/cycle` on open and
// `PATCH /settings/cycle` on Save. The PATCH is a **MERGE** — an omitted field
// is left UNCHANGED, and there is no way to clear one at all.
//
// Read `CycleSettingsRepository.updateSettings`'s dartdoc before this file; it
// carries the verified contract. What lives HERE is the state machine, and it
// is built against three rules:
//
//  1. **Only a field the user actually TOUCHED is sent.** [CycleSettingsForm]
//     carries six `touched*` booleans as their OWN explicit state. They are
//     never re-derived from whether the value is null, and the two differ on
//     precisely the input every seeded field starts at: "holding a value the
//     user has not edited".
//
//  2. **The two sanity warnings are an ADVISORY AFTER A SUCCESSFUL SAVE, never
//     a validator.** R-17 is a PO ruling: clinical bounds are estimator-only
//     and NEVER entry blockers, because endometriosis cycles are irregular. A
//     value outside the server's sanity band is **stored** and answered with a
//     200 carrying a non-blocking code, so the save happens first and the note
//     exists only afterwards. Nothing in this file inspects a number's size.
//
//  3. **No clinical bound and no clinical inference lives here** (R-17). The
//     C-03 figures appear nowhere in `client/lib` — not as a validator, not as
//     a constant, not as a numeral in a comment. The band's own edges are a
//     server constant (`CycleSettingsSanityBand`) and are not restated on this
//     side of the wire either.
//
// **The pause triple is NOT here.** `trackingPaused`, `pauseReason` and
// `pausedSince` are screen 32's pause card, which is T22b's. They carry their
// own 400s and their own state machine, and mixing them into this form is how
// a partial-update surface becomes untestable.
//
// **No clock.** Nothing in this file reads `DateTime.now()`; there is no date
// on this surface at all.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';

// ---------------------------------------------------------------------------
// Authored copy
// ---------------------------------------------------------------------------

/// Why Save is disabled until something changes.
///
/// **AUTHORED** — screen 32's mockup draws no Save control at all, so nothing
/// about it is extracted. On the T25 PO copy list.
///
/// **Not `kDayLogNothingChangedMessage` reused.** Screen 11's sentence names
/// its three fields (*"Change pain, mood or the note to save."*); this surface
/// has six, and listing them would be a paragraph. It is also ONE sentence
/// where screen 11 needs two: screen 11 separates "you have not touched
/// anything" from "what you touched would not save anything", because emptying
/// its note box reaches the second state. Here every control that can be
/// touched can only hold a legal value — the two number rows are edited
/// through a dialog whose own Save is inert while the box is empty, and the
/// chips and toggles have no empty state — so the second state is unreachable
/// from the UI and one honest sentence covers the whole block.
///
/// It exists so the user meets the endpoint's all-fields-absent 400
/// (`request`: *"at least one settings field is required"*) as a disabled
/// control with a stated reason rather than as a round trip that can only
/// fail. `goals_screen.dart`'s rule: the reason is never left to be guessed.
const String kCycleSettingsNothingChangedMessage = 'Change a setting to save.';

// ---------------------------------------------------------------------------
// CycleSettingsForm
// ---------------------------------------------------------------------------

/// Everything screen 32 renders and everything it can send.
///
/// Every value member is nullable and seeded straight off the 200 — nothing is
/// defaulted here. A `?? 28` on [avgCycleLengthDays] would put a self-report
/// the user never made in front of them, on a column onboarding also writes.
@immutable
class CycleSettingsForm {
  const CycleSettingsForm({
    this.avgCycleLengthDays,
    this.avgPeriodLengthDays,
    this.regularity,
    this.phasePredictionEnabled,
    this.autoDetectPeriodStartEnabled,
    this.showFertilityWindowEnabled,
    this.touchedAvgCycleLengthDays = false,
    this.touchedAvgPeriodLengthDays = false,
    this.touchedRegularity = false,
    this.touchedPhasePredictionEnabled = false,
    this.touchedAutoDetectPeriodStartEnabled = false,
    this.touchedShowFertilityWindowEnabled = false,
    this.submitting = false,
    this.failure,
    this.warnings = const <String>[],
  });

  /// The form as it opens over [settings] — the whole resource, exactly as the
  /// server sent it.
  ///
  /// **Seeding marks nothing as touched**, which is the whole point: a seeded
  /// value is the server's, not the user's, and asserting it back would be the
  /// lost update this design exists to make unreachable.
  ///
  /// **[CycleSettingsResponse.warnings] is deliberately NOT adopted.** The
  /// server computes the codes on the GET as well as the PATCH, but R3 makes
  /// the note an advisory after a *successful save*, and on open nothing has
  /// been saved. See [CycleSettingsController.submit] for the one place
  /// warnings enter this form. (The cost is recorded in the T22a report: a
  /// value stored in an earlier session never shows its hint, because a second
  /// save of unchanged values is blocked.)
  factory CycleSettingsForm.seededFrom(CycleSettingsResponse settings) {
    return CycleSettingsForm(
      avgCycleLengthDays: settings.avgCycleLengthDays,
      avgPeriodLengthDays: settings.avgPeriodLengthDays,
      regularity: settings.regularity,
      phasePredictionEnabled: settings.phasePredictionEnabled,
      autoDetectPeriodStartEnabled: settings.autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled: settings.showFertilityWindowEnabled,
    );
  }

  /// The self-reported average cycle length, or `null` when unknown.
  /// **Never inspected to decide whether to send it** — see
  /// [touchedAvgCycleLengthDays].
  final int? avgCycleLengthDays;

  /// The self-reported average period length, or `null` — the ordinary state
  /// of a user who has only completed onboarding, which never collects it.
  final int? avgPeriodLengthDays;

  /// One of the three ratified wire codes, or `null` when unknown.
  final String? regularity;

  /// Whether phase predictions are wanted. P6 honours it; P4a only stores it.
  final bool? phasePredictionEnabled;

  /// Whether C-04 `period_start` auto-detection may run once it exists.
  final bool? autoDetectPeriodStartEnabled;

  /// Whether the C-02 fertile-window overlay is shown once it exists.
  final bool? showFertilityWindowEnabled;

  /// Whether the user has changed the average cycle length since the screen
  /// opened — its own explicit state, **not** `avgCycleLengthDays != null`.
  ///
  /// The two shapes differ on exactly one input, and it is the one every
  /// seeded field starts at: a value with no edit behind it.
  /// `if (avgCycleLengthDays != null)` would send that value back, which under
  /// MERGE means re-asserting a possibly-stale read over whatever the server
  /// now holds — on a row `POST /onboarding/cycle` and T22b's pause card also
  /// write.
  ///
  /// **A touched field whose value is `null` keeps the flag `true`**, screen
  /// 11's rule for a prefilled editor: whether there is anything worth sending
  /// is [blockReason]'s question, answered from the flag AND the value
  /// together, at the one place that asks it.
  final bool touchedAvgCycleLengthDays;

  /// Whether the user has changed the average period length.
  final bool touchedAvgPeriodLengthDays;

  /// Whether the user has picked a regularity chip.
  final bool touchedRegularity;

  /// Whether the user has moved the phase-prediction toggle.
  ///
  /// Set by any move, including one that lands back on the seeded value.
  /// "Touched" means the gesture happened; re-sending an unchanged boolean is
  /// a harmless no-op under MERGE, while inferring touched-ness by comparing
  /// against the seed would be the value-derived guard rule 1 forbids.
  final bool touchedPhasePredictionEnabled;

  /// Whether the user has moved the auto-detect toggle.
  final bool touchedAutoDetectPeriodStartEnabled;

  /// Whether the user has moved the fertility-window toggle.
  final bool touchedShowFertilityWindowEnabled;

  /// Whether `PATCH /settings/cycle` is in flight. Every control refuses input
  /// while this is true.
  final bool submitting;

  /// Why the last attempt failed. Cleared the moment the user changes anything
  /// again, or starts a new attempt.
  final Failure? failure;

  /// The frozen `CycleSettingsWarnings` codes the last **successful** save came
  /// back with. Never a rejection: the value was stored.
  final List<String> warnings;

  /// Whether the average cycle length would actually reach the wire.
  ///
  /// Both halves are load-bearing: the flag, because an untouched seed must not
  /// travel; the null check, because the generated serializer omits a null
  /// member, so a "touched" field holding `null` contributes nothing at all.
  bool get _sendsAvgCycleLengthDays =>
      touchedAvgCycleLengthDays && avgCycleLengthDays != null;

  bool get _sendsAvgPeriodLengthDays =>
      touchedAvgPeriodLengthDays && avgPeriodLengthDays != null;

  bool get _sendsRegularity => touchedRegularity && regularity != null;

  bool get _sendsPhasePredictionEnabled =>
      touchedPhasePredictionEnabled && phasePredictionEnabled != null;

  bool get _sendsAutoDetectPeriodStartEnabled =>
      touchedAutoDetectPeriodStartEnabled &&
      autoDetectPeriodStartEnabled != null;

  bool get _sendsShowFertilityWindowEnabled =>
      touchedShowFertilityWindowEnabled && showFertilityWindowEnabled != null;

  /// Why Save is disabled, or `null` when it is enabled.
  ///
  /// Screen 11's and screen 12's shape: one `String?` getter returning a named
  /// module-level constant, rendered straight beside the CTA, with [canSubmit]
  /// defined from it so the two can never disagree.
  ///
  /// **The condition is "nothing would reach the wire", never "the number
  /// looks wrong".** There is no bound here and there must never be one — an
  /// out-of-band length is a legal, saveable answer that the server stores and
  /// merely comments on (R-17).
  String? get blockReason {
    if (_sendsAvgCycleLengthDays ||
        _sendsAvgPeriodLengthDays ||
        _sendsRegularity ||
        _sendsPhasePredictionEnabled ||
        _sendsAutoDetectPeriodStartEnabled ||
        _sendsShowFertilityWindowEnabled) {
      return null;
    }
    return kCycleSettingsNothingChangedMessage;
  }

  bool get canSubmit => blockReason == null;

  CycleSettingsForm copyWith({
    int? avgCycleLengthDays,
    bool clearAvgCycleLengthDays = false,
    int? avgPeriodLengthDays,
    bool clearAvgPeriodLengthDays = false,
    String? regularity,
    bool? phasePredictionEnabled,
    bool? autoDetectPeriodStartEnabled,
    bool? showFertilityWindowEnabled,
    bool? touchedAvgCycleLengthDays,
    bool? touchedAvgPeriodLengthDays,
    bool? touchedRegularity,
    bool? touchedPhasePredictionEnabled,
    bool? touchedAutoDetectPeriodStartEnabled,
    bool? touchedShowFertilityWindowEnabled,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
    List<String>? warnings,
  }) {
    return CycleSettingsForm(
      // Paired `clearX` flags rather than a bare `?? this.x`: without them
      // "set the length to null" and "do not pass a length" would be the same
      // call, and the touched+null state this form must be able to hold would
      // be unreachable.
      avgCycleLengthDays: clearAvgCycleLengthDays
          ? null
          : (avgCycleLengthDays ?? this.avgCycleLengthDays),
      avgPeriodLengthDays: clearAvgPeriodLengthDays
          ? null
          : (avgPeriodLengthDays ?? this.avgPeriodLengthDays),
      regularity: regularity ?? this.regularity,
      phasePredictionEnabled:
          phasePredictionEnabled ?? this.phasePredictionEnabled,
      autoDetectPeriodStartEnabled:
          autoDetectPeriodStartEnabled ?? this.autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled:
          showFertilityWindowEnabled ?? this.showFertilityWindowEnabled,
      touchedAvgCycleLengthDays:
          touchedAvgCycleLengthDays ?? this.touchedAvgCycleLengthDays,
      touchedAvgPeriodLengthDays:
          touchedAvgPeriodLengthDays ?? this.touchedAvgPeriodLengthDays,
      touchedRegularity: touchedRegularity ?? this.touchedRegularity,
      touchedPhasePredictionEnabled:
          touchedPhasePredictionEnabled ?? this.touchedPhasePredictionEnabled,
      touchedAutoDetectPeriodStartEnabled:
          touchedAutoDetectPeriodStartEnabled ??
          this.touchedAutoDetectPeriodStartEnabled,
      touchedShowFertilityWindowEnabled:
          touchedShowFertilityWindowEnabled ??
          this.touchedShowFertilityWindowEnabled,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      warnings: warnings ?? this.warnings,
    );
  }
}

// ---------------------------------------------------------------------------
// CycleSettingsController
// ---------------------------------------------------------------------------

/// Drives screen 32.
///
/// **Shape: an `AsyncNotifier<CycleSettingsForm>` whose `build()` awaits the
/// read** — `DayDetailController`'s and `ProfileController`'s branch of the
/// phase's controller-shape rule, not screen 3's. Screen 3 uses a synchronous
/// `build()` because its step body is rendered *while* the load runs and its
/// chips can be tapped before the read lands, which an `AsyncNotifier` would
/// then overwrite. Here the screen renders a spinner until this future
/// settles, so there is no control for a build result to race.
///
/// **[CacheResult] is unwrapped, not surfaced.** `Fresh` and `Stale` both seed
/// the form and are deliberately indistinguishable to the screen: under MERGE
/// an untouched field is omitted, so a stale seed cannot become a lost update,
/// and staleness stops mattering rather than having to be established. A
/// `NetworkRequired` is thrown, which turns into [AsyncError] and the screen's
/// designed error/retry body — a form with no seed would otherwise show the
/// user settings the server never sent.
///
/// `autoDispose`: the form holds the user's own self-reports, which are health
/// data, and the house rule is that such state does not outlive its screen.
class CycleSettingsController extends AsyncNotifier<CycleSettingsForm> {
  @override
  Future<CycleSettingsForm> build() async {
    final result = await ref.read(cycleSettingsRepositoryProvider).getSettings();
    return switch (result) {
      Fresh(:final value) => CycleSettingsForm.seededFrom(value),
      Stale(:final value) => CycleSettingsForm.seededFrom(value),
      NetworkRequired(:final failure) => throw failure,
    };
  }

  // ── Answering ─────────────────────────────────────────────────────────────

  /// Applies a change and drops whatever the last attempt said about the
  /// values it replaced.
  ///
  /// Both messages this form can hold describe a specific set of answers — a
  /// rejection of them, or a hint about them — so both stop being true the
  /// moment one of them changes. This is the ONLY place warnings are cleared;
  /// see [submit].
  void _write(CycleSettingsForm Function(CycleSettingsForm) change) {
    final form = state.value;
    // Settled-gate and in-flight guard in one: an action on an unsettled
    // controller is a no-op, and a control touched mid-write would be
    // discarded by the response a moment later.
    if (form == null || form.submitting) return;
    state = AsyncValue<CycleSettingsForm>.data(
      change(form).copyWith(clearFailure: true, warnings: const <String>[]),
    );
  }

  /// Records a new average cycle length.
  ///
  /// `null` is **unreachable from this surface** — the row's editor is a
  /// dialog whose own Save is inert while the box is empty, so no gesture
  /// produces one. It is handled rather than asserted because the honest
  /// answer to a `null` is the same one this method gives every other value:
  /// record it, mark the control touched, and let [CycleSettingsForm.
  /// blockReason] decide whether there is anything to send. What must never
  /// happen is a `?? 28`, which would turn "no answer" into a stored
  /// self-report on a MERGE endpoint with no clear.
  void setAvgCycleLengthDays(int? value) {
    _write(
      (form) => form.copyWith(
        avgCycleLengthDays: value,
        clearAvgCycleLengthDays: value == null,
        // Never `value != null` — see
        // [CycleSettingsForm.touchedAvgCycleLengthDays].
        touchedAvgCycleLengthDays: true,
      ),
    );
  }

  /// Records a new average period length. `null` as above.
  void setAvgPeriodLengthDays(int? value) {
    _write(
      (form) => form.copyWith(
        avgPeriodLengthDays: value,
        clearAvgPeriodLengthDays: value == null,
        touchedAvgPeriodLengthDays: true,
      ),
    );
  }

  /// Records a regularity chip tap. [value] MUST be one of the three ratified
  /// WIRE codes; the screen owns the label→code mapping and this method does
  /// not re-derive it.
  void setRegularity(String value) {
    _write(
      (form) => form.copyWith(regularity: value, touchedRegularity: true),
    );
  }

  /// Records a phase-prediction toggle.
  void setPhasePredictionEnabled(bool value) {
    _write(
      (form) => form.copyWith(
        phasePredictionEnabled: value,
        touchedPhasePredictionEnabled: true,
      ),
    );
  }

  /// Records an auto-detect toggle.
  void setAutoDetectPeriodStartEnabled(bool value) {
    _write(
      (form) => form.copyWith(
        autoDetectPeriodStartEnabled: value,
        touchedAutoDetectPeriodStartEnabled: true,
      ),
    );
  }

  /// Records a fertility-window toggle.
  void setShowFertilityWindowEnabled(bool value) {
    _write(
      (form) => form.copyWith(
        showFertilityWindowEnabled: value,
        touchedShowFertilityWindowEnabled: true,
      ),
    );
  }

  // ── Submitting ────────────────────────────────────────────────────────────

  /// Saves whatever was touched. Returns `true` on success, `false` on a
  /// blocked, rejected or already-in-flight attempt.
  ///
  /// **The 200 becomes the new SEED, and that is not a round trip.** The body
  /// is the whole stored resource, so it is the freshest truth this screen can
  /// hold — but it is adopted with every `touched*` flag back to `false`, so
  /// nothing in it can be *asserted* by a later save. Two consequences worth
  /// stating, because a reader will reach for screen 9's rule (refuse the
  /// response outright) unless the difference is written down:
  ///
  ///  * pressing Save again immediately is BLOCKED, not a second request; and
  ///  * the body physically cannot be echoed at the endpoint anyway —
  ///    [CycleSettingsRepository.updateSettings] has no `pauseReason`
  ///    parameter, and `pauseReason` is precisely the member that makes the
  ///    echo a 400 (it survives a resume by design, and the server rejects it
  ///    whenever the effective state is not paused).
  ///
  /// **The warnings are attached only here, only after a 200.** R-17: a value
  /// outside the sanity band is stored and answered with a non-blocking code,
  /// so the save has already happened by the time a hint exists. Nothing on
  /// this path can refuse a save because of a number's size.
  ///
  /// They are deliberately NOT cleared at the start of an attempt. They can
  /// only be non-empty immediately after a warned save, and at that point
  /// every flag is false, so [CycleSettingsForm.blockReason] returns early
  /// above and the only route back into this method is a change — which
  /// [_write] has already cleared them on. A clear here would be a line no
  /// test could ever redden.
  Future<bool> submit() async {
    final form = state.value;
    if (form == null || form.submitting) return false;
    if (form.blockReason != null) return false;

    state = AsyncValue<CycleSettingsForm>.data(
      form.copyWith(submitting: true, clearFailure: true),
    );

    Failure? rejected;
    CycleSettingsResponse? saved;
    try {
      saved = await ref
          .read(cycleSettingsRepositoryProvider)
          .updateSettings(
            avgCycleLengthDays: form.avgCycleLengthDays,
            avgPeriodLengthDays: form.avgPeriodLengthDays,
            regularity: form.regularity,
            phasePredictionEnabled: form.phasePredictionEnabled,
            autoDetectPeriodStartEnabled: form.autoDetectPeriodStartEnabled,
            showFertilityWindowEnabled: form.showFertilityWindowEnabled,
            touchedAvgCycleLengthDays: form.touchedAvgCycleLengthDays,
            touchedAvgPeriodLengthDays: form.touchedAvgPeriodLengthDays,
            touchedRegularity: form.touchedRegularity,
            touchedPhasePredictionEnabled: form.touchedPhasePredictionEnabled,
            touchedAutoDetectPeriodStartEnabled:
                form.touchedAutoDetectPeriodStartEnabled,
            touchedShowFertilityWindowEnabled:
                form.touchedShowFertilityWindowEnabled,
          );
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render — the
      // `goals_controller.dart` / `quick_checkin_controller.dart` precedent
      // (a concurrent cache purge during invalidation, e.g.).
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      // R6 — state preserved intact. Rebuilt from the PRE-submit snapshot, so
      // every answer and every touched flag survives exactly as the user left
      // them and the retry sends the identical request.
      state = AsyncValue<CycleSettingsForm>.data(
        form.copyWith(submitting: false, failure: rejected),
      );
      return false;
    }

    state = AsyncValue<CycleSettingsForm>.data(
      CycleSettingsForm.seededFrom(saved!).copyWith(
        // A body whose `warnings` member is absent is "no warnings", never a
        // third state: the two must not render differently.
        warnings: saved.warnings?.toList() ?? const <String>[],
      ),
    );
    return true;
  }

  // ── Dependents ────────────────────────────────────────────────────────────
  //
  // **A successful save refreshes NO other provider, and that is a decision
  // rather than an omission.** The repository invalidates the
  // `GET:/settings/cycle` cache key, which is the whole of what has gone
  // stale. Measured at the source this session:
  //
  //  * `DashboardController.build` reads `MeRepository.getMe` and
  //    `CycleRepository.getCalendarMonth`; `CycleCalendarController.build`
  //    reads `getCalendarMonth`. Neither touches `/settings/cycle`.
  //  * The phase state both of them render comes from
  //    `CycleCalendarResponse.phase`, which `CycleCalendarService` builds as a
  //    literal `new CyclePhaseAvailabilityResponse(false,
  //    PhaseEngineNotImplemented)` without consulting `user_cycle_settings` at
  //    all. So flipping `phasePredictionEnabled` — the one field that could
  //    plausibly reach a phase readout — changes nothing either screen draws
  //    in P4b. `CycleSettingsResponse.phasesUnavailable` has no reader outside
  //    this feature.
  //  * The only other consumer of the settings read is screen 3's
  //    `CycleSetupController`, which is `autoDispose` and unreachable for an
  //    onboarded user (`lumenRedirect` sends them away from `/onboarding`).
  //
  // Invalidating the dashboard would therefore re-issue three GETs (`/me` plus
  // two calendar months) for data that cannot have changed. `dependents` in
  // `cycle_settings_controller_test.dart` pins the absence with both providers
  // alive and counting, so re-adding an invalidation reddens a test rather
  // than passing unnoticed.
  //
  // If a later phase gives either screen something derived from these
  // settings, the shape to add is the shipped one: `ref.invalidate`
  // UNCONDITIONALLY (never wrapped in `ref.exists` — P4b-T20b traced riverpod
  // 3.3.2 and proved that variant inert), and `ref.exists` **and** `hasValue`
  // guarding only a `refresh()`.
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 32's controller.
final cycleSettingsControllerProvider =
    AsyncNotifierProvider.autoDispose<
      CycleSettingsController,
      CycleSettingsForm
    >(CycleSettingsController.new);
