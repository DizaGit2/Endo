import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/hormone_selection.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// The seven hormone codes and the copy screen 6 draws for each.
///
/// Wire codes from `HormoneCatalog.Codes`
/// (`backend/src/Lumen.Domain/Reference/HormoneCatalog.cs:31-45`); labels from
/// `HormoneCatalog.Labels` (`:49-62`), which is the same set of strings the
/// mockup's `.nm` spans carry (`Screens/screen_06_hormones.html`). Categories
/// are screen 6's `.cat` spans, ratified in `definitions.md:144-154` — they
/// exist on **this screen only**, appear in no backend file and travel on no
/// wire. Declaration order is `HormoneCatalog.Codes.All`, which is the mockup's
/// order and the server's frozen order.
///
/// **Codes are data; labels are not.** The lowercase code is what reaches the
/// wire and the database; the label is an i18n **source** string that is never
/// stored and never sent (B16, `HormoneCatalog.cs:7-12`). Two members
/// deliberately differ: `estradiol` renders as "Estrogen" and `glp1` as
/// "GLP-1". Sending a label is not a cosmetic slip — it is an unknown code and
/// a 400 keyed `chartedHormones[i]`.
///
/// **This is copy, not a source of truth about what exists.** The response to
/// `POST /onboarding/hormones` and `GET /onboarding/state` both list the
/// COMPLETE vocabulary in frozen order with a boolean per code, and the screen
/// renders *that* list ([HormonesForm.hormones]). This enum answers two
/// narrower questions: what to draw beside a code, and what a code's flag is
/// when the wire carried no list at all. The vocabulary is append-only on the
/// server, so a build will eventually meet a code that is not here —
/// [fromWireName] answers null for it and [HormonesForm] carries it through
/// untouched rather than dropping it.
///
/// **No display unit.** Screen 6 draws name, category and toggle and nothing
/// else; units belong to screen 33 and depend on the clinician-UNSIGNED C-07
/// whitelist, so there is nothing here to carry one
/// (`survey/decisions-and-vocabularies.md` §2.9, `HormoneCatalog.cs:14-19`).
enum HormoneOption {
  estradiol('estradiol', 'Estrogen', 'Sex'),
  progesterone('progesterone', 'Progesterone', 'Sex'),
  lh('lh', 'LH', 'Pituitary'),
  fsh('fsh', 'FSH', 'Pituitary'),
  testosterone('testosterone', 'Testosterone', 'Androgen'),
  cortisol('cortisol', 'Cortisol', 'Stress'),
  glp1('glp1', 'GLP-1', 'Metabolic');

  const HormoneOption(this.wireName, this.label, this.category);

  /// The code on the wire and in `user_hormone_prefs.HormoneCode`.
  final String wireName;

  /// The hormone's on-screen name — an i18n source string, never stored.
  final String label;

  /// The grouping word screen 6 prints beside the name.
  ///
  /// Also an i18n source string, and one with no wire code at all: the five
  /// categories are derived from screen 6 (`definitions.md:144-154`) and exist
  /// in no backend file, because `ref_hormone`'s `category` column waits on the
  /// clinician-UNSIGNED C-13/C-08 grouping (`HormoneCatalog.cs:14-19`).
  final String category;

  /// Whether D-14 seeds this hormone ON for a user who has never answered.
  ///
  /// True for every member, and a constant rather than a per-member field
  /// because that is the shape of the server's rule: `UserHormonePref
  /// .DefaultCharted` **is** `HormoneCatalog.Codes.All`
  /// (`UserHormonePref.cs:39`), so the seed is membership of the whole
  /// vocabulary rather than a flag that varies by code. A per-member field
  /// would invite a reader to look for the ones that are off; there are none.
  bool get defaultCharted => true;

  /// The member [code] names, or null — including for a code this build has
  /// never seen, and for every display label.
  ///
  /// Matched exactly and never case-folded: the server compares with
  /// `StringComparer.Ordinal` (`OnboardingStepsService.cs:1127-1149`), so a
  /// client that folded case would treat `Estradiol` as a hormone it knows and
  /// then send a code the server answers 400 for.
  static HormoneOption? fromWireName(String? code) {
    for (final HormoneOption value in values) {
      if (value.wireName == code) return value;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// HormoneChoice
// ---------------------------------------------------------------------------

/// One row of the server's hormone list: a code, and whether its series is
/// drawn.
@immutable
class HormoneChoice {
  const HormoneChoice({required this.code, required this.charted});

  /// The wire code, exactly as the server sent it.
  final String code;

  /// Whether the user currently has this hormone charted.
  ///
  /// `false` is a real answer — the row exists and records that the question
  /// was asked and declined. It says **nothing about extraction**: P7b pulls
  /// all seven hormones out of every lab regardless, so un-charting one hides a
  /// line and destroys no data (D-14, `UserHormonePref.cs:9-11`).
  final bool charted;

  /// The ratified copy for [code], or null when this build has none.
  HormoneOption? get option => HormoneOption.fromWireName(code);

  HormoneChoice get toggled => HormoneChoice(code: code, charted: !charted);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HormoneChoice && other.code == code && other.charted == charted;

  @override
  int get hashCode => Object.hash(code, charted);
}

// ---------------------------------------------------------------------------
// HormonesForm
// ---------------------------------------------------------------------------

/// Everything screen 6 renders.
@immutable
class HormonesForm {
  const HormonesForm({
    required this.hormones,
    this.submitting = false,
    this.failure,
  });

  /// The **complete** vocabulary the server sent, in the order it sent it.
  ///
  /// Not "the charted ones", and not a client-side list filtered by what this
  /// build can draw. It is the array the next write is built from, so anything
  /// missing from here is a code the write will store as deselected.
  final List<HormoneChoice> hormones;

  /// Whether `POST /onboarding/hormones` is in flight.
  final bool submitting;

  /// Why the last attempt failed. Cleared when the user answers again.
  final Failure? failure;

  /// The rows this build has copy for, in the server's order.
  ///
  /// A code with no [HormoneOption] is **not drawn** — there is no label, no
  /// category and no swatch for it, and inventing one from the wire code would
  /// be authoring copy. It is still carried in [hormones] and still travels in
  /// [chartedCodes]: on a FULL REPLACE endpoint, dropping an unknown code from
  /// the array is not "ignoring it", it is storing the user's answer as a
  /// deselection.
  List<HormoneChoice> get drawable => <HormoneChoice>[
    for (final HormoneChoice choice in hormones)
      if (choice.option != null) choice,
  ];

  /// Every charted code, in the server's order — the **whole body** of the
  /// write.
  ///
  /// `POST /onboarding/hormones` is a FULL REPLACE (§C.0.1): the array is the
  /// complete desired state, so a still-charted hormone left out of it is
  /// stored as deselected. This is therefore never a diff against what was
  /// read.
  ///
  /// **Empty is a legitimate value here**, unlike screen 5's `selectedCodes`:
  /// this endpoint has no minimum, and `[]` means "chart nothing".
  List<String> get chartedCodes => <String>[
    for (final HormoneChoice choice in hormones)
      if (choice.charted) choice.code,
  ];

  /// [code] flipped; every other row left exactly as it was.
  HormonesForm toggle(String code) {
    return copyWith(
      hormones: <HormoneChoice>[
        for (final HormoneChoice choice in hormones)
          choice.code == code ? choice.toggled : choice,
      ],
    );
  }

  HormonesForm copyWith({
    List<HormoneChoice>? hormones,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return HormonesForm(
      hormones: hormones ?? this.hormones,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  /// The form for [selections] as the server sent them.
  ///
  /// **Null means the wire carried no list**, which is the one case the
  /// ratified table is a source of truth for: every generated property is
  /// nullable (§C.0.2) and a P3b-era cached `GET /onboarding/state` predates
  /// this member entirely. The fallback is `UserHormonePref.DefaultCharted` —
  /// the same per-code seed `OnboardingStepsService.ReadHormonePrefsAsync`
  /// applies (`:620-633`) for a user who has never answered — so the two cannot
  /// disagree about what an unanswered step looks like.
  ///
  /// **An EMPTY list is not the same input**, and the two must not be allowed
  /// to collapse: `[]` off this endpoint is the user's own "chart nothing",
  /// which is a real answer here (no minimum), while null is "the wire said
  /// nothing at all".
  ///
  /// A row with a null `code` is dropped: it names nothing, so it can be
  /// neither drawn nor sent. A row with a null `charted` falls back to the same
  /// per-code seed, because the server declares that member non-nullable and
  /// always sends it — so a null is a truncated body rather than an answer. For
  /// a code this build has never seen there is no seed to apply and the
  /// fallback is `false`; that direction is safe **because charted is not
  /// extracted** — the lab value is still stored and still extractable, and the
  /// only cost is a line this build could not have drawn anyway, on a screen
  /// that offers no control for it.
  factory HormonesForm.fromWire(Iterable<HormoneSelection>? selections) {
    if (selections == null) {
      return HormonesForm(
        hormones: <HormoneChoice>[
          for (final HormoneOption option in HormoneOption.values)
            HormoneChoice(
              code: option.wireName,
              charted: option.defaultCharted,
            ),
        ],
      );
    }

    return HormonesForm(
      hormones: <HormoneChoice>[
        for (final HormoneSelection selection in selections)
          if (selection.code case final String code)
            HormoneChoice(
              code: code,
              charted:
                  selection.charted ??
                  (HormoneOption.fromWireName(code)?.defaultCharted ?? false),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HormonesController
// ---------------------------------------------------------------------------

/// Screen 6's state: the hormone list, the toggles, and the save.
///
/// **Shape: a plain `Notifier<HormonesForm>` with a synchronous `build()`.**
/// Classified before it was written, per the phase's controller-shape rule.
/// `build()` has no `await` at all — the resume read this screen prefills from
/// was already made by [OnboardingFlowController], and the response carries the
/// hormone list whole, so there is nothing left for this controller to fetch.
/// That is the **empty-build** case, and the rule's remedy for it — a
/// synchronous build, so no build future can land on top of a synchronous
/// `state =` — is taken here to its root: there is no `AsyncValue` and
/// therefore no build future at all. Every action on this screen is a
/// synchronous mutation (a tapped row), so that race is the one thing that
/// would break it.
///
/// It follows that there is **no loading arm and no error arm**, and neither is
/// a missing state: the shell mounts this body only behind a settled flow, and
/// the flow's own failure surfaces are already `LumenErrorRetry` (the resume
/// read) and `LumenErrorBanner` (the completion). What can still fail here is
/// the save, and that is held on [HormonesForm.failure].
///
/// The list is read **once**, with `ref.read` rather than `ref.watch`, and that
/// is deliberate: re-seeding from a later flow change would discard whatever
/// the user had toggled. Every member of the flow moves — the step, the
/// failure, and the `state` this very controller records its own save onto —
/// and a watch would rebuild this form on all three. The refresh is for the
/// NEXT build of this controller, after the user has left the step and come
/// back to it; it must not reach the one that made the save.
///
/// **It never reads `hormonesProvided`.** After P4b-T8b that boolean is the
/// resume read's answer, not the current one — [OnboardingFlowController
/// ._recordSaved] deliberately leaves the `*Provided` flags alone — so a
/// controller that gated on it would be reading a claim no behaviour holds. The
/// list is the only thing this screen needs, and the list is kept current.
///
/// `autoDispose`, because the form holds the user's own answers and the house
/// rule is that such state must not outlive the screen showing it.
class HormonesController extends Notifier<HormonesForm> {
  @override
  HormonesForm build() {
    final BuiltList<HormoneSelection>? hormones = ref
        .read(onboardingFlowControllerProvider)
        .value
        ?.state
        .hormones;
    return HormonesForm.fromWire(hormones);
  }

  // ── Answering ─────────────────────────────────────────────────────────────

  /// Flips [code], and drops whatever the last attempt said about the answers
  /// it replaced.
  ///
  /// **Every code can be turned off, including the last one**, and unlike
  /// screen 5 nothing downstream objects: charting nothing is a real answer
  /// this endpoint stores.
  ///
  /// A no-op while a save is in flight — that request already carries its
  /// codes, and the 200 replaces the form with the server's re-read, so a
  /// toggle accepted here would be silently discarded a moment later.
  void toggle(String code) {
    if (state.submitting) return;
    state = state.toggle(code).copyWith(clearFailure: true);
  }

  // ── Submitting ────────────────────────────────────────────────────────────

  /// Saves the complete charted set and walks on.
  ///
  /// **It always posts, and it always posts the whole set.** The endpoint is a
  /// FULL REPLACE and the set on screen *is* the answer. Re-posting an
  /// unchanged set is idempotent, and it is what makes `hormonesProvided` true
  /// for a user who accepted the defaults without touching a row.
  ///
  /// **With nothing charted it still posts** — and this is where screen 6 parts
  /// company with screen 5. There is no minimum on this endpoint: the server
  /// keys `value is required` on a NULL `chartedHormones` and on nothing else
  /// (`OnboardingStepsService.cs:435-436`), where `SaveGoalsAsync` adds a
  /// second arm for `Count == 0` (`:369-375`). "Chart nothing" is an answer,
  /// and it is a different state from having skipped the step, so refusing to
  /// send it would be this client refusing what the server stores.
  Future<void> submit() async {
    final HormonesForm form = state;
    // In-flight guard: a second press must not issue a second request.
    if (form.submitting) return;

    final List<String> codes = form.chartedCodes;

    // The previous rejection goes NOW, not when the new attempt lands: without
    // this the old banner sits beside the new spinner, telling the user the
    // attempt they are watching has already failed.
    state = form.copyWith(submitting: true, clearFailure: true);

    // Read BEFORE the await, and held across it, FOR THE RECORD ONLY.
    // `ref.read` on a disposed controller throws, and this one can be disposed
    // while the request is open: the shell's back affordance is not gated on
    // `submitting`, so Back mid-save is an ordinary gesture.
    //
    // Everything else keeps reading the notifier fresh through `ref` — see the
    // advance below. A held reference does NOT resurrect a provider that has
    // since been disposed, and using one for navigation would turn a
    // self-healing `ref.read` into a throw.
    final OnboardingFlowController flowForRecord = ref.read(
      onboardingFlowControllerProvider.notifier,
    );

    List<HormoneChoice>? saved;
    BuiltList<HormoneSelection>? savedOnTheWire;
    Failure? rejected;
    try {
      final response = await ref
          .read(onboardingRepositoryProvider)
          .saveHormones(codes: codes);
      // The 200 is the server's RE-READ of the stored rows rather than an echo
      // of the request, so it is the best answer to "what does the server hold
      // now" — including for a code this build cannot draw.
      savedOnTheWire = response.hormones;
      saved = HormonesForm.fromWire(savedOnTheWire).hormones;
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render.
      // `cachedWrite` invalidates its keys unguarded after a successful write,
      // so a concurrent logout purge closing the Hive box lands here — after
      // the answer was stored. Leaving it unhandled would be a spinner that
      // never stops and a banner that never appears. It is also the
      // stored-but-reported-failure arm: the row may be on the server while the
      // flow keeps the pre-save list. The user sees a banner, so it is not
      // silent, but it is the same class of loss.
      rejected = const UnknownFailure();
    }

    // BEFORE the disposal gate, deliberately. The shell's copy of
    // `GET /onboarding/state` still holds the set this save replaced, and this
    // controller is autoDispose: walking on to step 7 and back would rebuild
    // the form out of that stale list. On a FULL REPLACE endpoint that is not a
    // stale view — the array IS the next request's body, so the following
    // Continue would store the answer the user just changed as deselected.
    //
    // Putting this behind `!ref.mounted` would leave exactly that loss in a
    // narrower window: Back during the save disposes this controller, the 200
    // lands anyway, and the user then walks back through step 6 to reach 7 with
    // the pre-save rows on screen. The flow outlives the step — it is the
    // SHELL's state — so recording onto it is valid precisely when this
    // controller is gone. `_recordSaved` has the gate that matters, on the
    // flow's own lifetime.
    if (rejected == null) flowForRecord.recordHormonesSaved(savedOnTheWire);

    if (!ref.mounted) return;

    if (rejected != null) {
      state = state.copyWith(submitting: false, failure: rejected);
      return;
    }

    state = state.copyWith(
      hormones: saved,
      submitting: false,
      clearFailure: true,
    );

    // Read fresh, not through the held reference above: this line is reached
    // only with THIS controller still mounted, and a fresh `ref.read` rebuilds
    // the flow if it has gone in the meantime instead of throwing on a stale
    // notifier.
    ref.read(onboardingFlowControllerProvider.notifier).next();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 6's controller.
final hormonesControllerProvider =
    NotifierProvider.autoDispose<HormonesController, HormonesForm>(
      HormonesController.new,
    );
