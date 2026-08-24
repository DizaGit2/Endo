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
//  2. **The two sanity warnings are an ADVISORY, and NEVER a blocker.** R-17
//     is a PO ruling: clinical bounds are estimator-only and NEVER entry
//     blockers, because endometriosis cycles are irregular. A value outside
//     the server's sanity band is **stored** and answered with a 200 carrying
//     a non-blocking code. Nothing in this file inspects a number's size.
//
//     **They render on LOAD as well as after a save** (T22a fix round 1,
//     amending R3's "after a save"). The server computes the codes on the GET
//     too, and `CycleSettingsResponse.Warnings`' own contract doc says why:
//     *"because screen 32 shows the hint when it loads and not only after a
//     save"*. Dropping the read's codes made the hint unreachable for exactly
//     the user it exists for — someone whose bad value was stored in an
//     earlier session, who sees nothing on open and cannot re-save an
//     unchanged form past the empty-body block. Both seeds therefore carry
//     them; [CycleSettingsForm.seededFrom] is the ONE place they are adopted.
//
//  3. **No clinical bound and no clinical inference lives here** (R-17). The
//     C-03 figures appear nowhere in `client/lib` — not as a validator, not as
//     a constant, not as a numeral in a comment. The band's own edges are a
//     server constant (`CycleSettingsSanityBand`) and are not restated on this
//     side of the wire either.
//
//  4. **The C-12 pause sub-flow arrived at P4b-T22b, and it is a SECOND write
//     on the same row rather than six more fields on the first.** The two sets
//     cannot be sent together: a `pauseReason` that arrives while the
//     effective state is not paused is a 400, and the resumed user's own 200
//     is exactly that body. `CycleSettingsRepository` therefore exposes three
//     methods with disjoint parameter sets and no way to combine them; read
//     its class dartdoc for the guard. Here, the consequences are:
//
//       * **`trackingPaused` is the state; `pauseReason` never is**
//         ([CycleSettingsForm.trackingPaused]);
//       * a pause 200 is adopted for its pause fields ONLY
//         ([CycleSettingsForm.afterPauseSaved]), so it cannot discard an
//         unsaved settings edit;
//       * the two writes never overlap, and at most one failure is on the
//         form at a time ([CycleSettingsForm.pauseFailure]).
//
// **`pausedSince` is NOT here, and is not on the wire either.** The server
// defaults it to the caller's own user-local today; this client neither reads
// nor sends it. That is also what keeps the no-clock rule below true.
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

/// Why the pause control is disabled until a reason is picked.
///
/// **AUTHORED** — screen 32's mockup draws no pause card at all, so every
/// string in the sub-flow is new. On the T25 PO copy list.
///
/// **It states a requirement, and says nothing about any reason.** R4: the
/// five C-12 members are a vocabulary, not a diagnosis, and C-12 is PO-interim
/// with the clinician sign-off still pending — so no copy on this screen
/// characterises what a reason means, and nothing about `pregnancy` beyond the
/// word itself.
///
/// The requirement is the server's, at the transition into paused:
/// `CycleSettingsService.Validate` answers `pauseReason: required` when an
/// unpaused user is moved to paused with no reason in the request, because
/// *"an unpaused user is never paused for a reason they did not name in this
/// request — the remembered reason is a screen-32 pre-selection, not
/// consent"*. This message is that rule met as a disabled control with a
/// stated reason rather than a round trip that can only fail
/// (`goals_screen.dart`'s rule).
///
/// **There is no counterpart for RESUMING, and there must never be one.** R1 /
/// C-12: resume is unconditional for every reason including `pregnancy`.
const String kCycleSettingsChooseReasonMessage = 'Choose a reason to pause.';

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
    this.trackingPaused = false,
    this.pauseReason,
    this.selectedPauseReason,
    this.submitting = false,
    this.pausing = false,
    this.failure,
    this.pauseFailure,
    this.warnings = const <String>[],
  });

  /// The form as it opens over [settings] — the whole resource, exactly as the
  /// server sent it.
  ///
  /// **Seeding marks nothing as touched**, which is the whole point: a seeded
  /// value is the server's, not the user's, and asserting it back would be the
  /// lost update this design exists to make unreachable.
  ///
  /// **[CycleSettingsResponse.warnings] IS adopted, from either seed** — the
  /// read on open and the 200 after a save both come through here, and this is
  /// the only place the codes enter the form.
  ///
  /// The server computes them on the GET as well as the PATCH, on the STORED
  /// values, precisely so this screen can show the hint on arrival. Adopting
  /// them here does not make them a blocker: [blockReason] cannot see them,
  /// and a seeded form has every `touched*` flag false, so the codes describe
  /// values the server already holds rather than anything about to be sent.
  ///
  /// A body whose `warnings` member is ABSENT is "no warnings", never a third
  /// state — the two must not render differently.
  ///
  /// The clear is [CycleSettingsController._write]'s: the moment the user
  /// changes one of these values, a hint about them stops being true.
  factory CycleSettingsForm.seededFrom(CycleSettingsResponse settings) {
    return CycleSettingsForm(
      avgCycleLengthDays: settings.avgCycleLengthDays,
      avgPeriodLengthDays: settings.avgPeriodLengthDays,
      regularity: settings.regularity,
      phasePredictionEnabled: settings.phasePredictionEnabled,
      autoDetectPeriodStartEnabled: settings.autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled: settings.showFertilityWindowEnabled,
      // R2 — the STATE is the flag. `pauseReason` is carried alongside it and
      // is never consulted to answer "is this user paused"; see
      // [trackingPaused] and [pauseReason].
      trackingPaused: settings.trackingPaused ?? false,
      pauseReason: settings.pauseReason,
      // …and the remembered reason is used for exactly what the server says it
      // is for: pre-selecting the chip this user last chose.
      selectedPauseReason: settings.pauseReason,
      warnings: settings.warnings?.toList() ?? const <String>[],
    );
  }

  /// This form after a successful `PATCH` from the SETTINGS save.
  ///
  /// The 200 is the whole stored resource and becomes the new seed — with the
  /// pause card's pending [selectedPauseReason] carried across, because
  /// nothing in that request concerned it. Without the carry-over, tapping a
  /// reason chip and then saving an unrelated setting would silently reset the
  /// chip to whatever the server remembers.
  CycleSettingsForm afterSettingsSaved(CycleSettingsResponse saved) {
    return CycleSettingsForm.seededFrom(
      saved,
    ).copyWith(selectedPauseReason: selectedPauseReason);
  }

  /// This form after a successful pause or resume.
  ///
  /// **Only the pause state is adopted.** The six values and their `touched*`
  /// flags survive untouched, so a pause can never discard an answer the user
  /// has typed but not yet saved — the response's copies of them are the
  /// server's, and adopting them would be the same lost update the touched
  /// flags exist to prevent. [warnings] is left alone for the same reason: it
  /// describes the STORED values, which this request did not change, and the
  /// user may be holding edits that already made it stale.
  ///
  /// `pauseReason` is adopted with `??`, which cannot clear it — and that is
  /// the contract, not a convenience: `ReconcilePauseAsync`'s resume arm
  /// leaves the column alone on purpose (*"row.PauseReason is deliberately
  /// left alone"*), so a null here means "the server said nothing new", never
  /// "forget it".
  CycleSettingsForm afterPauseSaved(CycleSettingsResponse saved) {
    return copyWith(
      trackingPaused: saved.trackingPaused ?? false,
      pauseReason: saved.pauseReason,
      selectedPauseReason: saved.pauseReason,
      pausing: false,
      clearPauseFailure: true,
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

  /// **Whether cycle tracking is paused — the ONE field that answers that
  /// question.**
  ///
  /// Never [pauseReason] `!= null`. `CycleSettingsResponse.PauseReason`'s own
  /// contract doc: the reason for the most recent pause *"survives a resume on
  /// purpose"*, and *"there is deliberately no CHECK tying it to
  /// TrackingPaused"* — so **a non-null reason does not mean the user is
  /// paused**. A client that read it as one would show every resumed user as
  /// paused forever, with a Resume control they had already used.
  final bool trackingPaused;

  /// The reason for the user's MOST RECENT pause, which the server keeps after
  /// a resume so this screen can pre-select it. Read [trackingPaused] for the
  /// state; this is a memory, not a status.
  final String? pauseReason;

  /// The reason chip currently picked in the pause card, or `null` when none
  /// is. Seeded from [pauseReason] — that is what the server keeps it for —
  /// and it is what [CycleSettingsController.pause] sends.
  ///
  /// It is **not** a `touched*` flag's twin: nothing decides from it whether a
  /// field is omitted from a merge body. It is the argument of a request that
  /// either happens or does not.
  final String? selectedPauseReason;

  /// Whether the SETTINGS `PATCH /settings/cycle` is in flight. Every control
  /// refuses input while this is true.
  final bool submitting;

  /// Whether the PAUSE `PATCH /settings/cycle` is in flight. Both writes hit
  /// the same row, so neither may start while the other is running.
  final bool pausing;

  /// Why the last SETTINGS attempt failed. Cleared the moment the user changes
  /// anything again, or starts a new attempt of either kind.
  final Failure? failure;

  /// Why the last PAUSE or RESUME attempt failed.
  ///
  /// **At most one of [failure] and this is ever non-null**: starting either
  /// attempt clears both. Two simultaneous "this did not work" banners would
  /// be two explanations on one screen and — since both CTAs relabel to
  /// `Try again` — two controls with the same accessible name, which
  /// `findRetryAffordance` could not tell apart either.
  final Failure? pauseFailure;

  /// The frozen `CycleSettingsWarnings` codes the last SEED carried — the read
  /// on open, or a successful save. Never a rejection: the values are stored.
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

  /// Why the pause control is disabled, or `null` when it is enabled.
  ///
  /// **Gated on [trackingPaused], and there is exactly one condition.**
  ///
  ///  * Paused → `null`, always. **R1 / C-12: resume is unconditional for
  ///    every reason, `pregnancy` included** (*"resume is user-controlled and
  ///    always available for every pause reason"*; the contract repeats it —
  ///    *"no gate, no confirmation, not even for pregnancy"*). There is
  ///    deliberately no branch here that can look at [pauseReason].
  ///  * Not paused → blocked until a reason is named, because the server
  ///    requires one on the transition in.
  String? get pauseBlockReason {
    if (trackingPaused) return null;
    if (selectedPauseReason == null) return kCycleSettingsChooseReasonMessage;
    return null;
  }

  bool get canTogglePause => pauseBlockReason == null;

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
    bool? trackingPaused,
    String? pauseReason,
    String? selectedPauseReason,
    bool? submitting,
    bool? pausing,
    Failure? failure,
    bool clearFailure = false,
    Failure? pauseFailure,
    bool clearPauseFailure = false,
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
      trackingPaused: trackingPaused ?? this.trackingPaused,
      // No paired `clearX` for either of these, and that is the contract
      // rather than an omission: the server never clears `pauseReason` (its
      // resume arm leaves the column alone on purpose), and the pause card
      // offers no deselect, so neither value can legitimately go back to null.
      pauseReason: pauseReason ?? this.pauseReason,
      selectedPauseReason: selectedPauseReason ?? this.selectedPauseReason,
      submitting: submitting ?? this.submitting,
      pausing: pausing ?? this.pausing,
      failure: clearFailure ? null : (failure ?? this.failure),
      pauseFailure: clearPauseFailure
          ? null
          : (pauseFailure ?? this.pauseFailure),
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
    final result = await ref
        .read(cycleSettingsRepositoryProvider)
        .getSettings();
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
    // discarded by the response a moment later. Both writes on this row count
    // — a pause is as much a write as a save.
    if (form == null || form.submitting || form.pausing) return;
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
    _write((form) => form.copyWith(regularity: value, touchedRegularity: true));
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
  ///    whenever the effective state is not paused). P4b-T22b writes the same
  ///    row through the same endpoint and keeps that true rather than
  ///    inheriting it: `pauseTracking` sends `trackingPaused: true` as a
  ///    literal, `resumeTracking` takes no arguments at all, and neither can
  ///    carry one of these six values back.
  ///
  /// **The warnings come in with the seed, here and on the read alike** —
  /// [CycleSettingsForm.seededFrom] adopts them, so a warned save and a warned
  /// open reach the screen by the same route. R-17: a value outside the sanity
  /// band is stored and answered with a non-blocking code, so nothing on this
  /// path can refuse a save because of a number's size.
  ///
  /// They are deliberately NOT cleared at the start of an attempt, and the
  /// reason is now an invariant rather than a convenience: a form that can
  /// submit at all has had at least one `touched*` flag set, every setter goes
  /// through [_write], and [_write] clears the warnings — so `warnings` is
  /// ALWAYS empty by the time this method is reachable. Equivalently: warnings
  /// non-empty means nothing is touched, which means
  /// [CycleSettingsForm.blockReason] is non-null. A clear here would be a line
  /// no test could ever redden, and
  /// the in-flight states the ordering test samples are warning-free for a
  /// structural reason rather than an accidental one.
  Future<bool> submit() async {
    final form = state.value;
    if (form == null || form.submitting || form.pausing) return false;
    if (form.blockReason != null) return false;

    state = AsyncValue<CycleSettingsForm>.data(
      form.copyWith(
        submitting: true,
        clearFailure: true,
        // Both, so at most one banner is ever on screen — see
        // [CycleSettingsForm.pauseFailure].
        clearPauseFailure: true,
      ),
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
      // them and the retry sends the identical request. `clearPauseFailure`
      // because that snapshot also carries whatever the pause card last said,
      // and only one message may be on the form at a time
      // ([CycleSettingsForm.pauseFailure]).
      state = AsyncValue<CycleSettingsForm>.data(
        form.copyWith(
          submitting: false,
          failure: rejected,
          clearPauseFailure: true,
        ),
      );
      return false;
    }

    // The whole seed, warnings included — one adoption site for both the read
    // and the write, so a mutation that drops the codes reddens both. The
    // pause card's pending chip is the one thing carried across; see
    // [CycleSettingsForm.afterSettingsSaved].
    state = AsyncValue<CycleSettingsForm>.data(form.afterSettingsSaved(saved!));
    return true;
  }

  // ── The C-12 pause sub-flow ───────────────────────────────────────────────

  /// Records a reason chip tap. [code] MUST be one of the five ratified WIRE
  /// codes; the screen owns the label→code mapping, exactly as it does for
  /// regularity.
  ///
  /// A no-op while paused: the card draws no chips in that state, because
  /// changing the reason of a pause in progress is a second gesture with its
  /// own failure mode that C-12 does not ask for. Resume, then pause again.
  void selectPauseReason(String code) {
    final form = state.value;
    if (form == null || form.trackingPaused) return;
    _write(
      (f) => f.copyWith(selectedPauseReason: code, clearPauseFailure: true),
    );
  }

  /// Pauses cycle tracking with the selected reason. Returns `true` on
  /// success, `false` on a blocked, rejected or already-in-flight attempt.
  ///
  /// The reason travels **because this request is itself pausing** — R3, and
  /// the coupling is structural rather than remembered:
  /// `CycleSettingsRepository.pauseTracking` sends `trackingPaused: true` as a
  /// literal and is the only method with a reason parameter at all.
  Future<bool> pause() {
    final form = state.value;
    if (form == null) return Future<bool>.value(false);
    final reason = form.selectedPauseReason;
    if (form.trackingPaused || reason == null) {
      return Future<bool>.value(false);
    }
    return _pauseWrite(
      () => ref
          .read(cycleSettingsRepositoryProvider)
          .pauseTracking(reason: reason),
    );
  }

  /// Resumes cycle tracking. Returns `true` on success.
  ///
  /// **Nothing gates this and nothing may.** R1 / C-12: resume is
  /// unconditional for every one of the five reasons, `pregnancy` included —
  /// no confirmation, no second question, and no branch anywhere in this file
  /// that reads [CycleSettingsForm.pauseReason] to decide. The only refusal is
  /// the in-flight one every write on this row shares.
  Future<bool> resume() {
    final form = state.value;
    if (form == null || !form.trackingPaused) {
      return Future<bool>.value(false);
    }
    return _pauseWrite(
      ref.read(cycleSettingsRepositoryProvider).resumeTracking,
    );
  }

  /// The write half both [pause] and [resume] share: one in-flight gate, one
  /// failure slot, one adoption rule.
  ///
  /// On failure the form is rebuilt from the PRE-write snapshot, so the user's
  /// selection and every settings edit survive and a retry sends the identical
  /// request — [submit]'s rule, for [submit]'s reason.
  Future<bool> _pauseWrite(
    Future<CycleSettingsResponse> Function() write,
  ) async {
    final form = state.value;
    if (form == null || form.submitting || form.pausing) return false;

    state = AsyncValue<CycleSettingsForm>.data(
      form.copyWith(pausing: true, clearFailure: true, clearPauseFailure: true),
    );

    Failure? rejected;
    CycleSettingsResponse? saved;
    try {
      saved = await write();
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render —
      // [submit]'s precedent, for its reason.
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      // `clearFailure` even though the attempt cleared it on the way in: this
      // arm rebuilds from the PRE-write snapshot, which still holds whatever
      // the settings save last said. Without it the one-message invariant
      // would hold only until a save failed and a pause failed after it —
      // and the tests found exactly that.
      state = AsyncValue<CycleSettingsForm>.data(
        form.copyWith(
          pausing: false,
          clearFailure: true,
          pauseFailure: rejected,
        ),
      );
      return false;
    }

    state = AsyncValue<CycleSettingsForm>.data(form.afterPauseSaved(saved!));
    return true;
  }

  // ── Dependents ────────────────────────────────────────────────────────────
  //
  // **A successful save refreshes NO other provider, and that is a decision
  // rather than an omission — and P4b-T22b re-measured it for the PAUSE
  // writes rather than inheriting the answer.** Pausing is the one change on
  // this row that could plausibly reach another screen, since
  // `CycleSettingsResponse.phasesUnavailable` is
  // `trackingPaused || !phasePredictionEnabled`. It does not, in this phase:
  // that member still has no reader anywhere in `client/lib`, and
  // `CyclePhaseAvailability.TrackingPaused` is declared and reserved for P6
  // (`CycleContracts.cs` says so at the site) — P4a's calendar answers the
  // literal `phase_engine_not_implemented` and never consults
  // `user_cycle_settings`. `dependents — the pause sub-flow` in
  // `cycle_settings_controller_test.dart` pins that across a pause AND a
  // resume, with both providers alive and counting.
  //
  // The repository invalidates the
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
