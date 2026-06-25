import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../dashboard/controller/dashboard_controller.dart';
import '../model/cv_summary_model.dart';

// Dashboard state
class CvDashboardState {
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

  CvDashboardState({
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

  CvDashboardState copyWith({
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
    return CvDashboardState(
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

class DashboardController extends StateNotifier<CvDashboardState> {
  DashboardController(this._ref) : super(CvDashboardState(isLoading: true));
  final Ref _ref;

  bool _hasLoaded = false;
  final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  Future<void> loadDashboard({bool force = false}) async {
    debugPrint("Loading CV Dashboard");
    if (_hasLoaded && !force) {
      if (state.isLoading) state = state.copyWith(isLoading: false);
      return;
    }
    if (_uid == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Load subscription data
      final subDoc = await FirebaseService.getSubscription(_uid!);
      if (!mounted) return;
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
      final limits = await FirebaseService.getPlanLimits(plan);
      if (!mounted) return;
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
        if (!mounted) return;

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

  Future<void> deleteCV(String cvId) async {
    String title = 'Untitled';
    try {
      final cv = state.cvs.firstWhere((c) => c.id == cvId);
      title = cv.title;
    } catch (_) {}

    try {
      // 1. Server first — only update state if it succeeds
      await FirebaseService.deleteCV(_uid!, cvId);
      if (!mounted) return;
      // 2. Server succeeded → update local state
      state = state.copyWith(
        cvs: state.cvs.where((c) => c.id != cvId).toList(),
      );

      // 3. Notify main dashboard (synchronous, won't fail)
      _ref.read(dashboardControllerProvider.notifier).removeRecentItem(
        id: cvId,
        type: 'cv',
      );

      // 4. Fire-and-forget tracking (don't wait, don't block)
      ClaudeService.trackDocDeleted(
        tool: 'cv',
        documentId: cvId,
        documentTitle: title,
      );
    } catch (e) {
      debugPrint('Delete CV failed: $e');
      // State was never updated, so nothing to roll back
    }
  }

  Future<void> renameCV(String cvId, String newTitle) async {
    try {
      await FirebaseService.updateCV(_uid!, cvId, {
        'title': newTitle,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      if (!mounted) return;
      // Server succeeded → update local state
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

      _ref.read(dashboardControllerProvider.notifier).updateRecentItemTitle(
        id: cvId,
        newTitle: newTitle,
      );
    } catch (e) {
      debugPrint('renameCV error: $e');
    }
  }

  /// Called by CV editor after a new CV is created.
  void addCv(CvSummaryModel cv) {
    state = state.copyWith(cvs: [cv, ...state.cvs]);
    _ref.read(dashboardControllerProvider.notifier).addRecentItem(
      id: cv.id,
      title: cv.title,
      type: 'cv',
      templateId: cv.templateId,
    );
  }

  /// Called by CV editor after CV is updated (title or content).
  void updateCv(String cvId, {String? newTitle}) {
    final updated = state.cvs.map((cv) {
      if (cv.id == cvId) {
        return CvSummaryModel(
          id: cv.id,
          title: newTitle ?? cv.title,
          thumbnailUrl: cv.thumbnailUrl,
          templateId: cv.templateId,
          updatedAt: DateTime.now(),
          createdAt: cv.createdAt,
        );
      }
      return cv;
    }).toList();
    state = state.copyWith(cvs: updated);

    if (newTitle != null) {
      _ref.read(dashboardControllerProvider.notifier).updateRecentItemTitle(
        id: cvId,
        newTitle: newTitle,
      );
    }
  }

  /// Bump AI usage counter on CV dashboard.
  void incrementAiUsage() {
    state = state.copyWith(aiUsageCount: state.aiUsageCount + 1);
    _ref.read(dashboardControllerProvider.notifier).incrementAiUsage();
  }

  /// Bump export counter on CV dashboard.
  void incrementExportCount() {
    state = state.copyWith(exportCount: state.exportCount + 1);
    _ref.read(dashboardControllerProvider.notifier).incrementExportCount();
  }
}

final cvDashboardControllerProvider =
StateNotifierProvider<DashboardController, CvDashboardState>(
      (ref) => DashboardController(ref),
);