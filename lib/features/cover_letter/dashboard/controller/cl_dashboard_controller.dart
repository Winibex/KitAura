// lib/features/cover_letter/dashboard/controller/cl_dashboard_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../dashboard/controller/dashboard_controller.dart';
import '../model/cl_summary_model.dart';

class ClDashboardState {
  final bool isLoading;
  final String? error;
  final List<ClSummaryModel> coverLetters;
  final int exportCount;
  final int aiUsageCount;
  final String plan;

  // Limits from Firebase (not hardcoded)
  final int maxCoverLetters;
  final int exportsPerMonth;
  final int aiFillsPerMonth;

  ClDashboardState({
    this.isLoading = false,
    this.error,
    this.coverLetters = const [],
    this.exportCount = 0,
    this.aiUsageCount = 0,
    this.plan = 'free',
    this.maxCoverLetters = 3,
    this.exportsPerMonth = 3,
    this.aiFillsPerMonth = 15,
  });

  bool get isPro => plan == 'pro' || plan == 'trial';
  bool get canExport => isPro || exportCount < exportsPerMonth;
  bool get canCreateCL => isPro || coverLetters.length < maxCoverLetters;

  ClDashboardState copyWith({
    bool? isLoading,
    String? error,
    List<ClSummaryModel>? coverLetters,
    int? exportCount,
    int? aiUsageCount,
    String? plan,
    int? maxCoverLetters,
    int? exportsPerMonth,
    int? aiFillsPerMonth,
  })
  {
    return ClDashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      coverLetters: coverLetters ?? this.coverLetters,
      exportCount: exportCount ?? this.exportCount,
      aiUsageCount: aiUsageCount ?? this.aiUsageCount,
      plan: plan ?? this.plan,
      maxCoverLetters: maxCoverLetters ?? this.maxCoverLetters,
      exportsPerMonth: exportsPerMonth ?? this.exportsPerMonth,
      aiFillsPerMonth: aiFillsPerMonth ?? this.aiFillsPerMonth,
    );
  }
}

class ClDashboardController extends StateNotifier<ClDashboardState> {
  ClDashboardController(this._ref) : super(ClDashboardState(isLoading: true));
  final Ref _ref;

  bool _hasLoaded = false;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> loadDashboard({bool force = false}) async {
    debugPrint("Loading Cover Letter Dashboard");
    if (_hasLoaded && !force) {
      if (state.isLoading) state = state.copyWith(isLoading: false);
      return;
    }
    if (_uid == null) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Load subscription
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

      // Load limits from config/limits
      int maxCL = 3, maxExports = 3, maxAiFills = 15;
      final limits = await FirebaseService.getPlanLimits(state.plan);
      maxCL = limits['maxCoverLetters']!;
      maxExports = limits['exportsPerMonth']!;
      maxAiFills = limits['aiFillPerMonth']!;

      // Load cover letters
      List<ClSummaryModel> cls = [];
      try {
        final snapshot = await FirebaseService.getUserCoverLetters(_uid!);
        cls = snapshot.docs
            .map((doc) => ClSummaryModel.fromJson(doc.id, doc.data() as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Cover letters query failed: $e');
      }

      _hasLoaded = true;
      state = state.copyWith(
        isLoading: false,
        coverLetters: cls,
        plan: plan,
        exportCount: exportCount,
        aiUsageCount: aiUsageCount,
        maxCoverLetters: maxCL == -1 ? 999 : maxCL,
        exportsPerMonth: maxExports == -1 ? 999 : maxExports,
        aiFillsPerMonth: maxAiFills == -1 ? 999 : maxAiFills,
      );
    } catch (e, stack) {
      debugPrint('ClDashboard loadDashboard error: $e\n$stack');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> deleteCL(String clId) async {
    String title = 'Untitled';
    try {
      final cl = state.coverLetters.firstWhere((c) => c.id == clId);
      title = cl.title;
    } catch (_) {}

    try {

      // 1. Server first — only update state if it succeeds
      await FirebaseService.deleteCoverLetter(_uid!, clId);

      // 2. Server succeeded → update local state
      state = state.copyWith(
        coverLetters: state.coverLetters.where((c) => c.id != clId).toList(),
      );

      // 3. Notify main dashboard (synchronous, won't fail)
      _ref.read(dashboardControllerProvider.notifier).removeRecentItem(
        id: clId,
        type: 'coverLetter',
      );

      // 4. Fire-and-forget tracking (don't wait, don't block)
      ClaudeService.trackDocDeleted(
        tool: 'coverLetter',
        documentId: clId,
        documentTitle: title,
      );

    } catch (e) {
      debugPrint('Delete cover letter failed: $e');
      await loadDashboard(force: true);
    }
  }

  Future<void> renameCL(String clId, String newTitle) async {
    try {
      await FirebaseService.updateCoverLetter(_uid!, clId, {
        'title': newTitle,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Server succeeded → update local state
      final updated = state.coverLetters.map((cl) {
        if (cl.id == clId) {
          return ClSummaryModel(
            id: cl.id,
            title: newTitle,
            thumbnailUrl: cl.thumbnailUrl,
            templateId: cl.templateId,
            targetCompany: cl.targetCompany,
            targetRole: cl.targetRole,
            updatedAt: DateTime.now(),
            createdAt: cl.createdAt,
          );
        }
        return cl;
      }).toList();

      state = state.copyWith(coverLetters: updated);

      _ref.read(dashboardControllerProvider.notifier).updateRecentItemTitle(
        id: clId,
        newTitle: newTitle,
      );
    } catch (e) {
      debugPrint('renameCL error: $e');
    }
  }

  void addCl(ClSummaryModel cl) {
    state = state.copyWith(coverLetters: [cl, ...state.coverLetters]);
    _ref.read(dashboardControllerProvider.notifier).addRecentItem(
      id: cl.id,
      title: cl.title,
      type: 'coverLetter',
      templateId: cl.templateId ?? 'custom',
    );
  }

  void updateCl(String clId, {String? newTitle}) {
    final updated = state.coverLetters.map((cl) {
      if (cl.id == clId) {
        return ClSummaryModel(
          id: cl.id,
          title: newTitle ?? cl.title,
          thumbnailUrl: cl.thumbnailUrl,
          templateId: cl.templateId,
          targetCompany: cl.targetCompany,
          targetRole: cl.targetRole,
          updatedAt: DateTime.now(),
          createdAt: cl.createdAt,
          items: cl.items,
          canvasBackground: cl.canvasBackground,
        );
      }
      return cl;
    }).toList();
    state = state.copyWith(coverLetters: updated);

    if (newTitle != null) {
      _ref.read(dashboardControllerProvider.notifier).updateRecentItemTitle(
        id: clId,
        newTitle: newTitle,
      );
    }
  }

  void incrementAiUsage() {
    state = state.copyWith(aiUsageCount: state.aiUsageCount + 1);
    _ref.read(dashboardControllerProvider.notifier).incrementAiUsage();
  }

  void incrementExportCount() {
    state = state.copyWith(exportCount: state.exportCount + 1);
    _ref.read(dashboardControllerProvider.notifier).incrementExportCount();
  }
}

final clDashboardControllerProvider =
StateNotifierProvider<ClDashboardController, ClDashboardState>(
      (ref) => ClDashboardController(ref),
);