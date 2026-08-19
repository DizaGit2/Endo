import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/notification_category_selection.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/push/push_token_source.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// The four notification categories and the copy screen 7 draws for each.
///
/// Wire codes and canonical labels from `HormoneCatalog.NotificationCategories`
/// (`backend/src/Lumen.Domain/Reference/HormoneCatalog.cs:85-108`); the
/// sub-copy is screen 7's own `.ntd` line (`Screens/screen_07_notifications.html`,
/// ratified in `definitions.md:739-742`). Declaration order is
/// `NotificationCategories.All`, which that file documents as *"the screen-7
/// order the ON / ON / OFF / OFF seed is stated in"* — the mockup's order and
/// the server's frozen order at once.
///
/// **`phase_shift` is SINGULAR, and so is its label.** Screen 7's mockup draws
/// "Phase shifts"; the catalogue says, verbatim, *"`phase_shift` is **"Phase
/// shift"**, singular — screen 7's plural "Phase shifts" is the drift, and
/// screen 34's singular is canonical"* (`HormoneCatalog.cs:97-99`, and B16 /
/// `definitions.md:740`). The catalogue is the authority, so the plural does
/// not ship.
///
/// **Codes are data; labels are not.** The lowercase code is what reaches the
/// wire and `user_notification_prefs.CategoryCode`; the label is an i18n
/// **source** string that is never stored and never sent. Sending a label is
/// not a cosmetic slip — it is an unknown code and a 400 keyed
/// `enabledCategories[i]`.
///
/// **This is copy, not a source of truth about what exists.**
/// `POST /onboarding/notifications` and `GET /onboarding/state` both list the
/// COMPLETE vocabulary in frozen order with a boolean per code, and the screen
/// renders *that* list ([NotificationsForm.categories]). This enum answers two
/// narrower questions: what to draw beside a code, and what a code's flag is
/// when the wire carried no list at all. The vocabulary is append-only on the
/// server, so a build will eventually meet a code that is not here —
/// [fromWireName] answers null for it and [NotificationsForm] carries it
/// through untouched rather than dropping it.
///
/// **Quiet hours and the DAILY / CYCLE EVENTS grouping are not here**, and
/// their absence is not an omission: both belong to settings screen 34, and
/// `definitions.md:757` says group assignment is *"part of settings layout, not
/// a property of the category"*.
enum NotificationOption {
  dailyCheckin(
    'daily_checkin',
    'Daily check-in',
    'Log symptoms each evening',
    defaultEnabled: true,
  ),
  phaseShift(
    'phase_shift',
    'Phase shift',
    'When you enter a new phase',
    defaultEnabled: true,
  ),
  periodPrediction(
    'period_prediction',
    'Period prediction',
    'Two days before your period',
    defaultEnabled: false,
  ),
  medicationReminders(
    'medication_reminders',
    'Medication reminders',
    'Once you log a treatment',
    defaultEnabled: false,
  );

  const NotificationOption(
    this.wireName,
    this.label,
    this.description, {
    required this.defaultEnabled,
  });

  /// The code on the wire and in `user_notification_prefs.CategoryCode`.
  final String wireName;

  /// The category's on-screen name — an i18n source string, never stored.
  final String label;

  /// The sub-copy screen 7 prints under the name (the mockup's `.ntd`).
  final String description;

  /// Whether the onboarding seed has this category ON for a user who has never
  /// answered.
  ///
  /// **A per-member field, unlike screen 6's**, because the seed genuinely
  /// varies here: `daily_checkin` and `phase_shift` are ON, the other two OFF
  /// (`UserNotificationPref.DefaultEnabled`, `UserNotificationPref.cs:40-44`;
  /// `definitions.md:762-771` calls the onboarding screen the *authoritative*
  /// source for these initial values). Screen 34 draws all four ON — that is a
  /// populated sample, not a different default (`ARCHITECTURE.md:61`).
  final bool defaultEnabled;

  /// The member [code] names, or null — including for a code this build has
  /// never seen, and for every display label.
  ///
  /// Matched exactly and never case-folded: the server compares with
  /// `StringComparer.Ordinal` (`OnboardingStepsService.cs:1127-1149`), so a
  /// client that folded case would treat `Daily_Checkin` as a category it knows
  /// and then send a code the server answers 400 for.
  static NotificationOption? fromWireName(String? code) {
    for (final NotificationOption value in values) {
      if (value.wireName == code) return value;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// NotificationsAction
// ---------------------------------------------------------------------------

/// Which of screen 7's two CTAs is in flight.
///
/// The two are **different request sequences**, not two ways to send one
/// request, so "submitting" alone would not be enough to render the screen: the
/// spinner belongs to the control the user pressed.
enum NotificationsAction {
  /// `POST /onboarding/notifications`, then `POST /onboarding/complete`.
  allowAndFinish,

  /// `POST /onboarding/complete` **only** — D-02's skip, which writes no
  /// preference row.
  notNow,
}

// ---------------------------------------------------------------------------
// NotificationChoice
// ---------------------------------------------------------------------------

/// One row of the server's category list: a code, and whether it may notify.
@immutable
class NotificationChoice {
  const NotificationChoice({required this.code, required this.enabled});

  /// The wire code, exactly as the server sent it.
  final String code;

  /// Whether this category may notify.
  ///
  /// `false` is a real answer — the row exists and records that the question
  /// was asked and declined, which is a different state from never having
  /// answered (that state has no row at all).
  ///
  /// **Nothing in P4b reads it.** P4a stores these preferences and dispatches
  /// nothing (§G14, `OnboardingContracts.cs:303-306`); the rows exist so
  /// D-19's per-user schedule has something to read in P9a. That is deliberate,
  /// and no copy on screen says otherwise.
  final bool enabled;

  /// The ratified copy for [code], or null when this build has none.
  NotificationOption? get option => NotificationOption.fromWireName(code);

  NotificationChoice get toggled =>
      NotificationChoice(code: code, enabled: !enabled);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationChoice &&
          other.code == code &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(code, enabled);
}

// ---------------------------------------------------------------------------
// NotificationsForm
// ---------------------------------------------------------------------------

/// Everything screen 7 renders.
@immutable
class NotificationsForm {
  const NotificationsForm({
    required this.categories,
    this.inFlight,
    this.failure,
  });

  /// The **complete** vocabulary the server sent, in the order it sent it.
  ///
  /// Not "the enabled ones", and not a client-side list filtered by what this
  /// build can draw. It is the array the next write is built from, so anything
  /// missing from here is a code the write will store as deselected.
  final List<NotificationChoice> categories;

  /// Which CTA is in flight, or null.
  final NotificationsAction? inFlight;

  /// Why the last attempt to SAVE failed. Cleared when the user answers again.
  ///
  /// A failed **completion** is not here: `OnboardingFlowController.complete`
  /// holds it on the flow, because the 409 it can carry moves the user to
  /// another step and the message has to travel with them.
  final Failure? failure;

  /// Whether either CTA is in flight.
  bool get submitting => inFlight != null;

  /// The rows this build has copy for, in the server's order.
  ///
  /// A code with no [NotificationOption] is **not drawn** — there is no label
  /// and no sub-copy for it, and inventing one from the wire code would be
  /// authoring copy. It is still carried in [categories] and still travels in
  /// [enabledCodes]: on a FULL REPLACE endpoint, dropping an unknown code from
  /// the array is not "ignoring it", it is storing the user's answer as a
  /// deselection.
  List<NotificationChoice> get drawable => <NotificationChoice>[
    for (final NotificationChoice choice in categories)
      if (choice.option != null) choice,
  ];

  /// Every enabled code, in the server's order — the **whole body** of the
  /// write.
  ///
  /// `POST /onboarding/notifications` is a FULL REPLACE (§C.0.1): the array is
  /// the complete desired state, so an enabled category left out of it is
  /// stored as deselected. This is therefore never a diff against what was
  /// read.
  ///
  /// **Empty is a legitimate value here.** Muting everything is a real answer
  /// this endpoint stores — but it is emphatically not what "Not now" sends;
  /// see [NotificationsController.notNow].
  List<String> get enabledCodes => <String>[
    for (final NotificationChoice choice in categories)
      if (choice.enabled) choice.code,
  ];

  /// [code] flipped; every other row left exactly as it was.
  NotificationsForm toggle(String code) {
    return copyWith(
      categories: <NotificationChoice>[
        for (final NotificationChoice choice in categories)
          choice.code == code ? choice.toggled : choice,
      ],
    );
  }

  NotificationsForm copyWith({
    List<NotificationChoice>? categories,
    NotificationsAction? inFlight,
    bool clearInFlight = false,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return NotificationsForm(
      categories: categories ?? this.categories,
      inFlight: clearInFlight ? null : (inFlight ?? this.inFlight),
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  /// The form for [selections] as the server sent them.
  ///
  /// **Null means the RESUME READ carried no list**, which is the one case the
  /// ratified table is a source of truth for: every generated property is
  /// nullable (§C.0.2) and a P3b-era cached `GET /onboarding/state` predates
  /// this member entirely. The fallback is
  /// `UserNotificationPref.DefaultEnabled` — the same per-code seed
  /// `OnboardingStepsService.ReadNotificationPrefsAsync` applies (`:640-655`)
  /// for a user who has never answered — so the two cannot disagree about what
  /// an unanswered step looks like.
  ///
  /// **The WRITE path never reaches that branch, deliberately.** A truncated
  /// `POST /onboarding/notifications` response means the write succeeded and
  /// the body is malformed — a different fact from "this user has never
  /// answered", wanting a different answer — so
  /// [NotificationsController.allowAndFinish] substitutes the set it posted
  /// before calling this, and the seed stays what it is: the resume read's
  /// fallback and nothing else.
  ///
  /// **An EMPTY list is not the same input**, and the two must not be allowed
  /// to collapse: `[]` off this endpoint would be a form with no rows at all,
  /// while null is "the wire said nothing".
  ///
  /// A row with a null `code` is dropped: it names nothing, so it can be
  /// neither drawn nor sent. A row with a null `enabled` falls back to the same
  /// per-code seed, because the server declares that member non-nullable and
  /// always sends it — so a null is a truncated body rather than an answer. For
  /// a code this build has never seen there is no seed to apply and the
  /// fallback is `false`; that direction is the safe one, because it silences
  /// a notification this build could not have described rather than sending one
  /// the user never agreed to.
  factory NotificationsForm.fromWire(
    Iterable<NotificationCategorySelection>? selections,
  ) {
    if (selections == null) {
      return NotificationsForm(
        categories: <NotificationChoice>[
          for (final NotificationOption option in NotificationOption.values)
            NotificationChoice(
              code: option.wireName,
              enabled: option.defaultEnabled,
            ),
        ],
      );
    }

    return NotificationsForm(
      categories: <NotificationChoice>[
        for (final NotificationCategorySelection selection in selections)
          if (selection.code case final String code)
            NotificationChoice(
              code: code,
              enabled:
                  selection.enabled ??
                  (NotificationOption.fromWireName(code)?.defaultEnabled ??
                      false),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// NotificationsController
// ---------------------------------------------------------------------------

/// Screen 7's state: the four toggles, and the two ways to finish onboarding.
///
/// **Shape: a plain `Notifier<NotificationsForm>` with a synchronous
/// `build()`.** Classified before it was written, per the phase's
/// controller-shape rule. `build()` has no `await` at all — the resume read this
/// screen prefills from was already made by [OnboardingFlowController], and the
/// response carries the category list whole. That is the **empty-build** case,
/// and the rule's remedy is taken to its root: there is no `AsyncValue` and
/// therefore no build future for a synchronous `state =` to lose to.
///
/// The list is read **once**, with `ref.read` rather than `ref.watch`: re-seeding
/// from a later flow change would discard whatever the user had toggled. The
/// refresh this controller performs is for the NEXT build of it, after the user
/// has left the step and come back.
///
/// **It never reads `notificationsProvided`.** After P4b-T8b that boolean is the
/// resume read's answer, not the current one — [OnboardingFlowController]
/// deliberately leaves the `*Provided` flags alone — so a controller that gated
/// on it would be reading a claim no behaviour holds.
///
/// ## The two CTAs are two request sequences
///
/// This is the last step and the first screen that can end the flow, and D-02 is
/// what makes the difference load-bearing:
///
///  * [allowAndFinish] — `POST /onboarding/notifications` (FULL REPLACE of all
///    four rows), then `POST /onboarding/complete`;
///  * [notNow] — `POST /onboarding/complete` **only**, writing no preference
///    row at all.
///
/// See [notNow] for why an empty post is *not* a skip.
///
/// `autoDispose`, because the form holds the user's own answers and the house
/// rule is that such state must not outlive the screen showing it.
class NotificationsController extends Notifier<NotificationsForm> {
  @override
  NotificationsForm build() {
    final BuiltList<NotificationCategorySelection>? categories = ref
        .read(onboardingFlowControllerProvider)
        .value
        ?.state
        .notifications;
    return NotificationsForm.fromWire(categories);
  }

  // ── Answering ─────────────────────────────────────────────────────────────

  /// Flips [code], and drops whatever the last attempt said about the answers
  /// it replaced.
  ///
  /// Every category can be turned off, including the last one: muting
  /// everything is a real answer this endpoint stores.
  ///
  /// A no-op while a request is in flight — that request already carries its
  /// codes, and the 200 replaces the form with the server's re-read, so a
  /// toggle accepted here would be silently discarded a moment later.
  void toggle(String code) {
    if (state.submitting) return;
    state = state.toggle(code).copyWith(clearFailure: true);
  }

  // ── "Allow & finish" ──────────────────────────────────────────────────────

  /// Saves the complete enabled set — with the push pair, if there is one — and
  /// then finishes onboarding.
  ///
  /// **It always posts, and it always posts the whole set.** The endpoint is a
  /// FULL REPLACE and the set on screen *is* the answer. Re-posting an
  /// unchanged set is idempotent, and it is what makes `notificationsProvided`
  /// true for a user who accepted the seed without touching a row.
  ///
  /// **With nothing enabled it still posts.** There is no minimum on this
  /// endpoint: the server keys `value is required` on a NULL `enabledCategories`
  /// and on nothing else (`OnboardingStepsService.cs:515-517`). "Mute
  /// everything" is an answer, and it is a *different state* from having
  /// skipped the step — see [notNow].
  ///
  /// **The push pair (ruling R-09).** [PushTokenSource] is asked for a token
  /// and it travels whole when there is one. In P4b there never is: the shipped
  /// implementation answers null, so the request carries categories only and
  /// the server reports `deviceRegistered: false` — a documented normal
  /// outcome, not a failure (`OnboardingContracts.cs:290-293`). Asking anyway
  /// is what makes P9a a one-class change: the path is already wired and
  /// already tested.
  ///
  /// **A token source that throws does not cost the user their answer.** The
  /// categories are what this step is for, and D-19's scheduler reads them;
  /// losing them because a messaging SDK failed would be the tail wagging the
  /// dog. The read is guarded and falls back to "no device".
  ///
  /// **A failed save does not complete.** Completing after a rejected save
  /// would stamp `onboarding_completed_at` and materialise the SEED
  /// (`OnboardingStepsService.cs:1091-1105`), quietly replacing the answer the
  /// user was just told had failed.
  Future<void> allowAndFinish() async {
    final NotificationsForm form = state;
    // In-flight guard: a second press must not issue a second sequence.
    if (form.submitting) return;

    final List<String> codes = form.enabledCodes;

    // The previous rejection goes NOW, not when the new attempt lands: without
    // this the old banner sits beside the new spinner, telling the user the
    // attempt they are watching has already failed.
    state = form.copyWith(
      inFlight: NotificationsAction.allowAndFinish,
      clearFailure: true,
    );

    // Read BEFORE the await, and held across it, FOR THE RECORD ONLY.
    // `ref.read` on a disposed controller throws, and this one can be disposed
    // while the request is open: the shell's back affordance is not gated on
    // `submitting`, so Back mid-save is an ordinary gesture. Everything else
    // keeps reading the notifier fresh through `ref`.
    final OnboardingFlowController flowForRecord = ref.read(
      onboardingFlowControllerProvider.notifier,
    );

    final PushToken? token = await _pushToken();

    List<NotificationChoice>? saved;
    BuiltList<NotificationCategorySelection>? savedOnTheWire;
    Failure? rejected;
    try {
      final response = await ref
          .read(onboardingRepositoryProvider)
          .saveNotifications(
            codes: codes,
            pushToken: token?.token,
            platform: token?.platform,
          );
      // The 200 is the server's RE-READ of the stored rows rather than an echo
      // of the request, so it is the best answer to "what does the server hold
      // now" — including for a code this build cannot draw.
      //
      // A 200 whose `categories` member is ABSENT is the one case that answer
      // is unavailable, and the seed must NOT stand in for it. Every generated
      // property is `T?` (§C.0.2) while the server declares this one
      // non-nullable, so an absent list is a contract violation rather than an
      // answer — but the write still SUCCEEDED, and what the server holds is
      // therefore exactly what this screen posted. Falling through to
      // `fromWire(null)` would repaint the user's just-muted rows with the
      // ON / ON / OFF / OFF seed and record that on the flow, telling them
      // their answer was something they never chose.
      //
      // `form` is the pre-submit snapshot and a toggle is refused while a
      // request is in flight, so `form.categories` IS the desired state this
      // request carried. Nothing is invented: these are the user's own answers,
      // which the 200 says were stored.
      savedOnTheWire =
          response.categories ??
          BuiltList<NotificationCategorySelection>(
            <NotificationCategorySelection>[
              for (final NotificationChoice choice in form.categories)
                NotificationCategorySelection(
                  (b) => b
                    ..code = choice.code
                    ..enabled = choice.enabled,
                ),
            ],
          );
      saved = NotificationsForm.fromWire(savedOnTheWire).categories;
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render.
      // `cachedWrite` invalidates its keys unguarded after a successful write,
      // so a concurrent logout purge closing the Hive box lands here — after
      // the answer was stored. It is the stored-but-reported-failure arm: the
      // rows may be on the server while the flow keeps the pre-save list. The
      // user sees a banner, so it is not silent, but it is the same class of
      // loss (T8b invariant 2).
      rejected = const UnknownFailure();
    }

    // BEFORE the disposal gate, deliberately (T8b). The shell's copy of
    // `GET /onboarding/state` still holds the set this save replaced, and this
    // controller is autoDispose: walking away and back would rebuild the form
    // out of that stale list. On a FULL REPLACE endpoint that is not a stale
    // view — the array IS the next request's body — so the following save would
    // store the answer the user just changed as deselected. `_recordSaved` has
    // the gate that matters, on the FLOW's own lifetime.
    if (rejected == null) {
      flowForRecord.recordNotificationsSaved(savedOnTheWire);
    }

    if (!ref.mounted) return;

    if (rejected != null) {
      state = state.copyWith(failure: rejected, clearInFlight: true);
      return;
    }

    state = state.copyWith(categories: saved, clearFailure: true);

    // Read fresh, not through the held reference above: this line is reached
    // only with THIS controller still mounted, and a fresh `ref.read` rebuilds
    // the flow if it has gone in the meantime instead of throwing on a stale
    // notifier.
    await ref.read(onboardingFlowControllerProvider.notifier).complete();

    // The completion can END this controller: on success the router's gate
    // opens and the shell is unmounted; on a 409 the flow moves to the step
    // that still owes an answer and this step body is replaced. Either way
    // there is nothing left to settle.
    if (!ref.mounted) return;
    state = state.copyWith(clearInFlight: true);
  }

  // ── "Not now" ─────────────────────────────────────────────────────────────

  /// Finishes onboarding **without** answering this step.
  ///
  /// `POST /onboarding/complete` and nothing else. D-02 makes every step after
  /// the cycle anchor skippable, and "skip" means *not calling that step's
  /// endpoint at all* — so this method deliberately has no write of its own.
  ///
  /// **An empty post would not be the same thing, and the difference is
  /// silent.** `SaveNotificationPrefsAsync` writes a row for every category and
  /// sets `Enabled` from membership of the array
  /// (`OnboardingStepsService.cs:556-573`, through `StagePreferenceRows` at
  /// `:1172-1192`), so `enabledCategories: []` stores four rows with every flag
  /// `false`. `CompleteAsync`'s backfill is then guarded by
  /// `if (!await db.UserNotificationPrefs.AnyAsync(...))`
  /// (`:1091-1105`) and does nothing. A user who tapped "Not now" would end up
  /// with every notification muted instead of the ON / ON / OFF / OFF seed —
  /// and no screen would ever tell them.
  ///
  /// **It does not ask for a push token either.** There is nothing for one to
  /// travel on, and in P9a asking would raise the OS permission prompt on the
  /// one control whose entire meaning is "not now".
  Future<void> notNow() async {
    if (state.submitting) return;

    state = state.copyWith(
      inFlight: NotificationsAction.notNow,
      clearFailure: true,
    );

    await ref.read(onboardingFlowControllerProvider.notifier).complete();

    if (!ref.mounted) return;
    state = state.copyWith(clearInFlight: true);
  }

  // ── The push seam ─────────────────────────────────────────────────────────

  /// The device's push token, or null.
  ///
  /// Null is the only answer P4b can produce: [NoPushToken] is the shipped
  /// implementation.
  ///
  /// **Three ways to get null, and all three are the same normal outcome** —
  /// the categories-only request, whose `deviceRegistered: false` the contract
  /// reports rather than rejects:
  ///  * the source has no token (P4b, always);
  ///  * the source **threw** — P9a's talks to FCM/APNs and can. The categories
  ///    are what this step is for and D-19's scheduler reads them; losing them
  ///    to a messaging failure would be the tail wagging the dog;
  ///  * the source answered a **blank half** ([PushToken.sendable]). Left
  ///    unnormalised that is strictly worse than a throw: the blank token
  ///    reaches the repository, the server's own blank-is-absent rule makes it
  ///    half a pair, the all-or-nothing guard throws an [ArgumentError], and
  ///    the `catch (_)` in [allowAndFinish] renders it as an `UnknownFailure`
  ///    banner — so the user's four preference rows go unsaved and onboarding
  ///    never completes, over a token nobody asked about.
  Future<PushToken?> _pushToken() async {
    try {
      return PushToken.sendable(await ref.read(pushTokenSourceProvider).read());
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 7's controller.
final notificationsControllerProvider =
    NotifierProvider.autoDispose<NotificationsController, NotificationsForm>(
      NotificationsController.new,
    );
