// lib/features/cv/editor/controller/cv_editor_controller.dart
//
// MVC controller for the CV editor screen.
// Handles: template loading, auto-save, Firestore CRUD, profile autofill,
// export tracking, title management, AND the active Career Profile selection.

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
import '../../templates/data/cv_template_data.dart';
import 'section_autofill.dart';

class CvEditorState {
  final bool isTemplateLoading;
  final bool isSaving;
  final bool isSaved;
  final bool isExporting;
  final String title;
  final String? firestoreDocId;
  final String? error;
  final String? paywallMessage;

  /// ID of the Career Profile the user picked for AI Compose on this CV.
  /// Null = use the default profile (legacy behavior).
  final String? selectedProfileId;

  /// Display name of the selected profile. Cached so the right panel can
  /// show it without re-fetching.
  final String? selectedProfileName;

  const CvEditorState({
    this.isTemplateLoading = true,
    this.isSaving = false,
    this.isSaved = true,
    this.isExporting = false,
    this.title = 'Untitled CV',
    this.firestoreDocId,
    this.error,
    this.paywallMessage,
    this.selectedProfileId,
    this.selectedProfileName,
  });

  CvEditorState copyWith({
    bool? isTemplateLoading,
    bool? isSaving,
    bool? isSaved,
    bool? isExporting,
    String? title,
    String? firestoreDocId,
    String? error,
    String? paywallMessage,
    String? selectedProfileId,
    String? selectedProfileName,
    bool clearProfile = false,
  }) {
    return CvEditorState(
      isTemplateLoading: isTemplateLoading ?? this.isTemplateLoading,
      isSaving: isSaving ?? this.isSaving,
      isSaved: isSaved ?? this.isSaved,
      isExporting: isExporting ?? this.isExporting,
      title: title ?? this.title,
      firestoreDocId: firestoreDocId ?? this.firestoreDocId,
      error: error,
      paywallMessage: paywallMessage,
      selectedProfileId: clearProfile
          ? null
          : (selectedProfileId ?? this.selectedProfileId),
      selectedProfileName: clearProfile
          ? null
          : (selectedProfileName ?? this.selectedProfileName),
    );
  }
}

class CvEditorController extends ChangeNotifier {
  final CanvasController canvas;
  Timer? _autoSaveTimer;
  CvEditorState _state = const CvEditorState();
  CvEditorState get state => _state;

  set state(CvEditorState newState) {
    if (_disposed) return;
    _state = newState;
    notifyListeners();
  }

  CvEditorController({required this.canvas});

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool _disposed = false;

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
    debugPrint('📝 [CvEditor] Initializing with docId: $docId');

    final info = CvTemplateData.getInfo(docId);
    if (docId == 'blank') {
      state = state.copyWith(title: 'Untitled CV');
      canvas.init();
    } else if (info != null) {
      state = state.copyWith(title: '${info.label} CV');
      final json = await CvTemplateData.loadTemplateJson(docId);
      canvas.applyTemplateJson(json);
    } else {
      // Firestore document — already has user's content
      state = state.copyWith(firestoreDocId: docId);
      await _loadFromFirestore(docId);
      await canvas.preloadFonts();
      state = state.copyWith(isTemplateLoading: false);
      debugPrint('📝 [CvEditor] Initialization complete (existing doc)');
      return;
    }

    // Auto-fill is NO LONGER triggered on template open.
    // Users explicitly choose a Career Profile + click "Just Insert My Data"
    // or "Generate with AI" in the right panel.
    await canvas.preloadFonts();
    state = state.copyWith(isTemplateLoading: false);
    debugPrint('📝 [CvEditor] Initialization complete');
    // Auto-save initial state
    _autoSave();
  }

  // ─── FIRESTORE LOAD ───────────────────────────────────────────────────

  Future<void> _loadFromFirestore(String docId) async {
    if (_uid == null) {
      canvas.init();
      return;
    }
    try {
      debugPrint('📝 [CvEditor] Loading from Firestore: $docId');
      final doc = await FirebaseService.getCV(_uid!, docId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        state = state.copyWith(
          title: data['title'] ?? 'Untitled CV',
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
      debugPrint('📝 [CvEditor] Load failed: $e');
      state = state.copyWith(error: 'Failed to load CV');
      canvas.init();
    }
  }

  // ─── PROFILE AUTOFILL ─────────────────────────────────────────────────

  Future<void> _tryAutofillFromProfile() async {
    if (_uid == null) return;
    try {
      final doc = await FirebaseService.getAiProfile(_uid!);
      if (!doc.exists) return;
      final profile = AiProfileModel.fromJson(
        doc.data() as Map<String, dynamic>,
      );
      if (profile.fullName.isEmpty && profile.experiences.isEmpty) return;
      final filled = SectionAutofill.fillAll(canvas.items, profile);
      if (filled > 0) {
        debugPrint('📝 [CvEditor] Autofilled $filled sections from profile');
      }
    } catch (e) {
      debugPrint('📝 [CvEditor] Autofill failed (non-critical): $e');
    }
  }

  // ─── CAREER PROFILE SELECTION ─────────────────────────────────────────

  /// Called when the user picks a Career Profile from the right panel
  /// dropdown. Persists the choice to the CV's Firestore document.
  void selectCareerProfile({
    required String profileId,
    required String profileName,
  }) {
    state = state.copyWith(
      selectedProfileId: profileId,
      selectedProfileName: profileName,
    );
    debugPrint(
      '📝 [CvEditor] Career Profile selected: $profileName ($profileId)',
    );
    markDirty(); // triggers auto-save, which persists the new fields
  }

  /// Clear the explicitly-chosen profile (reverts to using the default).
  void clearCareerProfile() {
    state = state.copyWith(clearProfile: true);
    debugPrint('📝 [CvEditor] Career Profile cleared — will use default');
    markDirty();
  }

  // ─── TITLE ────────────────────────────────────────────────────────────

  void updateTitle(String newTitle) {
    final title = newTitle.trim().isEmpty ? 'Untitled CV' : newTitle.trim();
    state = state.copyWith(title: title);
    markDirty();
  }

  // ─── AUTO-SAVE ────────────────────────────────────────────────────────

  void markDirty() {
    if (state.isSaved) {
      debugPrint('📝 [CvEditor] Marked dirty — will auto-save in 2s');
    }
    state = state.copyWith(isSaved: false);
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
  }

  Future<void> _autoSave() async {
    if (state.isSaving || state.isTemplateLoading) return;
    if (_uid == null) return;
    state = state.copyWith(isSaving: true);
    debugPrint('📝 [CvEditor] Auto-saving...');
    try {
      final data = canvas.toFirestoreJson(_uid!, state.title);
      data['title'] = state.title;
      // Persist the Career Profile selection alongside the canvas content.
      data['selectedProfileId'] = state.selectedProfileId;
      data['selectedProfileName'] = state.selectedProfileName;
      if (state.firestoreDocId != null) {
        await FirebaseService.updateCV(_uid!, state.firestoreDocId!, data);
      } else {
        final check = await PaywallService.canCreateCV();
        if (!check.allowed) {
          state = state.copyWith(
            isSaving: false,
            paywallMessage: check.message,
          );
          return;
        }
        data['createdAt'] = FieldValue.serverTimestamp();
        final docRef = await FirebaseService.createCV(_uid!, data);
        state = state.copyWith(firestoreDocId: docRef.id);
        debugPrint('📝 [CvEditor] Created new CV: ${docRef.id}');
        ClaudeService.trackDocCreated(
          tool: 'cv',
          documentId: docRef.id,
          documentTitle: state.title,
        );
      }
      state = state.copyWith(isSaved: true, isSaving: false, error: null);
      debugPrint('📝 [CvEditor] Auto-save complete');
      if (!state.isSaved) {
        _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
      }
    } catch (e) {
      debugPrint('📝 [CvEditor] Auto-save failed: $e');
      state = state.copyWith(isSaving: false, error: 'Save failed: $e');
    }
  }

  Future<void> saveNow() async => await _autoSave();

  // ─── EXPORT PDF ───────────────────────────────────────────────────────

  Future<bool> trackExport() async {
    if (state.firestoreDocId == null) {
      await _autoSave();
    }
    state = state.copyWith(isExporting: true);
    try {
      await ClaudeService.trackExport(
        tool: 'cv',
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
