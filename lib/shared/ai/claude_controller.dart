// lib/features/cv/controller/claude_controller.dart
//
// AI Fill + AI Rewrite controller. All tracking happens server-side.
// Frontend only: load profile, call function, apply returned content.
//
// CHANGES FROM PREVIOUS VERSION:
//   1. Added rewriteSection() method for AI Rewrite feature
//   2. Debug prints on all operations

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/ai_profile_model.dart';
import '../models/section_type.dart';
import '../services/firebase_service.dart';
import 'claude_service.dart';

// ─── STATE ───────────────────────────────────────────────────────────────

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

// ─── STYLE PATTERN (extracted from template delta) ───────────────────────

class _StyleSet {
  final Map<String, dynamic> headingAttrs;
  final Map<String, dynamic> titleAttrs;
  final Map<String, dynamic> bodyAttrs;
  const _StyleSet({
    this.headingAttrs = const {},
    this.titleAttrs = const {},
    this.bodyAttrs = const {},
  });
}

// ─── CONTROLLER ──────────────────────────────────────────────────────────

class ClaudeController extends StateNotifier<ClaudeState> {
  ClaudeController() : super(const ClaudeState());

  AiProfileModel? _cachedProfile;

  // ═══════════════════════════════════════════════════════════════════════
  // AI FILL
  // ═══════════════════════════════════════════════════════════════════════

  /// Fill a text section: extract styles → call function → apply styled content.
  /// All tracking (tokens, cost, counters) happens server-side.
  Future<void> fillSection({
    required String itemId,
    required SectionType sectionType,
    required String sectionTitle,
    required QuillController controller,
    String? cvId,
    String? cvTitle,
    String? templateId,
    String tool = 'cv',
  }) async {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] fillSection($sectionTitle, type=${sectionType.key})');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }

    state = ClaudeState(status: AiFillStatus.loading, activeItemId: itemId, activeOperation: 'fill');

    // Load profile
    try {
      _cachedProfile ??= await _loadAiProfile(uid);
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Profile load failed: $e');
    }
    final profile = _cachedProfile ?? const AiProfileModel();

    // Extract styles from existing template content
    final styles = _extractStyles(controller.document);
    final beforeText = controller.document.toPlainText();

    // Call Cloud Function
    try {
      final content = await ClaudeService.aiFillSection(
        sectionType: sectionType.key,
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
        tool: tool,
        documentId: cvId,
        documentTitle: cvTitle,
        templateId: templateId,
        sectionTitle: sectionTitle,
        beforeText: beforeText,
      );

      if (!mounted) return;

      if (content == null) {
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: itemId,
          error: 'AI returned no content. Add more profile data.',
        );
        return;
      }

      // Apply old styles + new text
      try {
        // Reset cursor to position 0 BEFORE swapping document
        // (prevents flutter_quill from trying to paint cursor at stale offset)
        controller.updateSelection(
          const TextSelection.collapsed(offset: 0),
          ChangeSource.local,
        );
        controller.document = Document.fromJson(_buildStyledDelta(content, styles));
      } catch (e) {
        debugPrint('🤖 [ClaudeController] Delta apply failed: $e');
        _applyPlainFallback(controller, content);
      }

      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: itemId,
        streamedChars: controller.document.toPlainText().length,
      );
      debugPrint('🤖 [ClaudeController] fillSection OK');
    } catch (e) {
      if (!mounted) return;
      final isPaywall = e.toString().contains('limit') || e.toString().contains('Upgrade');
      state = ClaudeState(
        status: isPaywall ? AiFillStatus.paywalled : AiFillStatus.error,
        activeItemId: itemId,
        error: e.toString(),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AI REWRITE
  // ═══════════════════════════════════════════════════════════════════════

  /// Rewrite a text section: extract existing text → call function → apply.
  /// Preserves template formatting styles.
  ///
  /// [mode] — professional, concise, detailed, creative
  /// [customInstruction] — optional user instruction (e.g. "focus on metrics")
  Future<void> rewriteSection({
    required String itemId,
    required SectionType sectionType,
    required String sectionTitle,
    required QuillController controller,
    required String mode,
    String? customInstruction,
    String? cvId,
    String? cvTitle,
    String? templateId,
    String tool = 'cv',
  }) async {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] rewriteSection($sectionTitle, mode=$mode)');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }

    final currentText = controller.document.toPlainText().trim();
    if (currentText.isEmpty) {
      state = ClaudeState(
        status: AiFillStatus.error,
        activeItemId: itemId,
        error: 'Section is empty — nothing to rewrite. Use AI Fill first.',
      );
      return;
    }

    state = ClaudeState(status: AiFillStatus.loading, activeItemId: itemId, activeOperation: 'rewrite');

    // Extract styles from existing template content (to reapply after rewrite)
    final styles = _extractStyles(controller.document);

    try {
      final rewritten = await ClaudeService.aiRewriteSection(
        text: currentText,
        sectionType: sectionType.key,
        mode: mode,
        customInstruction: customInstruction,
        tool: tool,
        documentId: cvId,
        documentTitle: cvTitle,
        templateId: templateId,
      );

      if (!mounted) return;

      if (rewritten == null || rewritten.trim().isEmpty) {
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: itemId,
          error: 'AI returned no content. Please try again.',
        );
        return;
      }

      // Apply rewritten text with existing formatting styles
      _applyRewrittenText(controller, rewritten, styles);

      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: itemId,
        streamedChars: controller.document.toPlainText().length,
      );
      debugPrint('🤖 [ClaudeController] rewriteSection OK (${rewritten.length} chars)');
    } catch (e) {
      if (!mounted) return;
      final isPaywall = e.toString().contains('limit') || e.toString().contains('Upgrade');
      state = ClaudeState(
        status: isPaywall ? AiFillStatus.paywalled : AiFillStatus.error,
        activeItemId: itemId,
        error: e.toString(),
      );
    }
  }

  /// Apply rewritten text while preserving template formatting styles.
  void _applyRewrittenText(
      QuillController controller, String newText, _StyleSet styles) {
    try {
      // Get existing delta to preserve formatting
      final existingOps = controller.document.toDelta().toJson();

      // Find the dominant text style from existing content
      Map<String, dynamic> defaultAttrs = {};
      for (final op in existingOps) {
        final insert = op['insert'];
        if (insert is String && insert.trim().length > 3) {
          defaultAttrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
          if (!defaultAttrs.containsKey('bold')) break; // prefer body style
        }
      }

      // Build new delta: apply existing style to all rewritten text
      final ops = <Map<String, dynamic>>[];
      final lines = newText.split('\n');

      for (final line in lines) {
        if (line.trim().isEmpty) {
          ops.add({'insert': '\n'});
          continue;
        }
        final t = '$line\n';
        if (defaultAttrs.isNotEmpty) {
          ops.add({'insert': t, 'attributes': Map<String, dynamic>.from(defaultAttrs)});
        } else {
          ops.add({'insert': t});
        }
      }

      if (ops.isEmpty) ops.add({'insert': '\n'});

      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      controller.document = Document.fromJson(ops);
      debugPrint('🤖 [ClaudeController] Rewrite applied (${ops.length} ops)');
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Rewrite delta failed, using plain insert: $e');
      // Fallback: just replace all text
      final len = controller.document.length;
      if (len > 1) controller.replaceText(0, len - 1, '', null);
      controller.document.insert(0, newText.trimRight());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STYLE EXTRACTION (shared by Fill + Rewrite)
  // ═══════════════════════════════════════════════════════════════════════

  _StyleSet _extractStyles(Document doc) {
    final ops = doc.toDelta().toJson();
    Map<String, dynamic> heading = {}, title = {}, body = {};
    bool fH = false, fT = false, fB = false;

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String || insert.trim().isEmpty) continue;
      final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
      final isBold = attrs['bold'] == true;

      if (isBold && !fH) { heading = Map.from(attrs); fH = true; }
      else if (isBold && !fT) { title = Map.from(attrs); fT = true; }
      else if (!isBold && !fB && insert.trim().length > 5) { body = Map.from(attrs); fB = true; }
      if (fH && fT && fB) break;
    }

    if (!fT) title = Map.from(heading);
    if (title.containsKey('size')) {
      final hs = _parseSize(heading['size']), ts = _parseSize(title['size']);
      if (ts >= hs && hs > 11) title['size'] = '11';
    }
    if (!fB) { body = Map.from(title); body.remove('bold'); }

    return _StyleSet(headingAttrs: heading, titleAttrs: title, bodyAttrs: body);
  }

  double _parseSize(dynamic s) =>
      s == null ? 11 : double.tryParse(s.toString().replaceAll('pt', '')) ?? 11;

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD STYLED DELTA (for AI Fill)
  // ═══════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _buildStyledDelta(
      Map<String, dynamic> content, _StyleSet styles) {
    final ops = <Map<String, dynamic>>[];
    final heading = content['heading'] as String? ?? '';
    final entries = content['entries'] as List<dynamic>? ?? [];

    if (heading.isNotEmpty) ops.add(_op(heading, styles.headingAttrs));

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is! Map) continue;
      final t = entry['title'] as String? ?? '';
      final lines = (entry['lines'] as List?)?.map((l) => l.toString()).toList() ?? [];

      if (t.isNotEmpty) ops.add(_op(t, styles.titleAttrs));
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        ops.add(_op(line, styles.bodyAttrs));
      }
      if (i < entries.length - 1 && entries.length > 1) ops.add({'insert': '\n'});
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return ops;
  }

  Map<String, dynamic> _op(String text, Map<String, dynamic> attrs) {
    final t = text.endsWith('\n') ? text : '$text\n';
    return attrs.isEmpty
        ? {'insert': t}
        : {'insert': t, 'attributes': Map<String, dynamic>.from(attrs)};
  }

  void _applyPlainFallback(QuillController controller, Map<String, dynamic> content) {
    final buf = StringBuffer();
    final h = content['heading'] as String? ?? '';
    if (h.isNotEmpty) buf.writeln(h);
    for (final entry in (content['entries'] as List? ?? [])) {
      if (entry is! Map) continue;
      final t = entry['title'] as String? ?? '';
      if (t.isNotEmpty) buf.writeln(t);
      for (final l in (entry['lines'] as List? ?? [])) {
        buf.writeln(l);
      }
      buf.writeln();
    }
    final len = controller.document.length;
    controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    if (len > 1) controller.replaceText(0, len - 1, '', null);
    controller.document.insert(0, buf.toString().trimRight());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _sanitizeProfile(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    clean.remove('updatedAt');
    return clean;
  }

  void cancel() => state = const ClaudeState();
  void reset() => state = const ClaudeState();
  void invalidateProfile() => _cachedProfile = null;

  Future<AiProfileModel?> _loadAiProfile(String uid) async {
    debugPrint('🤖 [ClaudeController] Loading AI profile for $uid');
    final doc = await FirebaseService.getAiProfile(uid);
    if (doc.exists) {
      return AiProfileModel.fromJson(doc.data() as Map<String, dynamic>);
    }
    return null;
  }
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final claudeControllerProvider =
StateNotifierProvider.autoDispose<ClaudeController, ClaudeState>(
      (ref) => ClaudeController(),
);