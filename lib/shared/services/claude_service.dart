// lib/shared/services/claude_service.dart
//
// Anthropic Messages API — streaming + single-shot + AI spellcheck.

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─── CONFIG ──────────────────────────────────────────────────────────────

class ClaudeConfig {
  ClaudeConfig._();

  static const String apiUrl = 'https://api.anthropic.com/v1/messages';
  static const String model = 'claude-sonnet-4-20250514';
  static const String apiVersion = '2023-06-01';
  static const int maxTokens = 1024;

  /// Loaded from --dart-define=ANTHROPIC_KEY=sk-ant-xxx
  static String get apiKey => dotenv.env['ANTHROPIC_KEY'] ?? '';
}

// ─── RESPONSE TYPES ──────────────────────────────────────────────────────

class ClaudeStreamEvent {
  final String text;
  final bool isDone;
  final String? error;

  const ClaudeStreamEvent({
    this.text = '',
    this.isDone = false,
    this.error,
  });
}

// ─── SPELLCHECK MODEL ───────────────────────────────────────────────────

class SpellCorrection {
  final String sectionTitle;
  final String wrong;
  final String correct;
  final int offset; // char offset within that section's plain text

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
      offset: json['offset'] as int? ?? 0,
    );
  }
}

// ─── SERVICE ─────────────────────────────────────────────────────────────

class ClaudeService {
  ClaudeService._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
  ));

  // ── STREAMING (for AI Fill) ───────────────────────────────────────

  static Stream<ClaudeStreamEvent> streamMessage(
      String prompt, {
        String? systemPrompt,
        CancelToken? cancelToken,
      }) async* {
    if (ClaudeConfig.apiKey.isEmpty) {
      yield const ClaudeStreamEvent(
        error: 'API key not configured. Run with --dart-define=ANTHROPIC_KEY=sk-ant-xxx',
        isDone: true,
      );
      return;
    }

    try {
      final response = await _dio.post<ResponseBody>(
        ClaudeConfig.apiUrl,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ClaudeConfig.apiKey,
            'anthropic-version': ClaudeConfig.apiVersion,
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          responseType: ResponseType.stream,
        ),
        data: jsonEncode({
          'model': ClaudeConfig.model,
          'max_tokens': ClaudeConfig.maxTokens,
          'stream': true,
          'system': ?systemPrompt,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      String buffer = '';

      await for (final chunk in response.data!.stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);

        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);

          if (line.isEmpty || !line.startsWith('data:')) continue;

          final jsonStr = line.substring(5).trim();
          if (jsonStr == '[DONE]') {
            yield const ClaudeStreamEvent(isDone: true);
            return;
          }

          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = json['type'] as String?;

            if (type == 'content_block_delta') {
              final delta = json['delta'] as Map<String, dynamic>?;
              if (delta != null && delta['type'] == 'text_delta') {
                final text = delta['text'] as String? ?? '';
                if (text.isNotEmpty) {
                  yield ClaudeStreamEvent(text: text);
                }
              }
            } else if (type == 'message_stop') {
              yield const ClaudeStreamEvent(isDone: true);
              return;
            } else if (type == 'error') {
              final error = json['error'] as Map<String, dynamic>?;
              yield ClaudeStreamEvent(
                error: error?['message'] as String? ?? 'Unknown API error',
                isDone: true,
              );
              return;
            }
          } catch (_) {}
        }
      }

      yield const ClaudeStreamEvent(isDone: true);
    } on DioException catch (e) {
      yield ClaudeStreamEvent(error: _mapDioError(e), isDone: true);
    } catch (e) {
      debugPrint('ClaudeService error: $e');
      yield ClaudeStreamEvent(
        error: 'Something went wrong. Please try again.',
        isDone: true,
      );
    }
  }

  // ── SINGLE SHOT (for short tasks) ─────────────────────────────────

  static Future<String> sendMessage(
      String prompt, {
        String? systemPrompt,
        int maxTokens = 256,
      }) async {
    if (ClaudeConfig.apiKey.isEmpty) {
      throw Exception('API key not configured');
    }

    final response = await _dio.post<Map<String, dynamic>>(
      ClaudeConfig.apiUrl,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ClaudeConfig.apiKey,
          'anthropic-version': ClaudeConfig.apiVersion,
          'anthropic-dangerous-direct-browser-access': 'true',
        },
      ),
      data: jsonEncode({
        'model': ClaudeConfig.model,
        'max_tokens': maxTokens,
        'system': ?systemPrompt,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );

    final content = response.data?['content'] as List?;
    if (content != null && content.isNotEmpty) {
      return content.first['text'] as String? ?? '';
    }
    return '';
  }

  // ── AI SPELLCHECK ─────────────────────────────────────────────────

  /// Sends all text sections to Claude for spellcheck.
  /// Returns a list of corrections with section names, wrong words, and fixes.
  ///
  /// [sections] is a map of { sectionTitle: plainText }
  static Future<List<SpellCorrection>> spellcheckCV(
      Map<String, String> sections,
      ) async {
    if (ClaudeConfig.apiKey.isEmpty) {
      throw Exception('API key not configured');
    }

    if (sections.isEmpty) return [];

    // Build the content block for Claude
    final sectionsText = sections.entries
        .map((e) => '--- ${e.key} ---\n${e.value}')
        .join('\n\n');

    const systemPrompt = '''You are a spelling and grammar checker for a CV/resume.
Check ONLY for spelling mistakes — do NOT change meaning, tone, or style.
Skip proper nouns, company names, and technical terms.

Return ONLY a JSON array. Each element has:
- "section": the section title exactly as given
- "wrong": the misspelled word exactly as it appears
- "correct": the corrected spelling
- "offset": character position of the wrong word within that section's text (0-indexed)

If there are no spelling errors, return an empty array: []

Return ONLY the JSON array, no markdown, no explanation.''';

    final prompt = 'Check this CV for spelling errors:\n\n$sectionsText';

    try {
      final response = await sendMessage(
        prompt,
        systemPrompt: systemPrompt,
        maxTokens: 1024,
      );

      // Parse JSON response
      final cleaned = response
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final list = jsonDecode(cleaned) as List<dynamic>;
      return list
          .map((e) => SpellCorrection.fromJson(e as Map<String, dynamic>))
          .where((c) => c.wrong.isNotEmpty && c.correct.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Spellcheck error: $e');
      rethrow;
    }
  }

  // ── Error mapping ────────────────────────────────────────────────────

  static String _mapDioError(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return 'AI generation was cancelled.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Please check your internet and try again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No internet connection. Please check your network.';
    }

    final statusCode = e.response?.statusCode;
    switch (statusCode) {
      case 400: return 'Invalid request. Please try again.';
      case 401: return 'Invalid API key. Please check configuration.';
      case 403: return 'API access denied. Please check your API key permissions.';
      case 429: return 'Too many requests. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503: return 'AI service is temporarily unavailable. Please try again shortly.';
      case 529: return 'AI service is overloaded. Please try again in a moment.';
      default: return 'AI request failed (${statusCode ?? 'unknown'}). Please try again.';
    }
  }
}