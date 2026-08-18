import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/settings/data/me_repository.dart';

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// The three ratified endometriosis-status codes and the labels screen 4 draws.
///
/// Wire codes from `UserProfileEnc.EndoStatuses`
/// (`backend/src/Lumen.Domain/Entities/UserProfileEnc.cs:68-75`); labels from
/// `Screens/screen_04_baseline.html`'s three `.opt` rows, verbatim. The server
/// compares the code with `StringComparer.Ordinal` and answers 400 for anything
/// else, which is why [fromWireName] matches exactly and never normalises case:
/// a client that folded case would send a value it believed was valid.
///
/// It carries **no default**, and that is the point rather than an omission:
/// an unanswered question stays null, and `not_applicable` is a real answer
/// somebody gave — not the absence of one.
enum EndoStatus {
  diagnosed('diagnosed', 'Diagnosed'),
  suspected('suspected', 'Suspected, undiagnosed'),
  notApplicable('not_applicable', 'Not applicable');

  const EndoStatus(this.wireName, this.label);

  /// The code on the wire.
  final String wireName;

  /// The option's label, verbatim from the mockup.
  final String label;

  /// The member [code] names, or null — including for a code this build has
  /// never seen. The vocabulary is append-only on the server, and reading an
  /// unknown value as "no answer" is the only honest fallback: it sends
  /// nothing for the field, and the endpoint's merge leaves it alone.
  static EndoStatus? fromWireName(String? code) {
    for (final value in values) {
      if (value.wireName == code) return value;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// BaselineAnswers
// ---------------------------------------------------------------------------

/// The four things screen 4 can say about a user.
///
/// A **null means "this screen has no value to send"**, never "clear it": the
/// endpoint merges, so an omitted field leaves the stored one alone and there
/// is no way to clear a baseline field back to null from this client at all
/// (§C.0.1's accepted cost — `int?` cannot distinguish absent from
/// explicit-null under `System.Text.Json`, and `built_value` omits nulls).
///
/// **`rasrmStage` and `diagnosedOn` are deliberately not here.** They are real
/// columns with a real write path (`SaveBaselineRequest` carries both), but the
/// mockup draws no control for either and no label, option or unit for one
/// exists in `definitions.md` — so screen 4 collects neither, and a field here
/// would be a value nothing can set. See the screen's own doc comment.
@immutable
class BaselineAnswers {
  const BaselineAnswers({
    this.dob,
    this.heightCm,
    this.weightKg,
    this.endoStatus,
  });

  /// The date of birth. The screen shows a date and the model stores one — the
  /// mockup's "Age" is derived from it, which is why this is a full date and
  /// not a year: a year-only control would invent a day.
  final Date? dob;

  /// Height in whole centimetres (D-06 is metric-only in v1).
  final int? heightCm;

  /// Weight in kilograms, at most one decimal place.
  final double? weightKg;

  /// The self-reported endometriosis status.
  final EndoStatus? endoStatus;

  /// Whether there is nothing here to send.
  ///
  /// This is what "skip" means on this step: `POST /onboarding/baseline`
  /// answers **400** to a body carrying none of its fields, so a submit with
  /// nothing to say must not reach the network at all.
  bool get isEmpty =>
      dob == null && heightCm == null && weightKg == null && endoStatus == null;

  /// One field replaced. Four named copies rather than one `copyWith`, because
  /// a `copyWith` written the usual way (`dob ?? this.dob`) cannot express
  /// setting a field back to null — and emptying the height field is exactly
  /// that.
  BaselineAnswers withDob(Date? value) => BaselineAnswers(
    dob: value,
    heightCm: heightCm,
    weightKg: weightKg,
    endoStatus: endoStatus,
  );

  BaselineAnswers withHeightCm(int? value) => BaselineAnswers(
    dob: dob,
    heightCm: value,
    weightKg: weightKg,
    endoStatus: endoStatus,
  );

  BaselineAnswers withWeightKg(double? value) => BaselineAnswers(
    dob: dob,
    heightCm: heightCm,
    weightKg: value,
    endoStatus: endoStatus,
  );

  BaselineAnswers withEndoStatus(EndoStatus? value) => BaselineAnswers(
    dob: dob,
    heightCm: heightCm,
    weightKg: weightKg,
    endoStatus: value,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BaselineAnswers &&
          other.dob == dob &&
          other.heightCm == heightCm &&
          other.weightKg == weightKg &&
          other.endoStatus == endoStatus;

  @override
  int get hashCode => Object.hash(dob, heightCm, weightKg, endoStatus);
}

// ---------------------------------------------------------------------------
// BaselineForm
// ---------------------------------------------------------------------------

/// Everything screen 4 renders.
@immutable
class BaselineForm {
  const BaselineForm({
    required this.answers,
    required this.saved,
    this.today,
    this.submitting = false,
    this.failure,
  });

  /// What the user is looking at.
  final BaselineAnswers answers;

  /// What the server is believed to hold — the profile read at first, then
  /// whatever the last successful save re-read back.
  final BaselineAnswers saved;

  /// The user's current day **as the server computes it** (D-12), or null when
  /// that read failed. It is the ONLY bound on the date of birth, and null
  /// means the picker cannot be opened — never that a bound is guessed from the
  /// device clock.
  final Date? today;

  /// Whether `POST /onboarding/baseline` is in flight.
  final bool submitting;

  /// Why the last attempt failed, or why the profile read could not prefill.
  /// Cleared at the start of every new attempt.
  final Failure? failure;

  /// Whether a date of birth can be chosen at all.
  ///
  /// A picker needs an upper bound and the server rejects `dob > today`
  /// (`OnboardingStepsService.cs:172-173`), so without today there is no range
  /// to offer. **There is no lower bound and no age gate** — C-12 makes the
  /// population a design target, not a data-entry gate — so the only thing
  /// missing here is the top of the range.
  bool get canPickDob => today != null;

  /// Whether [day] may be chosen as a date of birth.
  bool canChooseDob(Date day) {
    final bound = today;
    if (bound == null) return false;
    return day.compareTo(bound) <= 0;
  }

  /// The answers that differ from what the server holds **and can travel**.
  ///
  /// A null is dropped rather than sent: on a merge endpoint an absent field
  /// and an explicit null mean the same thing, so a cleared field cannot clear
  /// anything and including it would only risk turning a real change into an
  /// empty body.
  BaselineAnswers get unsent => BaselineAnswers(
    dob: answers.dob == saved.dob ? null : answers.dob,
    heightCm: answers.heightCm == saved.heightCm ? null : answers.heightCm,
    weightKg: answers.weightKg == saved.weightKg ? null : answers.weightKg,
    endoStatus: answers.endoStatus == saved.endoStatus
        ? null
        : answers.endoStatus,
  );

  /// Whether there is anything to post at all.
  bool get hasUnsentAnswers => !unsent.isEmpty;

  BaselineForm copyWith({
    BaselineAnswers? answers,
    BaselineAnswers? saved,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return BaselineForm(
      answers: answers ?? this.answers,
      saved: saved ?? this.saved,
      today: today,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

// ---------------------------------------------------------------------------
// BaselineController
// ---------------------------------------------------------------------------

/// Screen 4's state: the resume, the answers, and the save.
///
/// **Shape: `Notifier<AsyncValue<BaselineForm>>` with a SYNCHRONOUS `build()`.**
/// Classified before it was written, the same way [CycleSetupController] was:
/// this controller loads, but it loads in a microtask that `build()` does not
/// await, so `build()` returns a fixed value and there is no build future for a
/// synchronous `state =` to race. That matters here because every answer on
/// this screen is a synchronous mutation — a picked date, a typed digit, a
/// tapped option — and an `AsyncNotifier` assigns its build result
/// unconditionally when it lands, so the first ones would silently disappear.
/// The other half of the rule is enforced rather than documented: every action
/// below is a no-op until the controller is settled.
///
/// **It never resolves to an error, and that is a decision rather than an
/// omission.** Both reads degrade instead: a failed profile read leaves the
/// answers unknown (nothing is invented, and the endpoint's merge means nothing
/// stored is at risk), and a failed `today` leaves the date-of-birth picker
/// closed. Neither may take the step away, because **this step is skippable and
/// skipping needs no network** — a whole-surface retry would strand an offline
/// user on a screen whose only working action is the one it was hiding.
///
/// `autoDispose`, because the form holds the user's own health answers and the
/// house rule is that such state must not outlive the screen showing it.
class BaselineController extends Notifier<AsyncValue<BaselineForm>> {
  /// Incremented on every build so a read that lands after a rebuild is
  /// discarded rather than overwriting a newer generation's answer.
  int _generation = 0;

  @override
  AsyncValue<BaselineForm> build() {
    final generation = ++_generation;
    // Deferred to a microtask so `state` is never assigned from inside build().
    unawaited(Future<void>.microtask(() => _load(generation)));
    return const AsyncValue<BaselineForm>.loading();
  }

  // ── Resume ────────────────────────────────────────────────────────────────

  /// The two reads screen 4 opens on.
  ///
  /// * `GET /me` — the stored baseline. It is the only read that reports it:
  ///   `GET /onboarding/state` answers `baselineProvided` and nothing else, and
  ///   P4a spliced `dob` / `heightCm` / `latestWeightKg` / `endoStatus` (and
  ///   the two members this screen has no control for) into `MeResponse` for
  ///   exactly this (§C.0.2).
  /// * `GET /cycle/calendar` — the user's today (D-12), the date-of-birth
  ///   picker's upper bound.
  ///
  /// CONCURRENT, not sequential: neither needs the other's answer. Each arm
  /// swallows its own failure, so neither future rejects and `.wait` cannot
  /// raise a `ParallelWaitError`.
  Future<void> _load(int generation) async {
    final (profile, day) = await (_readProfile(), _readToday()).wait;

    if (!ref.mounted || generation != _generation) return;

    final answers = profile.answers;

    state = AsyncValue<BaselineForm>.data(
      BaselineForm(
        answers: answers,
        // What the read says the server holds. A user who resumes and changes
        // nothing therefore presses Continue and walks on without a write —
        // which on a MERGE endpoint is not an optimisation but the difference
        // between observing a value and re-asserting it.
        saved: answers,
        today: day.today,
        // The profile's failure is preferred: it is the one that changed what
        // the user can see. A missing `today` closes one control; a missing
        // profile blanks all four.
        failure: profile.failure ?? day.failure,
      ),
    );
  }

  /// `GET /me`, with its failure captured rather than thrown.
  ///
  /// A **stale** answer is still the user's own profile and the read is
  /// idempotent, so it is used exactly as a fresh one. Note that a P3b-era
  /// cache entry predates all six baseline keys and therefore reads as
  /// "nothing answered" (§C.0.2) — which degrades to an empty form rather than
  /// to a wrong one, and cannot destroy anything, because a field with nothing
  /// in it is a field this screen sends nothing for.
  Future<({BaselineAnswers answers, Failure? failure})> _readProfile() async {
    try {
      final result = await ref.read(meRepositoryProvider).getMe();
      switch (result) {
        case Fresh(:final value) || Stale(:final value):
          return (
            answers: BaselineAnswers(
              dob: value.dob,
              heightCm: value.heightCm,
              // The response names it `latestWeightKg`: weight lives in
              // `body_metrics`, not on the profile (rider 4), so what comes
              // back is the latest live row rather than a profile column.
              weightKg: value.latestWeightKg,
              endoStatus: EndoStatus.fromWireName(value.endoStatus),
            ),
            failure: null,
          );
        case NetworkRequired(:final failure):
          return (answers: const BaselineAnswers(), failure: failure);
      }
    } on Failure catch (failure) {
      return (answers: const BaselineAnswers(), failure: failure);
    } catch (_) {
      return (answers: const BaselineAnswers(), failure: const UnknownFailure());
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

  /// Chooses the date of birth, unless [day] is in the future or there is no
  /// `today` to compare it against.
  ///
  /// **There is no lower bound**, deliberately: C-12 makes the population a
  /// design target and says in terms that it is *not* a data-entry or age gate,
  /// and the server applies no floor either — not even the D-13 backdate floor,
  /// which every real date of birth sits decades below.
  void chooseDob(Date day) {
    final form = state.value;
    if (form == null || !form.canChooseDob(day)) return;
    _write(form.copyWith(answers: form.answers.withDob(day)));
  }

  /// Sets the height in centimetres, or clears what the screen is showing.
  ///
  /// Takes a nullable: emptying the field is a real thing a user does, and the
  /// honest state for it is "this screen has no value to send". It does **not**
  /// clear the stored value — no P4a surface can.
  void setHeightCm(int? centimetres) {
    final form = state.value;
    if (form == null) return;
    _write(form.copyWith(answers: form.answers.withHeightCm(centimetres)));
  }

  /// Sets the weight in kilograms, on the same terms as [setHeightCm].
  ///
  /// The one-decimal rule is **not** applied here: it belongs immediately
  /// before serialisation (`OnboardingRepository.saveBaseline`), and rounding
  /// what a user is still typing would fight the keyboard.
  void setWeightKg(double? kilograms) {
    final form = state.value;
    if (form == null) return;
    _write(form.copyWith(answers: form.answers.withWeightKg(kilograms)));
  }

  /// Chooses the endometriosis status.
  ///
  /// There is no way to un-choose one, and that is the endpoint's limit rather
  /// than an oversight: a merge cannot carry a clear, so an affordance for it
  /// would do nothing.
  void chooseEndoStatus(EndoStatus status) {
    final form = state.value;
    if (form == null) return;
    _write(form.copyWith(answers: form.answers.withEndoStatus(status)));
  }

  /// Applies an answer change and drops whatever the last attempt said about
  /// the answers it replaced.
  void _write(BaselineForm form) {
    state = AsyncValue<BaselineForm>.data(form.copyWith(clearFailure: true));
  }

  // ── Submitting ────────────────────────────────────────────────────────────

  /// Saves whatever changed and walks on.
  ///
  /// **With nothing to send it posts nothing.** That is D-02's skip: this step
  /// is optional, "skip" means not calling the endpoint, and the endpoint
  /// answers **400** (`provide at least one baseline field`) to a body carrying
  /// none of its six — the only endpoint on the P4a surface that does. So an
  /// empty submit is not a request that happens to be empty; it is not a
  /// request. The same line covers a returning user who changed nothing.
  ///
  /// **What it sends is the DIFF**, not the form. The endpoint merges, so an
  /// unchanged field is omitted and the stored column is left alone; echoing
  /// one back would re-assert as a WRITE something this device only ever
  /// observed as a READ, and that read is stale-while-revalidate at a
  /// five-minute TTL.
  Future<void> submit() async {
    final form = state.value;
    // Settled-gate and in-flight guard in one: an action on an unsettled
    // controller is a no-op, and a second press while a save is in flight must
    // not issue a second request.
    if (form == null || form.submitting) return;

    final unsent = form.unsent;
    if (unsent.isEmpty) {
      _advance();
      return;
    }

    // The previous rejection goes NOW, not when the new attempt lands: without
    // this the old banner sits beside the new spinner, telling the user the
    // attempt they are watching has already failed.
    state = AsyncValue<BaselineForm>.data(
      form.copyWith(submitting: true, clearFailure: true),
    );

    BaselineAnswers? saved;
    Failure? rejected;
    try {
      final response = await ref
          .read(onboardingRepositoryProvider)
          .saveBaseline(
            dob: unsent.dob,
            heightCm: unsent.heightCm,
            weightKg: unsent.weightKg,
            endoStatus: unsent.endoStatus?.wireName,
          );
      // The response is the server's RE-READ of the whole stored row rather
      // than an echo of the request, so it is the best answer to "what does the
      // server hold now" — including for the fields this save never sent.
      saved = BaselineAnswers(
        dob: response.dob,
        heightCm: response.heightCm,
        weightKg: response.latestWeightKg,
        endoStatus: EndoStatus.fromWireName(response.endoStatus),
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

    if (!ref.mounted) return;
    final settled = state.value ?? form;

    if (rejected != null) {
      state = AsyncValue<BaselineForm>.data(
        settled.copyWith(submitting: false, failure: rejected),
      );
      return;
    }

    state = AsyncValue<BaselineForm>.data(
      settled.copyWith(submitting: false, answers: saved, saved: saved),
    );

    _advance();
  }

  void _advance() => ref.read(onboardingFlowControllerProvider.notifier).next();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 4's controller.
final baselineControllerProvider =
    NotifierProvider.autoDispose<BaselineController, AsyncValue<BaselineForm>>(
      BaselineController.new,
    );
