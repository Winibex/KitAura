// lib/features/cover_letter/editor/controller/cl_editor_controller.dart
//
// CHANGES FROM PREVIOUS VERSION:
//   1. Added job detail fields (hiringManagerName, hiringManagerTitle, companyAddress, etc.)
//   2. Added linkedCvId field + method to load linked CV content
//   3. Added fillAllSections() method for "AI Generate All"
//   4. Job details save/load with Firestore document
//   5. Removed "Generate from my profile" — replaced with context-aware generation

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/canvas/engine/canvas_controller.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../../shared/services/paywall_service.dart';
import '../../template/data/cl_template_data.dart';
import 'cl_section_autofill.dart';

class ClEditorState {
  final bool isTemplateLoading;
  final bool isSaving;
  final bool isSaved;
  final bool isExporting;
  final String title;
  final String? firestoreDocId;
  final String? error;
  final String? paywallMessage;

  // ── Job details ──────────────────────────────────────────────────
  final String? targetCompany;
  final String? targetRole;
  final String? hiringManagerName;
  final String? hiringManagerTitle;
  final String? companyAddress;
  final String? companyCityStateZip;
  final String? jobDescription;
  final String? linkedCvId;

  /// ID of the Career Profile picked for AI generation on this letter.
  final String? selectedProfileId;
  /// Display name of the selected profile. Cached for the right panel.
  final String? selectedProfileName;

  const ClEditorState({
    this.isTemplateLoading = true,
    this.isSaving = false,
    this.isSaved = true,
    this.isExporting = false,
    this.title = 'Untitled Cover Letter',
    this.firestoreDocId,
    this.error,
    this.paywallMessage,
    this.targetCompany,
    this.targetRole,
    this.hiringManagerName,
    this.hiringManagerTitle,
    this.companyAddress,
    this.companyCityStateZip,
    this.jobDescription,
    this.linkedCvId,
    this.selectedProfileId,
    this.selectedProfileName,
  });

  /// True if user has filled enough details for AI generation
  bool get hasJobDetails =>
      (targetCompany ?? '').isNotEmpty ||
      (targetRole ?? '').isNotEmpty ||
      (jobDescription ?? '').isNotEmpty;

  ClEditorState copyWith({
    bool? isTemplateLoading,
    bool? isSaving,
    bool? isSaved,
    bool? isExporting,
    String? title,
    String? firestoreDocId,
    String? error,
    String? paywallMessage,
    String? targetCompany,
    String? targetRole,
    String? hiringManagerName,
    String? hiringManagerTitle,
    String? companyAddress,
    String? companyCityStateZip,
    String? jobDescription,
    String? linkedCvId,
    String? selectedProfileId,
    String? selectedProfileName,
  }) {
    return ClEditorState(
      isTemplateLoading: isTemplateLoading ?? this.isTemplateLoading,
      isSaving: isSaving ?? this.isSaving,
      isSaved: isSaved ?? this.isSaved,
      isExporting: isExporting ?? this.isExporting,
      title: title ?? this.title,
      firestoreDocId: firestoreDocId ?? this.firestoreDocId,
      error: error,
      paywallMessage: paywallMessage,
      targetCompany: targetCompany ?? this.targetCompany,
      targetRole: targetRole ?? this.targetRole,
      hiringManagerName: hiringManagerName ?? this.hiringManagerName,
      hiringManagerTitle: hiringManagerTitle ?? this.hiringManagerTitle,
      companyAddress: companyAddress ?? this.companyAddress,
      companyCityStateZip: companyCityStateZip ?? this.companyCityStateZip,
      jobDescription: jobDescription ?? this.jobDescription,
      linkedCvId: linkedCvId ?? this.linkedCvId,
      selectedProfileId: selectedProfileId ?? this.selectedProfileId,
      selectedProfileName: selectedProfileName ?? this.selectedProfileName,
    );
  }
}

class ClEditorController extends ChangeNotifier {
  final CanvasController canvas;

  /// Called once after the cover letter is created in Firestore.
  final void Function({
  required String docId,
  required String title,
  required String templateId,
  })? onDocCreated;

  /// Called after a successful PDF export.
  final void Function()? onExported;

  Timer? _autoSaveTimer;
  ClEditorState _state = const ClEditorState();

  ClEditorState get state => _state;

  set state(ClEditorState newState) {
    if (_disposed) return;
    _state = newState;
    notifyListeners();
  }

  ClEditorController({
    required this.canvas,
    this.onDocCreated,
    this.onExported,
  });

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  bool _disposed = false;
  String _templateId = 'custom';

  @override
  void dispose() {
    _disposed = true;
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  // ─── INITIALIZATION ───────────────────────────────────────────────────

  bool _initialized = false;
  Future<void> initialize(String docId) async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('✉️ [ClEditor] Initializing with docId: $docId');

    final info = ClTemplateData.getInfo(docId);
    if (docId == 'blank') {
      _templateId = 'blank';
      state = state.copyWith(title: 'Untitled Cover Letter');
      canvas.init();
    } else if (info != null) {
      _templateId = docId;
      state = state.copyWith(title: '${info.label} Cover Letter');
      final json = await ClTemplateData.loadTemplateJson(docId);
      canvas.applyTemplateJson(json);
    } else {
      state = state.copyWith(firestoreDocId: docId);
      await _loadFromFirestore(docId);

      await canvas.preloadFonts();
      state = state.copyWith(isTemplateLoading: false);
      debugPrint(
        '✉️ [ClEditor] Initialization complete (existing doc, no autofill)',
      );
      return;
    }

    await _tryAutofillFromProfile();
    await canvas.preloadFonts();
    state = state.copyWith(isTemplateLoading: false);
    debugPrint('✉️ [ClEditor] Initialization complete');
    _autoSave();
  }

  // ─── FIRESTORE LOAD ───────────────────────────────────────────────────

  Future<void> _loadFromFirestore(String docId) async {
    if (_uid == null) {
      canvas.init();
      return;
    }

    try {
      debugPrint('✉️ [ClEditor] Loading from Firestore: $docId');
      final doc = await FirebaseService.getCoverLetter(_uid!, docId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        state = state.copyWith(
          title: data['title'] ?? 'Untitled Cover Letter',
          targetCompany: data['targetCompany'],
          targetRole: data['targetRole'],
          hiringManagerName: data['hiringManagerName'],
          hiringManagerTitle: data['hiringManagerTitle'],
          companyAddress: data['companyAddress'],
          companyCityStateZip: data['companyCityStateZip'],
          jobDescription: data['jobDescription'],
          linkedCvId: data['linkedCvId'],
          selectedProfileId: data['selectedProfileId'] as String?,
          selectedProfileName: data['selectedProfileName'] as String?,
        );

        final canvasData = <String, dynamic>{
          'canvasBackground': data['canvasBackground'] ?? '#FFFFFF',
          'items': data['items'] ?? [],
        };
        await canvas.loadFromJson(canvasData);
      } else {
        canvas.init();
      }
    } catch (e) {
      debugPrint('✉️ [ClEditor] Load failed: $e');
      state = state.copyWith(error: 'Failed to load cover letter');
      canvas.init();
    }
  }

  // ─── PROFILE AUTOFILL ─────────────────────────────────────────────────

  Future<void> _tryAutofillFromProfile() async {
    if (_uid == null) return;

    try {
      final profile = await FirebaseService.getDefaultAiProfile(_uid!);
      if (_disposed) return;
      if (profile == null || profile.fullName.isEmpty) return;

      final filled = ClSectionAutofill.fillAll(canvas.items, profile);
      if (filled > 0) {
        debugPrint('✉️ [ClEditor] Autofilled $filled sections from profile');
      }
    } catch (e) {
      debugPrint('✉️ [ClEditor] Autofill failed (non-critical): $e');
    }
  }

  void selectCareerProfile({
    required String profileId,
    required String profileName,
  })
  {
    state = state.copyWith(
      selectedProfileId: profileId,
      selectedProfileName: profileName,
    );
    debugPrint('✉️ [ClEditor] Career Profile selected: $profileName ($profileId)');
    markDirty();
  }

  // ─── JOB DETAILS ──────────────────────────────────────────────────────

  void updateJobDetails({
    String? targetCompany,
    String? targetRole,
    String? hiringManagerName,
    String? hiringManagerTitle,
    String? companyAddress,
    String? companyCityStateZip,
    String? jobDescription,
    String? linkedCvId,
  })
  {
    state = state.copyWith(
      targetCompany: targetCompany ?? state.targetCompany,
      targetRole: targetRole ?? state.targetRole,
      hiringManagerName: hiringManagerName ?? state.hiringManagerName,
      hiringManagerTitle: hiringManagerTitle ?? state.hiringManagerTitle,
      companyAddress: companyAddress ?? state.companyAddress,
      companyCityStateZip: companyCityStateZip ?? state.companyCityStateZip,
      jobDescription: jobDescription ?? state.jobDescription,
      linkedCvId: linkedCvId ?? state.linkedCvId,
    );
    markDirty();
  }

  void clearLinkedCv() {
    state = ClEditorState(
      isTemplateLoading: state.isTemplateLoading,
      isSaving: state.isSaving,
      isSaved: state.isSaved,
      isExporting: state.isExporting,
      title: state.title,
      firestoreDocId: state.firestoreDocId,
      error: state.error,
      paywallMessage: state.paywallMessage,
      targetCompany: state.targetCompany,
      targetRole: state.targetRole,
      hiringManagerName: state.hiringManagerName,
      hiringManagerTitle: state.hiringManagerTitle,
      companyAddress: state.companyAddress,
      companyCityStateZip: state.companyCityStateZip,
      jobDescription: state.jobDescription,
      linkedCvId: null,
    );
    markDirty();
  }

  /// Load plain text content from a linked CV for AI context.
  Future<String?> getLinkedCvContent() async {
    final cvId = state.linkedCvId;
    if (cvId == null || _uid == null) return null;

    try {
      final doc = await FirebaseService.getCV(_uid!, cvId);
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];

      // Extract plain text from all text sections in the CV
      final buffer = StringBuffer();
      for (final item in items) {
        if (item is! Map) continue;
        if (item['type'] != 'textSection') continue;
        final delta = item['delta'] as List<dynamic>?;
        if (delta == null) continue;
        final title = item['title'] ?? '';
        if (title.isNotEmpty) buffer.writeln('--- $title ---');
        for (final op in delta) {
          if (op is Map && op['insert'] is String) {
            buffer.write(op['insert']);
          }
        }
        buffer.writeln();
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('✉️ [ClEditor] Failed to load linked CV: $e');
      return null;
    }
  }

  /// Get list of user's CVs for the dropdown.
  Future<List<CvDropdownItem>> getUserCvs() async {
    if (_uid == null) return [];
    try {
      final snapshot = await FirebaseService.getUserCVs(_uid!);
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return CvDropdownItem(
          id: doc.id,
          title: data['title'] ?? 'Untitled CV',
        );
      }).toList();
    } catch (e) {
      debugPrint('✉️ [ClEditor] Failed to load CVs: $e');
      return [];
    }
  }

  // ─── TITLE ────────────────────────────────────────────────────────────

  void updateTitle(String newTitle) {
    final title = newTitle.trim().isEmpty
        ? 'Untitled Cover Letter'
        : newTitle.trim();
    state = state.copyWith(title: title);
    markDirty();
  }

  // ─── AUTO-SAVE ────────────────────────────────────────────────────────

  void markDirty() {
    if (state.isSaved) {
      debugPrint('✉️ [ClEditor] Marked dirty — will auto-save in 2s');
    }
    state = state.copyWith(isSaved: false);
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
  }

  Future<void> _autoSave() async {
    if (_disposed) return;
    if (state.isSaving || state.isTemplateLoading) return;
    if (_uid == null) return;

    state = state.copyWith(isSaving: true);
    debugPrint('✉️ [ClEditor] Auto-saving...');

    try {
      final data = _toFirestoreJson();

      if (state.firestoreDocId != null) {
        await FirebaseService.updateCoverLetter(
          _uid!,
          state.firestoreDocId!,
          data,
        );
      } else {
        final check = await PaywallService.canCreateCoverLetter();
        if (_disposed) return;
        if (!check.allowed) {
          state = state.copyWith(
            isSaving: false,
            paywallMessage: check.message,
          );
          return;
        }
        data['createdAt'] = FieldValue.serverTimestamp();
        final docRef = await FirebaseService.createCoverLetter(_uid!, data);
        if (_disposed) return;
        state = state.copyWith(firestoreDocId: docRef.id);
        debugPrint('✉️ [ClEditor] Created new cover letter: ${docRef.id}');

        ClaudeService.trackDocCreated(
          tool: 'coverLetter',
          documentId: docRef.id,
          documentTitle: state.title,
        );
        // Notify dashboard
        onDocCreated?.call(
          docId: docRef.id,
          title: state.title,
          templateId: _templateId,
        );
      }

      if (_disposed) return;
      state = state.copyWith(isSaved: true, isSaving: false, error: null);
      debugPrint('✉️ [ClEditor] Auto-save complete');

      if (!state.isSaved) {
        _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
      }
    } catch (e) {
      if (_disposed) return;
      debugPrint('✉️ [ClEditor] Auto-save failed: $e');
      state = state.copyWith(isSaving: false, error: 'Save failed: $e');
    }
  }

  Future<void> saveNow() async => await _autoSave();

  // ─── FIRESTORE JSON ───────────────────────────────────────────────────

  Map<String, dynamic> _toFirestoreJson() {
    final data = canvas.toFirestoreJson(_uid!, state.title);
    data['title'] = state.title;
    data['targetCompany'] = state.targetCompany;
    data['targetRole'] = state.targetRole;
    data['hiringManagerName'] = state.hiringManagerName;
    data['hiringManagerTitle'] = state.hiringManagerTitle;
    data['companyAddress'] = state.companyAddress;
    data['companyCityStateZip'] = state.companyCityStateZip;
    data['jobDescription'] = state.jobDescription;
    data['linkedCvId'] = state.linkedCvId;
    data['selectedProfileId'] = state.selectedProfileId;
    data['selectedProfileName'] = state.selectedProfileName;
    return data;
  }

  // ─── EXPORT PDF ───────────────────────────────────────────────────────

  Future<bool> trackExport() async {
    if (state.firestoreDocId == null) {
      await _autoSave();
    }

    state = state.copyWith(isExporting: true);

    try {
      await ClaudeService.trackExport(
        tool: 'coverLetter',
        documentId: state.firestoreDocId,
        documentTitle: state.title,
      );
      state = state.copyWith(isExporting: false);
      onExported?.call();
      return true;
    } on FirebaseFunctionsException catch (e) {
      state = state.copyWith(isExporting: false);
      if (e.code == 'resource-exhausted') {
        state = state.copyWith(paywallMessage: e.message);
        return false;
      }
      state = state.copyWith(error: 'Export failed: ${e.message}');
      return false;
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        error:
            'Something went wrong. Please check your connection and try again.',
      );
      return false;
    }
  }

  void clearPaywallMessage() {
    state = state.copyWith(paywallMessage: null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Simple model for the CV dropdown in the CL editor.
class CvDropdownItem {
  final String id;
  final String title;
  const CvDropdownItem({required this.id, required this.title});
}
