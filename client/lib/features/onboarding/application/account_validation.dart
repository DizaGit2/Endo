import 'package:lumen/core/error/failure.dart';

// ---------------------------------------------------------------------------
// AccountValidation — screen 2's client-side mirror of POST /onboarding/start
// (P4b-T7)
// ---------------------------------------------------------------------------

/// The `errors` map keys screen 2's three inputs answer to.
///
/// These are the **camelCase JSON paths the server sends on the wire**, not
/// display names: a 400 arrives as `errors: { "email": ["…"] }` and
/// `ValidationFailure.messageFor` is looked up with exactly these strings. The
/// client-side rules in [AccountValidation] deliberately key their failures the
/// same way, so screen 2 has ONE rendering path for a locally-rejected form and
/// a server-rejected one.
abstract final class AccountFields {
  /// The "Name" input — `OnboardingStartRequest.DisplayName`.
  ///
  /// The server never sends this key: `DisplayName` is **nullable**, so its
  /// only bound (200 characters, `OnboardingService.cs:41-43`) is reported
  /// under [ValidationFailure.requestKey] alongside three other members. The
  /// client uses the key anyway, for both halves of that gap — it is what
  /// [AccountValidation.displayNameTooLong] is filed under, and it is what the
  /// Name field binds, so a server branch that ever does key it lands at the
  /// right box with no screen change.
  static const String displayName = 'displayName';

  /// The "Email" input — `OnboardingStartRequest.Email`.
  static const String email = 'email';

  /// The "Password" input — `OnboardingStartRequest.Password`.
  static const String password = 'password';
}

/// Rejects, before any request is issued, exactly the input
/// `POST /onboarding/start` would reject — and **nothing else**.
///
/// ## What it mirrors
///
/// Every rule below is a line of
/// `backend/src/Lumen.Api/Onboarding/OnboardingService.cs`:
///
/// | rule | server | this file |
/// |---|---|---|
/// | email present | `:32` `IsNullOrWhiteSpace(Email)` | [emailRequired] |
/// | email shape | `:36-38` `MailAddress.TryCreate` round-trip | [emailInvalid] |
/// | password present | `:32` `IsNullOrWhiteSpace(Password)` | [passwordRequired] |
/// | password ≥ 12 | `:39` `Password.Length is < 12` (D-24) | [passwordTooShort] |
/// | password ≤ 128 | `:39` `Password.Length is … or > 128` (D-24) | [passwordTooLong] |
/// | name ≤ 200 | `:41-43` `DisplayName?.Length > 200` | [displayNameTooLong] |
///
/// The last two are **maximums, and they are mirrored deliberately** (T7 fix
/// round 1). The rule is "never invent a bound the server lacks", not "never
/// state one": D-24 reads *min 12 / max 128* and `:39` enforces both, so a
/// client cap at 128 refuses nothing the server would have stored. The
/// `displayName` cap earns its place twice over, because **the client can name
/// the field and the server cannot** — `:41-43` covers four members in one
/// branch and keys the rejection to [ValidationFailure.requestKey], so a
/// 201-character name arrives as a banner reading "a field exceeds its maximum
/// length" with nothing highlighted.
///
/// ## What it deliberately does NOT mirror
///
/// **A client that rejects what the server would accept is a defect**, and that
/// is the only failure mode this class is designed around. So:
///
/// * **No maximum on the EMAIL**, and none on `locale` / `timezone` /
///   `policyVersion`: the server bounds the latter three (`:41-43`) but screen 2
///   sends `null` for all of them, and a bound on an unsent field is a rule with
///   no input.
/// * **No character-class rule.** D-24 is "min 12, any Unicode" — no digit, no
///   symbol, no mixed case.
/// * **No breached-password check and no uniqueness check.** Neither is
///   knowable on the device: the first is a Keycloak policy (D-24, deferred to
///   P11) and the second is a 409 the controller already recovers from by
///   signing in. Approximating either locally would reject accounts the server
///   would create.
/// * **A far weaker email rule than `MailAddress`.** See [_hasEmailShape].
abstract final class AccountValidation {
  /// D-24's minimum, and `OnboardingService.cs:39`'s lower bound.
  static const int passwordMinLength = 12;

  /// D-24's maximum, and `OnboardingService.cs:39`'s upper bound.
  static const int passwordMaxLength = 128;

  /// `OnboardingService.cs:41`'s bound on `DisplayName`.
  static const int displayNameMaxLength = 200;

  /// Shown at the Email field when it is blank.
  ///
  /// The server keys this to `request` — from one branch it cannot say which
  /// of the two required inputs was missing (`:32`). The client can, so it
  /// keys it to the field. Same accept/reject decision, better placement.
  static const String emailRequired = 'Enter your email address.';

  /// Shown at the Email field when it cannot be an address at all.
  static const String emailInvalid = 'Enter a valid email address.';

  /// Shown at the Password field when it is blank or all whitespace.
  static const String passwordRequired = 'Enter a password.';

  /// Shown at the Password field when it is under [passwordMinLength].
  static const String passwordTooShort =
      'Use at least $passwordMinLength characters.';

  /// Shown at the Password field when it is over [passwordMaxLength].
  static const String passwordTooLong =
      'Use $passwordMaxLength characters or fewer.';

  /// Shown at the Name field when it is over [displayNameMaxLength].
  ///
  /// This message exists only on the client. The server's own rejection
  /// (`:41-43`) is keyed `request` and reads "a field exceeds its maximum
  /// length" — true, unhelpful, and attached to no input.
  static const String displayNameTooLong =
      'Use $displayNameMaxLength characters or fewer.';

  /// The banner copy for a locally-rejected form.
  ///
  /// Carried as [Failure.message] and **not** under
  /// [ValidationFailure.requestKey]: that key is the server's, for cross-field
  /// errors that name no input, and borrowing it would make a form the device
  /// rejected indistinguishable from one the server rejected as a whole.
  static const String summary = 'Check the highlighted fields.';

  /// Returns the failure screen 2 should render, or `null` when the form is
  /// good enough to send.
  ///
  /// Every bad field is reported at once. Reporting only the first would make
  /// the user fix it, submit, and be told about the next one.
  static ValidationFailure? validate({
    required String email,
    required String password,
    required String displayName,
  }) {
    final fields = <String, List<String>>{};

    // The server canonicalises with `Email.Trim().ToLowerInvariant()` (`:36`)
    // before it parses, so a pasted address with a trailing space is valid
    // input there. Lower-casing is the server's business — it is what the
    // stored username and the lookup hash are derived from, and doing it here
    // would only hide the difference.
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      fields[AccountFields.email] = const <String>[emailRequired];
    } else if (!_hasEmailShape(trimmedEmail)) {
      fields[AccountFields.email] = const <String>[emailInvalid];
    }

    // Order matters and matches the server's: `IsNullOrWhiteSpace` (`:32`)
    // runs BEFORE the length check (`:39`), so twelve spaces is a missing
    // password rather than a long enough one.
    //
    // THE ONE PLACE THIS CLASS IS STRICTER THAN THE SERVER, stated so nobody
    // has to rediscover it: Dart's `String.trim` strips the Unicode White_Space
    // set **plus U+FEFF** (the BOM); C#'s `char.IsWhiteSpace`, which
    // `IsNullOrWhiteSpace` is built on, does not — U+FEFF stopped counting as
    // whitespace in .NET 4. Everything else in the two sets matches, U+0085
    // included. MEASURED, not assumed — twelve U+FEFF characters give
    // `char.IsWhiteSpace == False` / `IsNullOrWhiteSpace == False` / `Length ==
    // 12` on .NET 10 and `length == 12` / `trim().isEmpty == true` on Dart,
    // while twelve U+0085 are blank on both. So a password of twelve or more
    // U+FEFF characters is stored by the server and refused here as missing.
    // It cannot be typed, only pasted from a file with a stray BOM, and closing
    // the gap would mean hand-rolling a whitespace predicate that then drifts
    // from the framework's — so this is a documented divergence, not a defect
    // to fix. The email field is unaffected: a BOM-only address fails the shape
    // check either way.
    if (password.trim().isEmpty) {
      fields[AccountFields.password] = const <String>[passwordRequired];
    } else if (password.length < passwordMinLength) {
      // `String.length` — UTF-16 code units, which is exactly what C#'s
      // `string.Length` counts at `:39`. NOT `characters.length`: under
      // grapheme clusters six astral emoji measure 6 and would be rejected,
      // while the server measures 12 and stores the account.
      fields[AccountFields.password] = const <String>[passwordTooShort];
    } else if (password.length > passwordMaxLength) {
      fields[AccountFields.password] = const <String>[passwordTooLong];
    }

    // Measured AFTER trimming, because trimming is what the wire value gets:
    // screen 2 sends `_nameCtrl.text.trim()`. Measuring the raw box would
    // reject a 201-character name whose 200-character trimmed form the server
    // stores — the exact over-rejection this file exists to avoid.
    if (displayName.trim().length > displayNameMaxLength) {
      fields[AccountFields.displayName] = const <String>[displayNameTooLong];
    }

    if (fields.isEmpty) return null;
    return ValidationFailure(message: summary, fields: fields);
  }

  /// Whether [email] could be an address: an `@` with something on both sides.
  ///
  /// This is **much** weaker than the server's
  /// `MailAddress.TryCreate(email) && parsed.Address == email` (`:36-38`), and
  /// that asymmetry is the whole design. The client's job is to catch the
  /// typo that cannot possibly be an address ("maya", "maya@", "@example.com");
  /// deciding the hard cases is the server's, because every extra condition is
  /// a chance to refuse an address .NET would have taken:
  ///
  /// * **No dot required in the domain.** `MailAddress` accepts `a@b`, so
  ///   `postmaster@localhost` is a 200. Most hand-rolled email regexes reject
  ///   it.
  /// * **No ASCII-only rule.** `mañana@ejemplo.es` parses.
  /// * **No "exactly one @" rule** — the split is on the LAST `@`, so
  ///   `a@b@c.com` passes here and is refused by the server, rather than the
  ///   other way round.
  /// * **No length, no whitespace rule** — `"maya s"@example.com` is a quoted
  ///   local part that round-trips through `MailAddress`.
  static bool _hasEmailShape(String email) {
    final at = email.lastIndexOf('@');
    return at > 0 && at < email.length - 1;
  }
}
