// lib/features/cv/controller/spellcheck_controller.dart
//
// AI-powered spellcheck: collects all text sections, sends to Claude,
// shows corrections, user can fix individually or fix all at once.

import 'package:flutter_riverpod/legacy.dart';
import 'claude_service.dart';
import '../models/canvas_item.dart';

// ─── STATE ───────────────────────────────────────────────────────────────

enum SpellcheckStatus { idle, checking, done, error }

class SpellcheckState {
  final SpellcheckStatus status;
  final List<SpellCorrection> corrections;
  final String? error;

  const SpellcheckState({
    this.status = SpellcheckStatus.idle,
    this.corrections = const [],
    this.error,
  });

  SpellcheckState copyWith({
    SpellcheckStatus? status,
    List<SpellCorrection>? corrections,
    String? error,
  }) {
    return SpellcheckState(
      status: status ?? this.status,
      corrections: corrections ?? this.corrections,
      error: error,
    );
  }

  bool get isChecking => status == SpellcheckStatus.checking;
  bool get hasCorrections => corrections.isNotEmpty;
  int get count => corrections.length;
}

// ─── CONTROLLER ──────────────────────────────────────────────────────────

class SpellcheckController extends StateNotifier<SpellcheckState> {
  SpellcheckController() : super(const SpellcheckState());

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

    state = state.copyWith(status: SpellcheckStatus.checking, error: null);

    try {
      final result = await ClaudeService.spellcheckCV(sections);
      state = state.copyWith(
        status: SpellcheckStatus.done,
        corrections: result.corrections,
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

    // Remove this correction from the list
    final updated = state.corrections
        .where((c) => c != correction)
        .toList();
    state = state.copyWith(corrections: updated);
  }

  /// Fix all corrections at once, applying from end to start
  /// to preserve offsets.
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
            plainText.substring(offset, offset + wrongWord.length) ==
                wrongWord) {
          controller.replaceText(
              offset, wrongWord.length, correction.correct, null);
        } else {
          // Fallback: find the word
          final idx = plainText.indexOf(wrongWord);
          if (idx >= 0) {
            controller.replaceText(
                idx, wrongWord.length, correction.correct, null);
          }
        }
      }
    }

    state = state.copyWith(corrections: []);
  }

  /// Dismiss a single correction (ignore it).
  void dismiss(SpellCorrection correction) {
    final updated = state.corrections.where((c) => c != correction).toList();
    state = state.copyWith(corrections: updated);
  }

  /// Reset state.
  void reset() {
    state = const SpellcheckState();
  }
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final spellcheckControllerProvider =
StateNotifierProvider<SpellcheckController, SpellcheckState>(
      (ref) => SpellcheckController(),
);