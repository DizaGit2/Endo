import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

// ---------------------------------------------------------------------------
// The scrim
// ---------------------------------------------------------------------------

/// Screen 9's `--ovl`: `rgba(59,42,32,.45)` light, `rgba(0,0,0,.6)` dark.
const _scrimLight = Color(0x733B2A20);
const _scrimDark = Color(0x99000000);

/// The modal scrim colour for [brightness].
///
/// This lives here rather than on [LumenColors] on purpose. The ten fields of
/// [LumenColors] map 1:1 to CLAUDE.md's token table; `--ovl` is not in it — it
/// is declared locally by screen 9's mockup and used by nothing but a modal
/// barrier. Adding an eleventh field would put the Dart tokens out of step
/// with the documented design system to serve one caller.
Color scrimFor(Brightness brightness) =>
    brightness == Brightness.dark ? _scrimDark : _scrimLight;

// ---------------------------------------------------------------------------
// Opening one
// ---------------------------------------------------------------------------

/// Opens the Lumen modal bottom sheet and resolves with whatever the sheet is
/// popped with (`null` if it was dismissed).
///
/// **This is P4b's modal standard.** Screens 9, 11, 12 and 13 are all
/// modals-with-input, and they open them through here so that the scrim, the
/// corner radius, the grab handle and the keyboard behaviour are decided once.
///
/// `isScrollControlled` is on and cannot be turned off: a sheet that owns a
/// text field must be free to grow past the default 9/16 of the screen when
/// the keyboard appears. Growing is not enough on its own, though — see
/// [LumenBottomSheet], which scrolls its content and insets it past the
/// keyboard so a caller never has to.
///
/// [isDismissible] gates BOTH the scrim tap and the drag, so a caller that
/// needs a decision cannot be escaped by a swipe instead.
///
/// **`useRootNavigator: true` (P4b-T18).** `screen-mockups.md:354` is
/// canonical for this screen and says verbatim: *"Bottom nav: belongs to Home
/// (the sheet covers the nav)."* Mounted on a BRANCH Navigator (the SDK
/// default), the sheet would leave the bottom nav's five destinations lit,
/// tappable and semantically live behind the scrim — a spec deviation, not a
/// design choice. Mounting on the app's root Navigator instead puts the sheet
/// above the whole shell, nav included.
Future<T?> showLumenBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    useSafeArea: true,
    // The sheet paints its own surface and its own top-only corners, so the
    // route's Material must not paint a second (square-cornered, tinted) one
    // behind it.
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: scrimFor(Theme.of(context).brightness),
    builder: (sheetContext) => LumenBottomSheet(child: builder(sheetContext)),
  );
}

// ---------------------------------------------------------------------------
// The sheet itself
// ---------------------------------------------------------------------------

/// The chrome of a Lumen bottom sheet: a surface panel with 24 px top corners,
/// a centred grab handle and the mockup's padding.
///
/// Metrics are screen 9's (`Screens/screen_09_quick_checkin.html`), which the
/// mockup survey names as the canonical sheet spec:
///
/// ```css
/// .sheet{ background:var(--f); border-radius:24px 24px 0 0;
///         padding:18px 22px 26px; }
/// .hd   { width:32px; height:3px; background:var(--bd); border-radius:2px;
///         margin:0 auto 14px; }
/// ```
///
/// Screen 20's sheet is 36x4 with 22/22/24 padding; survey decision §15-D9
/// asked for one of the two to become the standard, and this is it.
///
/// Normally reached through [showLumenBottomSheet]. It is public on its own so
/// a golden can photograph it without a [WidgetTester], and so a screen that
/// needs a persistent (non-modal) sheet gets the same chrome.
///
/// The grab handle is decorative: it is a drag affordance for a gesture, and
/// [showLumenBottomSheet] already exposes dismissal to assistive tech through
/// the modal barrier. It carries no semantics so a screen reader does not
/// announce a 32x3 rectangle before the sheet's actual content.
///
/// **[child] is scrolled, and the caller does not add a scroll view.** The
/// sheet grows to its content and stops at the viewport, after which the
/// content scrolls inside it. Doing this in the caller was rejected: screens
/// 9, 11, 12 and 13 all put a form in here, "label + eleven-stop scale + note
/// field + CTA" already exceeds a 667 pt device once a ~300 pt keyboard is up,
/// and the failure mode is a `RenderFlex overflowed` stripe rather than
/// anything a screen author would notice while the simulator has no keyboard.
/// The keyboard inset is added to the bottom PADDING rather than to the
/// scrollable, so the last control clears the keyboard instead of hiding
/// behind it.
class LumenBottomSheet extends StatelessWidget {
  const LumenBottomSheet({required this.child, super.key});

  /// The sheet's content, below the handle.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // The keyboard's height. Without it a sheet with a text field in it is
    // half-covered the moment the field takes focus.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, 18, 22, 26 + keyboard),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle — decorative, hence ExcludeSemantics.
          ExcludeSemantics(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Flexible (loose) + SingleChildScrollView, not Expanded: the sheet
          // must still hug short content — an Expanded would stretch every
          // sheet to the full viewport — while a tall form scrolls rather
          // than overflowing the route.
          Flexible(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}
