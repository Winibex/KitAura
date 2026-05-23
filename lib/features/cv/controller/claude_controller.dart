// lib/features/cv/controller/claude_controller.dart
//
// AI Fill controller — replaces TEXT only, keeps STYLES from the template.
//
// HOW IT WORKS:
//   1. BEFORE calling the API, extract the formatting pattern from the
//      section's existing Quill delta (colors, sizes, fonts, bold).
//   2. Call Cloud Function → get plain structured text (no styling).
//   3. Apply the template's formatting pattern to the new text.
//
// This way every template keeps its own colors/fonts/sizes automatically.
// Navy template stays navy, pink stays pink, etc.

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

// ─── STYLE PATTERN ───────────────────────────────────────────────────────

/// Holds the formatting attributes for one "role" in the pattern.
/// Extracted from the existing template delta.
class _StyleSet {
  final Map<String, dynamic> headingAttrs;  // SECTION HEADING (e.g. "EXPERIENCE")
  final Map<String, dynamic> titleAttrs;    // Role/degree title (bold line)
  final Map<String, dynamic> bodyAttrs;     // Body / bullet lines

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
  SubscriptionModel? _cachedSubscription;

  /// Fill a text section: replace text only, keep template styles.
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
          "You've used all 10 free AI fills this month. Upgrade to Pro.",
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

    // ── STEP 1: Extract styles from the existing template delta ──────
    final styles = _extractStyles(controller.document);

    // ── STEP 2: Call Cloud Function → get plain structured text ──────
    try {
      final content = await ClaudeService.aiFillSection(
        sectionType: sectionType.key,
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
      );

      if (!mounted) return;

      if (content == null) {
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: itemId,
          error: 'AI returned no content. Add more profile data and retry.',
        );
        return;
      }

      // ── STEP 3: Build new delta with OLD styles + NEW text ────────
      final newDelta = _buildStyledDelta(content, styles);

      try {
        controller.document = Document.fromJson(newDelta);
      } catch (e) {
        debugPrint('Delta apply failed: $e');
        // Fallback: apply as plain text
        _applyPlainFallback(controller, content);
      }

      final chars = controller.document.toPlainText().length;
      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: itemId,
        streamedChars: chars,
      );

      // Track usage (fire-and-forget)
      try {
        FirebaseService.trackAiFill(uid, cvId ?? 'current', sectionTitle);
      } catch (_) {}
      _cachedSubscription = null;
    } catch (e) {
      if (!mounted) return;
      state = ClaudeState(
        status: AiFillStatus.error,
        activeItemId: itemId,
        error: e.toString(),
      );
    }
  }

  // ── EXTRACT STYLES from existing delta ─────────────────────────────
  //
  // Reads the current template content and identifies 3 style roles:
  //   1. Heading: the first bold line (usually the section name in caps)
  //   2. Title:   subsequent bold lines (role/degree titles)
  //   3. Body:    non-bold lines (achievements, descriptions)
  //
  // The attributes (color, size, font, bold) are saved so we can
  // re-apply them to the AI's new text.

  _StyleSet _extractStyles(Document doc) {
    final ops = doc.toDelta().toJson();

    Map<String, dynamic> headingAttrs = {};
    Map<String, dynamic> titleAttrs = {};
    Map<String, dynamic> bodyAttrs = {};

    bool foundHeading = false;
    bool foundTitle = false;
    bool foundBody = false;

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String || insert.trim().isEmpty) continue;

      final attrs = Map<String, dynamic>.from(
          (op['attributes'] as Map?) ?? {});
      final isBold = attrs['bold'] == true;

      if (isBold && !foundHeading) {
        // First bold line → heading
        headingAttrs = Map<String, dynamic>.from(attrs);
        foundHeading = true;
      } else if (isBold && !foundTitle) {
        // Second bold line → title
        titleAttrs = Map<String, dynamic>.from(attrs);
        foundTitle = true;
      } else if (!isBold && !foundBody && insert.trim().length > 5) {
        // First non-bold, non-trivial line → body
        bodyAttrs = Map<String, dynamic>.from(attrs);
        foundBody = true;
      }

      if (foundHeading && foundTitle && foundBody) break;
    }

    // Fallbacks: if we only found 1-2 styles, fill in sensible defaults
    if (!foundTitle) titleAttrs = Map<String, dynamic>.from(headingAttrs);
    if (titleAttrs.containsKey('size')) {
      // Title usually slightly smaller than heading
      final headSize = _parseSize(headingAttrs['size']);
      final titleSize = _parseSize(titleAttrs['size']);
      if (titleSize >= headSize && headSize > 11) {
        titleAttrs['size'] = '11';
      }
    }
    if (!foundBody) {
      bodyAttrs = Map<String, dynamic>.from(titleAttrs);
      bodyAttrs.remove('bold');
    }

    return _StyleSet(
      headingAttrs: headingAttrs,
      titleAttrs: titleAttrs,
      bodyAttrs: bodyAttrs,
    );
  }

  double _parseSize(dynamic s) {
    if (s == null) return 11;
    return double.tryParse(s.toString().replaceAll('pt', '')) ?? 11;
  }

  // ── BUILD STYLED DELTA from structured content + template styles ───
  //
  // content = {
  //   "heading": "EXPERIENCE",
  //   "entries": [
  //     { "title": "CTO — Winibex | 2025–Present", "lines": ["• Led...", ...] }
  //   ]
  // }

  List<Map<String, dynamic>> _buildStyledDelta(
      Map<String, dynamic> content, _StyleSet styles) {
    final ops = <Map<String, dynamic>>[];
    final heading = content['heading'] as String? ?? '';
    final entries = content['entries'] as List<dynamic>? ?? [];

    // Heading line (if present)
    if (heading.isNotEmpty) {
      ops.add(_op(heading, styles.headingAttrs));
    }

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is! Map) continue;

      final title = entry['title'] as String? ?? '';
      final lines = (entry['lines'] as List<dynamic>?)
          ?.map((l) => l.toString())
          .toList() ??
          [];

      // Title line (role, degree, etc.)
      if (title.isNotEmpty) {
        ops.add(_op(title, styles.titleAttrs));
      }

      // Body/bullet lines
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        ops.add(_op(line, styles.bodyAttrs));
      }

      // Blank line between entries (not after last)
      if (i < entries.length - 1 && entries.length > 1) {
        ops.add({'insert': '\n'});
      }
    }

    // Quill requires the last insert to end with \n
    if (ops.isEmpty) {
      ops.add({'insert': '\n'});
    }

    return ops;
  }

  /// Build a single delta op: text + attributes.
  Map<String, dynamic> _op(String text, Map<String, dynamic> attrs) {
    final t = text.endsWith('\n') ? text : '$text\n';
    if (attrs.isEmpty) return {'insert': t};
    return {'insert': t, 'attributes': Map<String, dynamic>.from(attrs)};
  }

  // ── Fallback: plain text if styled delta fails ─────────────────────

  void _applyPlainFallback(
      QuillController controller, Map<String, dynamic> content) {
    final buffer = StringBuffer();
    final heading = content['heading'] as String? ?? '';
    if (heading.isNotEmpty) buffer.writeln(heading);

    for (final entry in (content['entries'] as List<dynamic>? ?? [])) {
      if (entry is! Map) continue;
      final title = entry['title'] as String? ?? '';
      if (title.isNotEmpty) buffer.writeln(title);
      for (final line in (entry['lines'] as List? ?? [])) {
        buffer.writeln(line.toString());
      }
      buffer.writeln();
    }

    final length = controller.document.length;
    if (length > 1) {
      controller.replaceText(0, length - 1, '', null);
    }
    controller.document.insert(0, buffer.toString().trimRight());
  }

  // ── Utilities ──────────────────────────────────────────────────────

  /// Strip Firestore types (Timestamp) that fail callable validation.
  Map<String, dynamic> _sanitizeProfile(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    clean.remove('updatedAt');
    return clean;
  }

  void cancel() => state = const ClaudeState();
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
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final claudeControllerProvider =
StateNotifierProvider.autoDispose<ClaudeController, ClaudeState>(
      (ref) => ClaudeController(),
);