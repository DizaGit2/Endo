import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';

// ---------------------------------------------------------------------------
// OnboardingFlow
// ---------------------------------------------------------------------------

/// Where the user is in onboarding, and everything screens 3-7 need to render
/// it.
///
/// [state] is the `GET /onboarding/state` response **whole**, not a narrowing
/// of it: screens 3-7 prefill from four different parts of it
/// (`lastPeriodStart`, `goals`, `hormones`, `notifications`), so a flow that
/// carried only the landing step would send each of those five tasks back to
/// the network for data the shell has already read.
@immutable
class OnboardingFlow {
  const OnboardingFlow({
    required this.step,
    required this.state,
    this.submitting = false,
    this.failure,
  });

  /// The step being shown.
  final OnboardingStep step;

  /// The resume read, unnarrowed.
  final OnboardingStateResponse state;

  /// Whether `POST /onboarding/complete` is in flight.
  final bool submitting;

  /// Why the last attempt to finish failed, or null.
  ///
  /// Cleared at the start of every new attempt, so a rejected submit can never
  /// be re-reported against a later one.
  final Failure? failure;

  OnboardingFlow copyWith({
    OnboardingStep? step,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return OnboardingFlow(
      step: step ?? this.step,
      state: state,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnboardingFlow &&
          other.step == step &&
          other.state == state &&
          other.submitting == submitting &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(step, state, submitting, failure);
}

// ---------------------------------------------------------------------------
// OnboardingFlowController
// ---------------------------------------------------------------------------

/// The onboarding shell's state: which step is showing, and what finishing did.
///
/// **Shape: `Notifier<AsyncValue<OnboardingFlow>>` with a SYNCHRONOUS
/// `build()`.** This controller does load — but it loads in a microtask that
/// `build()` does not await, exactly as [OnboardingStatusController] does, so
/// `build()` returns a fixed value and there is no build future for a
/// synchronous `state =` to race. That matters here more than anywhere: an
/// `AsyncNotifier` assigns its build result unconditionally when it lands, so a
/// rejection or a step change written first is silently dropped and the finish
/// button looks dead. The other half of the rule is enforced below rather than
/// documented: [goTo] and [complete] are **no-ops until the controller is
/// settled**, so an action taken during the resume read cannot be half-applied.
///
/// Lifecycle:
/// - built once per `/onboarding` mount (`autoDispose`) — the flow holds the
///   user's own health answers, so it must not outlive the screen that shows
///   them, the same rule `ProfileController` follows;
/// - the resume read runs once and resolves to the step the user left off on;
/// - if the server reports onboarding already complete, the router's gate is
///   opened rather than leaving the user inside a flow they have finished;
/// - `POST /onboarding/complete` opens the gate through
///   [OnboardingStatusController.markCompleted], so the user is not bounced
///   back into the flow while the cached profile is still stale.
class OnboardingFlowController extends Notifier<AsyncValue<OnboardingFlow>> {
  /// The machine-readable 409 code for a premature completion.
  ///
  /// A wire string (`OnboardingConflict.IncompleteCode`), matched exactly — the
  /// server sends it as a problem-details extension and `error_mapper.dart`
  /// lifts it onto [ConflictFailure.code].
  static const String incompleteCode = 'onboarding_incomplete';

  /// Incremented on every build so a read that lands after a rebuild is
  /// discarded rather than overwriting a newer generation's answer.
  int _generation = 0;

  @override
  AsyncValue<OnboardingFlow> build() {
    final generation = ++_generation;
    // Deferred to a microtask so `state` is never assigned from inside build().
    unawaited(Future<void>.microtask(() => _load(generation)));
    return const AsyncValue<OnboardingFlow>.loading();
  }

  // ── Resume ────────────────────────────────────────────────────────────────

  Future<void> _load(int generation) async {
    late final AsyncValue<OnboardingFlow> resolved;
    OnboardingStateResponse? loaded;

    try {
      final result = await ref.read(onboardingRepositoryProvider).getState();
      switch (result) {
        // A stale answer is still the user's own flow, and the read is
        // idempotent — treating it as an error would strand a user whose
        // network dropped mid-onboarding on a retry screen for data already in
        // hand.
        case Fresh(:final value) || Stale(:final value):
          loaded = value;
          resolved = AsyncValue<OnboardingFlow>.data(
            OnboardingFlow(step: resumeStepFrom(value), state: value),
          );
        case NetworkRequired(:final failure):
          resolved = AsyncValue<OnboardingFlow>.error(
            failure,
            StackTrace.current,
          );
      }
    } on Failure catch (failure, stack) {
      resolved = AsyncValue<OnboardingFlow>.error(failure, stack);
    } catch (error, stack) {
      resolved = AsyncValue<OnboardingFlow>.error(error, stack);
    }

    if (!ref.mounted || generation != _generation) return;

    // The gate, not the flow: the user has already finished, so the honest
    // answer is to let them out rather than to show them step 3 again. Done
    // before `state =` so the router is re-evaluated in the same turn.
    if (loaded != null && loaded.completed == true) {
      ref.read(onboardingStatusProvider.notifier).markCompleted();
    }

    state = resolved;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Shows [step], and drops whatever the last attempt to finish said.
  ///
  /// A no-op until the resume read has landed: there is no flow to move yet,
  /// and writing one would be a guess the load is about to overwrite.
  ///
  /// **[clearFailure] is not tidiness — [complete] itself creates the state it
  /// prevents.** A premature finish on step 7 answers 409, and this controller
  /// routes the user to the step that owes the answer *carrying the banner that
  /// says so*. Once they answer it and walk on, that message is describing a
  /// condition they have already fixed: without this it would still be on
  /// screen at steps 4, 5, 6 and 7, asserting something false. The banner
  /// belongs to the step the 409 sent the user to, and to no other.
  ///
  /// The 409's own routing therefore does NOT go through here — [complete]
  /// writes the step and the failure together, deliberately.
  void goTo(OnboardingStep step) {
    final flow = state.value;
    if (flow == null || flow.step == step) return;
    state = AsyncValue<OnboardingFlow>.data(
      flow.copyWith(step: step, clearFailure: true),
    );
  }

  /// Shows the next step, or stays put on the last one.
  void next() {
    final step = state.value?.step.next;
    if (step != null) goTo(step);
  }

  /// Shows the previous step, or stays put on the first one.
  ///
  /// The first step has nowhere to go back to: screen 2 created an account that
  /// now exists, so "back" out of the shell would offer to create it again.
  void back() {
    final step = state.value?.step.previous;
    if (step != null) goTo(step);
  }

  // ── Finishing ─────────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/complete` and opens the router's gate on success.
  ///
  /// **The 409 is the interesting path.** A premature completion answers
  /// `code: onboarding_incomplete` with `missingSteps: ["cycle"]`, and a
  /// conflict the user cannot act on is just a dead button — so the named step
  /// becomes the step the shell shows, and the server's own message is held on
  /// the flow for the screen to surface. Neither is read from
  /// `DioException.response.data`: `error_mapper.dart` lifted both onto
  /// [ConflictFailure] and this is their first consumer.
  ///
  /// A conflict that names no step this client knows leaves the user where they
  /// are. `missingSteps` is append-only on the server, and sending someone to a
  /// guessed screen on the strength of a code this build has never seen is
  /// worse than showing them the message.
  Future<void> complete() async {
    final flow = state.value;
    // Settled-gate + in-flight guard, in one line: an action on an unsettled
    // controller is a no-op, and a second press while the first is in flight
    // must not issue a second request.
    if (flow == null || flow.submitting) return;

    state = AsyncValue<OnboardingFlow>.data(
      flow.copyWith(submitting: true, clearFailure: true),
    );

    // Two arms, like `_load`'s, and the second one is load-bearing. `on Failure`
    // alone leaves anything that is NOT a typed failure escaping as an
    // unhandled async error with `submitting` still true and `failure` still
    // null — a spinner that never stops and a banner that never appears. That
    // is reachable, not theoretical: `cachedWrite` invalidates its keys
    // UNGUARDED after a successful write (unlike `cachedRead`, which treats a
    // cache write as best-effort), so a concurrent logout-purge closing the
    // Hive box throws a `HiveError` here — after the account was completed
    // server-side. Retrying is safe and is what the settled state below allows:
    // a repeat `POST /onboarding/complete` answers 200 with the original
    // timestamp and `alreadyCompleted: true`, never a 409.
    Failure? rejected;
    try {
      await ref.read(onboardingRepositoryProvider).complete();
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render.
      // `UnknownFailure`'s shipped message is what every other unclassifiable
      // error in the app already says.
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return;

    if (rejected != null) {
      final settled = state.value ?? flow;
      state = AsyncValue<OnboardingFlow>.data(
        settled.copyWith(
          submitting: false,
          failure: rejected,
          // Only a recognised 409 moves anyone. `_stepFor` answers null for
          // everything else, including the wrapped non-Failure above.
          step: _stepFor(rejected) ?? settled.step,
        ),
      );
      return;
    }

    // Before `state =`: the gate is what lets the router move the user off this
    // screen, and this controller is autoDispose — the flow it is about is on
    // its way out.
    ref.read(onboardingStatusProvider.notifier).markCompleted();

    final settled = state.value ?? flow;
    state = AsyncValue<OnboardingFlow>.data(
      settled.copyWith(submitting: false, clearFailure: true),
    );
  }

  /// The step a 409 says still owes an answer, or null.
  OnboardingStep? _stepFor(Failure failure) {
    if (failure is! ConflictFailure) return null;
    if (failure.code != incompleteCode) return null;
    for (final name in failure.missingSteps) {
      final step = OnboardingStep.fromWireName(name);
      if (step != null) return step;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// The onboarding shell's controller.
///
/// `autoDispose`, deliberately: the flow holds the resume read, which is the
/// user's own health answers, and per the house rule that state must not
/// outlive the screen showing it.
final onboardingFlowControllerProvider =
    NotifierProvider.autoDispose<
      OnboardingFlowController,
      AsyncValue<OnboardingFlow>
    >(OnboardingFlowController.new);
