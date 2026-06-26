// lib/shared/ai/claude_state.dart
//
// State classes for the Claude AI controller. Extracted from claude_controller.dart
// during E1 file structure cleanup.

/// AI Compose / Refine status. Drives spinner, error, and paywall UI states.
enum AiFillStatus { idle, loading, done, error, paywalled }

class ClaudeState {
  final AiFillStatus status;
  final String? activeItemId;
  final String? error;
  final int streamedChars;
  final String? activeOperation; // 'fill' or 'rewrite'

  const ClaudeState({
    this.status = AiFillStatus.idle,
    this.activeItemId,
    this.activeOperation,
    this.error,
    this.streamedChars = 0,
  });

  bool get isActive => status == AiFillStatus.loading;

  ClaudeState copyWith({
    AiFillStatus? status,
    String? activeItemId,
    String? activeOperation,
    String? error,
    int? streamedChars,
  }) => ClaudeState(
    status: status ?? this.status,
    activeItemId: activeItemId ?? this.activeItemId,
    activeOperation: activeOperation ?? this.activeOperation,
    error: error,
    streamedChars: streamedChars ?? this.streamedChars,
  );
}

/// Style pattern extracted from a template's existing Quill delta.
/// Used to reapply heading/title/body formatting on AI-generated content.
///
/// Made public (was `_StyleSet`) so the proposal-fill extension can use it.
class StyleSet {
  final Map<String, dynamic> headingAttrs;
  final Map<String, dynamic> titleAttrs;
  final Map<String, dynamic> bodyAttrs;
  const StyleSet({
    this.headingAttrs = const {},
    this.titleAttrs = const {},
    this.bodyAttrs = const {},
  });
}