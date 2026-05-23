// lib/shared/services/claude_service.dart
//
// Thin client over the KitAura Cloud Functions proxy.
// The Anthropic API key lives ONLY on the server — never in this app.
//
// Two calls:
//   - aiFillSection() → returns Quill Delta ops (List) for a CV section
//   - spellcheckCV()  → returns List<SpellCorrection>
//
// PUBSPEC: cloud_functions: ^5.x  (matches your firebase_core 4.x)

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

  factory SpellCorrection.fromJson(Map<String, dynamic> json) {
    return SpellCorrection(
      sectionTitle: json['section'] as String? ?? '',
      wrong: json['wrong'] as String? ?? '',
      correct: json['correct'] as String? ?? '',
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─── SERVICE ─────────────────────────────────────────────────────────────

class ClaudeService {
  ClaudeService._();

  static final FirebaseFunctions _functions =
  FirebaseFunctions.instanceFor(region: 'us-central1');

  /// AI Fill — generate polished Quill Delta ops for a CV section.
  ///
  /// [sectionType] is the SectionType.key (e.g. "experience").
  /// [profile] is the AiProfileModel.toJson() map.
  /// Returns a list of Quill delta op maps ready for Document.fromJson().
  static Future<List<Map<String, dynamic>>> aiFillSection({
    required String sectionType,
    required String tone,
    required String experienceLevel,
    required Map<String, dynamic> profile,
  }) async {
    try {
      final callable = _functions.httpsCallable('aiFill');
      final result = await callable.call<Map<String, dynamic>>({
        'sectionType': sectionType,
        'tone': tone,
        'experienceLevel': experienceLevel,
        'profile': profile,
      });

      final data = result.data;
      final delta = data['delta'] as List<dynamic>? ?? [];
      return delta
          .map((op) => Map<String, dynamic>.from(op as Map))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('aiFill error: ${e.code} ${e.message}');
      throw _mapFunctionsError(e);
    } catch (e) {
      debugPrint('aiFill unexpected: $e');
      throw 'AI generation failed. Please try again.';
    }
  }

  /// Spellcheck — returns corrections across all sections.
  ///
  /// [sections] is a map of { sectionTitle: plainText }.
  static Future<List<SpellCorrection>> spellcheckCV(
      Map<String, String> sections,
      ) async {
    if (sections.isEmpty) return [];

    try {
      final callable = _functions.httpsCallable('spellcheck');
      final result = await callable.call<Map<String, dynamic>>({
        'sections': sections,
      });

      final list = result.data['corrections'] as List<dynamic>? ?? [];
      return list
          .map((e) => SpellCorrection.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((c) => c.wrong.isNotEmpty && c.correct.isNotEmpty)
          .toList();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('spellcheck error: ${e.code} ${e.message}');
      throw _mapFunctionsError(e);
    } catch (e) {
      debugPrint('spellcheck unexpected: $e');
      throw 'Spellcheck failed. Please try again.';
    }
  }

  // ── Error mapping ────────────────────────────────────────────────────

  static String _mapFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Please sign in to use AI features.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a moment.';
      case 'deadline-exceeded':
        return 'Request timed out. Please try again.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}