// lib/shared/providers/feature_flags_provider.dart
//
// Reads config/featureFlags from Firestore and exposes the current flag
// state to the rest of the app.
//
// SAFE-DEFAULT POLICY (per schema):
//   - Missing doc → all flags TRUE
//   - Missing individual key → that flag TRUE
//   - Read error → all flags TRUE
// Reasoning: a flag failure should never silently kill a feature for
// every user. Killing a feature must be an explicit admin action.
//
// LIVE UPDATES:
//   StreamProvider listens to the doc, so flipping a flag in the admin
//   panel propagates to all live users within seconds. No app reload
//   required. Cost is one persistent listener per session — negligible
//   for a doc this small.
//
// USAGE:
//   final flags = ref.watch(flagsProvider);
//   if (flags.aiAssistantEnabled) { ... }
//
//   // Guest mode check:
//   final guestEnabled = ref.watch(guestModeEnabledProvider);
//
//   // Or, for code that needs to react to load/error states:
//   final async = ref.watch(featureFlagsProvider);
//   async.when(loading: ..., error: ..., data: (flags) { ... });

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── MODEL ───────────────────────────────────────────────────────────────

class FeatureFlags {
  final bool aiAssistantEnabled;
  final bool aiComposeEnabled;
  final bool aiRefineEnabled;
  final bool aiProofreadEnabled;
  final bool linkedinGeneratorEnabled;
  final bool trialEnabled;
  final bool signupEnabled;
  final bool guestModeEnabled;

  const FeatureFlags({
    this.aiAssistantEnabled = true,
    this.aiComposeEnabled = true,
    this.aiRefineEnabled = true,
    this.aiProofreadEnabled = true,
    this.linkedinGeneratorEnabled = true,
    this.trialEnabled = true,
    this.signupEnabled = true,
    this.guestModeEnabled = true,
  });

  /// All flags enabled — used as the safe default while loading,
  /// on read errors, or when the config doc doesn't exist.
  static const allEnabled = FeatureFlags();

  factory FeatureFlags.fromMap(Map<String, dynamic> m) {
    // Treat any non-false value (true, null, missing) as "enabled".
    // Only an explicit `false` disables a feature.
    bool flag(String key) => m[key] != false;
    return FeatureFlags(
      aiAssistantEnabled: flag('aiAssistantEnabled'),
      aiComposeEnabled: flag('aiComposeEnabled'),
      aiRefineEnabled: flag('aiRefineEnabled'),
      aiProofreadEnabled: flag('aiProofreadEnabled'),
      linkedinGeneratorEnabled: flag('linkedinGeneratorEnabled'),
      trialEnabled: flag('trialEnabled'),
      signupEnabled: flag('signupEnabled'),
      guestModeEnabled: flag('guestModeEnabled'),
    );
  }
}

// ─── PROVIDERS ───────────────────────────────────────────────────────────

/// Live stream of the feature-flags doc. Use this when you want to
/// react to loading/error states explicitly.
final featureFlagsProvider = StreamProvider<FeatureFlags>((ref) {
  return FirebaseFirestore.instance
      .doc('config/featureFlags')
      .snapshots()
      .map<FeatureFlags>((snap) {
        if (!snap.exists) return FeatureFlags.allEnabled;
        final data = snap.data();
        if (data == null) return FeatureFlags.allEnabled;
        return FeatureFlags.fromMap(data);
      })
      .handleError((_) {
        // Silent fallback — never kill features on a read error.
        return FeatureFlags.allEnabled;
      });
});

/// Convenience accessor — always returns a valid `FeatureFlags`
/// (defaults to all-enabled while loading or on error). Use this
/// everywhere except when you specifically need to show a loading
/// state for the flags themselves.
final flagsProvider = Provider<FeatureFlags>((ref) {
  final async = ref.watch(featureFlagsProvider);
  return async.maybeWhen(
    data: (flags) => flags,
    orElse: () => FeatureFlags.allEnabled,
  );
});

/// Convenience provider for guest mode — used by auth guard, dashboard
/// routing, and lazy sign-in logic. When false, unauthed visitors see
/// the login screen (current behavior). When true, they can browse
/// dashboards and template pickers without signing in.
final guestModeEnabledProvider = Provider<bool>((ref) {
  return ref.watch(flagsProvider).guestModeEnabled;
});
