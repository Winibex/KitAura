// lib/features/settings/controller/settings_controller.dart
//
// MVC controller for the Settings screen.
//
// Owns all settings-related state: user profile, subscription, preferences,
// Career Profiles, Client Profiles. Wraps all Firebase reads/writes so the
// view can stay UI-only.
//
// The view consumes state via ref.watch(settingsControllerProvider) and
// triggers actions via ref.read(settingsControllerProvider.notifier).xxx().

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/client_profile_model.dart';
import '../../../shared/models/subscription_model.dart';
import '../../../shared/models/user_preferences_model.dart';
import '../../../shared/models/user_profile_model.dart';
import '../../../shared/services/firebase_service.dart';

// ─── STATE ────────────────────────────────────────────────────────────

enum SettingsTab { profile, security, billing, preferences, aiProfile, clientProfiles }

/// Lightweight signal the view can react to without holding a snackbar service.
class SettingsFeedback {
  final String message;
  final bool isError;
  /// Random-ish id so the view can dedupe "show this once" reactions.
  final int id;

  const SettingsFeedback({
    required this.message,
    required this.id,
    this.isError = false,
  });
}

class SettingsState {
  // Top-level loading
  final bool isLoading;
  final bool isSaving;

  // Core docs
  final UserProfileModel? profile;
  final SubscriptionModel subscription;
  final UserPreferencesModel preferences;

  // Career Profiles tab
  final List<AiProfileModel> aiProfiles;
  final bool loadingAiProfiles;

  // Client Profiles tab
  final List<ClientProfileModel> clientProfiles;
  final bool loadingClientProfiles;

  // One-shot feedback the view shows as a snackbar. Null when nothing to show.
  final SettingsFeedback? feedback;

  const SettingsState({
    this.isLoading = true,
    this.isSaving = false,
    this.profile,
    this.subscription = const SubscriptionModel(),
    this.preferences = const UserPreferencesModel(),
    this.aiProfiles = const [],
    this.loadingAiProfiles = true,
    this.clientProfiles = const [],
    this.loadingClientProfiles = true,
    this.feedback,
  });

  SettingsState copyWith({
    bool? isLoading,
    bool? isSaving,
    UserProfileModel? profile,
    SubscriptionModel? subscription,
    UserPreferencesModel? preferences,
    List<AiProfileModel>? aiProfiles,
    bool? loadingAiProfiles,
    List<ClientProfileModel>? clientProfiles,
    bool? loadingClientProfiles,
    SettingsFeedback? feedback,
    bool clearFeedback = false,
  }) {
    return SettingsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      profile: profile ?? this.profile,
      subscription: subscription ?? this.subscription,
      preferences: preferences ?? this.preferences,
      aiProfiles: aiProfiles ?? this.aiProfiles,
      loadingAiProfiles: loadingAiProfiles ?? this.loadingAiProfiles,
      clientProfiles: clientProfiles ?? this.clientProfiles,
      loadingClientProfiles: loadingClientProfiles ?? this.loadingClientProfiles,
      feedback: clearFeedback ? null : (feedback ?? this.feedback),
    );
  }
}

// ─── CONTROLLER ───────────────────────────────────────────────────────

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController() : super(const SettingsState());

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  User? get _currentUser => FirebaseAuth.instance.currentUser;

  int _feedbackId = 0;
  int _nextFeedbackId() => ++_feedbackId;

  void _emitFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    state = state.copyWith(
      feedback: SettingsFeedback(
        message: message,
        isError: isError,
        id: _nextFeedbackId(),
      ),
    );
  }

  /// Called by the view after it has shown the snackbar so subsequent
  /// state changes don't re-trigger the same feedback.
  void acknowledgeFeedback() {
    if (state.feedback == null) return;
    state = state.copyWith(clearFeedback: true);
  }

  // ─── INITIAL LOAD ────────────────────────────────────────────────────

  /// Loads everything needed for the Settings screen in parallel.
  /// Safe to call multiple times — re-runs all fetches.
  Future<void> loadAll() async {
    final uid = _uid;
    if (uid == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final results = await Future.wait([
        FirebaseService.getUserProfile(uid),
        FirebaseService.getSubscription(uid),
        FirebaseService.getPreferences(uid),
      ]);
      if (!mounted) return;

      final profileDoc = results[0];
      final subDoc = results[1];
      final prefDoc = results[2];

      state = state.copyWith(
        profile: profileDoc.exists
            ? UserProfileModel.fromJson(profileDoc.data() as Map<String, dynamic>)
            : null,
        subscription: subDoc.exists
            ? SubscriptionModel.fromJson(subDoc.data() as Map<String, dynamic>)
            : const SubscriptionModel(),
        preferences: prefDoc.exists
            ? UserPreferencesModel.fromJson(prefDoc.data() as Map<String, dynamic>)
            : const UserPreferencesModel(),
        isLoading: false,
      );
    } catch (e) {
      debugPrint('SettingsController loadAll error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }

    // Kick off the two list loads in parallel — they have their own
    // loading flags so they don't block the main spinner.
    await Future.wait([loadAiProfiles(), loadClientProfiles()]);
  }

  // ─── USER PROFILE ────────────────────────────────────────────────────

  /// Saves the user profile. Returns true on success.
  Future<bool> saveProfile({
    required String displayName,
    String? phone,
    String? location,
    String? bio,
  }) async {
    final uid = _uid;
    if (uid == null) return false;

    state = state.copyWith(isSaving: true);

    try {
      final updates = <String, dynamic>{
        'displayName': displayName.trim(),
        'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
        'location': (location?.trim().isEmpty ?? true) ? null : location!.trim(),
        'bio': (bio?.trim().isEmpty ?? true) ? null : bio!.trim(),
      };
      await FirebaseService.updateUserProfile(uid, updates);

      // Keep Firebase Auth's displayName in sync — separate from the
      // Firestore user doc so we update it explicitly.
      if (displayName.trim().isNotEmpty) {
        await _currentUser?.updateDisplayName(displayName.trim());
      }

      if (!mounted) return true;

      state = state.copyWith(
        isSaving: false,
        profile: state.profile?.copyWith(
          displayName: displayName.trim(),
          phone: phone?.trim(),
          location: location?.trim(),
          bio: bio?.trim(),
        ),
      );
      _emitFeedback('Profile updated');
      return true;
    } catch (e) {
      debugPrint('SettingsController saveProfile error: $e');
      if (!mounted) return false;
      state = state.copyWith(isSaving: false);
      _emitFeedback('Could not save profile', isError: true);
      return false;
    }
  }

  // ─── ACCOUNT SECURITY ────────────────────────────────────────────────

  /// Links the current account with Google. Returns true on success.
  ///
  /// Note: this uses FirebaseAuth.linkWithPopup directly because the
  /// AuthController doesn't expose an "account linking" path — it owns
  /// sign-in flows, not account management. If you grow account-management
  /// features later, consider moving this to AuthController.
  Future<bool> linkGoogleAccount() async {
    final user = _currentUser;
    if (user == null) return false;

    try {
      final googleProvider = GoogleAuthProvider();
      await user.linkWithPopup(googleProvider);
      if (!mounted) return true;
      _emitFeedback('Google account linked successfully');
      // Reload to refresh sign-in method display
      await loadAll();
      return true;
    } catch (e) {
      debugPrint('SettingsController linkGoogleAccount error: $e');
      if (!mounted) return false;
      final msg = e.toString().contains('already')
          ? 'This Google account is already linked to another user'
          : 'Failed to link. Please try again.';
      _emitFeedback(msg, isError: true);
      return false;
    }
  }

  // ─── CAREER PROFILES ─────────────────────────────────────────────────

  Future<void> loadAiProfiles() async {
    final uid = _uid;
    if (uid == null) return;

    state = state.copyWith(loadingAiProfiles: true);

    try {
      final snap = await FirebaseService.getAiProfiles(uid);
      if (!mounted) return;

      final profiles = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return AiProfileModel.fromJson(data);
      }).toList();

      // Legacy migration fallback — if no profiles in the collection,
      // try the old default-profile path.
      if (profiles.isEmpty) {
        final legacy = await FirebaseService.getDefaultAiProfile(uid);
        if (legacy != null) profiles.add(legacy);
      }

      if (!mounted) return;
      state = state.copyWith(
        aiProfiles: profiles,
        loadingAiProfiles: false,
      );
    } catch (e) {
      debugPrint('SettingsController loadAiProfiles error: $e');
      if (!mounted) return;
      state = state.copyWith(loadingAiProfiles: false);
    }
  }

  Future<void> setDefaultAiProfile(AiProfileModel profile) async {
    final uid = _uid;
    if (uid == null || profile.id == null) return;

    try {
      await FirebaseService.setDefaultAiProfile(uid, profile.id!);
      await loadAiProfiles();
      _emitFeedback('${profile.name} set as default');
    } catch (e) {
      debugPrint('SettingsController setDefaultAiProfile error: $e');
      _emitFeedback('Could not set default', isError: true);
    }
  }

  Future<void> duplicateAiProfile(AiProfileModel profile) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final data = profile.toJson();
      data.remove('id');
      data['name'] = '${profile.name} (Copy)';
      data['isDefault'] = false;
      await FirebaseService.createAiProfile(uid, data);
      await loadAiProfiles();
      _emitFeedback('Profile duplicated');
    } catch (e) {
      debugPrint('SettingsController duplicateAiProfile error: $e');
      _emitFeedback('Could not duplicate', isError: true);
    }
  }

  Future<void> deleteAiProfile(AiProfileModel profile) async {
    final uid = _uid;
    if (uid == null || profile.id == null) return;

    try {
      await FirebaseService.deleteAiProfile(uid, profile.id!);

      // If the deleted profile was the default, auto-promote another.
      // Single-default invariant rule from Phase D.
      if (profile.isDefault) {
        final remaining = await FirebaseService.getAiProfiles(uid);
        if (remaining.docs.isNotEmpty) {
          await FirebaseService.setDefaultAiProfile(uid, remaining.docs.first.id);
        }
      }

      await loadAiProfiles();
      _emitFeedback('Profile deleted');
    } catch (e) {
      debugPrint('SettingsController deleteAiProfile error: $e');
      _emitFeedback('Could not delete profile', isError: true);
    }
  }

  // ─── CLIENT PROFILES ─────────────────────────────────────────────────

  Future<void> loadClientProfiles() async {
    final uid = _uid;
    if (uid == null) return;

    state = state.copyWith(loadingClientProfiles: true);

    try {
      final snap = await FirebaseService.getClientProfiles(uid);
      if (!mounted) return;

      final profiles = snap.docs
          .map((doc) => ClientProfileModel.fromJson(
        doc.id,
        doc.data() as Map<String, dynamic>,
      ))
          .toList();

      state = state.copyWith(
        clientProfiles: profiles,
        loadingClientProfiles: false,
      );
    } catch (e) {
      debugPrint('SettingsController loadClientProfiles error: $e');
      if (!mounted) return;
      state = state.copyWith(loadingClientProfiles: false);
    }
  }

  /// Saves a client — creates or updates depending on whether [existing]
  /// has an id. Pass the model returned from the wizard.
  Future<void> saveClientProfile({
    required ClientProfileModel client,
    ClientProfileModel? existing,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final data = client.toJson()..remove('id');
      if (existing?.id != null) {
        await FirebaseService.updateClientProfile(uid, existing!.id!, data);
        _emitFeedback('Client updated');
      } else {
        await FirebaseService.createClientProfile(uid, data);
        _emitFeedback('Client added');
      }
      await loadClientProfiles();
    } catch (e) {
      debugPrint('SettingsController saveClientProfile error: $e');
      _emitFeedback('Could not save client', isError: true);
    }
  }

  Future<void> duplicateClientProfile(ClientProfileModel client) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final data = client.toJson();
      data.remove('id');
      data['clientName'] = '${client.clientName} (Copy)';
      await FirebaseService.createClientProfile(uid, data);
      await loadClientProfiles();
      _emitFeedback('Client duplicated');
    } catch (e) {
      debugPrint('SettingsController duplicateClientProfile error: $e');
      _emitFeedback('Could not duplicate', isError: true);
    }
  }

  Future<void> deleteClientProfile(ClientProfileModel client) async {
    final uid = _uid;
    if (uid == null || client.id == null) return;

    try {
      await FirebaseService.deleteClientProfile(uid, client.id!);
      await loadClientProfiles();
      _emitFeedback('Client deleted');
    } catch (e) {
      debugPrint('SettingsController deleteClientProfile error: $e');
      _emitFeedback('Could not delete client', isError: true);
    }
  }
}

// ─── PROVIDER ─────────────────────────────────────────────────────────

final settingsControllerProvider =
StateNotifierProvider<SettingsController, SettingsState>(
      (ref) => SettingsController(),
);