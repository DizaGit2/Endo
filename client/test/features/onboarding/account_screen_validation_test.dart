// Screen 2 (account) — the submit path, end to end (P4b-T7).
//
// TDD (RED first): before this task screen 2 posted whatever was in the three
// boxes, so an empty email cost a round trip, and a 400's per-field `errors`
// map was flattened to one banner with no indication of which box was wrong.
//
// This file mounts the REAL `AccountController` over the REAL
// `OnboardingRepository` over a mock `LumenApiApi`, so "no request was issued"
// is a statement about the wire and not about a stubbed controller.
//
// ## The absence problem, and how every test here handles it
//
// Two of the three requirements are assertions about an ABSENCE — no request
// was issued; no OTHER field claimed the error — and an absence is also the
// state of a freshly-built harness. A test that asserts one without first
// establishing the opposite through the same harness cannot fail. So each test
// below carries its control inline:
//
//   * "issues no request"      -> the valid submit that DOES issue one, first,
//                                 through the same mock and the same tap.
//   * "no other field claims"  -> the field that DOES claim it, in the same
//                                 pumped tree, from the same response.
//   * "the values survive"     -> the rendered server error, asserted first,
//                                 proving the rejection actually landed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/api/model/onboarding_start_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/network/api_client.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// An [AuthController] whose [login] does nothing but record.
///
/// `FakeAuthController` from `provider_overrides.dart` pins a status but
/// inherits the real `login()`, which reaches for a live OIDC client the moment
/// a successful registration falls through to it.
class _RecordingAuthController extends AuthController {
  int logins = 0;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return AuthStatus.unauthenticated;
  }

  @override
  Future<void> login() async => logins++;
}

/// The three fields in the order screen 2 draws them.
const _name = 0;
const _email = 1;
const _password = 2;

Finder _field(int index) => find.descendant(
  of: find.byType(LumenInputField).at(index),
  matching: find.byType(TextField),
);

TextField _textField(WidgetTester tester, int index) =>
    tester.widget<TextField>(_field(index));

/// What the field is currently showing under itself, or null when it is clean.
String? _errorAt(WidgetTester tester, int index) =>
    _textField(tester, index).decoration!.errorText;

/// What the field currently holds — read off the widget's own controller, so
/// it works for the obscured password too.
String _valueAt(WidgetTester tester, int index) =>
    _textField(tester, index).controller!.text;

Future<void> _fill(
  WidgetTester tester, {
  String name = 'Maya',
  String email = 'maya@example.com',
  String password = 'a-good-passphrase',
}) async {
  await tester.enterText(_field(_name), name);
  await tester.enterText(_field(_email), email);
  await tester.enterText(_field(_password), password);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// A form the CLIENT accepts and the SERVER rejects — the input a
/// round-trip test needs.
///
/// Two `@`s. `AccountValidation` splits on the LAST one and asks only that both
/// sides are non-empty, while the server requires
/// `MailAddress.TryCreate(e) && parsed.Address == e`
/// (`OnboardingService.cs:36-38`), which this fails. That deliberate asymmetry
/// is what keeps the client from over-rejecting, and here it is also the only
/// remaining way to make a 400 reachable from screen 2: since T7 fix round 1
/// mirrored both password bounds and the 200-character name bound, a
/// 129-character password no longer leaves the device.
const _serverRejectsThis = 'maya@@example.com';

Future<_RecordingAuthController> _pump(
  WidgetTester tester,
  MockLumenApiApi api,
) async {
  final auth = _RecordingAuthController();
  await pumpApp(
    tester,
    home: const AccountScreen(),
    overrides: <Override>[
      // Built by hand rather than via `lumenOverrides`: this test needs its own
      // auth controller, and two overrides of one provider is a silent
      // last-one-wins.
      authStatusProvider.overrideWith(() => auth),
      lumenApiProvider.overrideWithValue(api),
    ],
  );
  return auth;
}

MockLumenApiApi _api() => MockLumenApiApi();

void _whenStart(MockLumenApiApi api, ApiAnswer<OnboardingStartResponse> answer) {
  when(
    () => api.onboardingStartPost(
      onboardingStartRequest: any(named: 'onboardingStartRequest'),
    ),
  ).thenAnswer(answer);
}

OnboardingStartResponse _created() => OnboardingStartResponse(
  (b) => b..userId = '11111111-1111-1111-1111-111111111111',
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      OnboardingStartRequest(
        (b) => b
          ..email = 'fallback@example.com'
          ..password = 'a-good-passphrase',
      ),
    );
  });

  // -------------------------------------------------------------------------
  // Requirement 3a — a validation failure issues no request
  // -------------------------------------------------------------------------

  testWidgets(
    'a locally-invalid submit issues NO request — while the same tap on a '
    'valid form issues one',
    (tester) async {
      final log = ApiCallLog();
      final api = _api();
      _whenStart(api, apiSuccess(_created(), onCall: log.record));
      final auth = await _pump(tester, api);

      // ---- POSITIVE CONTROL ----------------------------------------------
      // Zero calls is also the count before anything happens, so the valid
      // path runs first: same mock, same button, same tap sequence.
      await _fill(tester);
      await _submit(tester);
      expect(log.calls, 1, reason: 'the valid form must reach the server');
      expect(auth.logins, 1);

      // ---- SUBJECT --------------------------------------------------------
      await tester.enterText(_field(_password), 'elevenchars'); // 11
      await _submit(tester);

      expect(
        log.calls,
        1,
        reason:
            'the rejected submit must not have issued a second request — the '
            'count is unchanged from the control above',
      );
      expect(auth.logins, 1);
      // …and the tap was not a no-op: it produced the field error.
      expect(_errorAt(tester, _password), 'Use at least 12 characters.');
    },
  );

  testWidgets('an empty form issues no request and marks both empty fields', (
    tester,
  ) async {
    final log = ApiCallLog();
    final api = _api();
    _whenStart(api, apiSuccess(_created(), onCall: log.record));
    await _pump(tester, api);

    // Control first, for the same reason as above.
    await _fill(tester);
    await _submit(tester);
    expect(log.calls, 1);

    await _fill(tester, name: '', email: '', password: '');
    await _submit(tester);

    expect(log.calls, 1);
    expect(_errorAt(tester, _email), 'Enter your email address.');
    expect(_errorAt(tester, _password), 'Enter a password.');
    expect(
      _errorAt(tester, _name),
      isNull,
      reason:
          'Name maps to the nullable `displayName`; making it required would '
          'reject an account the server would create.',
    );
  });

  testWidgets('a name over the server bound is caught locally AND highlighted '
      "— which the server's own rejection cannot do", (tester) async {
    // `OnboardingService.cs:41-43` bounds `displayName` at 200 in a branch it
    // shares with three other members, and keys the rejection `request`. So
    // the round trip this saves is the lesser half: the real gain is that the
    // user is shown WHICH box is too long.
    final log = ApiCallLog();
    final api = _api();
    _whenStart(api, apiSuccess(_created(), onCall: log.record));
    await _pump(tester, api);

    // Control: the same form one character shorter goes to the server.
    await _fill(tester, name: 'M' * 200);
    await _submit(tester);
    expect(log.calls, 1);

    await tester.enterText(_field(_name), 'M' * 201);
    await _submit(tester);

    expect(log.calls, 1, reason: 'the over-long name must not have been sent');
    expect(_errorAt(tester, _name), 'Use 200 characters or fewer.');
    expect(_errorAt(tester, _email), isNull);
    expect(_errorAt(tester, _password), isNull);
  });

  // -------------------------------------------------------------------------
  // Requirement 2 — a server field error renders AT its field
  // -------------------------------------------------------------------------

  group('a 400 binds each message to its own field', () {
    // The server's own wire strings (OnboardingService.cs:38, :40 and the
    // `request` branch at :43) rather than invented ones, so a message that
    // stops being reachable is visible here.
    const cases = <({int index, String key, String message})>[
      (
        index: _email,
        key: 'email',
        message: 'invalid email format',
      ),
      (
        // The client now pre-empts BOTH of the server's password bounds, so
        // this exact message is no longer reachable from a clean install. The
        // case stays because the binding must not: a contract skew (a server
        // that raises the minimum under an installed client) and the booked
        // backend fix for the `notEmail` realm policy both land a 400 keyed
        // `password`, and screen 2 has to put it on the password box.
        index: _password,
        key: 'password',
        message: 'password must be between 12 and 128 characters',
      ),
      (
        // No branch keys `displayName` today — length errors on it go to
        // `request` (:43), which is why the client mirrors that bound itself.
        // This pins the binding the screen owes the contract in requirement 2
        // (`errors: { <camelCaseField>: [...] }`), so the Name field claims a
        // server message the day a branch does key it.
        index: _name,
        key: 'displayName',
        message: 'value is too long',
      ),
    ];

    for (final c in cases) {
      testWidgets('`${c.key}` lands on its field and on no other', (
        tester,
      ) async {
        final api = _api();
        _whenStart(
          api,
          apiValidationProblem<OnboardingStartResponse>(
            fields: <String, List<String>>{
              c.key: <String>[c.message],
            },
          ),
        );
        await _pump(tester, api);

        // The form has to pass client validation or there is no round trip to
        // bind anything from — and this test would then be asserting the
        // LOCAL failure while claiming to assert the server's.
        await _fill(tester, email: _serverRejectsThis);
        await _submit(tester);

        // The positive half comes first and is the control for the two
        // absences under it: one field in this exact tree DOES show the
        // message, so "the others show nothing" is about binding rather than
        // about a screen that renders no errors at all.
        expect(_errorAt(tester, c.index), c.message);
        for (final other in <int>[_name, _email, _password]) {
          if (other == c.index) continue;
          expect(
            _errorAt(tester, other),
            isNull,
            reason: 'field $other must not claim `${c.key}`\'s message',
          );
        }
      });
    }

    testWidgets('a `request`-keyed message stays in the banner, off the '
        'fields', (tester) async {
      final api = _api();
      _whenStart(
        api,
        apiValidationProblem<OnboardingStartResponse>(
          fields: const <String, List<String>>{
            'request': <String>['a field exceeds its maximum length'],
          },
        ),
      );
      await _pump(tester, api);

      // Not the 201-character name that provokes this message on the live
      // server: the client now catches that one itself and keys it
      // `displayName`, which is the improvement. The response is mocked, so
      // what this test needs from the form is only that it reaches the wire.
      await _fill(tester, email: _serverRejectsThis);
      await _submit(tester);

      // Control for the three absences below: the message IS on screen.
      expect(find.text('a field exceeds its maximum length'), findsOneWidget);
      expectLiveRegion(tester, 'a field exceeds its maximum length');
      for (final index in <int>[_name, _email, _password]) {
        expect(
          _errorAt(tester, index),
          isNull,
          reason:
              '`request` names no input — attaching it to a box would tell '
              'the user the wrong one is wrong',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 3b — the entered values survive a rejection
  // -------------------------------------------------------------------------

  testWidgets('a server rejection leaves every entered value in place', (
    tester,
  ) async {
    final api = _api();
    _whenStart(
      api,
      apiValidationProblem<OnboardingStartResponse>(
        fields: const <String, List<String>>{
          'email': <String>['invalid email format'],
        },
      ),
    );
    await _pump(tester, api);

    const password = 'a-good-passphrase';
    await _fill(tester, name: 'Maya', email: _serverRejectsThis, password: password);
    await _submit(tester);

    // Control: the rejection actually happened. Without this the three
    // assertions below are satisfied by a Continue button that does nothing —
    // the values were put there by this test and were already in place before
    // the tap.
    expect(_errorAt(tester, _email), 'invalid email format');

    expect(_valueAt(tester, _name), 'Maya');
    expect(_valueAt(tester, _email), _serverRejectsThis);
    expect(
      _valueAt(tester, _password),
      password,
      reason:
          'the password is obscured, so a cleared box is invisible — and it is '
          'the one value a user cannot re-read from the screen',
    );
  });

  testWidgets('a LOCAL rejection leaves every entered value in place too', (
    tester,
  ) async {
    final api = _api();
    _whenStart(api, apiSuccess(_created()));
    await _pump(tester, api);

    await _fill(tester, name: 'Maya', email: 'maya', password: 'short');
    await _submit(tester);

    expect(_errorAt(tester, _email), 'Enter a valid email address.');

    expect(_valueAt(tester, _name), 'Maya');
    expect(_valueAt(tester, _email), 'maya');
    expect(_valueAt(tester, _password), 'short');
  });
}
