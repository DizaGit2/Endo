// Unit tests for avatarInitials (profile_screen.dart) — TDD.
//
// Regression guard: a whitespace-only server-supplied displayName must NOT
// crash the avatar with a RangeError (the old `name.isEmpty` guard let '   '
// through, then indexed parts[0][0] on an empty string).

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

void main() {
  group('avatarInitials', () {
    test('null → ?', () => expect(avatarInitials(null), '?'));

    test('empty → ?', () => expect(avatarInitials(''), '?'));

    test('whitespace-only → ? (no RangeError)', () {
      expect(avatarInitials('   '), '?');
      expect(avatarInitials('\t \n'), '?');
    });

    test('single name → first initial, uppercased', () {
      expect(avatarInitials('maría'), 'M');
    });

    test('two names → first two initials', () {
      expect(avatarInitials('Maya Angelou'), 'MA');
    });

    test('surrounding and internal whitespace is collapsed', () {
      expect(avatarInitials('  María   García  '), 'MG');
    });
  });
}
