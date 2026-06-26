// lib/shared/ai/claude_controller.dart
//
// AI Compose + AI Refine controller. All tracking happens server-side.
// Frontend only: load profile, call function, apply returned content.
//
// E1 REFACTOR (June 26, 2026):
//   - State classes extracted to claude_state.dart
//   - Proposal-specific filling extracted to claude_proposal_fill.dart (extension)
//   - Fixed MVC violation in _loadAiProfile (now delegates to FirebaseService)
//   - Several helpers and the cached profile are now @protected / public so
//     the proposal-fill extension can call them while remaining a clean
//     extension (Dart extensions can't access private members).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../features/proposal/editor/controller/prop_editor_controller.dart';
import '../../features/proposal/template/data/prop_template_data.dart';
import '../models/client_profile_model.dart';
import '../../features/cover_letter/dashboard/controller/cl_dashboard_controller.dart';
import '../../features/cover_letter/editor/controller/cl_editor_controller.dart';
import '../../features/cv/dashboard/controller/cv_dashboard_controller.dart';
import '../../features/cv/editor/controller/section_autofill.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';
import '../../features/proposal/dashboard/controller/prop_dashboard_controller.dart';
import '../models/ai_profile_model.dart';
import '../models/canvas_item.dart';
import '../models/section_type.dart';
import '../services/firebase_service.dart';
import 'claude_service.dart';
import 'claude_state.dart';

// Re-export state classes so consumers can keep `import 'claude_controller.dart'`
// and still see ClaudeState, AiFillStatus.
export 'claude_state.dart';
part 'claude_proposal_fill.dart';

// ─── CONTROLLER ──────────────────────────────────────────────────────────

class ClaudeController extends StateNotifier<ClaudeState> {
  ClaudeController(this._ref) : super(const ClaudeState());

  final Ref _ref;
  AiProfileModel? cachedProfile;

  /// Private state setter used by the proposal-fill extension.
  /// The Riverpod StateNotifier marks the public `state =` setter as
  /// `@visibleForTesting` outside subclasses, which blocks extensions even
  /// when they live in the same library via `part of`. This wrapper sits
  /// inside the class itself, so it has full access.
  void setStateFromExtension(ClaudeState newState) {
    state = newState;
  }

  /// Private state getter for the proposal-fill extension. Same reason as
  /// setStateFromExtension — Riverpod restricts direct `state` access to
  /// subclass methods, blocking extensions.
  ClaudeState get stateForExtension => state;


  // ───────────────────────────────────────────────────────────────────────

  /// Bumps the dashboard counters for AI Compose / AI Refine after a
  /// successful AI call.
  void _bumpDashboardCounter({required String tool, required bool isRewrite}) {
    try {
      if (tool == 'cv') {
        _ref.read(cvDashboardControllerProvider.notifier).incrementAiUsage();
        _ref.read(dashboardControllerProvider.notifier)
            .incrementAiUsage(isRewrite: isRewrite);
      } else if (tool == 'coverLetter') {
        _ref.read(clDashboardControllerProvider.notifier).incrementAiUsage();
        _ref.read(dashboardControllerProvider.notifier)
            .incrementAiUsage(isRewrite: isRewrite);
      } else if (tool == 'proposal') {
        _ref.read(propDashboardControllerProvider.notifier).incrementAiUsage();
        _ref.read(dashboardControllerProvider.notifier)
            .incrementAiUsage(isRewrite: isRewrite);
      }
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Dashboard counter bump failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AI Compose
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> fillSection({
    required String itemId,
    required SectionType sectionType,
    required String sectionTitle,
    required QuillController controller,
    String? cvId,
    String? cvTitle,
    String? templateId,
    String tool = 'cv',
    String? profileId,
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

    AiProfileModel? profile;
    try {
      if (profileId != null) {
        profile = await _loadAiProfile(uid, profileId: profileId);
      } else {
        cachedProfile ??= await _loadAiProfile(uid);
        profile = cachedProfile;
      }
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Profile load failed: $e');
    }

    if (profile == null ||
        (profile.fullName.isEmpty && profile.experiences.isEmpty)) {
      state = ClaudeState(
        status: AiFillStatus.error,
        activeItemId: itemId,
        error: 'Career Profile is empty. Please add your details first by clicking the Career Profile picker.',
      );
      return;
    }

    final styles = _extractStyles(controller.document);
    final beforeText = controller.document.toPlainText();

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

      try {
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
      _bumpDashboardCounter(tool: tool, isRewrite: false);
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

  Future<void> fillAllClSections({
    required List<CanvasItem> items,
    required ClEditorController editor,
    String? profileId,
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

    AiProfileModel? profile;
    try {
      if (profileId != null) {
        profile = await _loadAiProfile(uid, profileId: profileId);
      } else {
        cachedProfile ??= await _loadAiProfile(uid);
        profile = cachedProfile;
      }
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Profile load failed: $e');
    }

    String? cvContent;
    if (editor.state.linkedCvId != null) {
      cvContent = await editor.getLinkedCvContent();
    }

    final hasUsefulProfile = profile != null &&
        profile.fullName.isNotEmpty &&
        profile.experiences.isNotEmpty;
    final hasUsefulCv = cvContent != null && cvContent.trim().length > 30;

    if (!hasUsefulProfile && !hasUsefulCv) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'Add a Career Profile or link a CV with content before using AI Compose.',
      );
      return;
    }

    profile ??= const AiProfileModel();

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

      int filled = 0;
      for (final item in items) {
        if (!item.isText || item.controller == null) continue;
        final sectionKey = item.sectionType.key;
        final sectionContent = content[sectionKey];
        if (sectionContent == null) continue;
        if (sectionContent is! Map) continue;

        final styles = _extractStyles(item.controller!.document);

        try {
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
      _bumpDashboardCounter(tool: 'coverLetter', isRewrite: false);
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

  Future<void> fillAllCvSections({
    required List<CanvasItem> items,
    String? cvId,
    String? cvTitle,
    String? templateId,
    String? profileId,
  }) async
  {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] fillAllCvSections');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }

    state = const ClaudeState(status: AiFillStatus.loading, activeOperation: 'fill');

    AiProfileModel? profile;
    try {
      profile = await _loadAiProfile(uid, profileId: profileId);
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Profile load failed: $e');
    }
    if (profile == null ||
        (profile.fullName.isEmpty && profile.experiences.isEmpty)) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'Career Profile is empty. Add data to your profile first.',
      );
      return;
    }

    final manifest = <Map<String, dynamic>>[];
    final keyToItem = <String, CanvasItem>{};
    int slot = 0;
    for (final item in items) {
      if (item.role == 'hero' ||
          item.role == 'top_band' ||
          item.role == 'signature' ||
          item.role == 'heading' ||
          item.role == 'underline') {
        continue;
      }
      if (!item.isText || item.controller == null) continue;
      if (!item.sectionType.isAutofillable) continue;

      final key = 's$slot';
      keyToItem[key] = item;
      manifest.add({
        'id': key,
        'sectionType': item.sectionType.key,
        'title': item.title,
        'kind': 'text',
      });
      slot++;
    }

    if (manifest.isEmpty) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'No fillable sections on this CV.',
      );
      return;
    }

    try {
      final content = await ClaudeService.aiFillSection(
        sectionType: 'all',
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
        tool: 'cv',
        documentId: cvId,
        documentTitle: cvTitle,
        templateId: templateId,
        sectionManifest: manifest,
      );

      if (!mounted) return;
      if (content == null) {
        state = const ClaudeState(
          status: AiFillStatus.error,
          error: 'AI returned no content. Add more profile data and try again.',
        );
        return;
      }

      debugPrint('🤖 [CV] returned keys: ${content.keys.toList()}');
      debugPrint('🤖 [CV] expected keys: ${keyToItem.keys.toList()}');

      int filled = 0;
      content.forEach((key, sec) {
        final item = keyToItem[key];
        if (item == null || sec is! Map) return;
        try {
          final styles = _extractStyles(item.controller!.document);
          item.controller!.updateSelection(
              const TextSelection.collapsed(offset: 0), ChangeSource.local);
          item.controller!.document = Document.fromJson(
              _buildStyledDelta(Map<String, dynamic>.from(sec), styles));
          filled++;
        } catch (e) {
          debugPrint('🤖 [ClaudeController] Apply failed for $key: $e');
        }
      });

      state = ClaudeState(
        status: AiFillStatus.done,
        streamedChars: filled,
      );
      _bumpDashboardCounter(tool: 'cv', isRewrite: false);
      debugPrint('🤖 [ClaudeController] fillAllCvSections OK — $filled filled');
    } catch (e) {
      if (!mounted) return;
      final isPaywall = e.toString().contains('limit') || e.toString().contains('Upgrade');
      state = ClaudeState(
        status: isPaywall ? AiFillStatus.paywalled : AiFillStatus.error,
        error: e.toString(),
      );
    }
  }


  Future<void> composeRawAllCvSections({
    required List<CanvasItem> items,
    String? profileId,
  }) async
  {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] composeRawAllCvSections');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }

    state = const ClaudeState(status: AiFillStatus.loading, activeOperation: 'fill');

    AiProfileModel? profile;
    try {
      profile = await _loadAiProfile(uid, profileId: profileId);
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Profile load failed: $e');
    }
    if (!mounted) return;
    if (profile == null ||
        (profile.fullName.isEmpty && profile.experiences.isEmpty)) {
      state = const ClaudeState(
        status: AiFillStatus.error,
        error: 'Career Profile is empty. Add data to your profile first.',
      );
      return;
    }

    try {
      final filled = SectionAutofill.fillAll(items, profile);
      state = ClaudeState(
        status: AiFillStatus.done,
        streamedChars: filled,
      );
      debugPrint('🤖 [ClaudeController] Raw fill-all OK — $filled sections');
    } catch (e) {
      state = ClaudeState(
        status: AiFillStatus.error,
        error: 'Could not fill sections: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RAW INSERT (no AI, no tokens — uses SectionAutofill)
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> composeRawFromProfile({
    required CanvasItem item,
    String? profileId,
  }) async
  {
    if (state.isActive) return;
    debugPrint('🤖 [ClaudeController] composeRawFromProfile(${item.title})');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.');
      return;
    }
    if (item.controller == null) return;

    state = ClaudeState(status: AiFillStatus.loading, activeItemId: item.id, activeOperation: 'fill');

    AiProfileModel? profile;
    try {
      profile = await _loadAiProfile(uid, profileId: profileId);
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Profile load failed: $e');
    }

    if (!mounted) return;

    if (profile == null ||
        (profile.fullName.isEmpty && profile.experiences.isEmpty)) {
      state = ClaudeState(
        status: AiFillStatus.error,
        activeItemId: item.id,
        error: 'Career Profile is empty. Add data to your profile first.',
      );
      return;
    }

    try {
      final filled = SectionAutofill.fillAll([item], profile);
      if (filled == 0) {
        state = ClaudeState(
          status: AiFillStatus.error,
          activeItemId: item.id,
          error: 'No data available for this section type. Try AI Compose instead.',
        );
        return;
      }
      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: item.id,
        streamedChars: item.controller!.document.toPlainText().length,
      );
      debugPrint('🤖 [ClaudeController] Raw insert OK');
    } catch (e) {
      debugPrint('🤖 [ClaudeController] Raw insert failed: $e');
      state = ClaudeState(
        status: AiFillStatus.error,
        activeItemId: item.id,
        error: 'Could not insert data: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AI Refine
  // ═══════════════════════════════════════════════════════════════════════

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
        error: 'Section is empty — nothing to rewrite. Use AI Compose first.',
      );
      return;
    }

    state = ClaudeState(status: AiFillStatus.loading, activeItemId: itemId, activeOperation: 'rewrite');

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

      _applyRewrittenText(controller, rewritten, styles);

      state = ClaudeState(
        status: AiFillStatus.done,
        activeItemId: itemId,
        streamedChars: controller.document.toPlainText().length,
      );
      _bumpDashboardCounter(tool: tool, isRewrite: true);
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

  void _applyRewrittenText(
      QuillController controller, String newText, StyleSet styles)
  {
    try {
      final existingOps = controller.document.toDelta().toJson();

      Map<String, dynamic> defaultAttrs = {};
      for (final op in existingOps) {
        final insert = op['insert'];
        if (insert is String && insert.trim().length > 3) {
          defaultAttrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
          if (!defaultAttrs.containsKey('bold')) break;
        }
      }

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
      final len = controller.document.length;
      if (len > 1) controller.replaceText(0, len - 1, '', null);
      controller.document.insert(0, newText.trimRight());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STYLE EXTRACTION (shared by Fill + Rewrite)
  // ═══════════════════════════════════════════════════════════════════════

  StyleSet _extractStyles(Document doc) {
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

    return StyleSet(headingAttrs: heading, titleAttrs: title, bodyAttrs: body);
  }

  double _parseSize(dynamic s) =>
      s == null ? 11 : double.tryParse(s.toString().replaceAll('pt', '')) ?? 11;

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD STYLED DELTA (for AI Compose)
  // ═══════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _buildStyledDelta(
      Map<String, dynamic> content, StyleSet styles)
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
  void invalidateProfile() => cachedProfile = null;

  /// Load a specific Career Profile by ID, or the default if [profileId]
  /// is null. Results are NOT cached across IDs — we always re-fetch when
  /// the ID changes so the editor can switch profiles mid-session.
  Future<AiProfileModel?> _loadAiProfile(String uid, {String? profileId}) async {
    if (profileId != null) {
      debugPrint('🤖 [ClaudeController] Loading specific profile $profileId');
      try {
        final doc = await FirebaseService.getAiProfileById(uid, profileId);
        if (!doc.exists) return null;
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return AiProfileModel.fromJson(data);
      } catch (e) {
        debugPrint('🤖 [ClaudeController] Profile load by ID failed: $e');
        return null;
      }
    }
    debugPrint('🤖 [ClaudeController] Loading default Career Profile for $uid');
    return await FirebaseService.getDefaultAiProfile(uid);
  }
}

// ─── PROVIDER ────────────────────────────────────────────────────────────

final claudeControllerProvider =
StateNotifierProvider.autoDispose<ClaudeController, ClaudeState>(
      (ref) => ClaudeController(ref),
);