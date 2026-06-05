// lib/shared/services/claude_service.dart
//
// Thin client over KitAura Cloud Functions.
// API key lives ONLY on the server. Token tracking happens server-side.
//
// CHANGES FROM PREVIOUS VERSION:
//   1. Added aiRewriteSection() method for AI Rewrite feature
//   2. Debug prints on all methods

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// ─── MODELS ──────────────────────────────────────────────────────────────

class SpellCorrection {
  final String sectionTitle;
  final String wrong;
  final String correct;
  final int offset;

  const SpellCorrection({
    required this.sectionTitle,
    required this.wrong,
    required this.correct,
    required this.offset,
  });

  factory SpellCorrection.fromJson(Map<String, dynamic> json) => SpellCorrection(
    sectionTitle: json['section'] as String? ?? '',
    wrong: json['wrong'] as String? ?? '',
    correct: json['correct'] as String? ?? '',
    offset: (json['offset'] as num?)?.toInt() ?? 0,
  );
}

class SpellcheckResult {
  final List<SpellCorrection> corrections;
  final String? activityId;

  const SpellcheckResult({required this.corrections, this.activityId});
}

// ─── SERVICE ─────────────────────────────────────────────────────────────

class ClaudeService {
  ClaudeService._();

  static final FirebaseFunctions _fn =
  FirebaseFunctions.instanceFor(region: 'us-central1');

  /// AI Fill — returns structured text for a CV/CL/proposal section.
  ///
  /// All tracking (tokens, cost, counters) happens server-side.
  /// Frontend only receives the content.
  static Future<Map<String, dynamic>?> aiFillSection({
    required String sectionType,
    required String tone,
    required String experienceLevel,
    required Map<String, dynamic> profile,
    String tool = 'cv',
    String? documentId,
    String? documentTitle,
    String? templateId,
    String? sectionTitle,
    String beforeText = '',
  }) async
  {
    debugPrint('🤖 [ClaudeService] aiFillSection(section=$sectionType, tone=$tone)');
    try {
      final result = await _fn.httpsCallable('aiFill').call<Map<String, dynamic>>({
        'sectionType': sectionType,
        'tone': tone,
        'experienceLevel': experienceLevel,
        'profile': profile,
        'tool': tool,
        'documentId': documentId,
        'documentTitle': documentTitle,
        'templateId': templateId,
        'sectionTitle': sectionTitle,
        'beforeText': beforeText,
      });
      final content = result.data['content'];
      if (content == null) {
        debugPrint('🤖 [ClaudeService] aiFillSection returned null content');
        return null;
      }
      debugPrint('🤖 [ClaudeService] aiFillSection OK');
      return Map<String, dynamic>.from(content as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('🤖 [ClaudeService] aiFillSection FAILED: ${e.code} ${e.message}');
      throw _mapError(e);
    } catch (e) {
      debugPrint('🤖 [ClaudeService] aiFillSection unexpected: $e');
      throw 'AI generation failed. Please try again.';
    }
  }

  /// AI Rewrite — rewrites existing text with a specified mode/tone.
  ///
  /// [text] — the current plain text content to rewrite
  /// [sectionType] — which CV section (experience, summary, etc.)
  /// [mode] — professional, concise, detailed, creative
  /// [customInstruction] — optional user instruction for how to rewrite
  ///
  /// Returns the rewritten text as a plain string.
  /// All tracking (tokens, cost, counters) happens server-side.
  static Future<String?> aiRewriteSection({
    required String text,
    required String sectionType,
    required String mode,
    String? customInstruction,
    String tool = 'cv',
    String? documentId,
    String? documentTitle,
    String? templateId,
  }) async
  {
    debugPrint('🤖 [ClaudeService] aiRewriteSection(section=$sectionType, mode=$mode)');
    try {
      final result = await _fn.httpsCallable('aiRewrite').call<Map<String, dynamic>>({
        'text': text,
        'sectionType': sectionType,
        'mode': mode,
        'customInstruction': customInstruction,
        'tool': tool,
        'documentId': documentId,
        'documentTitle': documentTitle,
        'templateId': templateId,
      });
      final content = result.data['content'] as String?;
      debugPrint('🤖 [ClaudeService] aiRewriteSection OK (${content?.length ?? 0} chars)');
      return content;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('🤖 [ClaudeService] aiRewriteSection FAILED: ${e.code} ${e.message}');
      throw _mapError(e);
    } catch (e) {
      debugPrint('🤖 [ClaudeService] aiRewriteSection unexpected: $e');
      throw 'AI rewrite failed. Please try again.';
    }
  }

  /// Spellcheck — returns corrections + activityId for updating accepted/dismissed.
  static Future<SpellcheckResult> spellcheckCV(
      Map<String, String> sections, {
        String tool = 'cv',
        String? documentId,
        String? documentTitle,
      }) async
  {
    if (sections.isEmpty) return const SpellcheckResult(corrections: []);
    debugPrint('🤖 [ClaudeService] spellcheckCV(${sections.length} sections)');
    try {
      final result = await _fn.httpsCallable('spellcheck').call<Map<String, dynamic>>({
        'sections': sections,
        'tool': tool,
        'documentId': documentId,
        'documentTitle': documentTitle,
      });
      final list = result.data['corrections'] as List<dynamic>? ?? [];
      final activityId = result.data['activityId'] as String?;
      debugPrint('🤖 [ClaudeService] spellcheckCV OK (${list.length} corrections)');
      return SpellcheckResult(
        corrections: list
            .map((e) => SpellCorrection.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((c) => c.wrong.isNotEmpty && c.correct.isNotEmpty)
            .toList(),
        activityId: activityId,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('🤖 [ClaudeService] spellcheckCV FAILED: ${e.code} ${e.message}');
      throw _mapError(e);
    } catch (e) {
      debugPrint('🤖 [ClaudeService] spellcheckCV unexpected: $e');
      throw 'Spellcheck failed. Please try again.';
    }
  }

  static Future<void> updateSpellcheckResult({
    required String activityId,
    required List<Map<String, dynamic>> corrections,
  }) async
  {
    try {
      await _fn.httpsCallable('updateSpellcheckResult').call({
        'activityId': activityId,
        'corrections': corrections,
      });
      debugPrint('🤖 [ClaudeService] updateSpellcheckResult OK');
    } catch (e) {
      // Non-critical — UI already updated, tracking is best-effort
      debugPrint('🤖 [ClaudeService] updateSpellcheckResult failed: $e');
    }
  }

  static String _mapError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Please sign in to use AI features.';
      case 'resource-exhausted':
        return e.message ?? 'Usage limit reached. Upgrade to Pro.';
      case 'not-found':
        return 'Account setup incomplete. Please sign out and back in.';
      case 'deadline-exceeded':
        return 'Request timed out. Please try again.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  /// Tracks an export server-side (increments counter + paywall check).
  /// Call BEFORE generating the PDF. Throws if over limit.
  static Future<void> trackExport({
    required String tool,
    String? documentId,
    String? documentTitle,
  }) async
  {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('trackExport')
        .call({
      'tool': tool,
      'documentId': documentId,
      'documentTitle': documentTitle,
    });
  }

  /// Tracks a login server-side.
  /// Updates analytics/summary.loginCount + monthly.logins.
  /// Call this AFTER every successful sign-in.
  static Future<void> trackLogin() async {
    try {
      await _fn.httpsCallable('trackLogin').call();
      debugPrint('🤖 [ClaudeService] trackLogin OK');
    } catch (e) {
      // Don't block sign-in flow if tracking fails
      debugPrint('🤖 [ClaudeService] trackLogin failed (non-critical): $e');
    }
  }

  /// Tracks document creation server-side.
  /// Increments subscription.{tool}Count + analytics totals + writes transaction.
  /// Call AFTER createCV/createCoverLetter/createProposal succeeds.
  ///
  /// [tool] must be one of: 'cv' | 'coverLetter' | 'proposal'
  static Future<void> trackDocCreated({
    required String tool,
    required String documentId,
    String? documentTitle,
  }) async
  {
    try {
      await _fn.httpsCallable('trackDocCreated').call({
        'tool': tool,
        'documentId': documentId,
        'documentTitle': documentTitle,
      });
      debugPrint('🤖 [ClaudeService] trackDocCreated OK (tool=$tool)');
    } catch (e) {
      debugPrint('🤖 [ClaudeService] trackDocCreated failed (non-critical): $e');
    }
  }

  /// Tracks document deletion server-side.
  /// Decrements subscription.{tool}Count + writes transaction.
  /// Call AFTER deleteCV/deleteCoverLetter/deleteProposal succeeds.
  ///
  /// [tool] must be one of: 'cv' | 'coverLetter' | 'proposal'
  static Future<void> trackDocDeleted({
    required String tool,
    required String documentId,
    String? documentTitle,
  }) async
  {
    try {
      await _fn.httpsCallable('trackDocDeleted').call({
        'tool': tool,
        'documentId': documentId,
        'documentTitle': documentTitle,
      });
      debugPrint('🤖 [ClaudeService] trackDocDeleted OK (tool=$tool)');
    } catch (e) {
      debugPrint('🤖 [ClaudeService] trackDocDeleted failed (non-critical): $e');
    }
  }

  /// Activates a 7-day free trial for the current user.
  /// Cloud Function checks if trial was already used.
  ///
  /// Returns a map with: success, plan, trialEndDate, daysRemaining
  /// Throws if trial already used or user is already Pro.
  static Future<Map<String, dynamic>> activateTrial() async {
    debugPrint('🤖 [ClaudeService] activateTrial');
    try {
      final result = await _fn.httpsCallable('activateTrial').call();
      final data = Map<String, dynamic>.from(result.data as Map);
      debugPrint('🤖 [ClaudeService] activateTrial OK — plan: ${data['plan']}');
      return data;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('🤖 [ClaudeService] activateTrial FAILED: ${e.code} ${e.message}');
      throw _mapError(e);
    } catch (e) {
      debugPrint('🤖 [ClaudeService] activateTrial unexpected: $e');
      throw 'Failed to activate trial. Please try again.';
    }
  }

}