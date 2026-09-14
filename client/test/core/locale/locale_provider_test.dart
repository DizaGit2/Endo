// ---------------------------------------------------------------------------
// locale_provider_test.dart — P4b-T6
// ---------------------------------------------------------------------------
//
// The effective locale is `MeResponse.locale` → device locale → es-ES (D-03).
// Every assertion below is written so that ONE of them goes red if the chain is
// reordered, if a step stops being consulted, or if a bad value is allowed
// through instead of being skipped.
//
// The es-ES / en-US pairs are deliberately BOTH directions: a formatter that
// ignored its locale argument and returned a constant would satisfy exactly one
// half of every pair.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';

import '../../support/provider_overrides.dart';
import '../../support/pump_app.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A container whose device locale is pinned, so no test depends on the host
/// machine's regional settings.
ProviderContainer _container({
  String? device = 'en-US',
  String? profile,
}) {
  final container = ProviderContainer(
    retry: lumenRetry,
    overrides: <Override>[
      deviceLocaleProvider.overrideWithValue(device),
      // Pinned because `profileLocaleProvider` watches it (it must forget the
      // locale on sign-out); the real AuthController reaches for secure
      // storage on its first build.
      authStatusProvider
          .overrideWith(() => _FakeAuthController(AuthStatus.authenticated)),
    ],
  );
  addTearDown(container.dispose);
  if (profile != null) {
    container.read(profileLocaleProvider.notifier).adopt(profile);
  }
  return container;
}

/// [AuthController] with no TokenStore / OidcClient, whose status the test
/// drives directly — the same fake shape `onboarding_status_controller_test`
/// uses, because sign-out here is a status transition, not a real logout.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthStatus _initial;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return _initial;
  }

  void setStatus(AuthStatus status) => state = status;
}

/// Formats a date through the provider, exactly as a screen would.
class _DateProbe extends ConsumerWidget {
  const _DateProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The whole point of the probe: the locale comes from the provider, read
    // synchronously during build. Nothing here knows which locale it is.
    return Text(LumenFormats.date(DateTime(2026, 3, 7), ref.watch(localeProvider)));
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Resolution order
  // -------------------------------------------------------------------------

  group('localeProvider — resolution order', () {
    test('the profile locale wins over the device locale', () {
      final container = _container(device: 'en-US', profile: 'es-ES');
      expect(container.read(localeProvider), 'es_ES');
    });

    test('the device locale is used when the profile has none', () {
      final container = _container(device: 'en-US');
      expect(container.read(profileLocaleProvider), isNull);
      expect(container.read(localeProvider), 'en_US');
    });

    test('es_ES when there is neither a profile nor a device locale', () {
      final container = _container(device: null);
      expect(container.read(localeProvider), kFallbackLocale);
      expect(kFallbackLocale, 'es_ES');
    });

    test('the profile locale updates the effective locale when it arrives', () {
      final container = _container(device: 'en-US');
      expect(container.read(localeProvider), 'en_US');

      container.read(profileLocaleProvider.notifier).adopt('es-ES');
      expect(container.read(localeProvider), 'es_ES');

      // …and when it changes again (a different account on a shared device).
      container.read(profileLocaleProvider.notifier).adopt('en-US');
      expect(container.read(localeProvider), 'en_US');
    });
  });

  // -------------------------------------------------------------------------
  // Fallbacks — each bad value must be SKIPPED, not thrown on, not accepted
  // -------------------------------------------------------------------------

  group('localeProvider — bad values fall back rather than throw', () {
    test('a malformed profile locale falls back to the device locale', () {
      final container = _container(device: 'en-US', profile: 'not a locale!!');
      expect(container.read(localeProvider), 'en_US');
    });

    test('an over-long profile locale (>35 chars) falls back', () {
      // The column is varchar(35); anything longer cannot have come from us.
      final tooLong = 'es-${'E' * 40}';
      expect(tooLong.length, greaterThan(kMaxLocaleLength));
      final container = _container(device: 'en-US', profile: tooLong);
      expect(container.read(localeProvider), 'en_US');
    });

    test('an empty profile locale falls back', () {
      final container = _container(device: 'en-US', profile: '   ');
      expect(container.read(localeProvider), 'en_US');
    });

    test('a well-formed locale intl has no data for falls back', () {
      // 'zz-ZZ' parses as a locale but has no CLDR data; formatting with it
      // throws ArgumentError deep inside intl, so it must never be returned.
      final container = _container(device: 'en-US', profile: 'zz-ZZ');
      expect(container.read(localeProvider), 'en_US');
    });

    test('a malformed device locale with no profile falls back to es_ES', () {
      final container = _container(device: 'nonsense!');
      expect(container.read(localeProvider), kFallbackLocale);
    });

    test('whatever the provider returns can always be formatted with', () {
      for (final bad in <String?>[null, '', 'zz-ZZ', 'not a locale!!', 'x']) {
        final container = _container(device: bad, profile: bad);
        final locale = container.read(localeProvider);
        expect(
          () => LumenFormats.date(DateTime(2026, 3, 7), locale),
          returnsNormally,
          reason: 'device/profile "$bad" resolved to "$locale", which throws',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Canonicalisation — BCP-47 in, intl form out
  // -------------------------------------------------------------------------

  group('localeProvider — canonicalisation', () {
    test('a BCP-47 hyphen tag is canonicalised to the intl underscore form', () {
      expect(_container(device: 'es-ES').read(localeProvider), 'es_ES');
      expect(_container(device: 'en-us').read(localeProvider), 'en_US');
    });

    test('a bare language tag is kept as-is when intl has data for it', () {
      // The `/me` fixture ships `locale: 'es'` — the bare form must survive.
      expect(_container(device: 'en-US', profile: 'es').read(localeProvider), 'es');
    });

    test('a region intl has no data for is shortened, not discarded', () {
      // intl has 'de' but no 'de_DE'. Falling back to the DEVICE locale here
      // would silently hand a German user an American calendar.
      expect(_container(device: 'en-US', profile: 'de-DE').read(localeProvider), 'de');
    });
  });

  // -------------------------------------------------------------------------
  // D-03 / D-05 conventions, read through the provider — both directions
  // -------------------------------------------------------------------------

  group('es-ES conventions (D-05)', () {
    late String locale;
    setUp(() => locale = _container(device: 'es-ES').read(localeProvider));

    test('weeks start on Monday', () {
      expect(_container(device: 'es-ES').read(firstDayOfWeekProvider), DateTime.monday);
      expect(LumenFormats.orderedWeekdays(locale).first, DateTime.monday);
      // April 2026 starts on a Wednesday: two blank cells before it.
      expect(LumenFormats.leadingBlankDays(DateTime(2026, 4, 1), locale), 2);
    });

    test('times render 24-hour', () {
      final formatted = LumenFormats.time(DateTime(2026, 1, 1, 16, 30), locale);
      expect(formatted, contains('16'));
      expect(formatted, isNot(contains('PM')));
    });

    test('decimals use a comma', () {
      expect(LumenFormats.decimal(1.5, locale), '1,5');
    });
  });

  group('en-US conventions (D-05)', () {
    late String locale;
    setUp(() => locale = _container(device: 'en-US').read(localeProvider));

    test('weeks start on Sunday', () {
      expect(_container(device: 'en-US').read(firstDayOfWeekProvider), DateTime.sunday);
      expect(LumenFormats.orderedWeekdays(locale).first, DateTime.sunday);
      // Same April 2026 Wednesday, one column further along a Sunday-first row.
      expect(LumenFormats.leadingBlankDays(DateTime(2026, 4, 1), locale), 3);
    });

    test('times render 12-hour', () {
      final formatted = LumenFormats.time(DateTime(2026, 1, 1, 16, 30), locale);
      expect(formatted, contains('PM'));
      expect(formatted, isNot(contains('16')));
    });

    test('decimals use a period', () {
      expect(LumenFormats.decimal(1.5, locale), '1.5');
    });
  });

  // -------------------------------------------------------------------------
  // Widgets read it synchronously, and rebuild when it changes
  // -------------------------------------------------------------------------

  group('a widget formats through the provider', () {
    testWidgets('the first frame already carries the resolved locale', (tester) async {
      await pumpApp(
        tester,
        home: const _DateProbe(),
        overrides: <Override>[
          deviceLocaleProvider.overrideWithValue('en-US'),
          // Pinned like every other Lumen widget test: without it the real
          // AuthController builds and reaches FlutterSecureStorage, and the
          // test passes only because the plugin miss happens to be swallowed
          // into `unauthenticated` before anything asserts.
          ...lumenOverrides(),
        ],
      );

      // Month first — en-US. No await, no loading state: synchronous.
      expect(find.text('3/7/2026'), findsOneWidget);
    });

    testWidgets('the profile locale arriving re-formats the date', (tester) async {
      final container = await pumpApp(
        tester,
        home: const _DateProbe(),
        overrides: <Override>[
          deviceLocaleProvider.overrideWithValue('en-US'),
          ...lumenOverrides(),
        ],
      );
      expect(find.text('3/7/2026'), findsOneWidget);

      container.read(profileLocaleProvider.notifier).adopt('es-ES');
      await tester.pump();

      // Day first — es-ES.
      expect(find.text('7/3/2026'), findsOneWidget);
      expect(find.text('3/7/2026'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Sign-out forgets it
  // -------------------------------------------------------------------------
  //
  // `profileLocaleProvider` is root-scoped and nothing else clears it:
  // `AuthController.logout` clears tokens and purges the Hive cache but resets
  // no providers. On a shared device that means user A's locale formatting
  // user B's dates.

  group('sign-out clears the profile locale', () {
    test('the adopted locale does not survive into the next session', () {
      final container = ProviderContainer(
        retry: lumenRetry,
        overrides: <Override>[
          deviceLocaleProvider.overrideWithValue('en-US'),
          authStatusProvider
              .overrideWith(() => _FakeAuthController(AuthStatus.authenticated)),
        ],
      );
      addTearDown(container.dispose);
      // Keep it alive so an auth transition rebuilds it eagerly, exactly as the
      // app does by watching it from a screen.
      container.listen(profileLocaleProvider, (_, _) {}, fireImmediately: true);

      container.read(profileLocaleProvider.notifier).adopt('es-ES');
      expect(container.read(localeProvider), 'es_ES');

      (container.read(authStatusProvider.notifier) as _FakeAuthController)
          .setStatus(AuthStatus.unauthenticated);

      expect(container.read(profileLocaleProvider), isNull,
          reason: 'user A\'s locale must not outlive user A\'s session');
      expect(container.read(localeProvider), 'en_US');
    });
  });
}
