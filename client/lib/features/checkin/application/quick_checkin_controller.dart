// ---------------------------------------------------------------------------
// QuickCheckinController — screen 9's form state (P4b-T18)
// ---------------------------------------------------------------------------
//
// `POST /checkin/quick` has no clear affordance: nothing this screen writes
// can ever be removed by the user, on any screen, in any later phase. A six-
// agent survey of this one task (`.superpowers/sdd/lumen-build/survey-t18/`)
// found eleven distinct paths by which it could write a value the user never
// entered — that is the risk this controller is built to close, not data
// loss. A lost value can be re-entered; an invented one is permanent.
//
// The rules this file exists to enforce (brief's own numbering):
//  1. Never send a field the user did not touch — [QuickCheckinForm.touchedPain]
//     / `.touchedMood` are their OWN explicit state, never derived from
//     whether [QuickCheckinForm.pain]/`.mood` happens to be null.
//  2. No `?? 0` anywhere near pain or mood — both stay `int?` end to end.
//  3. No non-nullable form field — same reason.
//  4. No prefill — [build] reads nothing. A prefilled value combined with
//     rule 1 would give the property "you can only overwrite what you
//     actually touched"; this controller keeps that property the simpler
//     way, by never prefilling at all.
//  5. CTA-only save, never save-on-change — [setPain]/[setMood] only ever
//     update [state]; nothing here calls [submit] on their behalf.
//  6. [QuickCheckinForm.canSubmit] is false until something is touched — the
//     screen must gate its CTA on it and must not default pain to make it
//     always true.
//  7. The 200 body is never adopted into form state — [submit] discards
//     [CheckinRepository.quickCheckin]'s return value entirely; the screen
//     pops the sheet on success rather than re-rendering from it.
//  8. Mood is 1-based on the wire; [setMood] takes the WIRE ordinal
//     (1..[kMoodLabels].length), and the screen must pass `index + 1`, never
//     a bare list index.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/checkin/data/checkin_repository.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';

// ---------------------------------------------------------------------------
// QuickCheckinForm
// ---------------------------------------------------------------------------

/// Everything screen 9 renders and everything it can send.
@immutable
class QuickCheckinForm {
  const QuickCheckinForm({
    this.pain,
    this.mood,
    this.touchedPain = false,
    this.touchedMood = false,
    this.submitting = false,
    this.failure,
  });

  /// The pain scale's current value — `0..10`, or `null` for "not touched
  /// this session". **Never inspected to decide whether to send it** — see
  /// [touchedPain].
  final int? pain;

  /// The mood grid's current value — the WIRE ordinal `1..4`, or `null`.
  /// **Never inspected to decide whether to send it** — see [touchedMood].
  final int? mood;

  /// Whether the user has interacted with the pain scale THIS session — its
  /// own explicit state, not `pain != null`. [LumenIntensityScale]'s clear
  /// gesture reports `null` for a field the user DID touch (and chose to
  /// leave unrecorded again); that is still represented here as
  /// `touchedPain: false`, because the wire effect of "touched, cleared back
  /// to null" and "never touched" is identical (both omit the field), and
  /// collapsing them is what makes rule 6's CTA-disables-again behaviour
  /// correct.
  final bool touchedPain;

  /// Whether the user has interacted with the mood grid this session.
  final bool touchedMood;

  /// Whether `POST /checkin/quick` is in flight. Every control on screen 9
  /// refuses taps while this is true (`goals_controller.dart:298`'s
  /// precedent).
  final bool submitting;

  /// Why the last attempt failed. Cleared the moment the user touches
  /// anything again, or starts a new attempt.
  final Failure? failure;

  /// Whether there is anything to send. D-11's own rule
  /// (`at least one of pain or mood is required`) is mirrored here so the
  /// CTA does not round-trip a request the server would 400 — and, just as
  /// importantly, is NEVER satisfied by defaulting pain to make this always
  /// true: it is satisfied only by an actual touch.
  bool get canSubmit => touchedPain || touchedMood;

  QuickCheckinForm copyWith({
    int? pain,
    bool clearPain = false,
    int? mood,
    bool clearMood = false,
    bool? touchedPain,
    bool? touchedMood,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return QuickCheckinForm(
      pain: clearPain ? null : (pain ?? this.pain),
      mood: clearMood ? null : (mood ?? this.mood),
      touchedPain: touchedPain ?? this.touchedPain,
      touchedMood: touchedMood ?? this.touchedMood,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

// ---------------------------------------------------------------------------
// QuickCheckinController
// ---------------------------------------------------------------------------

/// Drives screen 9.
///
/// **Shape: a plain `Notifier<QuickCheckinForm>` with a synchronous
/// `build()`.** Rule 4 (no prefill) makes this the empty-build case per the
/// phase's controller-shape rule: [build] makes no read at all, so there is
/// no build future that a synchronous mutation (a tapped stop, a tapped mood
/// tile) could race — the same reasoning `GoalsController` documents for
/// itself.
///
/// `autoDispose`: the form holds the user's own unsent pain/mood answers,
/// which is health data — the house rule elsewhere in this phase
/// (`ProfileController`, `GoalsController`, `CycleCalendarController`) is
/// that such state must not outlive the screen showing it.
class QuickCheckinController extends Notifier<QuickCheckinForm> {
  @override
  QuickCheckinForm build() => const QuickCheckinForm();

  // ── Answering ─────────────────────────────────────────────────────────

  /// Records a pain-scale tap. [value] is [LumenIntensityScale]'s own report
  /// — `int?`, where `null` means the clear gesture fired.
  ///
  /// A no-op while a save is in flight (rule 5's CTA-only save is guarded at
  /// the screen too, via `enabled: !form.submitting`; this is the second,
  /// controller-level guard the same shape `GoalsController.toggle` uses).
  void setPain(int? value) {
    if (state.submitting) return;
    state = state.copyWith(
      pain: value,
      clearPain: value == null,
      touchedPain: value != null,
      clearFailure: true,
    );
  }

  /// Records a mood-tile tap. [value] MUST be the WIRE ordinal (`1..4`),
  /// never a zero-based list index — the caller (the screen) is responsible
  /// for the `index + 1` translation; this method does not re-derive it,
  /// because doing so here would hide the exact off-by-one fabrication path
  /// the brief names (a selectable grid built on a bare list index writes
  /// `low` when the user tapped `tired`).
  void setMood(int value) {
    if (state.submitting) return;
    state = state.copyWith(mood: value, touchedMood: true, clearFailure: true);
  }

  // ── Submitting ────────────────────────────────────────────────────────

  /// Saves whatever was touched. Returns `true` on success, `false` on a
  /// rejected/failed attempt — the screen pops the sheet only on `true`.
  ///
  /// **Never adopts the response.** The 200 echoes the STORED row, not the
  /// request — a pain-only check-in can come back with a `mood` the caller
  /// never sent (`CycleDayService.cs:187`; live proof `CycleDayLiveTests.cs
  /// :215`). Patching that into [state] would make an echoed field
  /// indistinguishable from user input on the NEXT save. This method reads
  /// [CheckinRepository.quickCheckin]'s return value only to learn which day
  /// to invalidate (inside the repository) and discards it otherwise.
  Future<bool> submit() async {
    final form = state;
    if (form.submitting) return false;
    if (!form.canSubmit) return false;

    state = form.copyWith(submitting: true, clearFailure: true);

    Failure? rejected;
    try {
      final today = await ref.read(sessionTodayProvider.future);
      await ref
          .read(checkinRepositoryProvider)
          .quickCheckin(
            pain: form.pain,
            mood: form.mood,
            touchedPain: form.touchedPain,
            touchedMood: form.touchedMood,
            fallbackDay: today.toDateTime(),
          );
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render.
      // `goals_controller.dart`'s own precedent: a concurrent logout purge
      // closing the Hive cache box during invalidation lands here, after the
      // answer was already stored server-side. Leaving it unhandled would be
      // a spinner that never stops and a banner that never appears.
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      state = state.copyWith(submitting: false, failure: rejected);
      return false;
    }

    _refreshDependents();

    state = state.copyWith(submitting: false, clearFailure: true);
    return true;
  }

  /// Tells the screens that already cached today's pain/mood to re-fetch.
  ///
  /// **The dashboard is always refreshed** — the user is looking at it
  /// (screen 9 is a sheet OVER it). `ref.invalidate` on an actively-watched
  /// `autoDispose` provider schedules an immediate rebuild; nothing here
  /// awaits its future, the same fire-and-forget shape
  /// `_NetworkRequiredBody`'s own retry button already uses.
  ///
  /// **The calendar controller is refreshed only if it ALREADY EXISTS and
  /// ALREADY HAS A VALUE.** `cycleCalendarControllerProvider` is
  /// `autoDispose` (`cycle_calendar_controller.dart`); a bare `ref.read`
  /// from here would CREATE it — firing `sessionTodayProvider` plus three
  /// calendar-month GETs — for a Cycle tab screen nobody has opened yet.
  /// [Ref.exists] is what answers "does this provider already have an
  /// element" WITHOUT creating one (`riverpod-3.3.2/lib/src/core/ref.dart`'s
  /// own dartdoc: checking existence "is generally unsafe... but it can be
  /// useful... to avoid re-fetching"). The second condition —
  /// `.hasValue` — is what `CycleCalendarController.refresh()` itself checks
  /// before deciding whether to re-read the visible month or fall back to
  /// `ref.invalidateSelf()`; skipping the call entirely when there is no
  /// value yet avoids the documented snap-back to today's month that
  /// `invalidateSelf()` would otherwise cause, and this method never calls
  /// that branch directly — only `refresh()` itself decides that.
  void _refreshDependents() {
    ref.invalidate(dashboardControllerProvider);

    if (ref.exists(cycleCalendarControllerProvider)) {
      final calendarState = ref.read(cycleCalendarControllerProvider);
      if (calendarState.hasValue) {
        // Fire-and-forget: the calendar screen (if mounted) will show its
        // own loading/refresh treatment; screen 9 does not await this.
        unawaited(ref.read(cycleCalendarControllerProvider.notifier).refresh());
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 9's controller.
final quickCheckinControllerProvider =
    NotifierProvider.autoDispose<QuickCheckinController, QuickCheckinForm>(
      QuickCheckinController.new,
    );
