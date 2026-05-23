// lib/features/cv/controller/claude_controller.dart
//
// Riverpod controller for AI Fill on canvas text sections.
//
// FLOW:
//   1. User clicks "AI Fill" on a textSection
//   2. Paywall check (aiUsageCount < 10 for free)
//   3. Load AI profile from Firestore (cached)
//   4. Call Cloud Function → returns Quill Delta JSON (formatted)
//   5. REPLACE the section's document with that delta (clean, formatted)
//   6. Track usage
//
// No streaming — the function returns a complete, formatted delta which we
// apply as a whole document. This fixes the unformatted/overflow/duplicate bugs.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/section_type.dart';
import '../../../shared/models/subscription_model.dart';
import '../../../shared/services/claude_service.dart';
import '../../../shared/services/firebase_service.dart';

// ─── STATE ───────────────────────────────────────────────────────────────

enum AiFillStatus { idle, loading, done, error, paywalled }

class ClaudeState {
  final AiFillStatus status;
  final String? activeItemId;
  final String? error;
  final int streamedChars;

  const ClaudeState({
    this.status = AiFillStatus.idle,
    this.activeItemId,
    this.error,
    this.streamedChars = 0,
  });

  bool get isActive => status == AiFillStatus.loading;

  ClaudeState copyWith({
    AiFillStatus? status,
    String? activeItemId,
    String? error,
    int? streamedChars,
  }) {
    return ClaudeState(
      status: status ?? this.status,
      activeItemId: activeItemId ?? this.activeItemId,
      error: error,
      streamedChars: streamedChars ?? this.streamedChars,
    );
  }
}

// ─── CONTROLLER ──────────────────────────────────────────────────────────

class ClaudeController extends StateNotifier<ClaudeState> {
  ClaudeController() : super(const ClaudeState());

  AiProfileModel? _cachedProfile;
  SubscriptionModel? _cachedSubscription;

  /// Fill a text section with AI-generated, formatted content.
  Future<void> fillSection({
    required String itemId,
    required SectionType sectionType,
    required String sectionTitle,
    required QuillController controller,
    String? cvId,
  }) async {
    if (state.isActive) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'Please sign in to use AI generation.',
      );
      return;
    }

    state = ClaudeState(status: AiFillStatus.loading, activeItemId: itemId);

    // ── Paywall check ────────────────────────────────────────────────
    try {
      _cachedSubscription ??= await _loadSubscription(uid);
      if (_cachedSubscription != null && !_cachedSubscription!.canUseAI) {
        state = ClaudeState(
          status: AiFillStatus.paywalled,
          activeItemId: itemId,
          error:
          "You've used all 10 free AI fills this month. Upgrade to Pro for unlimited.",
        );
        return;
      }
    } catch (e) {
      debugPrint('Subscription check failed: $e');
    }

    // ── Load AI profile ──────────────────────────────────────────────
    try {
      _cachedProfile ??= await _loadAiProfile(uid);
    } catch (e) {
      debugPrint('AI profile load failed: $e');
    }
    final profile = _cachedProfile ?? const AiProfileModel();

    // ── Call Cloud Function → get formatted Quill Delta ──────────────
    try {
      final delta = await ClaudeService.aiFillSection(
        sectionType: sectionType.key,
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
      );

      if (!mounted) return;

      if (delta.isEmpty) {
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: itemId,
          error: 'AI returned no content. Add more profile data and retry.',
        );
        return;
      }

      // REPLACE the whole document with the formatted delta.
      try {
        controller.document = Document.fromJson(delta);
      } catch (e) {
        debugPrint('Delta apply failed: $e');
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: itemId,
          error: 'Could not apply AI content. Please try again.',
        );
        return;
      }

      // Count chars for the toast
      final chars = controller.document.toPlainText().length;
      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: itemId,
        streamedChars: chars,
      );

      // Fire-and-forget usage tracking
      try {
        FirebaseService.trackAiFill(uid, cvId ?? 'current', sectionTitle);
      } catch (_) {}
      _cachedSubscription = null; // re-check next time
    } catch (e) {
      if (!mounted) return;
      state = ClaudeState(
        status: AiFillStatus.error,
        activeItemId: itemId,
        error: e.toString(),
      );
    }
  }

  void cancel() {
    // Non-streaming now — just reset state.
    state = const ClaudeState();
  }

  void reset() => state = const ClaudeState();
  void invalidateProfile() => _cachedProfile = null;
  void invalidateSubscription() => _cachedSubscription = null;

  Future<AiProfileModel?> _loadAiProfile(String uid) async {
    final doc = await FirebaseService.getAiProfile(uid);
    if (doc.exists) {
      return AiProfileModel.fromJson(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  Future<SubscriptionModel?> _loadSubscription(String uid) async {
    final doc = await FirebaseService.getSubscription(uid);
    if (doc.exists) {
      return SubscriptionModel.fromJson(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  /// Cloud Functions callables only accept JSON primitives. Strip out
  /// Firestore types (Timestamp) and anything non-serializable.
  Map<String, dynamic> _sanitizeProfile(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    // updatedAt is a Firestore Timestamp — the function doesn't need it
    clean.remove('updatedAt');
    return clean;
  }
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final claudeControllerProvider =
StateNotifierProvider.autoDispose<ClaudeController, ClaudeState>(
      (ref) => ClaudeController(),
);