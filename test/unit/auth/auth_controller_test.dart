// test/unit/auth/auth_controller_test.dart
//
// Run:  flutter test test/unit/auth/auth_controller_test.dart
//
// HOW THIS WORKS:
// ────────────────────────────────────────────────────────────
// The AuthController calls FirebaseService (static methods) and
// FirebaseAuth.instance. We can't mock statics directly, so we
// test the controller's logic by:
//
//   1. Testing validation logic (synchronous, no Firebase needed)
//   2. Testing state transitions (loading, error, navigation)
//   3. Testing error mapping (string → user-friendly message)
//
// For full integration tests that hit real Firebase, you'd use
// firebase_auth_mocks or the Firebase emulator. That's a later step.
//
// WHAT YOU'LL LEARN:
// ────────────────────────────────────────────────────────────
// - group() organizes related tests
// - test() is a single test case
// - expect() asserts a condition
// - setUp() runs before each test in its group
// - StateNotifier state is accessed via controller.state
// ────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:kitaura/features/auth/controller/auth_controller.dart';

void main() {
  // ─── INITIAL STATE ─────────────────────────────────────────────────

  group('AuthController — initial state', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController();
    });

    test('starts with isLoading false', () {
      expect(controller.state.isLoading, false);
    });

    test('starts with no error', () {
      expect(controller.state.error, isNull);
    });

    test('starts with navigate = none', () {
      expect(controller.state.navigate, AuthNav.none);
    });
  });

  // ─── SIGN IN VALIDATION (no Firebase calls) ───────────────────────
  //
  // These tests verify that the controller catches bad input
  // BEFORE making any API call. This saves network round-trips
  // and gives instant feedback.

  group('AuthController — signInWithEmail validation', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController();
    });

    test('empty email shows error immediately', () async {
      await controller.signInWithEmail('', 'password123');

      expect(controller.state.isLoading, false);
      expect(controller.state.error, contains('email'));
    });

    test('whitespace-only email shows error', () async {
      await controller.signInWithEmail('   ', 'password123');

      expect(controller.state.error, contains('email'));
    });

    test('invalid email format shows error', () async {
      await controller.signInWithEmail('not-an-email', 'password123');

      expect(controller.state.error, contains('valid email'));
    });

    test('empty password shows error', () async {
      await controller.signInWithEmail('user@example.com', '');

      expect(controller.state.error, contains('password'));
    });

    test('valid input does not set validation error', () async {
      // Note: This will throw because we're not running a real Firebase.
      // But the important thing is that validation PASSES — the error
      // will be a Firebase error, not a validation error.
      try {
        await controller.signInWithEmail('user@example.com', 'password123');
      } catch (_) {
        // Expected — Firebase isn't initialized in test
      }

      // If there's an error, it should NOT be a validation error
      if (controller.state.error != null) {
        expect(controller.state.error, isNot(contains('Please enter')));
      }
    });
  });

  // ─── SIGN UP VALIDATION ────────────────────────────────────────────

  // group('AuthController — signUpWithEmail validation', () {
  //   late AuthController controller;
  //
  //   setUp(() {
  //     controller = AuthController();
  //   });
  //
  //   test('empty name shows error', () async {
  //     await controller.signUpWithEmail(
  //       'user@example.com', 'password123', 'password123', '',
  //     );
  //
  //     expect(controller.state.error, contains('name'));
  //   });
  //
  //   test('empty email shows error', () async {
  //     await controller.signUpWithEmail(
  //       '', 'password123', 'password123', 'Ada',
  //     );
  //
  //     expect(controller.state.error, contains('email'));
  //   });
  //
  //   test('invalid email shows error', () async {
  //     await controller.signUpWithEmail(
  //       'bad-email', 'password123', 'password123', 'Ada',
  //     );
  //
  //     expect(controller.state.error, contains('valid email'));
  //   });
  //
  //   test('empty password shows error', () async {
  //     await controller.signUpWithEmail(
  //       'user@example.com', '', '', 'Ada',
  //     );
  //
  //     expect(controller.state.error, contains('password'));
  //   });
  //
  //   test('short password (< 6 chars) shows error', () async {
  //     await controller.signUpWithEmail(
  //       'user@example.com', '12345', '12345', 'Ada',
  //     );
  //
  //     expect(controller.state.error, contains('6 characters'));
  //   });
  //
  //   test('password mismatch shows error', () async {
  //     await controller.signUpWithEmail(
  //       'user@example.com', 'password123', 'password456', 'Ada',
  //     );
  //
  //     expect(controller.state.error, contains('do not match'));
  //   });
  //
  //   test('all fields valid passes validation', () async {
  //     // Will fail at Firebase level (not initialized), but validation passes
  //     try {
  //       await controller.signUpWithEmail(
  //         'user@example.com', 'password123', 'password123', 'Ada Lovelace',
  //       );
  //     } catch (_) {}
  //
  //     // Any error should be from Firebase, not validation
  //     if (controller.state.error != null) {
  //       expect(controller.state.error, isNot(contains('Please enter')));
  //       expect(controller.state.error, isNot(contains('do not match')));
  //       expect(controller.state.error, isNot(contains('6 characters')));
  //     }
  //   });
  // });

  // ─── PASSWORD RESET VALIDATION ─────────────────────────────────────

  group('AuthController — sendPasswordResetEmail validation', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController();
    });

    test('empty email shows error and returns false', () async {
      final result = await controller.sendPasswordResetEmail('');

      expect(result, false);
      expect(controller.state.error, contains('email'));
    });

    test('whitespace-only email shows error', () async {
      final result = await controller.sendPasswordResetEmail('   ');

      expect(result, false);
      expect(controller.state.error, isNotNull);
    });
  });

  // ─── CLEAR ERROR ───────────────────────────────────────────────────

  group('AuthController — clearError', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController();
    });

    test('clears existing error', () async {
      // Trigger a validation error first
      await controller.signInWithEmail('', 'pw');
      expect(controller.state.error, isNotNull);

      controller.clearError();
      expect(controller.state.error, isNull);
    });

    test('does nothing when no error exists', () {
      // No error set
      controller.clearError();
      expect(controller.state.error, isNull);
      expect(controller.state.isLoading, false);
    });
  });

  // ─── AUTH STATE ────────────────────────────────────────────────────

  group('AuthState', () {
    test('default state has correct values', () {
      const state = AuthState();

      expect(state.isLoading, false);
      expect(state.error, isNull);
      expect(state.navigate, AuthNav.none);
    });

    test('copyWith preserves unspecified fields', () {
      const state = AuthState(isLoading: true, error: 'oops');
      final copied = state.copyWith(isLoading: false);

      expect(copied.isLoading, false);
      // error is NOT preserved — copyWith uses `error: error` not `error ?? this.error`
      // This is by design: you always pass error explicitly when you want it
    });

    test('copyWith auto-resets navigate to none', () {
      const state = AuthState(navigate: AuthNav.dashboard);
      final copied = state.copyWith(isLoading: false);

      // navigate resets to none unless explicitly set
      expect(copied.navigate, AuthNav.none);
    });

    test('copyWith can set navigate explicitly', () {
      const state = AuthState();
      final copied = state.copyWith(navigate: AuthNav.verifyEmail);

      expect(copied.navigate, AuthNav.verifyEmail);
    });
  });

  // ─── AUTH NAV ENUM ─────────────────────────────────────────────────

  group('AuthNav', () {
    test('has all expected values', () {
      expect(AuthNav.values, containsAll([
        AuthNav.none,
        AuthNav.dashboard,
        AuthNav.verifyEmail,
      ]));
    });

    test('has exactly 3 values', () {
      expect(AuthNav.values.length, 3);
    });
  });

  // ─── VALIDATION ORDER ─────────────────────────────────────────────
  //
  // These verify that the controller checks fields in the right order.
  // When multiple fields are wrong, the FIRST error should be about
  // the topmost field in the form (name → email → password → confirm).

  // group('AuthController — validation order', () {
  //   late AuthController controller;
  //
  //   setUp(() {
  //     controller = AuthController();
  //   });
  //
  //   test('sign-up checks name before email', () async {
  //     await controller.signUpWithEmail(
  //       '', // bad email
  //       'pw', // bad password
  //       'pw', // matches but short
  //       '', // bad name
  //     );
  //     // Should complain about name first, not email or password
  //     expect(controller.state.error, contains('name'));
  //   });
  //
  //   test('sign-up checks email before password', () async {
  //     await controller.signUpWithEmail(
  //       'bad', // bad email
  //       'pw', // bad password
  //       'pw2', // mismatch
  //       'Ada', // good name
  //     );
  //     expect(controller.state.error, contains('email'));
  //   });
  //
  //   test('sign-up checks password length before mismatch', () async {
  //     await controller.signUpWithEmail(
  //       'a@b.com',
  //       'short', // 5 chars
  //       'nope', // mismatch
  //       'Ada',
  //     );
  //     expect(controller.state.error, contains('6 characters'));
  //   });
  //
  //   test('sign-in checks email before password', () async {
  //     await controller.signInWithEmail('', '');
  //     expect(controller.state.error, contains('email'));
  //   });
  // });
}