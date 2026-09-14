// Tests for AccountValidation — screen 2's client-side mirror of the server's
// `POST /onboarding/start` rules (P4b-T7).
//
// TDD (RED first): this file was written before `account_validation.dart`
// existed. Screen 2 shipped with NO client-side validation, so an empty email
// or a five-character password cost a round trip and came back as a server
// field error.
//
// ## The rule this file is really enforcing
//
// A client that rejects what the SERVER would accept is a defect, and it is the
// defect this whole file is shaped around: every rule below is tested from both
// sides, and the ACCEPTING case is the one that matters. The rejecting half of
// each test is there as the in-test positive control — `isNull` proves nothing
// on its own, because a validator that returns `null` for everything satisfies
// every accepting assertion in the file. Pairing the two means each test can
// only pass if the boundary is where the server puts it.
//
// The mirrored source is `backend/src/Lumen.Api/Onboarding/OnboardingService.cs`
// (line numbers as of this commit):
//
//   :32  IsNullOrWhiteSpace(Email) || IsNullOrWhiteSpace(Password)
//        -> key `request`, "email and password are required"
//   :36-38  email.Trim().ToLowerInvariant() must round-trip MailAddress.TryCreate
//        -> key `email`, "invalid email format"
//   :39-40  Password.Length is < 12 or > 128
//        -> key `password`, "password must be between 12 and 128 characters"
//   :41-43  DisplayName?.Length > 200 (with three other members)
//        -> key `request`, "a field exceeds its maximum length"
//
// The two MAXIMUMS were added in T7 fix round 1. Mirroring a bound the server
// HAS cannot make the client stricter than it, and D-24 reads "min 12 / max
// 128"; the `displayName` cap additionally does something the server cannot,
// which is say WHICH field is too long (`:41-43` covers four members under one
// `request` key).
//
// Deliberately still NOT mirrored: the `locale`/`timezone`/`policyVersion`
// caps and the IANA time-zone check, because screen 2 sends `null` for all
// three; the breached-password lookup (Keycloak, P11); and uniqueness (a 409
// the controller recovers from). None of those is knowable on the device.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/account_validation.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A password the server accepts, for tests whose subject is the email.
const _goodPassword = 'a-good-passphrase';

/// An email the server accepts, for tests whose subject is the password.
const _goodEmail = 'maya@example.com';

ValidationFailure? _validate({String? email, String? password, String? name}) =>
    AccountValidation.validate(
      email: email ?? _goodEmail,
      password: password ?? _goodPassword,
      displayName: name ?? 'Maya',
    );

void main() {
  // -------------------------------------------------------------------------
  // Email — required
  // -------------------------------------------------------------------------

  group('email is required (OnboardingService.cs:32)', () {
    test('an empty email is rejected at the email field', () {
      // Keyed `email`, not `request`. The server cannot tell which of the two
      // required inputs was blank from one branch, so it keys the pair to
      // `request`; the client knows exactly which box is empty. Same accept /
      // reject decision, better placement — never a stricter rule.
      expect(
        _validate(email: '')?.messageFor('email'),
        'Enter your email address.',
      );
    });

    test('a whitespace-only email is rejected (IsNullOrWhiteSpace, not '
        'IsNullOrEmpty)', () {
      expect(
        _validate(email: '   ')?.messageFor('email'),
        'Enter your email address.',
      );
    });

    test('surrounding whitespace is trimmed away rather than rejected', () {
      // Control: the same call rejects the value once its content is gone, so
      // `isNull` below is the trim working and not a validator that accepts
      // everything.
      expect(_validate(email: '  \t ')?.messageFor('email'), isNotNull);
      // The server itself does `Email.Trim().ToLowerInvariant()` before it
      // parses (OnboardingService.cs:36), so a pasted address with a trailing
      // space is valid input there and must be valid input here.
      expect(_validate(email: '  maya@example.com  '), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Email — shape
  // -------------------------------------------------------------------------

  group('email shape (OnboardingService.cs:36-38)', () {
    test('an address with no @ at all is rejected', () {
      expect(
        _validate(email: 'maya')?.messageFor('email'),
        'Enter a valid email address.',
      );
    });

    test('an address with no domain is rejected', () {
      expect(
        _validate(email: 'maya@')?.messageFor('email'),
        'Enter a valid email address.',
      );
    });

    test('an address with no local part is rejected', () {
      expect(
        _validate(email: '@example.com')?.messageFor('email'),
        'Enter a valid email address.',
      );
    });

    test('a dotless domain is ACCEPTED — MailAddress accepts `a@b`', () {
      // The single most likely way to ship a client stricter than the server:
      // almost every hand-rolled email regex demands a dot in the domain.
      // .NET's MailAddress does not, so `postmaster@localhost` is a 200 on the
      // server and must not be a red field here.
      //
      // Control: one character less — the same value with its domain removed —
      // is rejected by the same call.
      expect(_validate(email: 'a@')?.messageFor('email'), isNotNull);
      expect(_validate(email: 'a@b'), isNull);
      expect(_validate(email: 'postmaster@localhost'), isNull);
    });

    test('a plus-tagged, subdomained, mixed-case address is accepted', () {
      expect(_validate(email: 'maya')?.messageFor('email'), isNotNull);
      expect(_validate(email: 'Maya+lumen@mail.example.co.uk'), isNull);
    });

    test('a non-ASCII address is accepted — no ASCII-only rule exists on the '
        'server', () {
      expect(_validate(email: 'mañana')?.messageFor('email'), isNotNull);
      expect(_validate(email: 'mañana@ejemplo.es'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Password — required
  // -------------------------------------------------------------------------

  group('password is required (OnboardingService.cs:32)', () {
    test('an empty password is rejected at the password field', () {
      expect(
        _validate(password: '')?.messageFor('password'),
        'Enter a password.',
      );
    });

    test('a whitespace-only password is rejected as MISSING, not as short', () {
      // Twelve spaces is twelve characters, so a length-only check would pass
      // it. The server runs IsNullOrWhiteSpace first (:32) and answers "email
      // and password are required" — never the length message.
      expect(
        _validate(password: '            ')?.messageFor('password'),
        'Enter a password.',
      );
    });

    test('a password is NOT trimmed before it is measured', () {
      // The server measures `request.Password.Length` on the raw string (:39),
      // not a trimmed copy. Eleven spaces and one letter is a 12-character
      // password the server stores, so trimming here would reject a password
      // the server accepts — and would also silently disagree with Keycloak
      // about what the user's password is.
      //
      // Control: the same shape one character shorter is rejected.
      expect(_validate(password: '${' ' * 10}a')?.messageFor('password'), isNotNull);
      expect(_validate(password: '${' ' * 11}a'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Password — minimum length (D-24)
  // -------------------------------------------------------------------------

  group('password minimum length (D-24, OnboardingService.cs:39-40)', () {
    test('eleven characters is rejected, twelve is accepted', () {
      expect(
        _validate(password: 'a' * 11)?.messageFor('password'),
        'Use at least 12 characters.',
      );
      expect(_validate(password: 'a' * 12), isNull);
    });

    test('length is counted in UTF-16 code units, exactly as C# counts it', () {
      // D-24 allows any Unicode, and this is where a client silently becomes
      // stricter than the server: `String.length` in Dart and `string.Length`
      // in C# both count UTF-16 code units, but `characters.length` counts
      // grapheme clusters. Six astral emoji are 12 code units (a 200 on the
      // server) and 6 grapheme clusters (a rejection under `characters`).
      //
      // Control: five of the same emoji — 10 code units — is rejected by the
      // same call, so this cannot pass by accepting everything.
      expect(_validate(password: '🌙' * 5)?.messageFor('password'), isNotNull);
      expect(_validate(password: '🌙' * 6), isNull);
    });

    test('no character-class rule: twelve lower-case letters is accepted', () {
      expect(_validate(password: 'abcdefghijk')?.messageFor('password'), isNotNull);
      expect(_validate(password: 'abcdefghijkl'), isNull);
    });

    test('128 characters is accepted, 129 is rejected', () {
      // The server's upper bound (`:39` `is < 12 or > 128`, D-24's "max 128"),
      // mirrored in T7 fix round 1. Mirroring a bound the server HAS cannot
      // make the client stricter than it — and the accepting side of the
      // boundary is asserted first precisely so an off-by-one cap (127) cannot
      // hide behind the rejecting one.
      expect(_validate(password: 'a' * 128), isNull);
      expect(
        _validate(password: 'a' * 129)?.messageFor('password'),
        'Use 128 characters or fewer.',
      );
    });

    test('both password bounds are live at once, and neither swallows the '
        'other', () {
      // One clause replacing the other would still pass a test that only ever
      // looked at one end.
      expect(
        _validate(password: 'a' * 11)?.messageFor('password'),
        'Use at least 12 characters.',
      );
      expect(
        _validate(password: 'a' * 129)?.messageFor('password'),
        'Use 128 characters or fewer.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Name — maximum length (the one bound the server cannot attribute)
  // -------------------------------------------------------------------------

  group('name maximum length (OnboardingService.cs:41-43)', () {
    test('200 characters is accepted, 201 is rejected AT THE NAME FIELD', () {
      // The point of mirroring this one is not the round trip saved. The
      // server's branch covers `displayName`, `locale`, `timezone` and
      // `policyVersion` together and keys the rejection to `request`, so its
      // message ("a field exceeds its maximum length") tells the user
      // something is too long without saying what. Only the client knows.
      expect(_validate(name: 'M' * 200), isNull);
      expect(
        _validate(name: 'M' * 201)?.messageFor('displayName'),
        'Use 200 characters or fewer.',
      );
    });

    test('an empty name is still accepted — the field is optional', () {
      // Control: the same call rejects the long end, so `isNull` here is the
      // field being optional and not the rule being absent.
      expect(_validate(name: 'M' * 201), isNotNull);
      expect(_validate(name: ''), isNull);
    });

    test('the name is measured AFTER trimming, because that is what is sent', () {
      // Screen 2 sends `_nameCtrl.text.trim()`. Measuring the raw box would
      // reject a name whose trimmed form the server stores.
      //
      // Control: 201 non-space characters — the same length, nothing to trim —
      // is rejected by the same call.
      expect(_validate(name: 'M' * 201)?.messageFor('displayName'), isNotNull);
      expect(_validate(name: '${'M' * 200}     '), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // The failure it builds
  // -------------------------------------------------------------------------

  group('the ValidationFailure it builds', () {
    test('reports every bad field at once, keyed the way the server keys '
        'them', () {
      final failure = _validate(
        email: 'maya',
        password: 'short',
        name: 'M' * 201,
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure!.messageFor('email'), 'Enter a valid email address.');
      expect(failure.messageFor('password'), 'Use at least 12 characters.');
      expect(failure.messageFor('displayName'), 'Use 200 characters or fewer.');
      // All three at once: stopping at the first bad field would make the user
      // fix one, submit, and be told about the next.
      expect(
        failure.fields.keys,
        unorderedEquals(<String>['email', 'password', 'displayName']),
      );
    });

    test('carries a form-level message but no `request` key', () {
      // The banner is driven by `message`; `requestMessages` is reserved for
      // the server's cross-field errors, and putting a client message there
      // would make a locally-rejected form indistinguishable from one the
      // server rejected as a whole.
      final failure = _validate(email: '', password: '')!;

      expect(failure.message, 'Check the highlighted fields.');
      expect(failure.requestMessages, isEmpty);
    });

    test('a fully valid form produces no failure at all', () {
      // Control: the same call with one character removed from the password
      // does produce one.
      expect(_validate(password: 'a' * 11), isNotNull);
      expect(_validate(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Field keys — the wire contract
  // -------------------------------------------------------------------------

  test('the field keys are the camelCase wire names the server sends', () {
    // These constants are what screen 2 binds its inputs with, so they have to
    // be the same strings `errors: { … }` arrives under. `displayName` is the
    // one the SERVER never sends (its bound is keyed `request`); the client
    // files its own name-too-long message under it so the Name field claims
    // both that and any future server branch.
    expect(AccountFields.email, 'email');
    expect(AccountFields.password, 'password');
    expect(AccountFields.displayName, 'displayName');
  });
}
