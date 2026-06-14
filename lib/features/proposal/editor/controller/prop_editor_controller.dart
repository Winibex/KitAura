// lib/features/proposal/editor/controller/prop_editor_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/canvas/engine/canvas_controller.dart';
import '../../../../shared/models/client_profile_model.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../../shared/services/paywall_service.dart';
import '../../template/data/prop_template_data.dart';

class PropEditorState {
  final bool isTemplateLoading;
  final bool isSaving;
  final bool isSaved;
  final bool isExporting;
  final String title;
  final String? firestoreDocId;
  final String? error;
  final String? paywallMessage;

  // Proposal-specific
  final String? linkedClientId;
  final String? linkedCvId;
  final String? clientName;
  final String? projectScope;

  const PropEditorState({
    this.isTemplateLoading = true,
    this.isSaving = false,
    this.isSaved = true,
    this.isExporting = false,
    this.title = 'Untitled Proposal',
    this.firestoreDocId,
    this.error,
    this.paywallMessage,
    this.linkedClientId,
    this.linkedCvId,
    this.clientName,
    this.projectScope,
  });

  bool get hasClientLinked => linkedClientId != null;

  PropEditorState copyWith({
    bool? isTemplateLoading,
    bool? isSaving,
    bool? isSaved,
    bool? isExporting,
    String? title,
    String? firestoreDocId,
    String? error,
    String? paywallMessage,
    String? linkedClientId,
    String? linkedCvId,
    String? clientName,
    String? projectScope,
  }) {
    return PropEditorState(
      isTemplateLoading: isTemplateLoading ?? this.isTemplateLoading,
      isSaving: isSaving ?? this.isSaving,
      isSaved: isSaved ?? this.isSaved,
      isExporting: isExporting ?? this.isExporting,
      title: title ?? this.title,
      firestoreDocId: firestoreDocId ?? this.firestoreDocId,
      error: error,
      paywallMessage: paywallMessage,
      linkedClientId: linkedClientId ?? this.linkedClientId,
      linkedCvId: linkedCvId ?? this.linkedCvId,
      clientName: clientName ?? this.clientName,
      projectScope: projectScope ?? this.projectScope,
    );
  }
}

class PropEditorController extends ChangeNotifier {
  final CanvasController canvas;
  Timer? _autoSaveTimer;
  PropEditorState _state = const PropEditorState();

  PropEditorState get state => _state;

  set state(PropEditorState newState) {
    if (_disposed) return;
    _state = newState;
    notifyListeners();
  }

  PropEditorController({required this.canvas});

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
    debugPrint('📋 [PropEditor] Initializing with docId: $docId');

    final info = PropTemplateData.getInfo(docId);
    if (docId == 'blank') {
      state = state.copyWith(title: 'Untitled Proposal');
      canvas.init();
    } else if (info != null) {
      state = state.copyWith(title: info.label);
      final json = await PropTemplateData.loadTemplateJson(docId);
      canvas.applyTemplateJson(json);
    } else {
      // Existing Firestore document
      state = state.copyWith(firestoreDocId: docId);
      await _loadFromFirestore(docId);
      await canvas.preloadFonts();
      state = state.copyWith(isTemplateLoading: false);
      debugPrint('📋 [PropEditor] Initialization complete (existing doc)');
      return;
    }

    await canvas.preloadFonts();
    state = state.copyWith(isTemplateLoading: false);
    debugPrint('📋 [PropEditor] Initialization complete');
    _autoSave();
  }

  // ─── FIRESTORE LOAD ───────────────────────────────────────────────────

  Future<void> _loadFromFirestore(String docId) async {
    if (_uid == null) {
      canvas.init();
      return;
    }

    try {
      debugPrint('📋 [PropEditor] Loading from Firestore: $docId');
      final doc = await FirebaseService.getProposal(_uid!, docId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        state = state.copyWith(
          title: data['title'] ?? 'Untitled Proposal',
          linkedClientId: data['linkedClientId'],
          linkedCvId: data['linkedCvId'],
          clientName: data['clientName'],
          projectScope: data['projectScope'],
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
      debugPrint('📋 [PropEditor] Load failed: $e');
      state = state.copyWith(error: 'Failed to load proposal');
      canvas.init();
    }
  }

  // ─── CLIENT + CV LINKING ──────────────────────────────────────────────

  void linkClient(ClientProfileModel client) {
    state = state.copyWith(
      linkedClientId: client.id,
      clientName: client.clientName,
      projectScope: client.projectTitle,
    );
    markDirty();
  }

  void unlinkClient() {
    _state = PropEditorState(
      isTemplateLoading: state.isTemplateLoading,
      isSaving: state.isSaving,
      isSaved: false,
      isExporting: state.isExporting,
      title: state.title,
      firestoreDocId: state.firestoreDocId,
      error: state.error,
      paywallMessage: state.paywallMessage,
      linkedClientId: null,
      linkedCvId: state.linkedCvId,
      clientName: null,
      projectScope: null,
    );
    notifyListeners();
    _scheduleAutoSave();
  }

  void linkCv(String cvId) {
    state = state.copyWith(linkedCvId: cvId);
    markDirty();
  }

  void unlinkCv() {
    _state = PropEditorState(
      isTemplateLoading: state.isTemplateLoading,
      isSaving: state.isSaving,
      isSaved: false,
      isExporting: state.isExporting,
      title: state.title,
      firestoreDocId: state.firestoreDocId,
      error: state.error,
      paywallMessage: state.paywallMessage,
      linkedClientId: state.linkedClientId,
      linkedCvId: null,
      clientName: state.clientName,
      projectScope: state.projectScope,
    );
    notifyListeners();
    _scheduleAutoSave();
  }

  /// Load saved client profiles for dropdown.
  Future<List<ClientProfileModel>> getClientProfiles() async {
    if (_uid == null) return [];
    try {
      final snapshot = await FirebaseService.getClientProfiles(_uid!);
      return snapshot.docs
          .map((doc) => ClientProfileModel.fromJson(
          doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('📋 [PropEditor] Failed to load client profiles: $e');
      return [];
    }
  }

  /// Load user CVs for dropdown.
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
      debugPrint('📋 [PropEditor] Failed to load CVs: $e');
      return [];
    }
  }

  /// Load linked client profile for AI context.
  Future<ClientProfileModel?> getLinkedClient() async {
    final clientId = state.linkedClientId;
    if (clientId == null || _uid == null) return null;
    try {
      final doc =
      await FirebaseService.getClientProfileById(_uid!, clientId);
      if (!doc.exists) return null;
      return ClientProfileModel.fromJson(
          doc.id, doc.data() as Map<String, dynamic>);
    } catch (e) {
      debugPrint('📋 [PropEditor] Failed to load linked client: $e');
      return null;
    }
  }

  /// Extract plain text from linked CV for AI context.
  Future<String?> getLinkedCvContent() async {
    final cvId = state.linkedCvId;
    if (cvId == null || _uid == null) return null;
    try {
      final doc = await FirebaseService.getCV(_uid!, cvId);
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
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
      debugPrint('📋 [PropEditor] Failed to load linked CV: $e');
      return null;
    }
  }

  // ─── TITLE ────────────────────────────────────────────────────────────

  void updateTitle(String newTitle) {
    final title =
    newTitle.trim().isEmpty ? 'Untitled Proposal' : newTitle.trim();
    state = state.copyWith(title: title);
    markDirty();
  }

  // ─── AUTO-SAVE ────────────────────────────────────────────────────────

  void markDirty() {
    if (state.isSaved) {
      debugPrint('📋 [PropEditor] Marked dirty — will auto-save in 2s');
    }
    state = state.copyWith(isSaved: false);
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
  }

  Future<void> _autoSave() async {
    if (state.isSaving || state.isTemplateLoading) return;
    if (_uid == null) return;

    state = state.copyWith(isSaving: true);
    debugPrint('📋 [PropEditor] Auto-saving...');

    try {
      final data = _toFirestoreJson();

      if (state.firestoreDocId != null) {
        await FirebaseService.updateProposal(
          _uid!,
          state.firestoreDocId!,
          data,
        );
      } else {
        final check = await PaywallService.canCreateProposal();
        if (!check.allowed) {
          state = state.copyWith(
            isSaving: false,
            paywallMessage: check.message,
          );
          return;
        }
        data['createdAt'] = FieldValue.serverTimestamp();
        final docRef = await FirebaseService.createProposal(_uid!, data);
        state = state.copyWith(firestoreDocId: docRef.id);
        debugPrint('📋 [PropEditor] Created new proposal: ${docRef.id}');

        ClaudeService.trackDocCreated(
          tool: 'proposal',
          documentId: docRef.id,
          documentTitle: state.title,
        );
      }

      state = state.copyWith(isSaved: true, isSaving: false, error: null);
      debugPrint('📋 [PropEditor] Auto-save complete');

      if (!state.isSaved) {
        _scheduleAutoSave();
      }
    } catch (e) {
      debugPrint('📋 [PropEditor] Auto-save failed: $e');
      state = state.copyWith(isSaving: false, error: 'Save failed: $e');
    }
  }

  Future<void> saveNow() async => await _autoSave();

  // ─── FIRESTORE JSON ───────────────────────────────────────────────────

  Map<String, dynamic> _toFirestoreJson() {
    final data = canvas.toFirestoreJson(_uid!, state.title);
    data['title'] = state.title;
    data['linkedClientId'] = state.linkedClientId;
    data['linkedCvId'] = state.linkedCvId;
    data['clientName'] = state.clientName;
    data['projectScope'] = state.projectScope;
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
        tool: 'proposal',
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

/// Simple model for the CV dropdown.
class CvDropdownItem {
  final String id;
  final String title;
  const CvDropdownItem({required this.id, required this.title});
}