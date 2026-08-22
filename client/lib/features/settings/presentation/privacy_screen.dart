import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/settings/application/account_erasure_controller.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------
//
// **Every AUTHORED string below is L-05/L-06-GATED and goes to the PO/legal
// pass before release.** P4a's STATUS records three open L-05/L-06 blockers,
// two of which falsify the wording this screen would otherwise have reached
// for: "erased data remains encrypted and unreadable" is no longer true of
// plaintext health data (§D mandates plaintext for the P6 engine, so
// destroying the DEK does nothing to those rows), and the backup horizon is
// UNBOUNDED (§G defines a nightly `pg_dump` with no expiry and no lifecycle
// rule). So the copy here describes WHAT THE USER'S ACTION DOES and stops
// there: it does not say what survives, for how long, or in what form. Any
// sentence about backups, encryption or irreversibility would be a legal
// claim, and `privacy_screen_erasure_test.dart` fails on one.

/// Screen 36's own title, and the NAME of the row on screen 31 that reaches
/// it.
///
/// **EXTRACTED** — `Screens/screen_36_privacy.html` draws `Privacy & security`.
/// One constant for both so the affordance and its destination cannot come to
/// be called different things (R-20's spirit: they ship together).
const String kPrivacyScreenTitle = 'Privacy & security';

/// The danger-zone row. **EXTRACTED** — the mockup's own words, unchanged.
///
/// Its scope is narrower than the endpoint's: `DELETE /me` erases the ACCOUNT
/// as well as the data in it, and disables the identity, which is why
/// [kPrivacyDeleteConfirmTitle] names both. Renaming the row is a copy
/// decision the PO owns, so the row keeps the drawn label and the confirmation
/// states the real scope — recorded in the T22c report rather than decided
/// here.
const String kPrivacyDeleteRowLabel = 'Delete all data';

/// The confirmation's question. **AUTHORED, L-05/L-06-gated.**
///
/// Names the account as well as the data, because the endpoint does both and
/// the row's extracted label mentions only one.
const String kPrivacyDeleteConfirmTitle = 'Delete your account and data?';

/// The confirmation's body. **AUTHORED, L-05/L-06-gated.**
///
/// Two sentences, both about THIS ACTION rather than about its aftermath: what
/// gets sent, and the one consequence the app itself delivers a moment later
/// (the sign-out). The house confirmation body on screen 11
/// (`kPeriodEditorDeleteConfirmBody`) ends *"It cannot be undone."*; that
/// sentence is deliberately NOT reused here — for one cycle event it is a
/// statement about a row, and for an account it is a legal claim that L-05/
/// L-06 blockers 2 and 3 have already falsified.
const String kPrivacyDeleteConfirmBody =
    'This sends a deletion request for your account and the data in it. '
    'You will be signed out.';

/// The confirmation's destructive action. **SHIPPED-PRECEDENT** — screen 11's
/// `kPeriodEditorDeleteConfirmLabel`.
const String kPrivacyDeleteConfirmLabel = 'Delete';

/// The confirmation's dismissal. **SHIPPED-PRECEDENT** — every dialog in this
/// app labels its dismissal `Cancel`.
const String kPrivacyDeleteCancelLabel = 'Cancel';

/// What the user is told when the server ACCEPTS the request.
/// **AUTHORED, L-05/L-06-gated.**
///
/// `DELETE /me` answers `202`: the erasure job is enqueued and the identity is
/// disabled, and that is all that has happened when this string appears. It
/// therefore reports RECEIPT, never completion — telling a user their data is
/// gone when the job has merely been queued would be false, and on this
/// surface it would also be a compliance statement.
const String kPrivacyErasureRequestedMessage =
    'Deletion request received. It is being processed.';

/// What the user is told when the request does not succeed.
/// **AUTHORED, L-05/L-06-gated.**
///
/// *"Could not confirm"* rather than *"did not go through"*, and the
/// difference is the same discipline [kPrivacyErasureRequestedMessage] applies
/// in the other direction. A refusal this client can see (a 401, a 400) does
/// mean nothing happened — but a dropped connection or a 5xx can hide a
/// request the server already accepted (S-6), and asserting failure there
/// would be claiming an outcome the client does not have. One string covers
/// all three because the next step is the same in all three, and retrying is
/// safe: the endpoint is idempotent and self-heals a half-finished erasure
/// (`Program.cs`'s `MapDelete("/me")`).
const String kPrivacyErasureFailedMessage =
    'We could not confirm your deletion request. Please try again.';

// ---------------------------------------------------------------------------

/// Leaves screen 36.
///
/// `canPop()` first, `go` second — screen 11's `_leaveDayDetail` shape, for
/// its reason: this is a CHILD route of the More branch, so it normally pops
/// back onto screen 31, but a COLD deep link straight to `/more/privacy`
/// leaves nothing on the branch's stack to pop to. `go` then puts the user on
/// the branch root rather than on a dead control.
void _leavePrivacy(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.more);
  }
}

// ---------------------------------------------------------------------------
// PrivacyScreen
// ---------------------------------------------------------------------------

/// Screen 36 — Privacy & security (Settings).
///
/// D-07: the "Anonymous analytics" toggle from the DATA section is omitted —
/// there is no analytics in v1.
///
/// Sections:
/// - APP LOCK: Face ID, Hide content in app switcher, Disguised app icon
///   (visual-only toggles — no preference behind them yet)
/// - DATA: Encryption status (no analytics toggle per D-07)
/// - DANGER ZONE: [kPrivacyDeleteRowLabel] — **live since P4b-T22c**
/// - Warrant-canary notice (reproduced as-is from mockup)
///
/// **This stopped being a static screen at P4b-T22c.** `DELETE /me` had worked
/// end to end since P4a and was reachable by nobody: the danger-zone row was
/// drawn with no `onTap`, and the screen itself was registered in no route
/// table. It now has both — see [Routes.privacy] for the mount and
/// [PrivacyScreen._confirmAndRequestErasure] for what the row does.
///
/// A `ConsumerWidget` and not a `StatefulWidget`: the only mutable state is
/// "is a request in flight", and that lives in
/// [accountErasureControllerProvider] where the row can watch it.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  /// Asks first, then requests the erasure, then ends the session.
  ///
  /// **The order is the ruling.** The 202 must be in hand before anything
  /// about the session moves: signing out first (or concurrently) would tell
  /// the user the request landed when it may not have. So the request is
  /// awaited, the outcome decides the message, and only an ACCEPTED request
  /// signs the user out.
  ///
  /// **The sign-out is not optional on acceptance.** The same call disables
  /// the Keycloak identity, so every subsequent authenticated request 401s;
  /// leaving the user inside an app whose every read fails is worse than
  /// ending the session for them. The router does the navigating —
  /// `authStatusProvider` flipping to unauthenticated is what `lumenRedirect`
  /// reacts to — so there is no `context.go` here to get out of step with it.
  ///
  /// **The messenger and the notifier are captured BEFORE the awaits, on
  /// purpose.** Both outlive this widget: the `ScaffoldMessenger` is the app
  /// root's, so the message survives the redirect the sign-out triggers, and
  /// holding the notifier means an unmount mid-request cannot skip the
  /// sign-out. Nothing here touches `context` or `ref` after an `await`.
  ///
  /// `confirmed != true` covers the explicit Cancel and a barrier tap alike,
  /// which pops `null`. Nothing is sent on either.
  Future<void> _confirmAndRequestErasure(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = ref.read(authStatusProvider.notifier);
    final erasure = ref.read(accountErasureControllerProvider.notifier);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteConfirmationDialog(),
    );
    if (confirmed != true) return;

    final accepted = await erasure.requestErasure();

    messenger.showSnackBar(
      SnackBar(
        // liveRegion: true — the house rule for a message that appears without
        // the user moving focus to it (LumenErrorBanner, LumenErrorRetry,
        // profile_screen's save-failure SnackBar).
        content: Semantics(
          liveRegion: true,
          child: Text(
            accepted
                ? kPrivacyErasureRequestedMessage
                : kPrivacyErasureFailedMessage,
          ),
        ),
      ),
    );

    if (accepted) await auth.logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final busy = ref.watch(accountErasureControllerProvider);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 44, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back affordance row (control + section tag).
                //
                // **The chevron is a real control since P4b-T22c, because the
                // screen is a real route since P4b-T22c.** It was a decorative
                // `Icon` while `PrivacyScreen` was registered in no route
                // table and could only be pumped directly by a test — the same
                // shape T17 REMOVED from screen 31, on the grounds that a
                // chevron nothing backs is a promise the screen cannot keep.
                // Screen 36 is now a child of the More branch, so there IS
                // something to pop back to, and the honest fix is the other
                // one: wire it.
                //
                // `semanticLabel` on the Icon (screens 11 and 12's precedent),
                // never `tooltip:` — Material surfaces a tooltip as a SEPARATE
                // semantics field rather than the button's own name, which
                // would leave this control announcing nothing. The word is
                // `MaterialLocalizations`' own translated name for the
                // control, not copy this screen invented.
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.chevron_left,
                        semanticLabel: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                      ),
                      iconSize: 22,
                      color: c.muted,
                      padding: EdgeInsets.zero,
                      onPressed: () => _leavePrivacy(context),
                    ),
                    const SizedBox(width: 2),
                    const LumenSectionLabel(
                      'Settings',
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Screen title
                Text(
                  kPrivacyScreenTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),

                const SizedBox(height: 14),

                // --- APP LOCK section ---
                const LumenSectionLabel('App lock'),
                const SizedBox(height: 6),
                const _SettingsToggleRow(
                  label: 'Face ID',
                  subtitle: 'Required to open',
                  enabled: true,
                ),
                const SizedBox(height: 5),
                const _SettingsToggleRow(
                  label: 'Hide content in app switcher',
                  subtitle: 'Show blank screen',
                  enabled: true,
                ),
                const SizedBox(height: 5),
                const _SettingsToggleRow(
                  label: 'Disguised app icon',
                  subtitle: 'Show as "Notes"',
                  enabled: false,
                ),

                const SizedBox(height: 14),

                // --- DATA section ---
                const LumenSectionLabel('Data'),
                const SizedBox(height: 6),
                _SettingsInfoRow(
                  label: 'Encryption status',
                  value: 'AES-256',
                  valueColor: c.sage,
                  trailingIcon: Icon(Icons.check, size: 14, color: c.sage),
                ),

                // NOTE: D-07 — "Anonymous analytics" toggle omitted (no analytics in v1).
                const SizedBox(height: 14),

                // --- DANGER ZONE section ---
                const LumenSectionLabel('Danger zone'),
                const SizedBox(height: 6),
                _DeleteAllDataRow(
                  // Frozen while a request is in flight — the guard against a
                  // second enqueue, and the reason the row reports itself as
                  // disabled rather than staying a button that does nothing
                  // (P4b-T16b's rule, applied here).
                  onTap: busy
                      ? null
                      : () => _confirmAndRequestErasure(context, ref),
                  busy: busy,
                ),

                const SizedBox(height: 14),

                // Warrant-canary notice (reproduced from mockup as-is,
                // '✦' dingbat replaced by an inline Icons.auto_awesome via
                // WidgetSpan so it wraps as part of the same paragraph).
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.sageSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: c.sage,
                          ),
                        ),
                        const TextSpan(
                          text: '  Lumen has never received a data request',
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: c.sage,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helper widgets
// ---------------------------------------------------------------------------

/// A settings row with a label, optional subtitle, and a toggle (on/off).
class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.label,
    required this.enabled,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // MergeSemantics: label + subtitle read as one unit. _MiniToggle is
    // documented visual-only (no onTap anywhere on this row today), so it is
    // safe to merge in too — unlike profile_screen.dart's _InfoRow, there is
    // no independently-actionable descendant here to protect.
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: c.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _MiniToggle(enabled: enabled),
          ],
        ),
      ),
    );
  }
}

/// A settings row showing a label and a static value string on the right,
/// with an optional trailing icon beside the value (e.g. a check mark).
class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.trailingIcon,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Widget? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // MergeSemantics: label + value (+ decorative icon, silent by default)
    // read as one unit, e.g. "Encryption status, AES-256".
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: c.ink,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: valueColor,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              trailingIcon!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The danger-zone row: the app's ONLY way to invoke `DELETE /me`.
///
/// It was `_SettingsNavRow` — a `MergeSemantics` over a label and a decorative
/// chevron, documented as informational *"because this row has no destination
/// screen wired up yet"*. P4b-T22c gave it one, so it is a real button now.
///
/// **[onTap] is `required` and nullable, deliberately.** Required, so a call
/// site cannot let this row drift back into inertness by omission; nullable,
/// because the row genuinely has nothing to do while a request is out. The
/// semantics `enabled` flag follows the ACTION rather than a separate
/// parameter (`LumenSelectableChip`'s rule, and `LumenIntensityScale._Stop`'s
/// before it): a node that keeps `isButton`, offers no tap action and still
/// claims to be enabled is "looks like a button, cannot be activated, never
/// says why".
///
/// While [busy] the trailing chevron is replaced by a spinner, because the
/// wait is a real network round trip (`dioProvider` allows up to 15 s to
/// connect) and a destructive action that swallows the tap and shows nothing
/// is how a user taps it twice.
class _DeleteAllDataRow extends StatelessWidget {
  const _DeleteAllDataRow({required this.onTap, required this.busy});

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Semantics(
      button: true,
      label: kPrivacyDeleteRowLabel,
      enabled: onTap != null,
      container: true,
      // excludeSemantics: true drops the descendant GestureDetector's own
      // SemanticsAction.tap, so this Semantics needs its own onTap — wired to
      // the SAME callback (not a second closure) so pointer taps and
      // assistive-tech activation always do the same thing.
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.input,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  kPrivacyDeleteRowLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: c.accent,
                  ),
                ),
              ),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                )
              else
                // Decorative — the row's Semantics(button, label) above
                // already excludes and replaces this subtree's semantics.
                Icon(Icons.chevron_right, size: 16, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The erasure confirmation
// ---------------------------------------------------------------------------

/// The house confirmation shape: `showDialog` + [AlertDialog], the same one
/// screen 11 uses for deleting a single cycle event
/// (`period_editor_screen.dart`'s `_DeleteConfirmationDialog`) and screen 31
/// uses for its edit dialog. Not a new idiom for a larger action — and
/// deliberately NOT a type-the-word-DELETE gate, which is a product decision
/// nobody has made.
///
/// Pops `true` for the destructive action and `false` for the dismissal; a
/// barrier tap pops `null`, and the caller treats anything that is not `true`
/// as "do nothing". **So the DEFAULT outcome of this dialog is to do
/// nothing**, and the dismissal is both first in the action row and the
/// autofocused control, so a stray keyboard or switch activation cannot take
/// the destructive branch either.
class _DeleteConfirmationDialog extends StatelessWidget {
  const _DeleteConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(kPrivacyDeleteConfirmTitle),
      content: const Text(kPrivacyDeleteConfirmBody),
      actions: <Widget>[
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text(kPrivacyDeleteCancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(kPrivacyDeleteConfirmLabel),
        ),
      ],
    );
  }
}

/// A compact visual-only toggle pill (26×16 px) matching the mockup's design.
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // OFF track: a low-opacity muted tint — visible in both light and dark themes
    // without referencing hard-coded brand hex. ON track: full accent colour.
    final trackColor = enabled ? c.accent : c.muted.withValues(alpha: 0.35);
    // Thumb: surface colour — contrasts clearly against both accent (ON) and the
    // muted tint (OFF) in light AND dark themes.
    final thumbColor = c.surface;
    return SizedBox(
      width: 26,
      height: 16,
      child: Stack(
        children: [
          // Track
          Container(
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // Thumb
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            left: enabled ? null : 2,
            right: enabled ? 2 : null,
            top: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: thumbColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
