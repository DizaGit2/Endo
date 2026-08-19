import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';

// ---------------------------------------------------------------------------
// Vocabularies
// ---------------------------------------------------------------------------

/// The three ratified regularity codes and the labels screen 3 draws.
///
/// Wire codes from `UserCycleSettings.RegularityValues`; labels from
/// `Screens/screen_03_cycle_setup.html` and `definitions.md`. The server
/// compares the code with `StringComparer.Ordinal` and answers 400 for anything
/// else, which is why [fromWireName] matches exactly and never normalises case:
/// a client that folded case would send a value it believed was valid.
///
/// It carries **no default**. Screen 3's `somewhat` comes back from
/// `GET /settings/cycle` — the server applies it when the row is created — so
/// there is nothing here to drift from `UserCycleSettings.RegularityValues.Default`.
enum CycleRegularity {
  regular('regular', 'Regular'),
  somewhat('somewhat', 'Somewhat'),
  irregular('irregular', 'Irregular');

  const CycleRegularity(this.wireName, this.label);

  /// The code on the wire.
  final String wireName;

  /// The chip label, verbatim from the mockup.
  final String label;

  /// The member [code] names, or null — including for a code this build has
  /// never seen. The vocabulary is closed today, but reading an unknown value
  /// as "no answer" is the only honest fallback.
  static CycleRegularity? fromWireName(String? code) {
    for (final value in values) {
      if (value.wireName == code) return value;
    }
    return null;
  }
}

/// What the two frozen `CycleSettingsWarnings` codes say to a user.
///
/// The codes are wire constants with **no user-facing string authored
/// anywhere** (survey §4-OQ6). These two sentences were written by the
/// orchestrator for this task and are product copy about how the app behaves —
/// not a clinical claim, and deliberately not a number: the band's edges are a
/// server constant (`CycleSettingsSanityBand`) that must not be restated on
/// this side of the wire, and the C-03 clinical figures must not exist here at
/// all — not as a validator, not as a constant, not as a numeral in a comment.
///
/// **An unknown code answers null**, and that is load-bearing rather than
/// defensive: the vocabulary is append-only on the server, so a third code
/// WILL arrive at a build that has never seen it. Inventing a sentence for it
/// would be authoring copy about behaviour nobody has described — and
/// [CycleSetupController.submit] reads this same function to decide whether
/// there is anything to hold the step for, so an unrenderable code cannot
/// strand the user on a page with nothing new on it.
///
/// It lives beside the controller rather than in the screen because both need
/// it, and the screen already depends on this file.
String? cycleWarningMessage(String code) => switch (code) {
  'avg_cycle_length_out_of_sanity_band' =>
    "Saved. That cycle length is unusual — double-check the number if it "
        "wasn't intended.",
  'avg_period_length_out_of_sanity_band' =>
    "Saved. That period length is unusual — double-check the number if it "
        "wasn't intended.",
  _ => null,
};

/// The five average-cycle-length quick picks the mockup draws.
///
/// **Quick picks over a free integer, not a closed enum.** The column is a
/// positive `smallint` and screen 32 sets values outside this list, so a stored
/// answer that is not one of these five is legitimate and screen 3 shows it
/// rather than pretending it does not exist. The C-03 clinical bounds
/// (clinician-UNSIGNED) are deliberately nowhere in this file, in this feature,
/// or anywhere under `lib/`.
const List<int> kAvgCycleLengthQuickPicks = <int>[26, 27, 28, 29, 30];

// ---------------------------------------------------------------------------
// CycleAnswers
// ---------------------------------------------------------------------------

/// The three things screen 3 can say about a user's cycle.
///
/// A **null means "this screen has no value to send"**, not "clear it": the
/// endpoint merges, so an omitted field leaves the stored one alone. That
/// distinction is the whole reason this is a separate type — it is compared
/// whole against the last answers the server acknowledged, which is what lets a
/// second Continue walk on instead of re-posting.
@immutable
class CycleAnswers {
  const CycleAnswers({
    this.lastPeriodStart,
    this.avgCycleLengthDays,
    this.regularity,
  });

  /// The period anchor. Required by the endpoint on every post, so a null here
  /// means the screen cannot submit at all yet.
  final Date? lastPeriodStart;

  /// The self-reported average cycle length, or null when the screen does not
  /// know it (the settings read failed) and therefore must not send one.
  final int? avgCycleLengthDays;

  /// The self-reported regularity, on the same terms.
  final CycleRegularity? regularity;

  CycleAnswers copyWith({
    Date? lastPeriodStart,
    int? avgCycleLengthDays,
    CycleRegularity? regularity,
  }) {
    return CycleAnswers(
      lastPeriodStart: lastPeriodStart ?? this.lastPeriodStart,
      avgCycleLengthDays: avgCycleLengthDays ?? this.avgCycleLengthDays,
      regularity: regularity ?? this.regularity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CycleAnswers &&
          other.lastPeriodStart == lastPeriodStart &&
          other.avgCycleLengthDays == avgCycleLengthDays &&
          other.regularity == regularity;

  @override
  int get hashCode =>
      Object.hash(lastPeriodStart, avgCycleLengthDays, regularity);
}

// ---------------------------------------------------------------------------
// CycleSetupForm
// ---------------------------------------------------------------------------

/// Everything screen 3 renders.
@immutable
class CycleSetupForm {
  const CycleSetupForm({
    required this.answers,
    required this.saved,
    required this.visibleMonth,
    this.today,
    this.submitting = false,
    this.failure,
    this.warnings = const <String>[],
  });

  /// What the user is looking at.
  final CycleAnswers answers;

  /// What the server is believed to hold — the two resume reads at first, then
  /// whatever the last successful save echoed back.
  final CycleAnswers saved;

  /// The first day of the month the calendar is showing.
  final DateTime visibleMonth;

  /// The user's current day **as the server computes it** (D-12), or null when
  /// that read failed. Null means no future-date bound is drawn — never that
  /// one is guessed from the device clock.
  final Date? today;

  /// Whether `POST /onboarding/cycle` is in flight.
  final bool submitting;

  /// Why the last attempt failed, or why the settings read could not prefill.
  /// Cleared at the start of every new attempt.
  final Failure? failure;

  /// The frozen `CycleSettingsWarnings` codes the last **successful** save came
  /// back with. Never a rejection: the value was stored.
  final List<String> warnings;

  /// Whether the answers on screen are exactly the ones the server acknowledged.
  bool get isSaved => answers == saved;

  /// Whether a day may be chosen: the server rejects `lastPeriodStart > today`,
  /// and with no today there is no bound to apply.
  bool canChoose(Date day) {
    final bound = today;
    if (bound == null) return true;
    return day.compareTo(bound) <= 0;
  }

  /// Whether the calendar can move forward — false once it is showing the
  /// month that holds today, every later day being unselectable.
  bool get canShowNextMonth {
    final bound = today;
    if (bound == null) return true;
    return visibleMonth.isBefore(DateTime(bound.year, bound.month));
  }

  CycleSetupForm copyWith({
    CycleAnswers? answers,
    CycleAnswers? saved,
    DateTime? visibleMonth,
    bool? submitting,
    Failure? failure,
    List<String>? warnings,
    bool clearFailure = false,
  }) {
    return CycleSetupForm(
      answers: answers ?? this.answers,
      saved: saved ?? this.saved,
      visibleMonth: visibleMonth ?? this.visibleMonth,
      today: today,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      warnings: warnings ?? this.warnings,
    );
  }
}

// ---------------------------------------------------------------------------
// CycleSetupController
// ---------------------------------------------------------------------------

/// Screen 3's state: the resume, the answers, and the save.
///
/// **Shape: `Notifier<AsyncValue<CycleSetupForm>>` with a SYNCHRONOUS
/// `build()`.** Classified before it was written, the same way
/// [OnboardingFlowController] was: this controller loads, but it loads in a
/// microtask that `build()` does not await, so `build()` returns a fixed value
/// and there is no build future for a synchronous `state =` to race. That
/// matters here because almost everything the screen does is a synchronous
/// mutation — every chip tap, every day, every month step — and an
/// `AsyncNotifier` assigns its build result unconditionally when it lands, so
/// the first taps would silently disappear. The other half of the rule is
/// enforced rather than documented: every action below is a no-op until the
/// controller is settled.
///
/// `autoDispose`, because the form holds the user's own health answers and the
/// house rule is that such state must not outlive the screen showing it.
class CycleSetupController extends Notifier<AsyncValue<CycleSetupForm>> {
  /// Incremented on every build so a read that lands after a rebuild is
  /// discarded rather than overwriting a newer generation's answer.
  int _generation = 0;

  @override
  AsyncValue<CycleSetupForm> build() {
    final generation = ++_generation;
    // Deferred to a microtask so `state` is never assigned from inside build().
    unawaited(Future<void>.microtask(() => _load(generation)));
    return const AsyncValue<CycleSetupForm>.loading();
  }

  // ── Resume ────────────────────────────────────────────────────────────────

  /// The two-call resume, plus the one call that answers "today".
  ///
  /// * `GET /onboarding/state` — **already made by the shell**, so the anchor
  ///   is read off the settled flow rather than fetched again. It is the only
  ///   one of the four values that endpoint reports.
  /// * `GET /settings/cycle` — the other two. Without it the screen would draw
  ///   the server's defaults over answers the user had already given, which is
  ///   the exact state the endpoint's merge semantics exist to prevent.
  /// * `GET /cycle/calendar` — the user's today (D-12), for the month the
  ///   calendar opens on and the days it refuses.
  ///
  /// Each degrades on its own terms. A failed settings read leaves both
  /// self-reports **unknown**, so nothing is sent for them and nothing stored
  /// is overwritten. A failed today leaves the future-date bound off — the
  /// server still enforces it. Only the combination of no anchor **and** no
  /// today is fatal, because then there is no month to open the calendar on and
  /// the only thing left to derive one from is the device clock.
  Future<void> _load(int generation) async {
    // The shell renders a step body only in its `data` arm, so the flow is
    // settled here by construction.
    final resumeAnchor = ref
        .read(onboardingFlowControllerProvider)
        .value
        ?.state
        .lastPeriodStart;

    // CONCURRENT, not sequential. Neither read needs the other's answer, and
    // this is the one mandatory step of onboarding — running them in series
    // doubles the time it shows nothing but a spinner. Each arm swallows its
    // own failure, so neither future rejects and `.wait` cannot raise a
    // `ParallelWaitError`.
    final (settings, day) = await (_readSettings(), _readToday()).wait;

    if (!ref.mounted || generation != _generation) return;

    final avgCycleLengthDays = settings.avgCycleLengthDays;
    final regularity = settings.regularity;
    final settingsFailure = settings.failure;
    final today = day.today;
    final todayFailure = day.failure;

    final anchorMonth = resumeAnchor ?? today;
    if (anchorMonth == null) {
      state = AsyncValue<CycleSetupForm>.error(
        todayFailure ?? settingsFailure ?? const UnknownFailure(),
        StackTrace.current,
      );
      return;
    }

    final answers = CycleAnswers(
      lastPeriodStart: resumeAnchor,
      avgCycleLengthDays: avgCycleLengthDays,
      regularity: regularity,
    );

    state = AsyncValue<CycleSetupForm>.data(
      CycleSetupForm(
        answers: answers,
        // What the two reads say the server holds. A user who resumes and
        // changes nothing therefore presses Continue and walks on without a
        // redundant write.
        saved: answers,
        visibleMonth: DateTime(anchorMonth.year, anchorMonth.month),
        today: today,
        failure: settingsFailure,
      ),
    );
  }

  /// `GET /settings/cycle`, with its failure captured rather than thrown.
  Future<
    ({int? avgCycleLengthDays, CycleRegularity? regularity, Failure? failure})
  >
  _readSettings() async {
    try {
      final result = await ref
          .read(cycleSettingsRepositoryProvider)
          .getSettings();
      switch (result) {
        // A stale answer is still the user's own settings and the read is
        // idempotent, so it is used exactly as a fresh one. What it must NOT do
        // is get written back — see the diff in [submit].
        case Fresh(:final value) || Stale(:final value):
          return (
            avgCycleLengthDays: value.avgCycleLengthDays,
            regularity: CycleRegularity.fromWireName(value.regularity),
            failure: null,
          );
        case NetworkRequired(:final failure):
          return (avgCycleLengthDays: null, regularity: null, failure: failure);
      }
    } on Failure catch (failure) {
      return (avgCycleLengthDays: null, regularity: null, failure: failure);
    } catch (_) {
      return (
        avgCycleLengthDays: null,
        regularity: null,
        failure: const UnknownFailure(),
      );
    }
  }

  /// `GET /cycle/calendar`'s `today`, with its failure captured rather than
  /// thrown.
  Future<({Date? today, Failure? failure})> _readToday() async {
    try {
      return (
        today: await ref.read(serverTodayRepositoryProvider).today(),
        failure: null,
      );
    } on Failure catch (failure) {
      return (today: null, failure: failure);
    } catch (_) {
      return (today: null, failure: const UnknownFailure());
    }
  }

  // ── Answering ─────────────────────────────────────────────────────────────

  /// Chooses the period anchor, unless [day] is in the future.
  ///
  /// The bound is the server's `today` or there is none — the calendar simply
  /// stops offering days it cannot accept. It is not a validator and it blocks
  /// no submit; the server's own rule (`lastPeriodStart > today` → 400) remains
  /// the one that decides.
  void chooseDay(Date day) {
    final form = state.value;
    if (form == null || !form.canChoose(day)) return;
    _write(form.copyWith(answers: form.answers.copyWith(lastPeriodStart: day)));
  }

  /// Chooses the average cycle length.
  ///
  /// Takes a plain integer rather than a member of [kAvgCycleLengthQuickPicks]:
  /// the column is a free positive `smallint` and the chips are quick picks
  /// over it, so a stored value from screen 32 is chooseable here too.
  void chooseCycleLength(int days) {
    final form = state.value;
    if (form == null) return;
    _write(
      form.copyWith(answers: form.answers.copyWith(avgCycleLengthDays: days)),
    );
  }

  /// Chooses the self-reported regularity.
  void chooseRegularity(CycleRegularity regularity) {
    final form = state.value;
    if (form == null) return;
    _write(
      form.copyWith(answers: form.answers.copyWith(regularity: regularity)),
    );
  }

  /// Shows the month before the one on screen.
  void showPreviousMonth() {
    final form = state.value;
    if (form == null) return;
    state = AsyncValue<CycleSetupForm>.data(
      form.copyWith(
        visibleMonth: DateTime(
          form.visibleMonth.year,
          form.visibleMonth.month - 1,
        ),
      ),
    );
  }

  /// Shows the month after the one on screen, unless that is past today.
  void showNextMonth() {
    final form = state.value;
    if (form == null || !form.canShowNextMonth) return;
    state = AsyncValue<CycleSetupForm>.data(
      form.copyWith(
        visibleMonth: DateTime(
          form.visibleMonth.year,
          form.visibleMonth.month + 1,
        ),
      ),
    );
  }

  /// Applies an answer change and drops whatever the last attempt said about
  /// the answers it replaced.
  ///
  /// Both messages this screen can hold describe a specific set of answers — a
  /// rejection of them, or a hint about them — so both stop being true the
  /// moment one of them changes. This is the ONLY place warnings are cleared;
  /// see [submit].
  void _write(CycleSetupForm form) {
    state = AsyncValue<CycleSetupForm>.data(
      form.copyWith(clearFailure: true, warnings: const <String>[]),
    );
  }

  // ── Submitting ────────────────────────────────────────────────────────────

  /// Saves the answers and walks on.
  ///
  /// **It sends the anchor and only the answers the screen is showing.** The
  /// endpoint merges, so an unknown self-report is omitted and the stored one
  /// survives; filling one in from a default is what silently reset a user's
  /// own answer when they came back to correct a mistyped date.
  ///
  /// **The sanity band is not a validator.** An out-of-band length is stored
  /// and answered with a 200 carrying a warning code, so the save has already
  /// happened by the time the hint exists. The step therefore holds, once, to
  /// show it — and a Continue pressed on unchanged answers walks on **without**
  /// re-posting, because a re-post would return the same warning and turn the
  /// hint into the entry blocker it must never be.
  Future<void> submit() async {
    final form = state.value;
    // Settled-gate and in-flight guard in one: an action on an unsettled
    // controller is a no-op, and a second press while a save is in flight must
    // not issue a second request.
    if (form == null || form.submitting) return;

    final anchor = form.answers.lastPeriodStart;
    // The one mandatory answer of onboarding (D-02) and the one field the
    // endpoint requires on every post. The CTA is disabled without it; this is
    // the same rule at the only place that can enforce it.
    if (anchor == null) return;

    if (form.isSaved) {
      _advance();
      return;
    }

    // The previous rejection goes NOW, not when the new attempt lands: without
    // this the old banner sits beside the new spinner, telling the user the
    // attempt they are watching has already failed.
    //
    // The warnings are deliberately NOT cleared here. They can only be
    // non-empty immediately after a successful warned save, and at that point
    // `answers == saved`, so the only route back into this line is an answer
    // change — which [_write] has already cleared them on. A clear here would
    // be a line no test could ever redden.
    state = AsyncValue<CycleSetupForm>.data(
      form.copyWith(submitting: true, clearFailure: true),
    );

    // Read BEFORE the await, and held across it, FOR THE RECORD ONLY. `ref.read`
    // on a disposed controller throws, and a step controller can be disposed
    // while its request is open. [_advance] deliberately keeps reading the
    // notifier fresh through `ref`: a held reference does NOT resurrect a
    // provider that has since been disposed, so using one for navigation would
    // turn a self-healing `ref.read` into a throw.
    final OnboardingFlowController flowForRecord = ref.read(
      onboardingFlowControllerProvider.notifier,
    );

    OnboardingCycleSaved? saved;
    Failure? rejected;
    try {
      final response = await ref
          .read(onboardingRepositoryProvider)
          .saveCycle(
            lastPeriodStart: anchor,
            // DIFFS, not values. A self-report that still equals what was READ
            // is omitted, so the endpoint's merge leaves the stored column
            // alone. Echoing one back would re-assert as a WRITE something this
            // device only ever observed as a READ — and that read is
            // stale-while-revalidate at a five-minute TTL, so the `29` on
            // screen can be a cache entry served after a failed refresh while
            // screen 32 on another device set `31`. A save of "only the date"
            // would then quietly drag it back to 29.
            avgCycleLengthDays:
                form.answers.avgCycleLengthDays == form.saved.avgCycleLengthDays
                ? null
                : form.answers.avgCycleLengthDays,
            regularity: form.answers.regularity == form.saved.regularity
                ? null
                : form.answers.regularity?.wireName,
            // The day the server currently holds the anchor on, so the write
            // can drop the cached calendar the anchor is leaving.
            previousLastPeriodStart: form.saved.lastPeriodStart,
          );
      saved = OnboardingCycleSaved(
        // The response echoes the RESOLVED values, which is how the screen can
        // show a 28 the user never typed. Falling back to what was sent covers
        // the nullable-everything contract (§C.0.2) rather than blanking an
        // answer the user just gave.
        answers: CycleAnswers(
          lastPeriodStart: response.lastPeriodStart ?? anchor,
          avgCycleLengthDays:
              response.avgCycleLengthDays ?? form.answers.avgCycleLengthDays,
          regularity:
              CycleRegularity.fromWireName(response.regularity) ??
              form.answers.regularity,
        ),
        warnings: response.warnings?.toList() ?? const <String>[],
      );
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render.
      // `cachedWrite` invalidates its keys unguarded after a successful write,
      // so a concurrent logout purge closing the Hive box lands here — after
      // the answer was stored. Leaving it unhandled would be a spinner that
      // never stops and a banner that never appears.
      rejected = const UnknownFailure();
    }

    // BEFORE the disposal gate, deliberately, and outside the warning branch
    // below. The shell's copy of `GET /onboarding/state` still holds the anchor
    // this save replaced, and this controller is autoDispose: walking off this
    // step and back would rebuild the form out of that stale value.
    // `lastPeriodStart` is REQUIRED on every post, so the anchor on screen
    // rides along with any later save of this step — a stale one is not a stale
    // view, it is a corrected date dragged back.
    //
    // The gate would otherwise leave that loss in a narrower window: Back
    // during the save disposes this controller and the 200 lands anyway. The
    // flow outlives the step — it is the SHELL's state — so recording onto it
    // is valid precisely when this controller is gone. A warned save has stored
    // just as much as an unwarned one, which is why this sits above `_advance`
    // rather than inside it.
    if (rejected == null) {
      flowForRecord.recordCycleSaved(saved!.answers.lastPeriodStart);
    }

    if (!ref.mounted) return;
    final settled = state.value ?? form;

    if (rejected != null) {
      state = AsyncValue<CycleSetupForm>.data(
        settled.copyWith(submitting: false, failure: rejected),
      );
      return;
    }

    state = AsyncValue<CycleSetupForm>.data(
      settled.copyWith(
        submitting: false,
        answers: saved!.answers,
        saved: saved.answers,
        warnings: saved.warnings,
      ),
    );

    // Hold the step only for a hint the user can actually SEE. `warnings` keeps
    // everything the server sent — that is the truth about the response — but a
    // code this build cannot render puts nothing on screen, and stopping for it
    // would leave the user looking at an unchanged page wondering why Continue
    // did nothing. The vocabulary is append-only, so a third code is a matter
    // of when, not if.
    if (!saved.warnings.any(_isRenderable)) _advance();
  }

  /// Whether [code] has copy to show. See [cycleWarningMessage].
  static bool _isRenderable(String code) => cycleWarningMessage(code) != null;

  void _advance() => ref.read(onboardingFlowControllerProvider.notifier).next();
}

/// What a successful `POST /onboarding/cycle` left the screen holding.
@immutable
class OnboardingCycleSaved {
  const OnboardingCycleSaved({required this.answers, required this.warnings});

  /// The values the server echoed back, resolved.
  final CycleAnswers answers;

  /// The frozen warning codes, in the server's stable order.
  final List<String> warnings;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 3's controller.
final cycleSetupControllerProvider =
    NotifierProvider.autoDispose<
      CycleSetupController,
      AsyncValue<CycleSetupForm>
    >(CycleSetupController.new);
