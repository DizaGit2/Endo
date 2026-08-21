// ---------------------------------------------------------------------------
// PeriodEditorController — screen 11's period-event editor (P4b-T16c)
// ---------------------------------------------------------------------------
//
// The write behind screen 11's Period section: `POST /cycle/events`, which is a
// **FULL UPSERT** — the body describes the row's whole desired final state, and
// **anything it does not carry is CLEARED**.
//
// Read `CycleRepository.logEvent`'s dartdoc before this file; it carries the
// verified contract. What lives HERE is the state machine, and it is built
// against four rules:
//
//  1. **Every save sends all four fields, always.** There are NO `touched`
//     flags on this surface and there must not be. The day-log editor beside
//     it on this same screen has three, and they are right there and wrong
//     here: on a MERGE endpoint an omitted field is left alone, so omitting is
//     the safe answer; on THIS endpoint omitting is a delete. `kind` and
//     `occurredOn` are the upsert key; `flowIntensity` and `notes` are cleared
//     by their own absence.
//
//  2. **A blank note is a REAL ERASE, and it is the only way to remove one.**
//     `CycleService` computes `notesEnc` as non-null only for a non-empty
//     trimmed note and then assigns `row.NotesEnc = notesEnc` UNCONDITIONALLY,
//     so `""` destroys the stored ciphertext. That is the opposite of
//     `POST /cycle/day/{date}`, where the same assignment sits inside
//     `if (notesEnc is not null)` and a blank note is a no-op. **Do not copy
//     `DayLogEditorForm`'s design into this file.**
//
//  3. **The kind chip chooses WHICH ROW is being edited.** The upsert key is
//     `(user, kind, occurredOn)` and `occurredOn` is fixed to the route's day,
//     so `kind` is the whole row selector. Changing it therefore re-seeds
//     `flowIntensity` and `notes` from that other row — carrying the previous
//     row's values across would post one event's note onto a different event
//     and wipe that event's own, under rule 1.
//
//  4. **There is no date control and no move operation** (RULING T16-G).
//     `occurredOn` is the route's own `:date`, already round-trip-verified by
//     `Routes.parseCycleDayDate`. A date change on this endpoint is not a move:
//     it writes a SECOND row at the new key and leaves the original live. The
//     supported shape is an explicit delete plus an explicit add. If a move is
//     ever built it is POST-then-DELETE, never DELETE-then-POST — the ordering
//     that leaves the user with nothing if the gap fails. Nothing here reads
//     `DateTime.now()`.
//
// **S-9 — this editor and the day-log editor are TWO SAVES, and nothing here
// couples them.** Screen 11 now carries both. A user can edit the day log and
// the period event in one sitting; those are two endpoints, two requests and
// two failure modes, and each sheet owns its own. Nothing in this file batches
// them, nothing makes one's success depend on the other, and each has its own
// failure state on its own sheet — because a "save everything" button is
// exactly how half a save becomes invisible: one 200 and one 400 on one tap,
// with one message, on an online-only client with no write queue. This is the
// same reasoning R-11 used to give screen 13 no repository.
//
// **Known residual, recorded rather than papered over (S-2/H-3).** The seed
// comes from a day read that may have been served from a 5-minute-TTL cache,
// and under FULL UPSERT every seeded value is re-asserted on save. So a stale
// seed CAN overwrite a newer server value here — the hazard the day-log
// editor's `touched` flags dissolve and this endpoint structurally cannot. The
// remedies the plan proposed are not available: `CacheResult.Fresh` also means
// "a cache hit inside the TTL" so "rehydrate only from Fresh" does not mean
// what it says, and `cachedRead` has no `forceRefresh`. Closing it needs a
// conditional-request or an `Optional<T>` on the wire — a contract change P4b
// does not make.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/period_vocabulary.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';

// ---------------------------------------------------------------------------
// Authored copy
// ---------------------------------------------------------------------------

/// Why Save is disabled with no kind chosen.
///
/// **AUTHORED** — queued for the T25 PO copy pass with the rest of screen 11's
/// strings. It is the editor's ONLY block reason, and that is the whole
/// difference from the day-log editor's two: there, a save that would carry
/// nothing is refused; here, a save that carries only a kind is a legal,
/// meaningful write (it clears the other two fields), so the only thing that
/// can be missing is the row selector itself.
///
/// It names the three chips rather than the wire field: `kind` is not a word
/// the user has seen.
const String kPeriodEditorNoKindMessage =
    'Choose period start, period end or spotting to save.';

// ---------------------------------------------------------------------------
// PeriodEditorForm
// ---------------------------------------------------------------------------

/// Everything the period editor renders and everything it can send.
@immutable
class PeriodEditorForm {
  const PeriodEditorForm({
    required this.stored,
    this.kind,
    this.flowIntensity,
    this.notes = '',
    this.submitting = false,
    this.deleting = false,
    this.failure,
  });

  /// The form as it opens over [events] — the day view's own already-loaded
  /// `cycle_events` rows, empty on a day with no period event.
  ///
  /// **R2: every control is seeded from the existing event.** Nothing that has
  /// a stored value opens blank, because under FULL UPSERT a blank control is
  /// not "unspecified" — it is an instruction to clear.
  ///
  /// Opens on the FIRST event whose kind the editor can actually address (one
  /// of [kPeriodKindCodes]), in the order `GET /cycle/day/{date}` returned
  /// them, which is also the order the Period section renders them in. An event
  /// with an unrecognisable kind is held in [stored] but is not selectable:
  /// this sheet can only ever SEND one of the three, so offering to edit a
  /// fourth would be a control that cannot do what it appears to.
  factory PeriodEditorForm.seededFrom(List<CycleEventResponse> events) {
    final stored = <String, CycleEventResponse>{};
    for (final event in events) {
      final kind = event.kind;
      if (kind != null) stored[kind] = event;
    }
    String? opening;
    for (final event in events) {
      final kind = event.kind;
      if (kind != null && kPeriodKindCodes.contains(kind)) {
        opening = kind;
        break;
      }
    }
    final selected = opening == null ? null : stored[opening];
    return PeriodEditorForm(
      stored: stored,
      kind: opening,
      // Straight through, never `?? 1` and never `?? 0`: `null` means the row
      // stores no flow level, which is a different fact from level 1.
      flowIntensity: selected?.flowIntensity,
      // The notes box is a `String`, never `String?` — a text field's empty
      // state IS the empty string, and carrying a second "no note" value would
      // give the same fact two representations. Here that empty string is also
      // the wire value that CLEARS, which is why it must not be confused with
      // "untouched".
      notes: selected?.notes ?? '',
    );
  }

  /// The day's stored events, keyed by their own `kind`.
  ///
  /// **NOT form input** — it is the re-seed source rule 3 needs and the delete
  /// target [selectedEvent] resolves through. It is updated only by a
  /// successful save, so the form always describes the row as the server last
  /// confirmed it.
  final Map<String, CycleEventResponse> stored;

  /// The selected `cycle_events.kind`, or `null` for "no row chosen".
  ///
  /// `null` is reachable by design (deselect-to-clear, T20-G) and blocks the
  /// save: the server answers a body without a kind with a 400.
  final String? kind;

  /// The flow chips' current value — the WIRE ordinal `1..4`, or `null`.
  ///
  /// `null` is not "unspecified" on this endpoint. It is CLEAR, and it is the
  /// only way a user can take a flow level back off an event.
  final int? flowIntensity;

  /// The notes box's current text, exactly as typed (untrimmed).
  ///
  /// An empty string here is a deliberate erase — see rule 2 in the file
  /// header. The server trims before deciding, so `'   '` erases too.
  final String notes;

  /// Whether `POST /cycle/events` is in flight.
  final bool submitting;

  /// Whether `DELETE /cycle/events/{id}` is in flight.
  ///
  /// Separate from [submitting] so the sheet can say which of the two is
  /// happening; both freeze every control through [busy].
  final bool deleting;

  /// Why the last attempt failed — from either request. Cleared the moment the
  /// user changes anything again, or starts a new attempt.
  final Failure? failure;

  /// The stored row the current [kind] addresses, or `null` when this kind has
  /// no event on this day yet.
  CycleEventResponse? get selectedEvent =>
      kind == null ? null : stored[kind];

  /// The stored row for [kind], whatever the form currently has selected.
  CycleEventResponse? storedFor(String kind) => stored[kind];

  /// Whether either request is in flight.
  bool get busy => submitting || deleting;

  /// Why Save is disabled, or `null` when it is enabled.
  ///
  /// Screen 12's `blockReason` shape — one `String?` getter returning a named
  /// module-level constant, rendered straight beside the CTA, with [canSubmit]
  /// defined from it so the two can never disagree.
  ///
  /// **There is deliberately no "nothing changed yet" reason.** An opened,
  /// untouched form IS submittable here: re-posting the row's own four values
  /// writes them back unchanged, which is a legal upsert and a no-op in
  /// effect. On the day-log editor the same state is blocked, because there a
  /// save with nothing touched sends an empty body the server rejects.
  String? get blockReason => kind == null ? kPeriodEditorNoKindMessage : null;

  bool get canSubmit => blockReason == null && !busy;

  /// Whether there is a row to delete, and enough of it to delete safely.
  ///
  /// **Both `id` and `occurredOn` are required, not just `id`.** Every
  /// generated property is nullable (§C.0.2); `id` is what
  /// `DELETE /cycle/events/{id}` takes and `occurredOn` is what names the cache
  /// keys the deletion invalidates. Falling back to the screen's route date for
  /// the second would be exactly the substitution S-7 forbids, so a row that
  /// cannot supply its own day is simply not deletable from here.
  bool get canDelete =>
      !busy &&
      selectedEvent?.id != null &&
      selectedEvent?.occurredOn != null;

  PeriodEditorForm copyWith({
    Map<String, CycleEventResponse>? stored,
    String? kind,
    bool clearKind = false,
    int? flowIntensity,
    bool clearFlow = false,
    String? notes,
    bool? submitting,
    bool? deleting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return PeriodEditorForm(
      stored: stored ?? this.stored,
      // Paired `clearX` flags rather than a bare `x ?? this.x`: without them
      // "set this to null" and "do not pass this" would be the same call, and
      // on this endpoint that difference is the difference between keeping a
      // value and deleting it.
      kind: clearKind ? null : (kind ?? this.kind),
      flowIntensity: clearFlow ? null : (flowIntensity ?? this.flowIntensity),
      notes: notes ?? this.notes,
      submitting: submitting ?? this.submitting,
      deleting: deleting ?? this.deleting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

// ---------------------------------------------------------------------------
// PeriodEditorController
// ---------------------------------------------------------------------------

/// Drives the period editor for one [date].
///
/// **Shape: a plain `Notifier<PeriodEditorForm>` with a SYNCHRONOUS
/// `build()`** — the empty-build branch of the phase's controller-shape rule,
/// the same one screens 9, 12 and 13 and the day-log editor use. It reads no
/// repository: the seed comes from the day view screen 11 has already settled,
/// so there is no build future for a tapped chip to race.
///
/// **A family, keyed by [date]**, matching `DayDetailController` — the editor
/// belongs to one day and cannot be pointed at another.
///
/// `autoDispose`: the form holds the user's own unsent period, flow and note
/// answers, which is health data. Closing the sheet tears it down.
class PeriodEditorController extends Notifier<PeriodEditorForm> {
  PeriodEditorController(this.date);

  /// The day this editor writes. Set once, at construction, from the route.
  final DateTime date;

  /// Seeds the form from the day view that is already on screen.
  ///
  /// **`ref.exists` before `ref.read`, and it is load-bearing.**
  /// `dayDetailControllerProvider` is `autoDispose`; a bare `ref.read` would
  /// CREATE it for a day nobody is looking at, firing `GET /cycle/day` and
  /// `GET /symptoms` from behind a modal. In production the guard is always
  /// true — screen 11 is watching that provider, since the sheet opens over
  /// it — so the empty branch is the honest answer to "opened some other way".
  ///
  /// An empty seed is SAFE HERE ONLY BECAUSE THE SAVE IS STILL BLOCKED: with
  /// no events there is no kind, and with no kind [PeriodEditorForm.blockReason]
  /// refuses the save. It is not safe in the day-log editor's sense — nothing
  /// on this endpoint makes an untouched field harmless — which is why the
  /// guard's failure mode is "you cannot save", not "your save omits things".
  @override
  PeriodEditorForm build() {
    final provider = dayDetailControllerProvider(date);
    final events = ref.exists(provider)
        ? ref.read(provider).value?.events
        : null;
    return PeriodEditorForm.seededFrom(
      events ?? const <CycleEventResponse>[],
    );
  }

  // ── Answering ─────────────────────────────────────────────────────────

  /// Selects the row this sheet describes, or deselects it with `null`.
  ///
  /// **RE-SEEDS `flowIntensity` and `notes` from the newly-addressed row**, and
  /// blanks them when that row does not exist yet. See rule 3 in the file
  /// header: `kind` is part of the upsert key, so a different kind is a
  /// different row, and under FULL UPSERT carrying the previous row's values
  /// across would write them onto — and over — the new row.
  ///
  /// **The SHEET never passes `null`, and that is a decision with a reason.**
  /// The kind row is single-select with NO deselect: a re-tap of the selected
  /// kind is a no-op, so the screen gives that chip a null `onTap` and the
  /// node drops its action rather than announcing one that does nothing. The
  /// flow row, by contrast, DOES deselect-to-clear — because there `null` is a
  /// real, otherwise-unreachable wire value ("remove my flow level"), while
  /// here it is only "no row selected", a state that can do nothing but block
  /// the save. Offering it would also make a single mis-tap discard text the
  /// user had just typed, since re-seeding is what keeps one row's note off
  /// another row — which is the very harm T20-G's deselect rule exists to
  /// prevent, produced by the deselect. A kind mis-tap is already recoverable
  /// in one tap: choose the right kind.
  ///
  /// `null` is still HANDLED here rather than asserted away, because the
  /// parameter is nullable and because `null` is the form's own opening state
  /// on a day with no events — [PeriodEditorForm.blockReason] answers it.
  void setKind(String? value) {
    if (state.busy) return;
    final target = value == null ? null : state.stored[value];
    // Constructed rather than copied: three members move together and two of
    // them move to null, which is exactly the case `copyWith`'s paired
    // `clearX` flags exist to keep honest — writing it out is clearer than
    // three flags.
    state = PeriodEditorForm(
      stored: state.stored,
      kind: value,
      flowIntensity: target?.flowIntensity,
      notes: target?.notes ?? '',
    );
  }

  /// Records a flow-chip tap. `null` is a deliberate CLEAR, not "unspecified".
  void setFlow(int? value) {
    if (state.busy) return;
    state = state.copyWith(
      flowIntensity: value,
      clearFlow: value == null,
      clearFailure: true,
    );
  }

  /// Records an edit to the notes box. An empty [value] is an erase — rule 2.
  void setNotes(String value) {
    if (state.busy) return;
    state = state.copyWith(notes: value, clearFailure: true);
  }

  // ── Submitting ────────────────────────────────────────────────────────

  /// Writes the selected row whole. Returns `true` on success, `false` on a
  /// blocked, rejected or already-in-flight attempt — the screen closes the
  /// sheet only on `true`.
  ///
  /// **All four fields, every time** (rule 1). `CycleRepository.logEvent`'s
  /// four `required` named parameters make an omission a compile error; what
  /// this method adds is that none of them is filtered on its way there. There
  /// is no `if (touched…)` in this file and there must not be one.
  ///
  /// **The 200 body is adopted into the READ VIEW, never into the FORM.** Say
  /// it in those words, because the house rule points the other way:
  /// `quick_checkin_controller.dart`'s rule 7 and screen 12's success arm both
  /// refuse the response outright.
  ///
  ///  * **Never into the form.** Verified at the source and it differs from
  ///    the sibling endpoint: `POST /cycle/events`'s 200 is built from the
  ///    REQUEST's own trimmed note and the row's just-assigned flow, plus
  ///    three things only the server knows — `id`, `source` (an
  ///    onboarding-seeded row keeps `onboarding` when the user edits it) and
  ///    `createdAt` (the ORIGINAL observation's timestamp, not this edit's).
  ///    `POST /cycle/day/{date}`'s 200, by contrast, is built from the stored
  ///    row and can tell you a field you did not send. Neither belongs in a
  ///    form: an echoed value patched into [state] is indistinguishable from
  ///    user input on the next save.
  ///  * **Into the read view, yes** — [applyToDayView]. The three server-only
  ///    fields are precisely what the day view needs and cannot compute, `id`
  ///    most of all, since it is the only handle a later delete accepts.
  Future<bool> submit() async {
    final form = state;
    if (!form.canSubmit) return false;
    final kind = form.kind!;

    state = form.copyWith(submitting: true, clearFailure: true);

    Failure? rejected;
    CycleEventResponse? saved;
    try {
      saved = await ref
          .read(cycleRepositoryProvider)
          .logEvent(
            kind: kind,
            // The ROUTE's day, never re-derived from a response or from a
            // stored row — and never a clock read.
            occurredOn: date.toDate(),
            flowIntensity: form.flowIntensity,
            notes: form.notes,
          );
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render — the
      // `goals_controller.dart`/`quick_checkin_controller.dart` precedent (a
      // concurrent cache purge during invalidation, e.g.).
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      // Rebuilt from the PRE-submit snapshot, so every answer survives a
      // failure exactly as the user left it and the retry sends the same
      // request.
      state = form.copyWith(submitting: false, failure: rejected);
      return false;
    }

    _refreshDependents(saved!);

    // The saved row replaces this kind's entry in `stored` — so a later
    // re-select of this kind re-seeds from what was actually written rather
    // than from what the day read held when the sheet opened. Note this is
    // the row's new IDENTITY and values, not the form's answers: nothing here
    // touches `kind`, `flowIntensity` or `notes`.
    state = form.copyWith(
      stored: <String, CycleEventResponse>{...form.stored, kind: saved},
      submitting: false,
      clearFailure: true,
    );
    return true;
  }

  /// Soft-deletes the selected row. Returns `true` on success.
  ///
  /// **The screen confirms first.** This method does not confirm anything: it
  /// is the irreversible half, and the confirmation belongs where the user is.
  /// See `PeriodEditorScreen`'s delete affordance.
  ///
  /// **Keyed on the ROW's own `id` and `occurredOn`**, both read off the stored
  /// event — never the screen's route date (S-7). The 204 carries no body, so
  /// `occurredOn` is the only way the repository can name the keys the deletion
  /// invalidates, and [PeriodEditorForm.canDelete] refuses a row that cannot
  /// supply its own rather than substituting one.
  ///
  /// A second delete of an already-deleted row answers 404 and
  /// `CycleRepository.deleteEvent` treats that as success (D-13) — so this
  /// returns `true` for it, which is correct: the row is gone either way.
  Future<bool> delete() async {
    final form = state;
    if (!form.canDelete) return false;
    final event = form.selectedEvent!;
    final id = event.id!;
    final occurredOn = event.occurredOn!;

    state = form.copyWith(deleting: true, clearFailure: true);

    Failure? rejected;
    try {
      await ref
          .read(cycleRepositoryProvider)
          .deleteEvent(id: id, occurredOn: occurredOn);
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      state = form.copyWith(deleting: false, failure: rejected);
      return false;
    }

    _refreshDependentsAfterDelete(id);

    final stored = <String, CycleEventResponse>{...form.stored}
      ..remove(event.kind);
    state = form.copyWith(
      stored: stored,
      deleting: false,
      clearFailure: true,
    );
    return true;
  }

  // ── Telling the screens around this one ───────────────────────────────

  /// Tells the screens showing this day that one of its events changed.
  ///
  /// **The dashboard: invalidated unconditionally.** [Ref.invalidate] never
  /// CREATES an element, so it costs nothing when the dashboard is not
  /// mounted, and wrapping it in `ref.exists` would be INERT — P4b-T20b
  /// established that by tracing riverpod 3.3.2: `invalidate` is
  /// `readPointer(provider)?.element?.invalidateSelf(...)` and `exists` is the
  /// same lookup returning a bool. The dashboard renders today's pain and mood,
  /// which THIS write cannot move; what it can move is the calendar row those
  /// are read out of (`eventCount`, `hasNotes`), whose cache key this write has
  /// just invalidated. Leaving the controller holding a body the cache no
  /// longer has is the state worth avoiding.
  ///
  /// **This day's detail view: ADOPTED, not invalidated — [applyToDayView].**
  /// The sheet sits directly ON TOP of the provider it would be invalidating,
  /// so invalidating would drop screen 11 to a spinner behind the scrim and
  /// re-issue two GETs whose answer the 200 already carries. The repository has
  /// already invalidated the CACHE keys, so no staleness is being papered over.
  ///
  /// **The cycle calendar: refreshed only if it already exists AND already has
  /// a value** — screens 9 and 12's guard verbatim, for their reason.
  /// `ref.exists` stops a `ref.read` from creating an unopened calendar, and
  /// `hasValue` avoids `refresh()`'s own `invalidateSelf()` branch, which snaps
  /// the visible month back to today. A period event changes that day's
  /// `eventCount`, so an open calendar is genuinely out of date.
  void _refreshDependents(CycleEventResponse saved) {
    ref.invalidate(dashboardControllerProvider);
    applyToDayView(saved);
    _refreshCalendar();
  }

  void _refreshDependentsAfterDelete(String id) {
    ref.invalidate(dashboardControllerProvider);
    final provider = dayDetailControllerProvider(date);
    if (ref.exists(provider) && ref.read(provider).hasValue) {
      ref.read(provider.notifier).applyDeletedEvent(id);
    } else {
      ref.invalidate(provider);
    }
    _refreshCalendar();
  }

  void _refreshCalendar() {
    if (ref.exists(cycleCalendarControllerProvider)) {
      final calendarState = ref.read(cycleCalendarControllerProvider);
      if (calendarState.hasValue) {
        unawaited(ref.read(cycleCalendarControllerProvider.notifier).refresh());
      }
    }
  }

  /// Puts [saved] onto this day's detail view, or invalidates that view when
  /// there is nothing to put it onto — or when [saved] is not this day's.
  ///
  /// Three branches, none of them interchangeable:
  ///
  ///  * **Settled, and the saved row is dated THIS day ⇒ adopt.**
  ///    `DayDetailController.applySavedEvent` replaces the row with the same
  ///    `id` (or appends it) and leaves `log`, `symptoms` and `date` alone.
  ///  * **Settled, but the saved row is dated somewhere ELSE ⇒ invalidate.**
  ///    Unreachable in production — the server echoes the request's own upsert
  ///    key, and the request carried this screen's day — which is exactly why
  ///    the check is here rather than assumed: adopting on trust would draw an
  ///    event onto a day it did not happen on, and nothing downstream could
  ///    tell. S-7's rule is that the RESPONSE's `occurredOn` decides, and this
  ///    is that rule applied to the view instead of to the cache keys.
  ///  * **Still loading ⇒ invalidate.** There is no value to patch, and the
  ///    in-flight read was issued BEFORE this write committed, so it would land
  ///    as pre-write data with nothing left to correct it (P4b-T20b's finding).
  @visibleForTesting
  void applyToDayView(CycleEventResponse saved) {
    final provider = dayDetailControllerProvider(date);
    final savedDay = saved.occurredOn?.toDateTime();
    final isThisDay =
        savedDay != null &&
        savedDay.year == date.year &&
        savedDay.month == date.month &&
        savedDay.day == date.day;
    if (isThisDay && ref.exists(provider) && ref.read(provider).hasValue) {
      ref.read(provider.notifier).applySavedEvent(saved);
    } else {
      ref.invalidate(provider);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// The period editor's controller, one per day navigated to.
final periodEditorControllerProvider =
    NotifierProvider.autoDispose
        .family<PeriodEditorController, PeriodEditorForm, DateTime>(
          PeriodEditorController.new,
        );
