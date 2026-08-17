// Tests for lumenRedirect — the pure redirect decision function (P4b-T1).
//
// TDD (RED first). Two things changed in P4b-T1:
//
//  1. "Is this location known?" is no longer a hand-maintained Set<String> of
//     literals. It is answered by GoRouter's own matcher and handed to
//     [lumenRedirect] as [isKnownLocation], so a parameterised location such as
//     "/cycle/day/2026-04-07" can be known even though no literal by that name
//     exists anywhere. The wiring that produces that flag from the real route
//     table is exercised in route_table_test.dart — this file covers the
//     decision matrix downstream of it.
//
//  2. Authenticated users are gated on onboarding completion
//     ([OnboardingStatus]), closing the P3b-T5 stub.
//
// One test per row of the matrix in lumenRedirect's doc comment.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Calls [lumenRedirect] with the location marked as registered in the route
/// table (the common case — most rows differ only in status/onboarding).
String? _known(
  AuthStatus status,
  String location, {
  OnboardingStatus onboarding = OnboardingStatus.unknown,
}) {
  return lumenRedirect(
    status: status,
    onboarding: onboarding,
    location: location,
    isKnownLocation: true,
  );
}

/// Calls [lumenRedirect] for a location that matches no route at all.
String? _unknownLocation(
  AuthStatus status,
  String location, {
  OnboardingStatus onboarding = OnboardingStatus.unknown,
}) {
  return lumenRedirect(
    status: status,
    onboarding: onboarding,
    location: location,
    isKnownLocation: false,
  );
}

MeResponse _me({bool? onboardingCompleted}) {
  return MeResponse(
    (b) => b
      ..id = 'user-1'
      ..displayName = 'María'
      ..locale = 'es'
      ..timezone = 'Europe/Madrid'
      ..onboardingCompleted = onboardingCompleted,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // AuthStatus.unknown — cold start holds on the splash (unchanged behaviour)
  // -------------------------------------------------------------------------

  group('lumenRedirect — auth unknown (holds on splash)', () {
    test('unknown + "/" redirects to "/splash"', () {
      expect(_known(AuthStatus.unknown, '/'), equals('/splash'));
    });

    test('unknown + "/account" redirects to "/splash"', () {
      expect(_known(AuthStatus.unknown, '/account'), equals('/splash'));
    });

    test('unknown + "/profile" redirects to "/splash"', () {
      expect(_known(AuthStatus.unknown, '/profile'), equals('/splash'));
    });

    test('unknown + "/onboarding" redirects to "/splash"', () {
      expect(_known(AuthStatus.unknown, '/onboarding'), equals('/splash'));
    });

    test('unknown + "/splash" returns null (already on splash)', () {
      expect(_known(AuthStatus.unknown, '/splash'), isNull);
    });

    test('unknown + an unmatched location redirects to "/splash"', () {
      expect(_unknownLocation(AuthStatus.unknown, '/nope'), equals('/splash'));
    });
  });

  // -------------------------------------------------------------------------
  // AuthStatus.unauthenticated — unchanged from today
  // -------------------------------------------------------------------------

  group('lumenRedirect — unauthenticated', () {
    test('unauthenticated on "/" returns null (already at welcome)', () {
      expect(_known(AuthStatus.unauthenticated, '/'), isNull);
    });

    test('unauthenticated on "/account" returns null (login screen allowed)', () {
      expect(_known(AuthStatus.unauthenticated, '/account'), isNull);
    });

    test('unauthenticated on "/profile" redirects to "/"', () {
      expect(_known(AuthStatus.unauthenticated, '/profile'), equals('/'));
    });

    test('unauthenticated on "/splash" redirects to "/"', () {
      expect(_known(AuthStatus.unauthenticated, '/splash'), equals('/'));
    });

    test('unauthenticated on "/onboarding" redirects to "/" (auth comes first)',
        () {
      expect(_known(AuthStatus.unauthenticated, '/onboarding'), equals('/'));
    });

    test('unauthenticated on an unmatched location redirects to "/"', () {
      expect(_unknownLocation(AuthStatus.unauthenticated, '/nope'), equals('/'));
    });

    test('unauthenticated on a deep unmatched location redirects to "/"', () {
      expect(
        _unknownLocation(AuthStatus.unauthenticated, '/some/deep/path'),
        equals('/'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AuthStatus.authenticated + onboarding completed — today's authed behaviour
  // -------------------------------------------------------------------------

  group('lumenRedirect — authenticated and onboarded', () {
    const onboarded = OnboardingStatus.completed;

    test('authenticated + onboarded on "/profile" returns null', () {
      expect(
        _known(AuthStatus.authenticated, '/profile', onboarding: onboarded),
        isNull,
      );
    });

    test('authenticated + onboarded on "/" redirects to "/profile"', () {
      expect(
        _known(AuthStatus.authenticated, '/', onboarding: onboarded),
        equals('/profile'),
      );
    });

    test('authenticated + onboarded on "/account" redirects to "/profile"', () {
      expect(
        _known(AuthStatus.authenticated, '/account', onboarding: onboarded),
        equals('/profile'),
      );
    });

    test('authenticated + onboarded on "/splash" redirects to "/profile"', () {
      expect(
        _known(AuthStatus.authenticated, '/splash', onboarding: onboarded),
        equals('/profile'),
      );
    });

    test(
      'authenticated + onboarded on "/onboarding" redirects to "/profile" '
      '(the flow is done — do not re-enter it)',
      () {
        expect(
          _known(AuthStatus.authenticated, '/onboarding', onboarding: onboarded),
          equals('/profile'),
        );
      },
    );

    test(
      'authenticated + onboarded on any other registered route returns null '
      '(the requested route is honoured)',
      () {
        expect(
          _known(
            AuthStatus.authenticated,
            '/cycle/day/2026-04-07',
            onboarding: onboarded,
          ),
          isNull,
        );
      },
    );

    test(
      'authenticated + onboarded on an unmatched location redirects to '
      '"/profile"',
      () {
        expect(
          _unknownLocation(
            AuthStatus.authenticated,
            '/nope',
            onboarding: onboarded,
          ),
          equals('/profile'),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // AuthStatus.authenticated + onboarding incomplete — THE GATE
  // -------------------------------------------------------------------------

  group('lumenRedirect — authenticated but not onboarded (the gate)', () {
    const notOnboarded = OnboardingStatus.incomplete;

    test('authenticated + not onboarded on "/profile" redirects to "/onboarding"',
        () {
      expect(
        _known(AuthStatus.authenticated, '/profile', onboarding: notOnboarded),
        equals('/onboarding'),
      );
    });

    test('authenticated + not onboarded on "/" redirects to "/onboarding"', () {
      expect(
        _known(AuthStatus.authenticated, '/', onboarding: notOnboarded),
        equals('/onboarding'),
      );
    });

    test('authenticated + not onboarded on "/account" redirects to "/onboarding"',
        () {
      expect(
        _known(AuthStatus.authenticated, '/account', onboarding: notOnboarded),
        equals('/onboarding'),
      );
    });

    test('authenticated + not onboarded on "/splash" redirects to "/onboarding"',
        () {
      expect(
        _known(AuthStatus.authenticated, '/splash', onboarding: notOnboarded),
        equals('/onboarding'),
      );
    });

    test(
      'authenticated + not onboarded on a deep registered route redirects to '
      '"/onboarding"',
      () {
        expect(
          _known(
            AuthStatus.authenticated,
            '/cycle/day/2026-04-07',
            onboarding: notOnboarded,
          ),
          equals('/onboarding'),
        );
      },
    );

    test(
      'authenticated + not onboarded ALREADY on "/onboarding" returns null '
      '(no redirect loop)',
      () {
        expect(
          _known(
            AuthStatus.authenticated,
            '/onboarding',
            onboarding: notOnboarded,
          ),
          isNull,
        );
      },
    );

    test(
      'authenticated + not onboarded on an unmatched location redirects to '
      '"/onboarding"',
      () {
        expect(
          _unknownLocation(
            AuthStatus.authenticated,
            '/nope',
            onboarding: notOnboarded,
          ),
          equals('/onboarding'),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // AuthStatus.authenticated + onboarding NOT LOADED YET
  // The redirect never fetches /me (it runs synchronously and often), so the
  // "not yet known" state must hold the user on the loading path rather than
  // guessing a side of the gate.
  // -------------------------------------------------------------------------

  group('lumenRedirect — authenticated, onboarding state not loaded yet', () {
    const loading = OnboardingStatus.unknown;

    test('authenticated + unknown onboarding on "/splash" returns null', () {
      expect(
        _known(AuthStatus.authenticated, '/splash', onboarding: loading),
        isNull,
      );
    });

    test('authenticated + unknown onboarding on "/profile" holds on "/splash"',
        () {
      expect(
        _known(AuthStatus.authenticated, '/profile', onboarding: loading),
        equals('/splash'),
      );
    });

    test('authenticated + unknown onboarding on "/onboarding" holds on "/splash"',
        () {
      expect(
        _known(AuthStatus.authenticated, '/onboarding', onboarding: loading),
        equals('/splash'),
      );
    });

    test(
      'authenticated + unknown onboarding on an unmatched location holds on '
      '"/splash"',
      () {
        expect(
          _unknownLocation(
            AuthStatus.authenticated,
            '/nope',
            onboarding: loading,
          ),
          equals('/splash'),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // The gate's read failed or outran its bounded wait. Still "no answer", so
  // the routing decision is identical to `unknown` — the splash is the surface
  // that changes (it renders a retry instead of an endless spinner), not the
  // destination.
  // -------------------------------------------------------------------------

  group('lumenRedirect — authenticated, onboarding state unavailable', () {
    const unavailable = OnboardingStatus.unavailable;

    test('authenticated + unavailable on "/splash" returns null', () {
      expect(
        _known(AuthStatus.authenticated, '/splash', onboarding: unavailable),
        isNull,
      );
    });

    test('authenticated + unavailable on "/profile" holds on "/splash"', () {
      expect(
        _known(AuthStatus.authenticated, '/profile', onboarding: unavailable),
        equals('/splash'),
      );
    });

    test('authenticated + unavailable on "/onboarding" holds on "/splash"', () {
      expect(
        _known(AuthStatus.authenticated, '/onboarding', onboarding: unavailable),
        equals('/splash'),
      );
    });

    test(
      'authenticated + unavailable on an unmatched location holds on "/splash"',
      () {
        expect(
          _unknownLocation(
            AuthStatus.authenticated,
            '/nope',
            onboarding: unavailable,
          ),
          equals('/splash'),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // onboardingCompleted is nullable (ARCHITECTURE §C.0.2: every generated Dart
  // property is T?). null must mean NOT onboarded — the direction that routes a
  // user into a flow they can leave rather than past a gate they needed.
  // -------------------------------------------------------------------------

  group('onboardingStatusFrom — nullable onboardingCompleted', () {
    test('onboardingCompleted == true maps to completed', () {
      expect(
        onboardingStatusFrom(_me(onboardingCompleted: true)),
        OnboardingStatus.completed,
      );
    });

    test('onboardingCompleted == false maps to incomplete', () {
      expect(
        onboardingStatusFrom(_me(onboardingCompleted: false)),
        OnboardingStatus.incomplete,
      );
    });

    test('onboardingCompleted == null maps to incomplete', () {
      expect(
        onboardingStatusFrom(_me()),
        OnboardingStatus.incomplete,
      );
    });

    test('a null profile maps to incomplete', () {
      expect(onboardingStatusFrom(null), OnboardingStatus.incomplete);
    });

    test(
      'a profile whose onboardingCompleted is null routes an authenticated '
      'user to "/onboarding"',
      () {
        final status = onboardingStatusFrom(_me());
        expect(
          _known(AuthStatus.authenticated, '/profile', onboarding: status),
          equals('/onboarding'),
        );
      },
    );
  });
}
