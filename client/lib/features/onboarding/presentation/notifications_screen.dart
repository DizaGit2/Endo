import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/notifications_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

// ---------------------------------------------------------------------------
// Constants the tests and the screen share
// ---------------------------------------------------------------------------

/// The stable handle for one category row.
///
/// A key rather than a semantics label, because a test that taps a control by
/// what it ANNOUNCES fails inside `tester.tap` when the announcement changes —
/// which is indistinguishable from a passing assertion having been broken
/// (P4b-T5c). Tests locate a row with this; `find.bySemanticsLabel` appears
/// only inside assertions about what is announced.
Key notificationRowKey(String code) => ValueKey<String>('notification:$code');

/// The stable handle for one category's pill toggle.
///
/// The pill announces nothing — the row carries the state as
/// `SemanticsFlag.isSelected` — so its appearance is reachable only by reading
/// its `BoxDecoration` and its knob's `Align`. Without this key its two
/// conditional lines would be covered by the goldens alone.
Key notificationTogglePillKey(String code) =>
    ValueKey<String>('notification-toggle:$code');

/// The stable handle for the primary CTA ("Allow & finish").
const Key kNotificationsAllowKey = ValueKey<String>('notifications-allow');

/// The stable handle for the skip CTA ("Not now").
///
/// The two CTAs are two different **request sequences**, so a test must be able
/// to name each of them without going through what it says.
const Key kNotificationsSkipKey = ValueKey<String>('notifications-skip');

// ---------------------------------------------------------------------------
// NotificationsScreen
// ---------------------------------------------------------------------------

/// Screen 7 — "Stay in tune" (onboarding step 7 of 7), **the last step and the
/// only screen that can finish the flow**.
///
/// It is a step BODY, not a route: the eyebrow, the back affordance, the dot
/// row and the padding all belong to `OnboardingShellScreen`, which mounts this
/// in place of the `notifications` arm of its exhaustive switch.
///
/// ## The list it draws is the server's
///
/// `GET /onboarding/state` and `POST /onboarding/notifications` both answer the
/// **complete** vocabulary in frozen order with a boolean per code, and this
/// screen renders that list ([NotificationsForm.categories]). It does not
/// iterate [NotificationOption] to decide what exists — that enum is copy plus
/// the seed for the one case the wire cannot answer. The vocabulary is
/// append-only on the server, so a client that re-derived it would silently
/// disagree with storage the day a fifth code lands.
///
/// A code this build has no copy for is therefore **not drawn**, but it is
/// still carried into the write. See [NotificationsForm.drawable].
///
/// ## "Phase shift", singular
///
/// The mockup's row reads "Phase shifts".
/// `HormoneCatalog.NotificationCategories.Labels` says the canonical label is
/// **"Phase shift"** and names the plural as the drift
/// (`HormoneCatalog.cs:85-108`, B16, `definitions.md:740`). The catalogue is
/// the authority and the plural does not ship.
///
/// ## Two CTAs, two request sequences
///
/// **"Allow & finish"** → `POST /onboarding/notifications` (FULL REPLACE of all
/// four rows) then `POST /onboarding/complete`.
/// **"Not now"** → `POST /onboarding/complete` **only**, writing no preference
/// row at all — D-02's skip means *not calling the step endpoint*. They are not
/// two paths to one request, and an empty post would not be a skip: see
/// [NotificationsController.notNow] for what the server does with each.
///
/// The completion's **409** is the interesting path, and this screen is its
/// first real consumer: `code: onboarding_incomplete` with e.g.
/// `missingSteps: ["cycle"]` becomes an actionable route to that step, carrying
/// the server's own message, handled in [OnboardingFlowController.complete]. A
/// step code this build does not know leaves the user where they are.
///
/// ## The preferences are stored and unconsumed, deliberately
///
/// **P4a stores these rows and dispatches nothing** (§G14,
/// `OnboardingContracts.cs:303-306`), so no notification will fire in P4b at
/// all. That is ruling R-10 and not an oversight: they are real stored
/// preferences P6 and P9a consume, and the phase-unavailable states elsewhere
/// already tell the user what this build does not do yet. So there is **no
/// explanatory note on this screen**, and no copy about when notifications will
/// start — inventing one would be a promise with no date behind it.
///
/// ## Quiet hours and the DAILY / CYCLE EVENTS grouping are not here
///
/// Both belong to settings screen 34. `definitions.md:757` puts group
/// assignment in "settings layout, not a property of the category", and
/// onboarding is a single ungrouped list.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(notificationsControllerProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);
    final c = Theme.of(context).extension<LumenColors>()!;

    final bannerMessage = _bannerMessage(form.failure);
    final bool busy = form.submitting;

    // There is no loading arm and no error arm, and neither is missing: this
    // body makes no read of its own. The category list came with the shell's
    // resume read, which has already settled by the time the shell mounts a
    // step, and the shell owns both of that read's failure surfaces — including
    // the completion's, which is why a 409 shows no banner here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The mockup's `.bell`: a 64 px accent-soft circle with a glyph in it,
        // centred, `margin: 6px auto 14px`.
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accentSoft,
            ),
            alignment: Alignment.center,
            // No `semanticLabel`: an Icon without one contributes no node at
            // all, so the screen announces its heading rather than a shape.
            //
            // The mockup fills this circle with `◐` — a text fallback for a
            // shape its author could not draw, in an element its own CSS names
            // `.bell`. P3c's rule turns a decorative dingbat into an `Icon`, and
            // the class name is the better evidence of intent than the glyph
            // that stood in for it, so this is a bell and not the `Icons
            // .contrast` that screen 5 maps `◐` to where the element has no such
            // name.
            child: Icon(Icons.notifications_none, size: 28, color: c.accent),
          ),
        ),

        const SizedBox(height: 14),

        // Centred, unlike screens 3-6: the mockup puts `text-align:center` on
        // this screen's `.h` and `.sb` alone.
        SizedBox(
          width: double.infinity,
          child: Semantics(
            header: true,
            child: Text(
              'Stay in tune',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w500,
                color: c.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        SizedBox(
          width: double.infinity,
          child: Text(
            'Soft nudges only. Mute anytime.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
          ),
        ),

        const SizedBox(height: 18),

        // The mockup's `.nl` column, at its 8 px gap. Built from the SERVER's
        // list, in the SERVER's order.
        for (final (int index, NotificationChoice choice)
            in form.drawable.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: 8),
          _CategoryRow(
            key: notificationRowKey(choice.code),
            code: choice.code,
            option: choice.option!,
            enabled: choice.enabled,
            interactive: !busy,
            onTap: () => controller.toggle(choice.code),
          ),
        ],

        // No minimum and no message explaining one: muting everything is an
        // answer this endpoint stores.

        // The mockup's `.btn { margin-top:auto }`. What it pushes against is
        // `OnboardingStepSlot`, which is why this is a `Spacer` and not a
        // `SizedBox` of some measured height.
        const Spacer(),

        if (bannerMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          LumenErrorBanner(message: bannerMessage),
        ],

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: kNotificationsAllowKey,
            // Live with nothing enabled, deliberately: there is no minimum on
            // this endpoint. The only thing that takes it away is a request
            // already in flight.
            onPressed: busy ? null : controller.allowAndFinish,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              elevation: 0,
            ),
            child: form.inFlight == NotificationsAction.allowAndFinish
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.surface,
                      // The shell's own spinner label, reused rather than
                      // invented: no copy for this state exists in the mockup
                      // or in `definitions.md`.
                      semanticsLabel: 'Loading',
                    ),
                  )
                : const Text('Allow & finish'),
          ),
        ),

        const SizedBox(height: 8),

        // The mockup's `.skip`: muted 12 px text under the primary, with no box
        // of its own. It stands down while a request is in flight — it would
        // otherwise complete the flow while the save it is racing decides what
        // the server holds.
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: kNotificationsSkipKey,
            onPressed: busy ? null : controller.notNow,
            style: TextButton.styleFrom(
              foregroundColor: c.muted,
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
            child: form.inFlight == NotificationsAction.notNow
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.muted,
                      semanticsLabel: 'Loading',
                    ),
                  )
                : const Text('Not now'),
          ),
        ),
      ],
    );
  }
}

/// What the banner above the CTAs says, or null when there is nothing wrong.
///
/// Same shape as screens 2-6: the banner is this body's live region for a failed
/// WRITE. For a [ValidationFailure] it prefers the server's reserved cross-field
/// messages, which name no input.
///
/// **A failed COMPLETION is not here.** `OnboardingFlowController.complete`
/// holds that on the flow and the shell renders it, because the 409 it can carry
/// moves the user to another step and the message has to travel with them.
///
/// There is no per-field slot below the list, and that is not an omission: the
/// only fields this endpoint can reject on the categories are
/// `enabledCategories` and `enabledCategories[i]`, and both are statements about
/// the list of rows as a whole.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
  return failure.message;
}

// ---------------------------------------------------------------------------
// One category
// ---------------------------------------------------------------------------

/// The mockup's `.n` row: a name, a sub-description and a pill toggle.
///
/// Announced as ONE node carrying both strings. They are joined with a newline
/// and nothing else — that is the separator `MergeSemantics` uses when it folds
/// sibling labels together, so the reading order is the framework's own and no
/// punctuation is invented between two pieces of mockup copy.
///
/// The box, the selected styling and the button semantics are
/// [LumenSelectableRow]'s (P4b-T5d); this class is the category-specific content
/// inside it. Screen 7's `.n` is `padding:12px 14px; border-radius:12px`, which
/// is exactly that widget's default, so it passes neither.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.code,
    required this.option,
    required this.enabled,
    required this.interactive,
    required this.onTap,
    super.key,
  });

  /// The wire code, used for the toggle's handle.
  final String code;

  /// The copy this build holds for [code].
  final NotificationOption option;

  /// Whether this category may notify.
  final bool enabled;

  /// False only while a request is in flight — a toggle accepted then would be
  /// discarded by the response a moment later, so the row stops offering one.
  final bool interactive;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return LumenSelectableRow(
      selected: enabled,
      enabled: interactive,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.description,
                  style: TextStyle(fontSize: 10, color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PillToggle(code: code, on: enabled),
        ],
      ),
    );
  }
}

/// The mockup's `.tgl`: a 30x18 pill with a 14 px knob at one end.
///
/// Pure decoration. It draws the same fact the row already announces as
/// `SemanticsFlag.isSelected`, and it contributes no semantics node of its own —
/// a `Container` without a `Semantics` ancestor of its own adds nothing to the
/// tree, so the row keeps announcing its name and sub-copy rather than "switch,
/// on".
///
/// **Being silent is exactly why it carries [notificationTogglePillKey]**:
/// announcing nothing means no accessibility assertion can see it, so its two
/// conditional lines are read directly in
/// `notifications_screen_semantics_test.dart`.
///
/// It is screen 7's own geometry and not screen 6's: that pill is 28x16 with a
/// 12 px knob, and the mockups' absolute sizes are this phase's fidelity bar.
/// Two near-identical private pills is a promotion candidate for whichever task
/// draws a third — the shape T5d's shared-widget registry would then demand a
/// golden pair and a semantics test for.
class _PillToggle extends StatelessWidget {
  const _PillToggle({required this.code, required this.on});

  /// The wire code, for the handle only — the pill draws nothing from it.
  final String code;

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Container(
      key: notificationTogglePillKey(code),
      width: 30,
      height: 18,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? c.accent : c.border,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Align(
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            // The mockup's `background: var(--f)` — the surface token, so the
            // knob reads against the accent fill in both themes.
            color: c.surface,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
