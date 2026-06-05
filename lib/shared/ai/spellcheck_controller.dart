// lib/features/cv/controller/spellcheck_controller.dart
//
// AI-powered spellcheck: collects all text sections, sends to Claude,
// shows corrections, user can fix individually or fix all at once.
//
// CHANGES FROM PREVIOUS VERSION:
//   1. Stores activityId returned from spellcheckCV()
//   2. Tracks accepted/dismissed actions per correction
//   3. Pushes final tracking to Cloud Function (updateSpellcheckResult)

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'claude_service.dart';
import '../models/canvas_item.dart';

// ─── STATE ───────────────────────────────────────────────────────────────

enum SpellcheckStatus { idle, checking, done, error }

class SpellcheckState {
  final SpellcheckStatus status;
  final List<SpellCorrection> corrections;
  final String? error;
  final String? activityId; // Cloud Function activity ID for tracking

  const SpellcheckState({
    this.status = SpellcheckStatus.idle,
    this.corrections = const [],
    this.error,
    this.activityId,
  });

  SpellcheckState copyWith({
    SpellcheckStatus? status,
    List<SpellCorrection>? corrections,
    String? error,
    String? activityId,
  }) {
    return SpellcheckState(
      status: status ?? this.status,
      corrections: corrections ?? this.corrections,
      error: error,
      activityId: activityId ?? this.activityId,
    );
  }

  bool get isChecking => status == SpellcheckStatus.checking;
  bool get hasCorrections => corrections.isNotEmpty;
  int get count => corrections.length;
}

// ─── CONTROLLER ──────────────────────────────────────────────────────────

class SpellcheckController extends StateNotifier<SpellcheckState> {
  SpellcheckController() : super(const SpellcheckState());

  /// Tracks the user action for each correction.
  /// Key = unique identifier ('section|wrong|offset'), value = 'accepted' | 'dismissed' | 'pending'.
  /// Persists even after correction is removed from state.corrections list.
  final Map<String, _TrackedCorrection> _tracked = {};

  /// Build a unique key for a correction so we can track it across removals.
  String _keyFor(SpellCorrection c) => '${c.sectionTitle}|${c.wrong}|${c.offset}';

  /// Run AI spellcheck on all text sections.
  /// [items] should be the canvas items list from CanvasController.
  Future<void> checkAll(List<CanvasItem> items) async {
    // Collect text from all text sections
    final sections = <String, String>{};
    for (final item in items) {
      if (!item.isText || item.controller == null) continue;
      final text = item.controller!.document.toPlainText().trim();
      if (text.isNotEmpty && text.length > 1) {
        sections[item.title] = text;
      }
    }

    if (sections.isEmpty) {
      state = state.copyWith(
        status: SpellcheckStatus.done,
        corrections: [],
        error: null,
      );
      return;
    }

    // Reset tracking from any previous check
    _tracked.clear();

    state = state.copyWith(status: SpellcheckStatus.checking, error: null);

    try {
      final result = await ClaudeService.spellcheckCV(sections);

      // Seed tracking with 'pending' for every correction
      for (final c in result.corrections) {
        _tracked[_keyFor(c)] = _TrackedCorrection(correction: c, action: 'pending');
      }

      state = state.copyWith(
        status: SpellcheckStatus.done,
        corrections: result.corrections,
        activityId: result.activityId,
      );
    } catch (e) {
      state = state.copyWith(
        status: SpellcheckStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Fix a single correction in the Quill controller.
  void fixOne(SpellCorrection correction, List<CanvasItem> items) {
    final item = items.where((i) =>
    i.isText && i.title == correction.sectionTitle).firstOrNull;
    if (item == null || item.controller == null) return;

    final controller = item.controller!;
    final plainText = controller.document.toPlainText();

    // Find the word at the given offset (or search for it nearby)
    int offset = correction.offset;
    final wrongWord = correction.wrong;

    // Verify the word is at the expected offset
    if (offset >= 0 &&
        offset + wrongWord.length <= plainText.length &&
        plainText.substring(offset, offset + wrongWord.length) == wrongWord) {
      // Perfect match at offset
      controller.replaceText(offset, wrongWord.length, correction.correct, null);
    } else {
      // Offset might be wrong — search for the word in the section
      final idx = plainText.indexOf(wrongWord);
      if (idx >= 0) {
        controller.replaceText(idx, wrongWord.length, correction.correct, null);
      }
    }

    // Mark as accepted in tracking map
    _markAction(correction, 'accepted');

    // Remove this correction from the list
    final updated = state.corrections.where((c) => c != correction).toList();
    state = state.copyWith(corrections: updated);

    // Push tracking to server (fire-and-forget)
    _pushTrackingToServer();
  }

  /// Fix all corrections at once, applying from end to start to preserve offsets.
  void fixAll(List<CanvasItem> items) {
    // Group corrections by section
    final grouped = <String, List<SpellCorrection>>{};
    for (final c in state.corrections) {
      grouped.putIfAbsent(c.sectionTitle, () => []).add(c);
    }

    for (final entry in grouped.entries) {
      final item = items.where((i) =>
      i.isText && i.title == entry.key).firstOrNull;
      if (item == null || item.controller == null) continue;

      final controller = item.controller!;

      // Sort corrections by offset descending so we replace from end first
      final sorted = List<SpellCorrection>.from(entry.value)
        ..sort((a, b) => b.offset.compareTo(a.offset));

      for (final correction in sorted) {
        final plainText = controller.document.toPlainText();
        final wrongWord = correction.wrong;
        int offset = correction.offset;

        if (offset >= 0 &&
            offset + wrongWord.length <= plainText.length &&
            plainText.substring(offset, offset + wrongWord.length) == wrongWord) {
          controller.replaceText(offset, wrongWord.length, correction.correct, null);
        } else {
          final idx = plainText.indexOf(wrongWord);
          if (idx >= 0) {
            controller.replaceText(idx, wrongWord.length, correction.correct, null);
          }
        }

        // Mark as accepted
        _markAction(correction, 'accepted');
      }
    }

    state = state.copyWith(corrections: []);
    _pushTrackingToServer();
  }

  /// Dismiss a single correction (ignore it).
  void dismiss(SpellCorrection correction) {
    _markAction(correction, 'dismissed');

    final updated = state.corrections.where((c) => c != correction).toList();
    state = state.copyWith(corrections: updated);

    _pushTrackingToServer();
  }

  /// Reset state. Called when panel closes — pushes final tracking
  /// (any remaining corrections become 'dismissed' implicitly).
  void reset() {
    // Any corrections still in the list when reset is called → user ignored them
    for (final c in state.corrections) {
      _markAction(c, 'dismissed');
    }
    _pushTrackingToServer();

    state = const SpellcheckState();
    _tracked.clear();
  }

  // ─── PRIVATE TRACKING HELPERS ────────────────────────────────────────

  void _markAction(SpellCorrection correction, String action) {
    final key = _keyFor(correction);
    final existing = _tracked[key];
    if (existing != null) {
      _tracked[key] = _TrackedCorrection(correction: existing.correction, action: action);
    }
  }

  /// Pushes current tracking state to the Cloud Function.
  /// Fire-and-forget — failures don't block the UI.
  void _pushTrackingToServer() {
    final activityId = state.activityId;
    if (activityId == null || _tracked.isEmpty) return;

    final payload = _tracked.values.map((t) => {
      'section': t.correction.sectionTitle,
      'wrong': t.correction.wrong,
      'correct': t.correction.correct,
      'offset': t.correction.offset,
      'userAction': t.action,
    }).toList();

    ClaudeService.updateSpellcheckResult(
      activityId: activityId,
      corrections: payload,
    );
    debugPrint('✏️ [Spellcheck] Tracking pushed (${payload.length} corrections)');
  }
}

/// Internal helper — bundles a SpellCorrection with its current user action.
class _TrackedCorrection {
  final SpellCorrection correction;
  final String action; // 'pending' | 'accepted' | 'dismissed'
  const _TrackedCorrection({required this.correction, required this.action});
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final spellcheckControllerProvider =
StateNotifierProvider<SpellcheckController, SpellcheckState>(
      (ref) => SpellcheckController(),
);