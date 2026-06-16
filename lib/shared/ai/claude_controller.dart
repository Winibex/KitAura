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
import '../../features/cover_letter/editor/controller/cl_editor_controller.dart';
import '../../features/proposal/editor/controller/prop_editor_controller.dart';
import '../../features/proposal/template/data/prop_template_data.dart';
import '../models/ai_profile_model.dart';
import '../models/canvas_item.dart';
import '../models/client_profile_model.dart';
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
  }) async
  {
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

  /// Fills ALL cover letter sections at once using job details + linked CV.
  /// Called from the CL editor's "AI Generate Cover Letter" button.
  Future<void> fillAllClSections({
    required List<CanvasItem> items,
    required ClEditorController editor,
  }) async
  {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] fillAllClSections');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }

    state = const ClaudeState(status: AiFillStatus.loading, activeOperation: 'fill');

    // Load profile
    try {
      _cachedProfile ??= await _loadAiProfile(uid);
    } catch (_) {}
    final profile = _cachedProfile ?? const AiProfileModel();

    // Load linked CV content
    String? cvContent;
    if (editor.state.linkedCvId != null) {
      cvContent = await editor.getLinkedCvContent();
    }

    // Build job details map
    final jobDetails = <String, dynamic>{
      'companyName': editor.state.targetCompany ?? '',
      'jobRole': editor.state.targetRole ?? '',
      'hiringManagerName': editor.state.hiringManagerName ?? '',
      'hiringManagerTitle': editor.state.hiringManagerTitle ?? '',
      'companyAddress': editor.state.companyAddress ?? '',
      'companyCityStateZip': editor.state.companyCityStateZip ?? '',
      'jobDescription': editor.state.jobDescription ?? '',
    };

    try {
      final content = await ClaudeService.aiFillSection(
        sectionType: 'all',
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
        tool: 'coverLetter',
        documentId: editor.state.firestoreDocId,
        documentTitle: editor.state.title,
        jobDetails: jobDetails,
        cvContent: cvContent,
      );

      if (!mounted || content == null) {
        state = ClaudeState(
          status: AiFillStatus.error,
          error: 'AI returned no content. Try adding more job details.',
        );
        return;
      }

      // Apply each section's content to matching canvas items
      int filled = 0;
      for (final item in items) {
        if (!item.isText || item.controller == null) continue;
        final sectionKey = item.sectionType.key;
        final sectionContent = content[sectionKey];
        if (sectionContent == null) continue;
        if (sectionContent is! Map) continue;

        final styles = _extractStyles(item.controller!.document);

        try {
          // Reset cursor before swapping document
          item.controller!.updateSelection(
            const TextSelection.collapsed(offset: 0),
            ChangeSource.local,
          );
          item.controller!.document = Document.fromJson(
            _buildStyledDelta(Map<String, dynamic>.from(sectionContent), styles),
          );
          filled++;
        } catch (e) {
          debugPrint('🤖 [ClaudeController] Failed to apply section $sectionKey: $e');
        }
      }

      state = ClaudeState(
        status: AiFillStatus.done,
        streamedChars: filled,
      );
      debugPrint('🤖 [ClaudeController] fillAllClSections OK — $filled sections filled');
    } catch (e) {
      if (!mounted) return;
      final isPaywall = e.toString().contains('limit') || e.toString().contains('Upgrade');
      state = ClaudeState(
        status: isPaywall ? AiFillStatus.paywalled : AiFillStatus.error,
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
  }) async
  {
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
      QuillController controller, String newText, _StyleSet styles)
  {
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
      Map<String, dynamic> content, _StyleSet styles)
  {
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
    debugPrint('🤖 [ClaudeController] Loading default AI profile for $uid');
    return await FirebaseService.getDefaultAiProfile(uid);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AI GENERATE PROPOSAL (one-shot, whole proposal: text + tables)
  // ═══════════════════════════════════════════════════════════════════════

  /// Generates an entire proposal in one call. Builds a manifest of the
  /// canvas sections (text vs table + headers), sends client brief + AI
  /// profile + optional CV, then applies returned content keyed by item id.
  Future<void> fillAllProposalSections({
    required List<CanvasItem> items,
    required PropEditorController editor,
  }) async
  {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] fillAllProposalSections');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }

    state = const ClaudeState(status: AiFillStatus.loading, activeOperation: 'fill');

    // Profile (sender)
    try {
      _cachedProfile ??= await _loadAiProfile(uid);
    } catch (_) {}
    final profile = _cachedProfile ?? const AiProfileModel();
    final templateId = editor.state.templateId ?? '';

    // Client brief (the rich 6-step client profile)
    final client = await editor.getLinkedClient();
    if (client == null) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'No client linked. Select a client first.',
      );
      return;
    }

    // Optional linked CV
    String? cvContent;
    if (editor.state.linkedCvId != null) {
      cvContent = await editor.getLinkedCvContent();
    }

    // ── Build the section manifest from the canvas ──────────────────
    // Only text + table sections are fillable. Each gets a stable id so
    // the AI can target it (two pricing tables won't collide).
    final manifest = <Map<String, dynamic>>[];
    final keyToItem = <String, CanvasItem>{}; // NEW: maps slot key → item
    int slot = 0;
    for (final item in items) {
      if (item.role == 'hero' ||
          item.role == 'top_band' ||
          item.role == 'signature' ||
          item.role == 'heading' ||
          item.role == 'underline') {
        continue;
      }
      final lt = item.title.trim().toLowerCase();
      if (lt == 'signature' || lt == 'signature author') continue; // footer filled locally
      if (item.isText && item.controller != null) {
        final key = 's$slot';
        keyToItem[key] = item;
        final shape = PropTemplateData.getContentShape(templateId, item.title);
        manifest.add({
          'id': key,
          'sectionType': item.sectionType.key,
          'title': item.title,
          'kind': 'text',
          if (shape != null) 'shape': shape,
        });
        slot++;
      } else if (item.isTable && item.tableData != null) {
        final key = 's$slot';
        keyToItem[key] = item;
        manifest.add({
          'id': key,
          'sectionType': item.sectionType.key,
          'title': item.title,
          'kind': 'table',
          'headers': item.tableData!.headers,
          'columnCount': item.tableData!.columnCount,
          'maxRows': item.tableData!.rowCount, // keep AI from bloating tables
        });
        slot++;
      }
    }

    if (manifest.isEmpty) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'No fillable sections on this proposal.',
      );
      return;
    }

    // Client brief as a structured map (mirrors CL's jobDetails channel)
    final clientBrief = _buildClientBrief(client);

    try {
      final content = await ClaudeService.aiFillSection(
        sectionType: 'all',
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
        tool: 'proposal',
        documentId: editor.state.firestoreDocId,
        documentTitle: editor.state.title,
        jobDetails: clientBrief,
        cvContent: cvContent,
        sectionManifest: manifest,
      );

      if (!mounted) return;
      if (content == null) {
        state = const ClaudeState(
          status: AiFillStatus.error,
          error: 'AI returned no content. Add more client detail.',
        );
        return;
      }

      debugPrint('🤖 [Proposal] returned keys: ${content.keys.toList()}');
      debugPrint('🤖 [Proposal] expected keys: ${keyToItem.keys.toList()}');

      // ── Apply, keyed by slot ──────────────────────────────────────
      int filled = 0;
      content.forEach((key, sec) {
        final item = keyToItem[key];
        if (item == null || sec is! Map) return;
        final map = Map<String, dynamic>.from(sec);
        final kind = map['kind'] as String?;

        try {
          if (item.isText && item.controller != null && kind != 'table') {
            final styles = _extractStyles(item.controller!.document);
            item.controller!.updateSelection(
                const TextSelection.collapsed(offset: 0), ChangeSource.local);
            item.controller!.document =
                Document.fromJson(_buildStyledDelta(map, styles));
            filled++;
          } else if (item.isTable && item.tableData != null && kind == 'table') {
            final newRows = _coerceRows(map['rows'], item.tableData!.columnCount);
            if (newRows.isNotEmpty) {
              item.tableData!.rows = newRows;
              filled++;
            }
          }
        } catch (e) {
          debugPrint('🤖 [ClaudeController] Apply failed for $key: $e');
        }
      });

      _fillCoverSlots(items, client: client, profile: profile);
      _fillSignatureSlots(items, client: client, profile: profile);
      editor.canvas.autoArrange();
      editor.markDirty();

      state = ClaudeState(status: AiFillStatus.done, streamedChars: filled);
      debugPrint('🤖 [ClaudeController] fillAllProposalSections OK — $filled filled');
    } catch (e) {
      if (!mounted) return;
      final isPaywall = e.toString().contains('limit') || e.toString().contains('Upgrade');
      state = ClaudeState(
        status: isPaywall ? AiFillStatus.paywalled : AiFillStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Normalize AI rows to exactly [cols] cells each (pad/truncate defensively).
  List<List<String>> _coerceRows(dynamic raw, int cols) {
    if (raw is! List) return [];
    final out = <List<String>>[];
    for (final r in raw) {
      if (r is! List) continue;
      final cells = r.map((c) => c?.toString() ?? '').toList();
      while (cells.length < cols) {
        cells.add('');
      }
      out.add(cells.length > cols ? cells.sublist(0, cols) : cells);
    }
    return out;
  }

  /// Flatten the client profile into a compact brief for the prompt.
  Map<String, dynamic> _buildClientBrief(ClientProfileModel c) {
    return {
      'clientName': c.clientName,
      'clientCompany': c.clientCompany,
      'industry': c.industry,
      'projectTitle': c.projectTitle,
      'projectType': c.projectType,
      'projectDescription': c.projectDescription,
      'problemStatement': c.problemStatement,
      'projectGoals': c.projectGoals,
      'deliverables': c.deliverables.map((d) => {
        'name': d.name, 'description': d.description,
      }).toList(),
      'scopeNotes': c.scopeNotes,
      'startDate': c.startDate,
      'endDate': c.endDate,
      'milestones': c.milestones.map((m) => {
        'title': m.title, 'date': m.date, 'description': m.description,
      }).toList(),
      'budgetRange': c.budgetRange,
      'pricingModel': c.pricingModel,
      'lineItems': c.lineItems.map((l) => {
        'item': l.item, 'description': l.description, 'amount': l.amount,
      }).toList(),
      'competitorInfo': c.competitorInfo,
      'specialRequirements': c.specialRequirements,
      'customNotes': c.customNotes,
      'typeSpecific': {
        'techStack': c.typeSpecific.techStack,
        'platformTargets': c.typeSpecific.platformTargets,
        'creativeBrief': c.typeSpecific.creativeBrief,
        'channels': c.typeSpecific.channels,
        'targetAudience': c.typeSpecific.targetAudience,
      },
    };
  }

  /// Fills the cover-page hero slots directly from the client brief + sender
  /// profile, matching the template's per-line layout. Keeps each line's
  /// existing formatting (label lines stay styled; only values are swapped).
  void _fillCoverSlots(
      List<CanvasItem> items, {
        required ClientProfileModel client,
        required AiProfileModel profile,
      }) {
    for (final item in items) {
      final isCover = item.role == 'hero' || item.role == 'top_band';
      if (!isCover || !item.isText || item.controller == null) {
        continue;
      }
      final title = item.title.trim().toLowerCase();

      List<String>? values; // the value lines, in order, for this slot
      switch (title) {
        case 'proposal title':
        // line 0 = "BUSINESS PROPOSAL" label (keep), line 1 = project title
          values = [
            _keepLine0,
            (client.projectTitle.isNotEmpty
                ? client.projectTitle
                : 'Project Proposal'),
          ];
          break;
        case 'client info':
        // line 0 = "PREPARED FOR" label (keep), then name, then company | email
          values = [
            _keepLine0,
            client.clientName.isNotEmpty ? client.clientName : 'Client Name',
            _joinPipe([client.clientCompany, client.clientEmail]),
          ];
          break;
        case 'author info':
          values = [
            profile.fullName.isNotEmpty ? profile.fullName : 'Your Name',
            (profile.jobTitle ?? '').isNotEmpty
                ? profile.jobTitle!
                : (profile.industry),
            _joinPipe([profile.email, profile.phone]),
          ];
          break;
        case 'date':
          values = [_todayLong()];
          break;
        case 'header':
        // Freelance template: line 0 = freelancer name (bold), line 1 = title | "Freelance Professional"
          values = [
            profile.fullName.isNotEmpty ? profile.fullName : 'Your Name',
            _joinPipe([
              (profile.jobTitle ?? '').isNotEmpty
                  ? profile.jobTitle!
                  : profile.industry,
              'Freelance Professional',
            ]),
          ];
          break;

        case 'contact':
        // Freelance: 3 lines — email, phone, website
          values = [
            profile.email.isNotEmpty ? profile.email : 'email@example.com',
            profile.phone.isNotEmpty ? profile.phone : '+1 234 567 890',
            (profile.website ?? '').isNotEmpty
                ? profile.website!
                : 'www.yourwebsite.com',
          ];
          break;

        case 'proposal for':
        // Freelance: single line "Proposal for {client}  |  {date}"
        // The template's delta has 3 inline ops (label / client bold / date),
        // but they live on ONE logical line — replace line 0 fully.
          final clientName = client.clientName.isNotEmpty
              ? client.clientName
              : 'Client Name';
          values = ['Proposal for $clientName  |  ${_todayLong()}'];
          break;
        case 'title':
        // Executive template: lines 0-2 stay as template ("EXECUTIVE" / "PROPOSAL" / blank).
        // Line 3 is the tagline — fill with project title.
          final projectName = client.projectTitle.isNotEmpty
              ? client.projectTitle
              : 'Project Name';
          values = [
            _keepLine0,
            _keepLine0,
            _keepLine0,
            'Strategic Partnership for $projectName',
          ];
          break;

        case 'client':
        // Executive: line 0 = "PREPARED FOR" label (keep),
        // line 1 = "Client Name, Title", line 2 = "Company  |  Date"
          final clientName = client.clientName.isNotEmpty
              ? client.clientName
              : 'Client Name';
          values = [
            _keepLine0,
            clientName,
            _joinPipe([client.clientCompany, _todayLong()]),
          ];
          break;
      // 'company' and 'confidential' intentionally NOT matched — they stay static.
        default:
          continue; // unknown hero slot — leave as-is
      }

      _applyCoverValues(item.controller!, values);
    }
  }

  /// Sentinel: keep the existing line 0 text (a styled label like "PREPARED FOR").
  static const String _keepLine0 = '\u0000KEEP\u0000';

  /// Rewrites a hero text item line-by-line, preserving each line's existing
  /// attributes. value[i] replaces line i; the _keepLine0 sentinel keeps the
  /// original line text. Extra existing lines beyond `values` are dropped.
  void _applyCoverValues(QuillController controller, List<String> values) {
    final oldOps = controller.document.toDelta().toJson();

    // Split old delta into lines, remembering each line's attributes.
    final lineTexts = <String>[];
    final lineAttrs = <Map<String, dynamic>>[];
    String curText = '';
    Map<String, dynamic> curAttrs = {};
    for (final op in oldOps) {
      final ins = op['insert'];
      if (ins is! String) continue;
      final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
      final parts = ins.split('\n');
      for (int i = 0; i < parts.length; i++) {
        curText += parts[i];
        if (parts[i].isNotEmpty) curAttrs = attrs;
        if (i < parts.length - 1) {
          lineTexts.add(curText);
          lineAttrs.add(curAttrs);
          curText = '';
          curAttrs = {};
        }
      }
    }
    if (curText.isNotEmpty) { lineTexts.add(curText); lineAttrs.add(curAttrs); }

    Map<String, dynamic> attrsFor(int i) =>
        i < lineAttrs.length ? lineAttrs[i] : (lineAttrs.isNotEmpty ? lineAttrs.last : {});

    final ops = <Map<String, dynamic>>[];
    for (int i = 0; i < values.length; i++) {
      var text = values[i];
      if (text == _keepLine0) text = i < lineTexts.length ? lineTexts[i] : '';
      final a = attrsFor(i);
      ops.add(a.isEmpty
          ? {'insert': text}
          : {'insert': text, 'attributes': Map<String, dynamic>.from(a)});
      ops.add({'insert': '\n'}); // plain newline (engine + quill safe)
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});

    controller.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);
    controller.document = Document.fromJson(ops);
  }

  String _joinPipe(List<String?> parts) =>
      parts.where((p) => p != null && p.trim().isNotEmpty)
          .map((p) => p!.trim())
          .join('  |  ');

  String _todayLong() {
    const months = [
      'January','February','March','April','May','June','July',
      'August','September','October','November','December'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  /// Fills the signature footer ("Accepted by" / "Submitted by") directly from
  /// data, keeping the template's exact line structure and formatting. Only the
  /// name line's value changes; "Date" and the signature rule stay as-is.
  void _fillSignatureSlots(
      List<CanvasItem> items, {
        required ClientProfileModel client,
        required AiProfileModel profile,
      }) {
    for (final item in items) {
      if (item.role != 'signature' || !item.isText || item.controller == null) {
        continue;
      }
      final plain = item.controller!.document.toPlainText().toLowerCase();
      String name;
      if (plain.contains('accepted')) {
        name = client.clientName.isNotEmpty ? client.clientName : 'Client Name';
      } else if (plain.contains('submitted')) {
        name = profile.fullName.isNotEmpty ? profile.fullName : 'Your Name';
      } else {
        continue;
      }

      // Rebuild line-by-line, preserving each line's attributes. We keep every
      // line as-is EXCEPT the last non-empty line ("X Name  |  Date"), where we
      // swap the part before the pipe with the real name.
      final oldOps = item.controller!.document.toDelta().toJson();
      final lineTexts = <String>[];
      final lineAttrs = <Map<String, dynamic>>[];
      String curText = '';
      Map<String, dynamic> curAttrs = {};
      for (final op in oldOps) {
        final ins = op['insert'];
        if (ins is! String) continue;
        final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
        final parts = ins.split('\n');
        for (int i = 0; i < parts.length; i++) {
          curText += parts[i];
          if (parts[i].isNotEmpty) curAttrs = attrs;
          if (i < parts.length - 1) {
            lineTexts.add(curText);
            lineAttrs.add(curAttrs);
            curText = '';
            curAttrs = {};
          }
        }
      }
      if (curText.isNotEmpty) { lineTexts.add(curText); lineAttrs.add(curAttrs); }

      // Find the "... | Date" line and replace the name part.
      for (int i = 0; i < lineTexts.length; i++) {
        if (lineTexts[i].contains('|')) {
          final pipeIdx = lineTexts[i].indexOf('|');
          final after = lineTexts[i].substring(pipeIdx); // "|  Date"
          lineTexts[i] = '$name  $after';
          break;
        }
      }

      final ops = <Map<String, dynamic>>[];
      for (int i = 0; i < lineTexts.length; i++) {
        final a = i < lineAttrs.length ? lineAttrs[i] : {};
        if (lineTexts[i].isNotEmpty) {
          ops.add(a.isEmpty
              ? {'insert': lineTexts[i]}
              : {'insert': lineTexts[i], 'attributes': Map<String, dynamic>.from(a)});
        }
        ops.add({'insert': '\n'});
      }
      if (ops.isEmpty) ops.add({'insert': '\n'});

      item.controller!.updateSelection(
          const TextSelection.collapsed(offset: 0), ChangeSource.local);
      item.controller!.document = Document.fromJson(ops);
    }
  }
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final claudeControllerProvider =
StateNotifierProvider.autoDispose<ClaudeController, ClaudeState>(
      (ref) => ClaudeController(),
);