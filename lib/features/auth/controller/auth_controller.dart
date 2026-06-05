// =============================================================================
// auth_controller.dart
//
// Authentication state management using Riverpod's StateNotifier pattern.
//
// Exports:
//   • AuthNav             — navigation intent enum
//   • AuthState           — immutable state snapshot
//   • AuthController      — StateNotifier that drives all auth operations
//   • authControllerProvider — Riverpod provider for the controller + state
//   • authStateProvider      — StreamProvider wrapping Firebase auth changes
// =============================================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../shared/ai/claude_service.dart';
import '../../../shared/services/firebase_service.dart';

// =============================================================================
// AUTH STATE
// =============================================================================

/// Navigation intent emitted by [AuthController] after a successful operation.
///
/// The UI watches [AuthState.navigate] and routes accordingly.
/// [AuthNav.none] is the idle/default — no navigation required.
enum AuthNav {
  none,
  dashboard,    // user is authenticated and verified
  verifyEmail,  // user is authenticated but email is unverified
}

/// Immutable snapshot of the current authentication UI state.
///
/// Consumed by screens via `ref.watch(authControllerProvider)`.
class AuthState {
  final bool isLoading;   // true while an async auth operation is in progress
  final String? error;    // non-null when the last operation produced an error
  final AuthNav navigate; // navigation intent; resets to [AuthNav.none] after read

  const AuthState({
    this.isLoading = false,
    this.error,
    this.navigate = AuthNav.none,
  });

  /// Returns a new [AuthState] with the given fields replaced.
  ///
  /// Note: [navigate] always resets to [AuthNav.none] unless explicitly
  /// provided. This ensures one-shot navigation — the UI routes once and
  /// the intent is cleared on the next state emission.
  AuthState copyWith({
    bool?    isLoading,
    String?  error,
    AuthNav? navigate,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error:     error,                           // null clears the previous error
      navigate:  navigate ?? AuthNav.none,        // auto-reset after read
    );
  }
}

// =============================================================================
// AUTH CONTROLLER
// =============================================================================

/// Handles all Firebase Auth operations and exposes the result as [AuthState].
///
/// Pattern used throughout:
///   1. Run client-side validation → emit error state and return early if invalid.
///   2. Emit loading state.
///   3. Await Firebase operation.
///   4. On success → emit navigation intent.
///   5. On [FirebaseAuthException] → map the error code to a human-readable message.
///   6. On unknown error → emit a generic fallback message.
class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState());

  // ===========================================================================
  // Sign In
  // ===========================================================================

  /// Signs the user in with [email] and [password].
  ///
  /// After a successful sign-in, routes to Dashboard (email verified)
  /// or VerifyEmail (email not yet verified).
  Future<void> signInWithEmail(String email, String password) async {
    // Validate inputs before hitting the network.
    final validationError = _validateSignIn(email, password);
    if (validationError != null) {
      state = AuthState(error: validationError);
      return;
    }

    state = const AuthState(isLoading: true);
    try {
      await FirebaseService.signInWithEmail(email, password);
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Track the login event without blocking navigation — analytics
        // failures should never prevent the user from reaching the dashboard.
        ClaudeService.trackLogin();

        state = AuthState(
          navigate: user.emailVerified ? AuthNav.dashboard : AuthNav.verifyEmail,
        );
      }
    } on FirebaseAuthException catch (e) {
      state = AuthState(error: _mapFirebaseError(e.code));
    } catch (e) {
      debugPrint('SignIn error: $e');
      state = const AuthState(error: 'Something went wrong. Please try again.');
    }
  }

  // ===========================================================================
  // Sign Up
  // ===========================================================================

  /// Creates a new account with [email] and [password], then bootstraps all
  /// required Firestore documents for the new user.
  ///
  /// Document creation is batched atomically via [FirebaseService] so the
  /// database is never left in a partially-initialised state.
  Future<void> signUpWithEmail(
      String email,
      String password,
      String confirmPassword,
      String displayName,
      ) async
  {
    // Validate inputs before hitting the network.
    final validationError =
    _validateSignUp(email, password, confirmPassword, displayName);
    if (validationError != null) {
      state = AuthState(error: validationError);
      return;
    }

    state = const AuthState(isLoading: true);
    try {
      final credential =
      await FirebaseService.signUpWithEmail(email, password);
      final user = credential.user!;

      // Persist the display name to the Firebase Auth profile.
      await user.updateDisplayName(displayName);

      // Write all initial Firestore documents in a single batch —
      // this is atomic: either all documents are created or none are.
      await FirebaseService.createNewUserDocuments(
        uid:          user.uid,
        email:        email,
        displayName:  displayName,
        signupSource: 'email',
      );

      // Email verification is required before dashboard access.
      state = const AuthState(navigate: AuthNav.verifyEmail);
    } on FirebaseAuthException catch (e) {
      state = AuthState(error: _mapFirebaseError(e.code));
    } catch (e) {
      debugPrint('SignUp error: $e');
      state = const AuthState(error: 'Something went wrong. Please try again.');
    }
  }

  // ===========================================================================
  // Google Sign In
  // ===========================================================================

  /// Launches the Google OAuth popup / native flow and signs the user in.
  ///
  /// For brand-new Google users, bootstraps Firestore documents in the same
  /// way as email sign-up. For returning users, skips document creation and
  /// tracks the login event.
  Future<void> signInWithGoogle() async {
    state = const AuthState(isLoading: true);
    try {
      final credential = await FirebaseService.signInWithGoogle();
      final user = credential.user!;

      // Only initialise Firestore documents on the very first sign-in.
      final isNewUser = credential.additionalUserInfo?.isNewUser == true;
      if (isNewUser) {
        await FirebaseService.createNewUserDocuments(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? '',
          photoUrl: user.photoURL,
          signupSource: 'google',
        );
        // Skip trackLogin — createNewUserDocuments already seeded loginCount=1
      } else {
        ClaudeService.trackLogin();
      }

      // Google accounts arrive pre-verified, but we still check the flag so
      // any edge cases (e.g. custom domain policy) are handled correctly.
      state = AuthState(
        navigate: user.emailVerified ? AuthNav.dashboard : AuthNav.verifyEmail,
      );
    } on FirebaseAuthException catch (e) {
      // The user dismissed the popup — this is not an error worth surfacing.
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        state = const AuthState();
        return;
      }
      state = AuthState(error: _mapFirebaseError(e.code));
    } catch (e) {
      debugPrint('Google SignIn error: $e');
      state =
      const AuthState(error: 'Google sign in failed. Please try again.');
    }
  }

  // ===========================================================================
  // Sign Out
  // ===========================================================================

  /// Signs the current user out and resets state to idle.
  Future<void> signOut() async {
    await FirebaseService.signOut();
    state = const AuthState();
  }

  // ===========================================================================
  // Email Verification
  // ===========================================================================

  /// Sends a verification email to the currently signed-in user.
  /// No-op if the user is already verified or there is no current user.
  Future<void> sendEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } catch (e) {
      debugPrint('sendEmailVerification error: $e');
    }
  }

  /// Reloads the Firebase Auth user object and returns the current
  /// verification status.
  ///
  /// Called by the polling loop on [VerifyEmailScreen] so the UI transitions
  /// automatically once the user clicks the link in their inbox.
  Future<bool> checkEmailVerified() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Force a server refresh — the cached value won't update on its own.
        await user.reload();
        return FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      }
    } catch (e) {
      debugPrint('checkEmailVerified error: $e');
    }
    return false;
  }

  // ===========================================================================
  // Password Reset
  // ===========================================================================

  /// Sends a password-reset email to [email].
  ///
  /// Returns `true` on success (caller can show a confirmation UI),
  /// `false` on failure (error is written to state for the UI to display).
  Future<bool> sendPasswordResetEmail(String email) async {
    if (email.trim().isEmpty) {
      state = const AuthState(error: 'Please enter your email address.');
      return false;
    }

    state = const AuthState(isLoading: true);
    try {
      await FirebaseService.sendPasswordResetEmail(email);
      state = const AuthState(); // clear loading; no error
      return true;
    } on FirebaseAuthException catch (e) {
      state = AuthState(error: _mapFirebaseError(e.code));
      return false;
    } catch (e) {
      debugPrint('PasswordReset error: $e');
      state =
      const AuthState(error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Clears the current error from state without triggering navigation.
  /// Typically called when the user edits a field after seeing an error.
  void clearError() {
    if (state.error != null) {
      state = const AuthState();
    }
  }

  // ---------------------------------------------------------------------------
  // Client-side validation
  // ---------------------------------------------------------------------------

  /// Returns an error message string if the sign-in inputs are invalid,
  /// or null if all inputs pass validation.
  String? _validateSignIn(String email, String password) {
    if (email.trim().isEmpty)               return 'Please enter your email address.';
    if (!_emailRegex.hasMatch(email.trim())) return 'Please enter a valid email address.';
    if (password.isEmpty)                   return 'Please enter your password.';
    return null;
  }

  /// Returns an error message string if any sign-up input is invalid,
  /// or null if all inputs pass validation.
  String? _validateSignUp(
      String email,
      String password,
      String confirmPassword,
      String displayName,
      ) {
    if (displayName.trim().isEmpty)          return 'Please enter your full name.';
    if (email.trim().isEmpty)                return 'Please enter your email address.';
    if (!_emailRegex.hasMatch(email.trim())) return 'Please enter a valid email address.';
    if (password.isEmpty)                    return 'Please enter a password.';
    if (password.length < 6)                 return 'Password must be at least 6 characters.';
    if (password != confirmPassword)          return 'Passwords do not match.';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  /// Simple email format check — the full RFC regex isn't needed for a UI.
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Maps Firebase Auth error codes to human-readable messages.
  /// Kept as a constant map so lookup is O(1) and strings are compile-time constants.
  static const _errorMap = <String, String>{
    'user-not-found':     'No account found with this email address.',
    'wrong-password':     'Incorrect password. Please try again.',
    'invalid-credential': 'Invalid email or password. Please check and try again.',
    'user-disabled':      'This account has been disabled. Contact support.',
    'email-already-in-use':   'An account already exists with this email.',
    'weak-password':          'Password is too weak. Use at least 6 characters.',
    'invalid-email':          'Please enter a valid email address.',
    'operation-not-allowed':  'Email/password sign in is not enabled.',
    'account-exists-with-different-credential':
    'An account already exists with a different sign-in method.',
    'popup-closed-by-user':    'Google sign in was cancelled.',
    'popup-blocked':           'Popup was blocked. Please allow popups and try again.',
    'cancelled-popup-request': 'Sign in was cancelled.',
    'network-request-failed':  'Network error. Please check your connection.',
    'too-many-requests':       'Too many attempts. Please wait a moment and try again.',
    'requires-recent-login':   'Please sign in again to continue.',
  };

  /// Returns the mapped message for [code], or a generic fallback that
  /// includes the raw code to assist debugging.
  String _mapFirebaseError(String code) {
    return _errorMap[code] ?? 'Something went wrong ($code). Please try again.';
  }
}

// =============================================================================
// PROVIDERS
// =============================================================================

/// Provides the [AuthController] instance and its [AuthState] to the widget tree.
///
/// Usage:
///   final authState = ref.watch(authControllerProvider);
///   ref.read(authControllerProvider.notifier).signInWithEmail(email, pw);
final authControllerProvider =
StateNotifierProvider<AuthController, AuthState>(
      (ref) => AuthController(),
);

/// A [StreamProvider] that exposes the raw Firebase [User?] auth stream.
///
/// Useful for widgets that need to react to sign-in / sign-out events globally
/// (e.g. the router redirect guard) without going through [AuthController].
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseService.authStateChanges;
});