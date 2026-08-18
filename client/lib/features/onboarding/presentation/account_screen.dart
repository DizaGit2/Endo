import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/application/account_validation.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

// D-01 was REOPENED on 2026-07-08: social login is IN for v1, and lands in its
// own phase, P4c. The mockup's "Apple · Google" buttons are therefore not
// dropped — they are simply not this phase's work, and P4b must not add them.
// Until P4c, registration is Keycloak email/password only (architecture §A).

/// Screen 2 — Create your account / sign in (onboarding step 2 of 7).
///
/// Full-bleed layout (no 300px phone card): Scaffold → SafeArea →
/// SingleChildScrollView → Padding → Column, matching the pattern established
/// in [WelcomeScreen] and the settings screens.
///
/// States:
/// - Idle  — form is editable, submit button shows label.
/// - Loading — submit button shows [CircularProgressIndicator].
/// - Error — inline banner above the submit button, plus a message under each
///   rejected field, form still editable and still holding what was typed.
///
/// **Rejections have one rendering path** (P4b-T7). [AccountController]
/// answers a locally-invalid form with the same [ValidationFailure] shape a
/// server 400 produces — `fields` keyed by the camelCase wire name — so
/// `messageFor` below does not know or care which end rejected the form.
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
    final errorMessage = _bannerMessage(failure);
    // Non-null only for a rejection that named fields; every other failure
    // leaves all three fields clean and speaks through the banner alone.
    final rejected = failure is ValidationFailure ? failure : null;

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
                        LumenInputField(
                          controller: _nameCtrl,
                          label: 'Name',
                          hint: 'Maya',
                          enabled: !isLoading,
                          errorText: rejected?.messageFor(
                            AccountFields.displayName,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Email field
                        _FieldLabel('Email', color: c.muted),
                        const SizedBox(height: 6),
                        LumenInputField(
                          controller: _emailCtrl,
                          label: 'Email',
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          enabled: !isLoading,
                          errorText: rejected?.messageFor(AccountFields.email),
                        ),

                        const SizedBox(height: 14),

                        // Password field
                        _FieldLabel('Password', color: c.muted),
                        const SizedBox(height: 6),
                        LumenInputField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          hint: '••••••••',
                          obscure: true,
                          enabled: !isLoading,
                          errorText: rejected?.messageFor(
                            AccountFields.password,
                          ),
                        ),

                        const Spacer(),

                        // Inline error message
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          LumenErrorBanner(message: errorMessage),
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
                        const LumenStepDots(count: 7, activeIndex: 1),
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

/// What the banner above the CTA says, or `null` when there is nothing wrong.
///
/// The banner is never suppressed in favour of the field errors, even though
/// they say more: it is the screen's only live region, so dropping it would
/// mean a screen-reader user got no announcement at all that the submit had
/// failed — the field messages are ordinary nodes and stay silent until
/// swiped onto.
///
/// For a [ValidationFailure] it prefers the server's reserved
/// [ValidationFailure.requestKey] messages, which are the cross-field errors
/// that name no input and would otherwise render nowhere.
String? _bannerMessage(Object? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
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

