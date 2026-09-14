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
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/device_timezone.dart';
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
  // The two device seams registration reads (D1 / D-12), pinned so no test
  // depends on the host machine. Deliberately NOT Madrid / es-ES: the server
  // defaults to exactly those, so a test that used them could not tell "sent"
  // from "defaulted".
  String? deviceTimezone = 'America/Mexico_City',
  String? deviceLocale = 'en-US',
}) {
  final fakeAuth = _FakeAuthController()..loginShouldThrow = loginShouldThrow;

  final container = ProviderContainer(
    retry: lumenRetry,
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(repo),
      authStatusProvider.overrideWith(() => fakeAuth),
      deviceTimezoneProvider.overrideWith((_) async => deviceTimezone),
      deviceLocaleProvider.overrideWithValue(deviceLocale),
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
            locale: any(named: 'locale'),
            timezone: any(named: 'timezone'),
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
            locale: 'en-US',
            timezone: 'America/Mexico_City',
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
            locale: any(named: 'locale'),
            timezone: any(named: 'timezone'),
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
            locale: any(named: 'locale'),
            timezone: any(named: 'timezone'),
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
  // register() — the device's timezone and locale ride along (D1 / D-12)
  // -------------------------------------------------------------------------
  //
  // Walk 2026-08-25, B-50: `register()` sent neither, the server defaulted
  // both to es-ES / Europe/Madrid, and every day-keyed row of an account
  // registered in Mexico City was filed under Madrid's calendar day — with
  // real data loss on the one-row-per-day check-in upsert. D-12 says the zone
  // is "captured at /onboarding/start"; this is where.

  group('AccountController.register() sends the device timezone and locale',
      () {
    void stubStart(MockOnboardingRepository repo) {
      when(
        () => repo.startOnboarding(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
          locale: any(named: 'locale'),
          timezone: any(named: 'timezone'),
        ),
      ).thenAnswer((_) async {});
    }

    test('the device IANA zone and BCP-47 locale are passed to the '
        'repository', () async {
      stubStart(repo);
      final (:container, fakeAuth: _) = makeContainer(
        repo: repo,
        deviceTimezone: 'America/Argentina/Buenos_Aires',
        deviceLocale: 'es-AR',
      );
      addTearDown(container.dispose);

      await container.read(accountControllerProvider.notifier).register(
            email: 'test@example.com',
            password: 'a-good-passphrase',
            displayName: 'Maya',
          );

      verify(
        () => repo.startOnboarding(
          email: 'test@example.com',
          password: 'a-good-passphrase',
          displayName: 'Maya',
          locale: 'es-AR',
          timezone: 'America/Argentina/Buenos_Aires',
        ),
      ).called(1);
    });

    test('when the device will not say, both are sent as null and the server '
        'defaults apply — registration is never blocked on them', () async {
      stubStart(repo);
      final (:container, :fakeAuth) = makeContainer(
        repo: repo,
        deviceTimezone: null,
        deviceLocale: null,
      );
      addTearDown(container.dispose);

      await container.read(accountControllerProvider.notifier).register(
            email: 'test@example.com',
            password: 'a-good-passphrase',
            displayName: 'Maya',
          );

      verify(
        () => repo.startOnboarding(
          email: 'test@example.com',
          password: 'a-good-passphrase',
          displayName: 'Maya',
          locale: null,
          timezone: null,
        ),
      ).called(1);
      expect(fakeAuth.loginCalled, isTrue);
    });

    test('a 400 that names the timezone or locale is retried ONCE without '
        'them — screen 2 shows neither field, so the user could never fix it',
        () async {
      // The server resolves the zone with TimeZoneInfo; an id the device
      // reports but the server's tz database lacks would otherwise dead-end
      // registration on a field the form does not draw.
      var calls = 0;
      when(
        () => repo.startOnboarding(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
          locale: any(named: 'locale'),
          timezone: any(named: 'timezone'),
        ),
      ).thenAnswer((invocation) async {
        calls++;
        if (invocation.namedArguments[#timezone] != null) {
          throw const ValidationFailure(
            fields: {
              'timezone': ['timezone must be an IANA zone id'],
            },
          );
        }
      });
      final (:container, :fakeAuth) = makeContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(accountControllerProvider.notifier).register(
            email: 'test@example.com',
            password: 'a-good-passphrase',
            displayName: 'Maya',
          );

      expect(calls, 2);
      verify(
        () => repo.startOnboarding(
          email: 'test@example.com',
          password: 'a-good-passphrase',
          displayName: 'Maya',
          locale: null,
          timezone: null,
        ),
      ).called(1);
      expect(fakeAuth.loginCalled, isTrue);
      expect(container.read(accountControllerProvider), isA<AsyncData<void>>());
    });

    test('a 400 that names any OTHER field is surfaced as-is, not retried',
        () async {
      const failure = ValidationFailure(
        fields: {
          'email': ['email is already taken'],
        },
      );
      when(
        () => repo.startOnboarding(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
          locale: any(named: 'locale'),
          timezone: any(named: 'timezone'),
        ),
      ).thenThrow(failure);
      final (:container, :fakeAuth) = makeContainer(repo: repo);
      addTearDown(container.dispose);

      await container.read(accountControllerProvider.notifier).register(
            email: 'test@example.com',
            password: 'a-good-passphrase',
            displayName: 'Maya',
          );

      verify(
        () => repo.startOnboarding(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
          locale: any(named: 'locale'),
          timezone: any(named: 'timezone'),
        ),
      ).called(1);
      expect(fakeAuth.loginCalled, isFalse);
      final state = container.read(accountControllerProvider);
      expect(state, isA<AsyncError<void>>());
      expect((state as AsyncError<void>).error, same(failure));
    });
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
            locale: any(named: 'locale'),
            timezone: any(named: 'timezone'),
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
            locale: 'en-US',
            timezone: 'America/Mexico_City',
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
