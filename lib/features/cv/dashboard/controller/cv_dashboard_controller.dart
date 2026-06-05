import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/services/firebase_service.dart';
import '../model/cv_summary_model.dart';

// Dashboard state
class DashboardState {
  final bool isLoading;
  final String? error;
  final List<CvSummaryModel> cvs;
  final int exportCount;
  final int aiUsageCount;
  final String plan;

  // Limits from Firebase config/limits
  final int maxCvs;
  final int exportsPerMonth;
  final int aiFillsPerMonth;

  DashboardState({
    this.isLoading = false,
    this.error,
    this.cvs = const [],
    this.exportCount = 0,
    this.aiUsageCount = 0,
    this.plan = 'free',
    this.maxCvs = 3,
    this.exportsPerMonth = 3,
    this.aiFillsPerMonth = 15,
  });

  bool get isPro => plan == 'pro' || plan == 'trial';
  bool get canExport => isPro || exportCount < exportsPerMonth;
  bool get canCreateCV => isPro || cvs.length < maxCvs;

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    List<CvSummaryModel>? cvs,
    int? exportCount,
    int? aiUsageCount,
    String? plan,
    int? maxCvs,
    int? exportsPerMonth,
    int? aiFillsPerMonth,
  })
  {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      cvs: cvs ?? this.cvs,
      exportCount: exportCount ?? this.exportCount,
      aiUsageCount: aiUsageCount ?? this.aiUsageCount,
      plan: plan ?? this.plan,
      maxCvs: maxCvs ?? this.maxCvs,
      exportsPerMonth: exportsPerMonth ?? this.exportsPerMonth,
      aiFillsPerMonth: aiFillsPerMonth ?? this.aiFillsPerMonth,
    );
  }
}

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController() : super(DashboardState());

  bool _hasLoaded = false;

  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> loadDashboard({bool force = false}) async {
    if (_hasLoaded && !force) return; // Skip if already loaded
    if (_uid == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Load subscription data
      final subDoc = await FirebaseService.getSubscription(_uid!);
      String plan = 'free';
      int exportCount = 0;
      int aiUsageCount = 0;

      if (subDoc.exists) {
        final data = subDoc.data() as Map<String, dynamic>;
        plan = data['plan'] ?? 'free';
        exportCount = data['exportCount'] ?? 0;
        aiUsageCount = data['aiFillCount'] ?? 0;
      }

      // Load limits from config/limits (not hardcoded)
      int maxCvs = 3, maxExports = 3, maxAiFills = 15;
      final limits = await FirebaseService.getPlanLimits(state.plan);
      maxCvs = limits['maxCvs']!;
      maxExports = limits['exportsPerMonth']!;
      maxAiFills = limits['aiFillPerMonth']!;


      state = state.copyWith(
        plan: plan,
        exportCount: exportCount,
        aiUsageCount: aiUsageCount,
        maxCvs: maxCvs == -1 ? 999 : maxCvs,
        exportsPerMonth: maxExports == -1 ? 999 : maxExports,
        aiFillsPerMonth: maxAiFills == -1 ? 999 : maxAiFills,
      );

      // Load CVs
      List<CvSummaryModel> cvs = [];
      try {
        final cvsSnapshot = await FirebaseService.getUserCVs(_uid!);

        cvs = cvsSnapshot.docs
            .map((doc) => CvSummaryModel.fromJson(
            doc.id, doc.data() as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Firestore CVs query failed: $e');
      }

      _hasLoaded = true;
      state = state.copyWith(isLoading: false, cvs: cvs);
    } catch (e, stack) {
      debugPrint('loadDashboard error: $e\n$stack');
      state = state.copyWith(
        isLoading: false,
      );
    }
  }

  // REPLACE the `empty()` lookup with this:
  Future<void> deleteCV(String cvId) async {
    // Capture title BEFORE removing from state (for transaction log)
    String title = 'Untitled';
    try {
      final cv = state.cvs.firstWhere((c) => c.id == cvId);
      title = cv.title;
    } catch (_) {
      // CV not in state — fall through with default title
    }

    try {
      state = state.copyWith(cvs: state.cvs.where((c) => c.id != cvId).toList());
      await FirebaseService.deleteCV(_uid!, cvId);

      ClaudeService.trackDocDeleted(
        tool: 'cv',
        documentId: cvId,
        documentTitle: title,
      );
    } catch (e) {
      debugPrint('Delete CV failed: $e');
      await loadDashboard(force: true);
    }
  }

  Future<void> renameCV(String cvId, String newTitle) async {
    try {
      await FirebaseService.updateCV(_uid!, cvId, {
        'title': newTitle,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      final updated = state.cvs.map((cv) {
        if (cv.id == cvId) {
          return CvSummaryModel(
            id: cv.id,
            title: newTitle,
            thumbnailUrl: cv.thumbnailUrl,
            templateId: cv.templateId,
            updatedAt: DateTime.now(),
            createdAt: cv.createdAt,
          );
        }
        return cv;
      }).toList();
      state = state.copyWith(cvs: updated);
    } catch (e) {
      debugPrint('renameCV error: $e');
    }
  }
}

// Providers
final cvDashboardControllerProvider =
StateNotifierProvider<DashboardController, DashboardState>(
      (ref) => DashboardController(),
);