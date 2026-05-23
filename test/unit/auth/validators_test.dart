// test/unit/auth/validators_test.dart
//
// Run:  flutter test test/unit/auth/validators_test.dart
//
// These are pure unit tests — no Firebase, no Widget tree, no async.
// They test the Validators utility class which does client-side
// validation before any API call is made.

import 'package:flutter_test/flutter_test.dart';
import 'package:kitaura/core/utils/validators.dart';

void main() {
  // ─── EMAIL VALIDATION ──────────────────────────────────────────────

  group('Validators.email', () {
    test('returns error when null', () {
      expect(Validators.email(null), isNotNull);
    });

    test('returns error when empty string', () {
      expect(Validators.email(''), 'Email is required');
    });

    test('returns error when whitespace only', () {
      expect(Validators.email('   '), 'Enter a valid email address');
    });

    test('returns error for missing @', () {
      expect(Validators.email('userexample.com'), isNotNull);
    });

    test('returns error for missing domain', () {
      expect(Validators.email('user@'), isNotNull);
    });

    test('returns error for missing TLD', () {
      expect(Validators.email('user@example'), isNotNull);
    });

    test('returns null (valid) for correct email', () {
      expect(Validators.email('user@example.com'), isNull);
    });

    test('accepts email with subdomain', () {
      expect(Validators.email('user@mail.example.co.uk'), isNull);
    });

    test('accepts email with + alias', () {
      expect(Validators.email('user+tag@example.com'), isNull);
    });
  });

  // ─── PASSWORD VALIDATION ───────────────────────────────────────────

  group('Validators.password', () {
    test('returns error when null', () {
      expect(Validators.password(null), isNotNull);
    });

    test('returns error when empty', () {
      expect(Validators.password(''), 'Password is required');
    });

    test('returns error when less than 6 chars', () {
      expect(Validators.password('12345'), isNotNull);
    });

    test('returns error when exactly 5 chars', () {
      expect(Validators.password('abcde'), isNotNull);
    });

    test('returns null (valid) when exactly 6 chars', () {
      expect(Validators.password('abcdef'), isNull);
    });

    test('returns null (valid) for long password', () {
      expect(Validators.password('a' * 100), isNull);
    });
  });

  // ─── REQUIRED FIELD VALIDATION ─────────────────────────────────────

  group('Validators.required', () {
    test('returns error with field name when null', () {
      expect(Validators.required(null, 'Full name'), 'Full name is required');
    });

    test('returns error with field name when empty', () {
      expect(Validators.required('', 'Full name'), 'Full name is required');
    });

    test('returns error when whitespace only', () {
      expect(Validators.required('   ', 'Full name'), 'Full name is required');
    });

    test('returns null (valid) when has content', () {
      expect(Validators.required('Ada Lovelace', 'Full name'), isNull);
    });
  });

  // ─── CONFIRM PASSWORD VALIDATION ───────────────────────────────────

  group('Validators.confirmPassword', () {
    test('returns error when null', () {
      expect(Validators.confirmPassword(null, 'abc123'), isNotNull);
    });

    test('returns error when empty', () {
      expect(
        Validators.confirmPassword('', 'abc123'),
        'Please confirm your password',
      );
    });

    test('returns error when passwords do not match', () {
      expect(
        Validators.confirmPassword('abc124', 'abc123'),
        'Passwords do not match',
      );
    });

    test('returns null (valid) when passwords match', () {
      expect(Validators.confirmPassword('abc123', 'abc123'), isNull);
    });

    test('is case-sensitive', () {
      expect(Validators.confirmPassword('Abc123', 'abc123'), isNotNull);
    });
  });
}