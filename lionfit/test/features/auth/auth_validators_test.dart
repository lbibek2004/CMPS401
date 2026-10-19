import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/features/auth/domain/auth_validators.dart';

/// Validators return null when the value is acceptable, or a message to show.
void main() {
  group('email', () {
    test('accepts ordinary addresses including the seeded one', () {
      expect(AuthValidators.email('pao@selu.edu'), isNull);
      expect(AuthValidators.email('a.b-c+tag@sub.domain.co'), isNull);
    });

    test('rejects empty and whitespace-only input', () {
      expect(AuthValidators.email(null), isNotNull);
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.email('   '), isNotNull);
    });

    test('rejects malformed addresses', () {
      for (final bad in [
        'pao',
        'pao@',
        '@selu.edu',
        'pao selu.edu',
        'pao@selu',
      ]) {
        expect(
          AuthValidators.email(bad),
          isNotNull,
          reason: 'should reject "$bad"',
        );
      }
    });

    test('tolerates surrounding whitespace on an otherwise valid address', () {
      expect(AuthValidators.email('  pao@selu.edu  '), isNull);
    });
  });

  group('password', () {
    test('accepts a password at the Supabase minimum length', () {
      expect(
        AuthValidators.password('a' * AuthValidators.minPasswordLength),
        isNull,
      );
    });

    test('accepts the seeded development password', () {
      expect(AuthValidators.password('superAdmin'), isNull);
    });

    test('rejects anything shorter than the Supabase minimum', () {
      expect(
        AuthValidators.password('a' * (AuthValidators.minPasswordLength - 1)),
        isNotNull,
      );
      expect(AuthValidators.password(''), isNotNull);
      expect(AuthValidators.password(null), isNotNull);
    });

    test(
      'does not trim — leading and trailing spaces are part of the password',
      () {
        // 8 characters including the spaces; trimming would wrongly reject it.
        expect(AuthValidators.password('  abcd  '), isNull);
      },
    );
  });

  group('confirmPassword', () {
    test('accepts an exact match', () {
      expect(
        AuthValidators.confirmPassword('superAdmin', 'superAdmin'),
        isNull,
      );
    });

    test('rejects a mismatch, including case-only differences', () {
      expect(
        AuthValidators.confirmPassword('superadmin', 'superAdmin'),
        isNotNull,
      );
      expect(AuthValidators.confirmPassword('other', 'superAdmin'), isNotNull);
    });

    test('rejects empty confirmation', () {
      expect(AuthValidators.confirmPassword('', 'superAdmin'), isNotNull);
      expect(AuthValidators.confirmPassword(null, 'superAdmin'), isNotNull);
    });
  });

  group('displayName', () {
    test('accepts a normal name', () {
      expect(AuthValidators.displayName('Pao'), isNull);
    });

    test('rejects empty or whitespace-only', () {
      expect(AuthValidators.displayName(null), isNotNull);
      expect(AuthValidators.displayName('   '), isNotNull);
    });

    test('rejects a name longer than the maximum', () {
      final tooLong = 'a' * (AuthValidators.maxDisplayNameLength + 1);
      expect(AuthValidators.displayName(tooLong), isNotNull);
    });

    test('accepts a name exactly at the maximum', () {
      expect(
        AuthValidators.displayName('a' * AuthValidators.maxDisplayNameLength),
        isNull,
      );
    });
  });
}
