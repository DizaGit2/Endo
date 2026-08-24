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
import 'package:lumen/core/error/retry_policy.dart';
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
    retry: lumenRetry,
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
              password: 'a-good-passphrase',
              displayName: 'Maya',
            );

        // Repo must have been called with the supplied arguments.
        verify(
          () => repo.startOnboarding(
            email: 'test@example.com',
            password: 'a-good-passphrase',
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
              password: 'a-good-passphrase',
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
              password: 'a-good-passphrase',
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
  // register() — client-side validation (P4b-T7)
  // -------------------------------------------------------------------------

  group('AccountController.register() client-side validation', () {
    test(
      'a locally-invalid form never reaches the repository — and the same '
      'harness DOES record a call on the valid path',
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
        final controller = container.read(accountControllerProvider.notifier);

        // ---- POSITIVE CONTROL --------------------------------------------
        // "no request was issued" is an assertion about an ABSENCE, and an
        // absence is also this mock's state before anything runs — a register()
        // that silently did nothing at all would satisfy it. So the valid path
        // goes first, through this exact container and this exact mock, and
        // proves the recorder records.
        //
        // The empty displayName is deliberate and is its own assertion: the
        // server's `DisplayName` is nullable (OnboardingContracts.cs, the
        // `OnboardingStartRequest` record), so a client that made Name required
        // would reject an account the server would create.
        await controller.register(
          email: 'maya@example.com',
          password: 'a-good-passphrase',
          displayName: '',
        );

        verify(
          () => repo.startOnboarding(
            email: 'maya@example.com',
            password: 'a-good-passphrase',
            displayName: '',
          ),
        ).called(1);
        expect(fakeAuth.loginCalled, isTrue);

        // ---- SUBJECT ------------------------------------------------------
        fakeAuth.loginCalled = false;
        await controller.register(
          email: 'maya@example.com',
          password: 'elevenchars', // 11 — one short of D-24's minimum
          displayName: 'Maya',
        );

        // Nothing new happened on the repository. `verify` above consumed the
        // one interaction it asserted, so this can only pass if the rejected
        // submit added none.
        verifyNoMoreInteractions(repo);
        expect(
          fakeAuth.loginCalled,
          isFalse,
          reason:
              'A locally-rejected registration must not start an OIDC session '
              'either — the account it would sign in to was never created.',
        );

        final state = container.read(accountControllerProvider);
        expect(state, isA<AsyncError<void>>());
        final failure = (state as AsyncError<void>).error;
        expect(failure, isA<ValidationFailure>());
        expect(
          (failure as ValidationFailure).messageFor('password'),
          'Use at least 12 characters.',
        );
      },
    );

    test(
      'the state it leaves behind is the same typed failure a server 400 '
      'leaves, so one rendering path serves both',
      () async {
        final (:container, :fakeAuth) = makeContainer(repo: repo);
        addTearDown(container.dispose);

        // Let the notifier's own `build()` land before rejecting anything.
        // `AccountController.build()` is `async` and resolves to AsyncData(null)
        // a microtask after the notifier is first read; the rejection below is
        // written to `state` SYNCHRONOUSLY, so a container that has not settled
        // would have the rejection overwritten by the arriving build. Screen 2
        // never hits that — it `ref.watch`es the provider a frame before the
        // user can tap Continue — but a test that reads the notifier and
        // immediately submits does, and it would have looked like a bug in the
        // validation rather than in the setup.
        await container.read(accountControllerProvider.future);

        await container
            .read(accountControllerProvider.notifier)
            .register(email: 'maya', password: 'short', displayName: 'Maya');

        final state =
            container.read(accountControllerProvider) as AsyncError<void>;
        final failure = state.error as ValidationFailure;

        // Keyed exactly the way `error_mapper.dart` keys a 400's `errors` map,
        // which is what lets screen 2 bind fields without asking where the
        // failure came from.
        expect(failure.fields.keys, unorderedEquals(<String>['email', 'password']));
        expect(failure.messageFor('email'), 'Enter a valid email address.');
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
