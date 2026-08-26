import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

// ---------------------------------------------------------------------------
// ProfileScreen
// ---------------------------------------------------------------------------

/// Screen 31 — Profile & health (Settings).
///
/// Full-bleed layout (Scaffold → SafeArea → SingleChildScrollView → Padding →
/// Column) matching the mockup's 22 px horizontal, 44 px top, 20 px bottom
/// padding — same pattern as [PrivacyScreen] and other settings screens.
///
/// States handled:
/// - Loading  : circular progress indicator.
/// - Loaded (Fresh / Stale) : profile content; Stale shows a subtle notice.
/// - NetworkRequired : "Connect to load profile" message.
/// - Error    : generic error message.
///
/// L-03 trust copy: the mockup's inaccurate "Health info stays on your device"
/// is replaced with the approved legal text (see docs/superpowers/specs/).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final profileAsync = ref.watch(profileControllerProvider);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(semanticsLabel: 'Loading profile'),
          ),
          error: (e, _) => const _ErrorBody(),
          data: (result) => _ProfileBody(result: result),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error body
// ---------------------------------------------------------------------------

/// The generic failure surface.
///
/// The error object itself is deliberately not rendered: it can carry a server
/// `detail` string, and this screen holds PII. The message is the same one the
/// splash's gate-unavailable surface shows, from the same widget.
class _ErrorBody extends ConsumerWidget {
  const _ErrorBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LumenErrorRetry(
      message: 'Something went wrong. Please try again.',
      onRetry: () => ref.invalidate(profileControllerProvider),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile body — handles Fresh / Stale / NetworkRequired
// ---------------------------------------------------------------------------

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.result});
  final CacheResult<MeResponse> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;

    if (result is NetworkRequired<MeResponse>) {
      return const _NetworkRequiredBody();
    }

    final me = result is Fresh<MeResponse>
        ? (result as Fresh<MeResponse>).value
        : (result as Stale<MeResponse>).value;
    final isStale = result is Stale<MeResponse>;

    // Pull-to-refresh: re-reads the profile (never queues a write — the
    // online-only invariant applies to reads too, there is no offline mutation
    // here). AlwaysScrollableScrollPhysics lets the gesture trigger even when
    // the content is shorter than the viewport.
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(profileControllerProvider);
        return ref.read(profileControllerProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 44, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section tag. Fix round 1, M6 (P4b-T17): this used to be a
              // "back affordance row" — a decorative `Icon(chevron_left)`
              // beside this label — which was tolerable while `/profile`
              // was a top-level route (arguably implying "back to wherever
              // you came from") but is dishonest now that this screen is
              // the More branch's ROOT (R-19): there is nothing behind a
              // root to go back TO, and the icon owns no semantics node, so
              // it was purely a visual promise nothing backs. R-10 is the
              // codebase's own rule against exactly this shape (it is what
              // removed `Edit` and `+ Add to this day` at T16); the label
              // alone stays as a plain section eyebrow, matching every
              // other tab root's own `LumenSectionLabel` (e.g. screen 10's
              // "Cycle").
              const LumenSectionLabel(
                'Settings',
                fontSize: 11,
                letterSpacing: 1.5,
              ),

              const SizedBox(height: 4),

              // Screen title
              Text(
                'Profile & health',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),

              const SizedBox(height: 14),

              // Stale notice
              if (isStale) ...[_StaleNotice(c: c), const SizedBox(height: 10)],

              // --- User card ---
              _UserCard(me: me, c: c, ref: ref),

              const SizedBox(height: 14),

              // --- ACCOUNT section ---
              const LumenSectionLabel('Account'),
              const SizedBox(height: 6),
              _InfoRow(
                label: 'Display name',
                value: me.displayName ?? '—',
                c: c,
                trailing: _EditButton(me: me, c: c),
              ),
              const SizedBox(height: 5),
              _InfoRow(label: 'Locale', value: me.locale ?? '—', c: c),
              const SizedBox(height: 5),
              _InfoRow(label: 'Timezone', value: me.timezone ?? '—', c: c),

              const SizedBox(height: 14),

              // --- CYCLE SETTINGS (screen 32) ---
              // Ships in the SAME commit as the route it points at (R-20,
              // P4b-T22a). Screen 32 is the only surface in the app that can
              // ever set `avgPeriodLengthDays`, so a route with no affordance
              // would leave that field unreachable by every user who is not
              // typing URLs.
              _CycleSettingsRow(c: c),

              const SizedBox(height: 5),

              // --- PRIVACY & SECURITY (screen 36) ---
              // Ships in the SAME commit as the route it points at (R-20,
              // P4b-T22c). Screen 36 had existed since P3a and was registered
              // in no route table, so the danger-zone affordance it draws —
              // the app's only way to invoke `DELETE /me` — was reachable by
              // nobody. This row is the other half of closing that.
              _PrivacyRow(c: c),

              const SizedBox(height: 5),

              // --- SIGN OUT ---
              _SignOutRow(c: c),

              const SizedBox(height: 14),

              // --- L-03 trust copy (approved legal text) ---
              _TrustNotice(c: c),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Network-required body
// ---------------------------------------------------------------------------

class _NetworkRequiredBody extends ConsumerWidget {
  const _NetworkRequiredBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: c.muted, size: 40),
            const SizedBox(height: 16),
            // liveRegion: true — same reasoning as _ErrorBody: announce the
            // state as it appears instead of staying silent.
            Semantics(
              liveRegion: true,
              child: Text(
                'Connect to load your profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your profile requires a network connection\nand no cached data is available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            const SizedBox(height: 16),
            LumenRetryButton(
              label: 'Retry',
              onPressed: () => ref.invalidate(profileControllerProvider),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User card
// ---------------------------------------------------------------------------

class _UserCard extends StatelessWidget {
  const _UserCard({required this.me, required this.c, required this.ref});
  final MeResponse me;
  final LumenColors c;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final initials = avatarInitials(me.displayName);
    // MergeSemantics: no onTap exists on this row today (the mockup's
    // chevron has nothing wired behind it yet) — read avatar + name + id as
    // one informational unit rather than three disconnected fragments.
    // NOT Semantics(button: true): that would announce "button" for a tap
    // that does nothing, which is worse than no semantics at all.
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.input,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: c.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    me.displayName ?? '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    me.id ?? '',
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ],
              ),
            ),
            // Decorative — the row's overall meaning is carried by the merged
            // name/id text above; a bare chevron has nothing to announce.
            Icon(Icons.chevron_right, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// Computes 1–2 uppercase initials for the profile avatar from a (possibly
/// null, empty, or whitespace-only) display name. Returns `'?'` when there is
/// no usable name — guarding against a `RangeError` on a blank server value.
@visibleForTesting
String avatarInitials(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

// ---------------------------------------------------------------------------
// Info row (label + value, optional trailing widget)
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.c,
    this.trailing,
  });
  final String label;
  final String value;
  final LumenColors c;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // MergeSemantics is scoped to the label+value pair ONLY (wrapped in its
    // own Expanded, not the whole row): MergeSemantics unconditionally
    // absorbs ALL descendant semantics, including ones that set their own
    // Semantics(container: true) boundary — so a `trailing` action widget
    // (e.g. _EditButton) sits as a sibling OUTSIDE this MergeSemantics scope,
    // keeping its own button identity instead of being swallowed into the
    // row's merged label. The inner Spacer still pushes `value` flush against
    // `trailing` — visually identical to a single un-scoped Row.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.input,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: c.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit button (inline affordance for display name)
// ---------------------------------------------------------------------------

class _EditButton extends ConsumerWidget {
  const _EditButton({required this.me, required this.c});
  final MeResponse me;
  final LumenColors c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shared callback reference: excludeSemantics:true drops the descendant
    // GestureDetector's SemanticsAction.tap from the tree entirely, so
    // Semantics itself needs its own onTap — wired to the SAME callback (not
    // a second closure) so pointer taps and assistive-tech activation always
    // do the same thing.
    void onTap() => _showEditDialog(context, ref);
    return Semantics(
      button: true,
      label: 'Edit',
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          'Edit',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: c.accent,
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    // The dialog OWNS its controller (see [_EditDisplayNameDialog]); this
    // function only receives the resulting text, or null if it was dismissed.
    final entered = await showDialog<String>(
      context: context,
      builder: (_) =>
          _EditDisplayNameDialog(initialValue: me.displayName ?? ''),
    );

    final name = entered?.trim() ?? '';
    if (name.isEmpty) return;

    try {
      await ref.read(profileControllerProvider.notifier).saveDisplayName(name);
    } catch (_) {
      // Online-only: the save failed and is NOT queued. Keep the profile on
      // screen and tell the user to retry (no pending-write is persisted).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // liveRegion: true — same reasoning as LumenErrorBanner /
            // LumenErrorRetry: announce the failure as it appears.
            content: Semantics(
              liveRegion: true,
              child: const Text(
                'Could not save your changes. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Edit-display-name dialog
// ---------------------------------------------------------------------------

/// The edit dialog, as a [StatefulWidget] so that the [TextEditingController]
/// belongs to the dialog's own subtree.
///
/// **This shape is the fix, not a style preference.** The controller used to be
/// a local of `_showEditDialog`, disposed in a `finally`. `showDialog`'s future
/// completes synchronously on `Navigator.pop`, so that `finally` ran one
/// microtask later — while the route's ~150 ms exit transition was still
/// playing. The pop moves focus off the dialog's `FocusScope`, `_TextFieldState`
/// calls `setState`, `TextField.build` allocates a fresh `Listenable.merge`
/// (which has no `==`), and `_AnimatedState.didUpdateWidget` calls
/// `addListener` on the by-then-disposed controller.
///
/// In release that assert is compiled out and nothing user-visible happens, so
/// this was never a device bug. What it cost was coverage: it made the
/// save-failure SnackBar — a `liveRegion` accessibility affordance — impossible
/// to reach from a widget test. Holding the controller in [State] ties its
/// lifetime to the subtree, so it is disposed after the transition, not during.
///
/// Pops with the entered text on Save, and with `null` on Cancel — so the
/// caller never needs to reach into a controller it does not own.
class _EditDisplayNameDialog extends StatefulWidget {
  const _EditDisplayNameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_EditDisplayNameDialog> createState() => _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState extends State<_EditDisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit display name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Display name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cycle settings row — the entry affordance for screen 32
// ---------------------------------------------------------------------------

/// Navigates into screen 32 (`Routes.cycleSettings`), a CHILD of this branch
/// root — [_PrivacyRow]'s shape, for [_PrivacyRow]'s reasons.
///
/// The row's name is [kCycleSettingsRowLabel] (`Cycle settings`) and not the
/// destination's own title (`Cycle`): the bottom nav already announces a
/// destination called `Cycle`, and two controls with one name is a
/// screen-reader problem. The constant's own dartdoc carries that reasoning.
class _CycleSettingsRow extends StatelessWidget {
  const _CycleSettingsRow({required this.c});
  final LumenColors c;

  @override
  Widget build(BuildContext context) {
    // Shared callback reference: excludeSemantics:true drops the descendant
    // GestureDetector's SemanticsAction.tap from the tree entirely, so
    // Semantics itself needs its own onTap — wired to the SAME callback (not
    // a second closure) so pointer taps and assistive-tech activation always
    // do the same thing.
    void onTap() => context.push(Routes.cycleSettings);
    return Semantics(
      button: true,
      label: kCycleSettingsRowLabel,
      container: true,
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
                  kCycleSettingsRowLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: c.ink,
                  ),
                ),
              ),
              // Decorative — the row's Semantics(button, label) above already
              // excludes and replaces this subtree's semantics.
              Icon(Icons.chevron_right, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy & security row — the entry affordance for screen 36
// ---------------------------------------------------------------------------

/// Navigates into screen 36 (`Routes.privacy`), a CHILD of this branch root.
///
/// `push`, not `go`: screen 36 stacks on top of screen 31 inside the More
/// branch's own Navigator, so its back chevron pops back here with the tab
/// still selected. `go` would replace the branch's location and leave the
/// chevron nothing to pop.
///
/// Shaped after [_SignOutRow] rather than extracted into a shared widget: both
/// are private rows on their own screen, and a widget under `lib/shared/
/// widgets/` owes the registry its own golden pair and semantics test
/// (`test/shared/screen_registry_test.dart`) — a cost worth paying for a
/// reused control, not for the second instance of a container with a chevron
/// in it.
class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({required this.c});
  final LumenColors c;

  @override
  Widget build(BuildContext context) {
    // Shared callback reference: excludeSemantics:true drops the descendant
    // GestureDetector's SemanticsAction.tap from the tree entirely, so
    // Semantics itself needs its own onTap — wired to the SAME callback (not
    // a second closure) so pointer taps and assistive-tech activation always
    // do the same thing.
    void onTap() => context.push(Routes.privacy);
    return Semantics(
      button: true,
      label: kPrivacyScreenTitle,
      container: true,
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
                  kPrivacyScreenTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: c.ink,
                  ),
                ),
              ),
              // Decorative — the row's Semantics(button, label) above already
              // excludes and replaces this subtree's semantics.
              Icon(Icons.chevron_right, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sign-out row
// ---------------------------------------------------------------------------

class _SignOutRow extends ConsumerWidget {
  const _SignOutRow({required this.c});
  final LumenColors c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shared callback reference: excludeSemantics:true drops the descendant
    // GestureDetector's SemanticsAction.tap from the tree entirely, so
    // Semantics itself needs its own onTap — wired to the SAME callback (not
    // a second closure) so pointer taps and assistive-tech activation always
    // do the same thing.
    void onTap() => ref.read(authStatusProvider.notifier).logout();
    return Semantics(
      button: true,
      label: 'Sign out',
      container: true,
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
                  'Sign out',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: c.accent,
                  ),
                ),
              ),
              // Decorative — the row's Semantics(button, label: 'Sign out')
              // above already excludes and replaces this subtree's semantics.
              Icon(Icons.chevron_right, size: 16, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stale notice
// ---------------------------------------------------------------------------

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.c});
  final LumenColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.sageSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Showing cached profile — connect to refresh',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: c.sage,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// L-03 trust notice (approved legal copy — replaces the inaccurate mockup text)
// ---------------------------------------------------------------------------

class _TrustNotice extends StatelessWidget {
  const _TrustNotice({required this.c});
  final LumenColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.sageSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Your health data is encrypted and stored on EU servers — only you can '
        'read it. Lab PDFs you upload are processed by our AI provider '
        '(Anthropic) to extract your results, then encrypted at rest.',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: c.sage,
        ),
      ),
    );
  }
}
