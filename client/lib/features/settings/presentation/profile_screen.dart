import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
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
          error: (e, _) => _ErrorBody(error: e),
          data: (result) => _ProfileBody(result: result),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error body
// ---------------------------------------------------------------------------

class _ErrorBody extends ConsumerWidget {
  const _ErrorBody({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // liveRegion: true — announces the failure as soon as it renders,
            // rather than relying on the user to swipe onto it.
            Semantics(
              liveRegion: true,
              child: Text(
                'Something went wrong. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
            const SizedBox(height: 16),
            _RetryButton(
              label: 'Try again',
              c: c,
              onPressed: () => ref.invalidate(profileControllerProvider),
            ),
          ],
        ),
      ),
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
              // Back affordance row (icon + section tag)
              Row(
                children: [
                  Icon(Icons.chevron_left, color: c.muted, size: 22),
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
            _RetryButton(
              label: 'Retry',
              c: c,
              onPressed: () => ref.invalidate(profileControllerProvider),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Retry button — shared outlined affordance for _ErrorBody/_NetworkRequiredBody
// ---------------------------------------------------------------------------

/// A secondary (outlined) retry affordance that calls back into
/// [profileControllerProvider] via [onPressed] (`ref.invalidate` at the call
/// site — this widget stays a dumb [StatelessWidget] so it has no Riverpod
/// dependency of its own). Token colors only: [LumenColors.accent] for the
/// label, [LumenColors.border] for the outline.
class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.label,
    required this.c,
    required this.onPressed,
  });
  final String label;
  final LumenColors c;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
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
    return Semantics(
      button: true,
      label: 'Edit',
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _showEditDialog(context, ref),
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
    final controller = TextEditingController(text: me.displayName ?? '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Edit display name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (confirmed == true && controller.text.trim().isNotEmpty) {
        try {
          await ref
              .read(profileControllerProvider.notifier)
              .saveDisplayName(controller.text.trim());
        } catch (_) {
          // Online-only: the save failed and is NOT queued. Keep the profile on
          // screen and tell the user to retry (no pending-write is persisted).
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                // liveRegion: true — same reasoning as _ErrorBanner/_ErrorBody:
                // announce the failure as it appears.
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
    } finally {
      controller.dispose();
    }
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
    return Semantics(
      button: true,
      label: 'Sign out',
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => ref.read(authStatusProvider.notifier).logout(),
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
