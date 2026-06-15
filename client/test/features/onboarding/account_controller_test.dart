// Tests for AccountController.
//
// TDD cycle: RED first — this file was written before any production code.
// The controller coordinates:
//   1. register() → OnboardingRepository.startOnboarding() → AuthController.login()
//   2. signIn()   → AuthController.login() only (existing user)
//
// Coverage:
//   - register success: repo called, login called, state is AsyncData(null)
//   - register failure: repo throws Failure, login NOT called, state is AsyncError
//   - signIn success: login called, state is AsyncData(null)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// A thin [AuthController] stub that records whether [login] was called.
/// Extends [AuthController] (a Notifier) so it satisfies the provider type.
class _FakeAuthController extends AuthController {
  bool loginCalled = false;
  bool loginShouldThrow = false;

  @override
  AuthStatus build() => AuthStatus.unauthenticated;

  @override
  Future<void> login() async {
    loginCalled = true;
    if (loginShouldThrow) throw Exception('login failed');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [ProviderContainer] with:
///  - [onboardingRepositoryProvider] overridden with a mock repository.
///  - [authStatusProvider] overridden with a [_FakeAuthController].
///
/// Returns both the container and the fake controller so tests can inspect state.
({ProviderContainer container, _FakeAuthController fakeAuth}) makeContainer({
  required MockOnboardingRepository repo,
  bool loginShouldThrow = false,
}) {
  final fakeAuth = _FakeAuthController()..loginShouldThrow = loginShouldThrow;

  final container = ProviderContainer(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(repo),
      authStatusProvider.overrideWith(() => fakeAuth),
    ],
  );

  return (container: container, fakeAuth: fakeAuth);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockOnboardingRepository repo;

  setUp(() {
    repo = MockOnboardingRepository();
  });

  // Provide default fallback values for named params used with any().
  setUpAll(() {
    registerFallbackValue(const NetworkFailure());
  });

  // -------------------------------------------------------------------------
  // register()
  // -------------------------------------------------------------------------

  group('AccountController.register()', () {
    test(
      'success: calls startOnboarding then login; state becomes AsyncData(null)',
      () async {
        when(
          () => repo.startOnboarding(
            email: any(named: 'email'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
          ),
        ).thenAnswer((_) async {});

        final (:container, :fakeAuth) = makeContainer(repo: repo);
        addTearDown(container.dispose);

        await container
            .read(accountControllerProvider.notifier)
            .register(
              email: 'test@example.com',
              password: 'secret123',
              displayName: 'Maya',
            );

        // Repo must have been called with the supplied arguments.
        verify(
          () => repo.startOnboarding(
            email: 'test@example.com',
            password: 'secret123',
            displayName: 'Maya',
          ),
        ).called(1);

        // Auth login must have been triggered.
        expect(fakeAuth.loginCalled, isTrue);

        // Controller state must be a success (AsyncData with null payload).
        expect(
          container.read(accountControllerProvider),
          isA<AsyncData<void>>(),
        );
      },
    );

    test(
      'failure: repo throws Failure → state is AsyncError; login NOT called',
      () async {
        const failure = ServerFailure();
        when(
          () => repo.startOnboarding(
            email: any(named: 'email'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
          ),
        ).thenThrow(failure);

        final (:container, :fakeAuth) = makeContainer(repo: repo);
        addTearDown(container.dispose);

        await container
            .read(accountControllerProvider.notifier)
            .register(
              email: 'bad@example.com',
              password: 'wrongpw',
              displayName: 'Maya',
            );

        // Login must NOT have been called when registration fails.
        expect(fakeAuth.loginCalled, isFalse);

        // State must surface the error.
        final state = container.read(accountControllerProvider);
        expect(state, isA<AsyncError<void>>());
        expect((state as AsyncError<void>).error, equals(failure));
      },
    );

    test(
      'account already exists (409 → ConflictFailure): falls through to login '
      'instead of dead-ending on an error',
      () async {
        // e.g. a prior attempt created the Keycloak account but the interactive
        // login was cancelled; re-tapping Continue re-POSTs and gets a 409.
        when(
          () => repo.startOnboarding(
            email: any(named: 'email'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
          ),
        ).thenThrow(const ConflictFailure());

        final (:container, :fakeAuth) = makeContainer(repo: repo);
        addTearDown(container.dispose);

        await container
            .read(accountControllerProvider.notifier)
            .register(
              email: 'existing@example.com',
              password: 'secret123',
              displayName: 'Maya',
            );

        // Must proceed to login (recovery), not surface a generic error.
        expect(fakeAuth.loginCalled, isTrue);
        expect(
          container.read(accountControllerProvider),
          isA<AsyncData<void>>(),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // signIn()
  // -------------------------------------------------------------------------

  group('AccountController.signIn()', () {
    test(
      'calls login() and state becomes AsyncData(null)',
      () async {
        final (:container, :fakeAuth) = makeContainer(repo: repo);
        addTearDown(container.dispose);

        await container.read(accountControllerProvider.notifier).signIn();

        expect(fakeAuth.loginCalled, isTrue);
        expect(
          container.read(accountControllerProvider),
          isA<AsyncData<void>>(),
        );
      },
    );
  });
}
