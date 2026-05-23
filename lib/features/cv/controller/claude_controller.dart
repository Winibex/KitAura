// lib/features/cv/controller/claude_controller.dart
//
// Riverpod controller for AI text generation in the canvas cv.
//
// FLOW:
//   1. User clicks "AI Fill" on a textSection canvas item
//   2. Controller checks paywall (aiUsageCount < 10 for free plan)
//   3. Loads AI profile from Firestore (cached after first load)
//   4. Builds prompt based on the section's title (matchSection)
//   5. Streams Claude response → inserts into QuillController live
//   6. Increments aiUsageCount in Firestore on success

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/subscription_model.dart';
import '../../../shared/services/claude_service.dart';
import '../../../shared/services/ai_prompts.dart';
import '../../../shared/services/firebase_service.dart';

// ─── STATE ───────────────────────────────────────────────────────────────

enum AiFillStatus { idle, loading, streaming, done, error, paywalled }

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

  bool get isActive =>
      status == AiFillStatus.loading || status == AiFillStatus.streaming;

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

  CancelToken? _cancelToken;
  AiProfileModel? _cachedProfile;
  SubscriptionModel? _cachedSubscription;

  /// Fills a text section with AI-generated content.
  Future<void> fillSection({
    required String itemId,
    required String sectionTitle,
    required QuillController controller,
    bool clearExisting = true,
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
          'You\'ve used all 10 free AI fills this month. Upgrade to Pro for unlimited.',
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

    // ── Build prompt ─────────────────────────────────────────────────

    final userPrompt = AiPrompts.matchSection(
      sectionTitle: sectionTitle,
      jobTitle: profile.jobTitle ?? profile.fullName,
      experienceLevel: profile.experienceLevel,
      tone: profile.tone,
      skills: profile.skills,
      industry: profile.industry.isNotEmpty ? profile.industry : null,
      experiences: profile.experiences.map((e) => e.toJson()).toList(),
      education: profile.education.map((e) => e.toJson()).toList(),
      certifications: profile.certifications,
      languages: profile.languages.map((e) => e.toJson()).toList(),
      fullName: profile.fullName,
      email: profile.email,
      phone: profile.phone,
      location: profile.location,
      linkedIn: profile.linkedIn,
      website: profile.website,
    );

    final systemPrompt = AiPrompts.system(
      tone: profile.tone,
      experienceLevel: profile.experienceLevel,
    );

    // ── Clear existing content ───────────────────────────────────────

    if (clearExisting) {
      final length = controller.document.length;
      if (length > 1) {
        controller.replaceText(0, length - 1, '', null);
      }
    }

    // ── Stream into QuillController ──────────────────────────────────

    _cancelToken = CancelToken();
    state = state.copyWith(status: AiFillStatus.streaming, streamedChars: 0);

    int insertOffset = clearExisting ? 0 : controller.document.length - 1;
    int totalChars = 0;
    bool hadError = false;

    try {
      await for (final event in ClaudeService.streamMessage(
        userPrompt,
        systemPrompt: systemPrompt,
        cancelToken: _cancelToken,
      )) {
        if (!mounted) return;

        if (event.error != null) {
          state = ClaudeState(
            status: AiFillStatus.error,
            activeItemId: itemId,
            error: event.error,
          );
          hadError = true;
          break;
        }

        if (event.isDone) break;

        if (event.text.isNotEmpty) {
          controller.document.insert(insertOffset, event.text);
          insertOffset += event.text.length;
          totalChars += event.text.length;
          state = state.copyWith(streamedChars: totalChars);
        }
      }
    } catch (e) {
      if (e is! DioException || e.type != DioExceptionType.cancel) {
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: itemId,
          error: 'AI generation failed. Please try again.',
        );
        hadError = true;
      }
    }

    _cancelToken = null;

    // ── Track usage ──────────────────────────────────────────────────

    if (!hadError && totalChars > 0 && state.status != AiFillStatus.error) {
      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: itemId,
        streamedChars: totalChars,
      );

      // Fire-and-forget
      try {
        FirebaseService.trackAiFill(uid, cvId ?? 'current', sectionTitle);
      } catch (_) {}

      _cachedSubscription = null; // re-check next time
    }
  }

  void cancel() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
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

  @override
  void dispose() {
    _cancelToken?.cancel('Controller disposed');
    super.dispose();
  }
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final claudeControllerProvider =
StateNotifierProvider.autoDispose<ClaudeController, ClaudeState>(
      (ref) => ClaudeController(),
);