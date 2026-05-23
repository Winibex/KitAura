// =============================================================================
// validators.dart
//
// A pure-static utility class that provides form field validators compatible
// with Flutter's [FormField.validator] signature:
//
//   String? Function(String? value)
//
// Every method returns:
//   • null   — the value is valid (no error message to display).
//   • String — a human-readable error message to show beneath the field.
//
// Usage example:
//   TextFormField(validator: Validators.email)
//   TextFormField(validator: Validators.password)
//   TextFormField(validator: (v) => Validators.required(v, 'Full name'))
//   TextFormField(validator: (v) => Validators.confirmPassword(v, _pwController.text))
// =============================================================================

class Validators {
  // Private constructor prevents instantiation — all members are static.
  Validators._();

  // ---------------------------------------------------------------------------
  // Email
  // ---------------------------------------------------------------------------

  /// Validates that [value] is a non-empty, plausible email address.
  ///
  /// The regex is intentionally lenient (user@host.tld) — exhaustive RFC 5322
  /// validation is not worth the complexity for a UI validator; the server
  /// will reject truly malformed addresses anyway.
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }

    return null; // valid
  }

  // ---------------------------------------------------------------------------
  // Password
  // ---------------------------------------------------------------------------

  /// Validates that [value] is present and meets the minimum length policy
  /// (6 characters), matching Firebase Auth's default minimum.
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }

    return null; // valid
  }

  // ---------------------------------------------------------------------------
  // Generic required field
  // ---------------------------------------------------------------------------

  /// Validates that [value] is non-null and not blank (whitespace-only counts
  /// as empty).
  ///
  /// Pass [fieldName] to produce a contextual error message, e.g.
  ///   `Validators.required(v, 'Full name')` → "Full name is required"
  static String? required(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }

    return null; // valid
  }

  // ---------------------------------------------------------------------------
  // Confirm password
  // ---------------------------------------------------------------------------

  /// Validates that [value] matches [original] (the first password entry).
  ///
  /// Typically wired to the "confirm password" field, with [original] sourced
  /// from the primary password controller's current text:
  ///   `validator: (v) => Validators.confirmPassword(v, _pwController.text)`
  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != original) {
      return 'Passwords do not match';
    }

    return null; // valid
  }
}