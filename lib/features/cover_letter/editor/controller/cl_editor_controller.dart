// lib/features/cover_letter/editor/controller/cl_editor_controller.dart
//
// MVC controller for the Cover Letter editor screen.
// Handles: template loading, auto-save, Firestore CRUD, profile autofill,
// export tracking, title management, target company/role.
// Mirrors CvEditorController — same patterns, CL-specific collection + fields.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/canvas/engine/canvas_controller.dart';
import '../../../../shared/models/ai_profile_model.dart';
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
  final String? targetCompany;
  final String? targetRole;
  final String? error;
  final String? paywallMessage;

  const ClEditorState({
    this.isTemplateLoading = true,
    this.isSaving = false,
    this.isSaved = true,
    this.isExporting = false,
    this.title = 'Untitled Cover Letter',
    this.firestoreDocId,
    this.targetCompany,
    this.targetRole,
    this.error,
    this.paywallMessage,
  });

  ClEditorState copyWith({
    bool? isTemplateLoading,
    bool? isSaving,
    bool? isSaved,
    bool? isExporting,
    String? title,
    String? firestoreDocId,
    String? targetCompany,
    String? targetRole,
    String? error,
    String? paywallMessage,
  }) {
    return ClEditorState(
      isTemplateLoading: isTemplateLoading ?? this.isTemplateLoading,
      isSaving: isSaving ?? this.isSaving,
      isSaved: isSaved ?? this.isSaved,
      isExporting: isExporting ?? this.isExporting,
      title: title ?? this.title,
      firestoreDocId: firestoreDocId ?? this.firestoreDocId,
      targetCompany: targetCompany ?? this.targetCompany,
      targetRole: targetRole ?? this.targetRole,
      error: error,
      paywallMessage: paywallMessage,
    );
  }
}

class ClEditorController extends ChangeNotifier {
  final CanvasController canvas;
  Timer? _autoSaveTimer;
  ClEditorState _state = const ClEditorState();

  ClEditorState get state => _state;

  set state(ClEditorState newState) {
    _state = newState;
    notifyListeners();
  }

  ClEditorController({required this.canvas});

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
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
      state = state.copyWith(title: 'Untitled Cover Letter');
      canvas.init();
    } else if (info != null) {
      // New template — load JSON + autofill
      state = state.copyWith(title: '${info.label} Cover Letter');
      final json = await ClTemplateData.loadTemplateJson(docId);
      canvas.applyTemplateJson(json);
    } else {
      // Existing Firestore document — load content, skip autofill
      state = state.copyWith(firestoreDocId: docId);
      await _loadFromFirestore(docId);

      await canvas.preloadFonts();
      state = state.copyWith(isTemplateLoading: false);
      debugPrint('✉️ [ClEditor] Initialization complete (existing doc, no autofill)');
      return;
    }

    // Autofill only for NEW templates
    await _tryAutofillFromProfile();

    await canvas.preloadFonts();
    state = state.copyWith(isTemplateLoading: false);
    debugPrint('✉️ [ClEditor] Initialization complete');

    _autoSave();
  }

  // ─── FIRESTORE LOAD ───────────────────────────────────────────────────

  Future<void> _loadFromFirestore(String docId) async {
    if (_uid == null) { canvas.init(); return; }

    try {
      debugPrint('✉️ [ClEditor] Loading from Firestore: $docId');
      final doc = await FirebaseService.getCoverLetter(_uid!, docId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        state = state.copyWith(
          title: data['title'] ?? 'Untitled Cover Letter',
          targetCompany: data['targetCompany'],
          targetRole: data['targetRole'],
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
      final doc = await FirebaseService.getAiProfile(_uid!);
      if (!doc.exists) return;

      final profile = AiProfileModel.fromJson(doc.data() as Map<String, dynamic>);
      if (profile.fullName.isEmpty) return;

      final filled = ClSectionAutofill.fillAll(canvas.items, profile);
      if (filled > 0) {
        debugPrint('✉️ [ClEditor] Autofilled $filled sections from profile');
      }
    } catch (e) {
      debugPrint('✉️ [ClEditor] Autofill failed (non-critical): $e');
    }
  }

  // ─── TITLE ────────────────────────────────────────────────────────────

  void updateTitle(String newTitle) {
    final title = newTitle.trim().isEmpty ? 'Untitled Cover Letter' : newTitle.trim();
    state = state.copyWith(title: title);
    markDirty();
  }

  // ─── TARGET COMPANY / ROLE ────────────────────────────────────────────

  void updateTargetCompany(String value) {
    state = state.copyWith(targetCompany: value.trim().isEmpty ? null : value.trim());
    markDirty();
  }

  void updateTargetRole(String value) {
    state = state.copyWith(targetRole: value.trim().isEmpty ? null : value.trim());
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
    if (state.isSaving || state.isTemplateLoading) return;
    if (_uid == null) return;

    state = state.copyWith(isSaving: true);
    debugPrint('✉️ [ClEditor] Auto-saving...');

    try {
      final data = _toFirestoreJson();

      if (state.firestoreDocId != null) {
        await FirebaseService.updateCoverLetter(_uid!, state.firestoreDocId!, data);
      } else {
        // Paywall check before creating
        final check = await PaywallService.canCreateCoverLetter();
        if (!check.allowed) {
          state = state.copyWith(
            isSaving: false,
            paywallMessage: check.message,
          );
          return;
        }
        data['createdAt'] = FieldValue.serverTimestamp();
        final docRef = await FirebaseService.createCoverLetter(_uid!, data);
        state = state.copyWith(firestoreDocId: docRef.id);
        debugPrint('✉️ [ClEditor] Created new cover letter: ${docRef.id}');

        // Track creation server-side (counters + transaction log)
       ClaudeService.trackDocCreated(
         tool: 'coverLetter',
         documentId: docRef.id,
         documentTitle: state.title,
       );
      }

      state = state.copyWith(isSaved: true, isSaving: false, error: null);
      debugPrint('✉️ [ClEditor] Auto-save complete');

      if (!state.isSaved) {
        _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
      }
    } catch (e) {
      debugPrint('✉️ [ClEditor] Auto-save failed: $e');
      state = state.copyWith(isSaving: false, error: 'Save failed: $e');
    }
  }

  Future<void> saveNow() async => await _autoSave();

  // ─── FIRESTORE JSON ───────────────────────────────────────────────────

  Map<String, dynamic> _toFirestoreJson() {
    final data = canvas.toFirestoreJson(_uid!, state.title);
    // Override CV-specific defaults with CL fields
    data['title'] = state.title;
    data['targetCompany'] = state.targetCompany;
    data['targetRole'] = state.targetRole;
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
        error: 'Something went wrong. Please check your connection and try again.',
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