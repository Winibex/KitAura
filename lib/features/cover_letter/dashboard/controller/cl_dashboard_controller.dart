// lib/features/cover_letter/dashboard/controller/cl_dashboard_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/services/firebase_service.dart';
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
  ClDashboardController() : super(ClDashboardState());

  bool _hasLoaded = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> loadDashboard({bool force = false}) async {
    if (_hasLoaded && !force) return; // Skip if already loaded
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
      state = state.copyWith(
        coverLetters: state.coverLetters.where((c) => c.id != clId).toList(),
      );
      await FirebaseService.deleteCoverLetter(_uid!, clId);

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
    } catch (e) {
      debugPrint('renameCL error: $e');
    }
  }
}

final clDashboardControllerProvider =
StateNotifierProvider<ClDashboardController, ClDashboardState>(
      (ref) => ClDashboardController(),
);