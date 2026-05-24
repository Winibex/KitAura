// lib/shared/services/claude_service.dart
//
// Thin client over KitAura Cloud Functions.
// API key lives ONLY on the server. Token tracking happens server-side.
//
// aiFillSection → returns structured text (heading + entries)
// spellcheckCV  → returns corrections + activityId

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
  }) async {
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
      if (content == null) return null;
      return Map<String, dynamic>.from(content as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('aiFill error: ${e.code} ${e.message}');
      throw _mapError(e);
    } catch (e) {
      debugPrint('aiFill unexpected: $e');
      throw 'AI generation failed. Please try again.';
    }
  }

  /// Spellcheck — returns corrections + activityId for updating accepted/dismissed.
  static Future<SpellcheckResult> spellcheckCV(
      Map<String, String> sections, {
        String tool = 'cv',
        String? documentId,
        String? documentTitle,
      }) async {
    if (sections.isEmpty) return const SpellcheckResult(corrections: []);
    try {
      final result = await _fn.httpsCallable('spellcheck').call<Map<String, dynamic>>({
        'sections': sections,
        'tool': tool,
        'documentId': documentId,
        'documentTitle': documentTitle,
      });
      final list = result.data['corrections'] as List<dynamic>? ?? [];
      final activityId = result.data['activityId'] as String?;
      return SpellcheckResult(
        corrections: list
            .map((e) => SpellCorrection.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((c) => c.wrong.isNotEmpty && c.correct.isNotEmpty)
            .toList(),
        activityId: activityId,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('spellcheck error: ${e.code} ${e.message}');
      throw _mapError(e);
    } catch (e) {
      debugPrint('spellcheck unexpected: $e');
      throw 'Spellcheck failed. Please try again.';
    }
  }

  static String _mapError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated': return 'Please sign in to use AI features.';
      case 'resource-exhausted': return e.message ?? 'Usage limit reached. Upgrade to Pro.';
      case 'not-found': return 'Account setup incomplete. Please sign out and back in.';
      case 'deadline-exceeded': return 'Request timed out. Please try again.';
      default: return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}