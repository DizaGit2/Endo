import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

// D-01: social login deferred to phase 2.
// The mockup shows "Apple · Google" buttons — omitted in v1 (Keycloak email/
// password only per architecture §A).

/// Screen 2 — Create your account / sign in (onboarding step 2 of 7).
///
/// Full-bleed layout (no 300px phone card): Scaffold → SafeArea →
/// SingleChildScrollView → Padding → Column, matching the pattern established
/// in [WelcomeScreen] and the settings screens.
///
/// States:
/// - Idle  — form is editable, submit button shows label.
/// - Loading — submit button shows [CircularProgressIndicator].
/// - Error — inline red banner above the submit button, form still editable.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _register() async {
    await ref
        .read(accountControllerProvider.notifier)
        .register(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
        );
  }

  Future<void> _signIn() async {
    await ref.read(accountControllerProvider.notifier).signIn();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final state = ref.watch(accountControllerProvider);
    final isLoading = state is AsyncLoading;

    // Extract failure message when in error state.
    final failure = state is AsyncError ? state.error : null;
    final errorMessage = _failureMessage(failure);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section tag
                        const Center(
                          child: LumenSectionLabel(
                            'Step 2 of 7',
                            fontSize: 11,
                            letterSpacing: 1.5,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Headline
                        Text(
                          'Create your account',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          'Your data is encrypted and yours alone.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: c.muted,
                            height: 1.6,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Name field
                        _FieldLabel('Name', color: c.muted),
                        const SizedBox(height: 6),
                        _InputField(
                          controller: _nameCtrl,
                          hint: 'Maya',
                          colors: c,
                          enabled: !isLoading,
                        ),

                        const SizedBox(height: 14),

                        // Email field
                        _FieldLabel('Email', color: c.muted),
                        const SizedBox(height: 6),
                        _InputField(
                          controller: _emailCtrl,
                          hint: 'you@example.com',
                          colors: c,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !isLoading,
                        ),

                        const SizedBox(height: 14),

                        // Password field
                        _FieldLabel('Password', color: c.muted),
                        const SizedBox(height: 6),
                        _InputField(
                          controller: _passwordCtrl,
                          hint: '••••••••',
                          colors: c,
                          obscure: true,
                          enabled: !isLoading,
                        ),

                        const Spacer(),

                        // Inline error message
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBanner(message: errorMessage, colors: c),
                        ],

                        const SizedBox(height: 16),

                        // Primary CTA — "Continue" (register)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: isLoading ? null : _register,
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
                            child: isLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.surface,
                                      semanticsLabel: 'Signing in',
                                    ),
                                  )
                                : const Text('Continue'),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Sign-in affordance — existing users
                        Center(
                          child: TextButton(
                            onPressed: isLoading ? null : _signIn,
                            style: TextButton.styleFrom(
                              foregroundColor: c.muted,
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text('I already have an account'),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Step-indicator dots (7 total, second is active)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 7; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              _StepDot(
                                active: i == 1,
                                color: c.accent,
                                border: c.border,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers — failure message
// ---------------------------------------------------------------------------

String? _failureMessage(Object? failure) {
  if (failure == null) return null;
  if (failure is Failure) return failure.message;
  return 'An unexpected error occurred.';
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    required this.colors,
    this.obscure = false,
    this.keyboardType,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final LumenColors colors;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      enabled: enabled,
      style: TextStyle(fontSize: 14, color: colors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: colors.muted.withValues(alpha: 0.6),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: colors.input,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.colors});
  final String message;
  final LumenColors colors;

  @override
  Widget build(BuildContext context) {
    // liveRegion: true — a screen reader announces this banner as soon as it
    // appears, rather than staying silent about a failed registration/sign-in
    // attempt until the user happens to swipe onto it.
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.accentSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
        ),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: colors.accent,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// A single step-indicator dot.
///
/// Active: accent colour, wider (18×6) pill. Inactive: border colour, circle.
class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.active,
    required this.color,
    required this.border,
  });

  final bool active;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? color : border,
        borderRadius: BorderRadius.circular(active ? 3 : 50),
      ),
    );
  }
}
