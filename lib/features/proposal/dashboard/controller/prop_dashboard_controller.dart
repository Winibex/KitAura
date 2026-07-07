// lib/features/proposal/dashboard/controller/prop_dashboard_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../dashboard/controller/dashboard_controller.dart';
import '../model/prop_summary_model.dart';

class PropDashboardState {
  final bool isLoading;
  final String? error;
  final List<PropSummaryModel> proposals;
  final int exportCount;
  final int aiUsageCount;
  final String plan;

  // Limits from Firebase (not hardcoded)
  final int maxProposals;
  final int exportsPerMonth;
  final int aiFillsPerMonth;

  PropDashboardState({
    this.isLoading = false,
    this.error,
    this.proposals = const [],
    this.exportCount = 0,
    this.aiUsageCount = 0,
    this.plan = 'free',
    this.maxProposals = 3,
    this.exportsPerMonth = 3,
    this.aiFillsPerMonth = 15,
  });

  bool get isPro => plan == 'pro' || plan == 'trial';
  bool get canExport => isPro || exportCount < exportsPerMonth;
  bool get canCreateProposal => isPro || proposals.length < maxProposals;

  PropDashboardState copyWith({
    bool? isLoading,
    String? error,
    List<PropSummaryModel>? proposals,
    int? exportCount,
    int? aiUsageCount,
    String? plan,
    int? maxProposals,
    int? exportsPerMonth,
    int? aiFillsPerMonth,
  }) {
    return PropDashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      proposals: proposals ?? this.proposals,
      exportCount: exportCount ?? this.exportCount,
      aiUsageCount: aiUsageCount ?? this.aiUsageCount,
      plan: plan ?? this.plan,
      maxProposals: maxProposals ?? this.maxProposals,
      exportsPerMonth: exportsPerMonth ?? this.exportsPerMonth,
      aiFillsPerMonth: aiFillsPerMonth ?? this.aiFillsPerMonth,
    );
  }
}

class PropDashboardController extends StateNotifier<PropDashboardState> {
  PropDashboardController(this._ref) : super(PropDashboardState(isLoading: true));
  final Ref _ref;

  bool _hasLoaded = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> loadDashboard({bool force = false}) async {
    debugPrint("Loading Proposal Dashboard");
    if (_hasLoaded && !force) {
      if (state.isLoading) state = state.copyWith(isLoading: false);
      return;
    }
    if (_uid == null) {
      // Guest with no anon session yet — show empty dashboard, not shimmer
      state = state.copyWith(
        isLoading: false,
      );
      _hasLoaded = false; // re-fetch once they sign in (anon or real)
      debugPrint("User is null so proposal dashboard does not loaded.");
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Run subscription + proposals fetch in PARALLEL (3x faster)
      final results = await Future.wait([
        FirebaseService.getSubscription(_uid!),
        FirebaseService.getUserProposals(_uid!),
      ]);
      if (!mounted) return;
      final subDoc = results[0] as DocumentSnapshot;
      final propsSnapshot = results[1] as QuerySnapshot;

      String plan = 'free';
      int exportCount = 0;
      int aiUsageCount = 0;
      if (subDoc.exists) {
        final data = subDoc.data() as Map<String, dynamic>;
        plan = data['plan'] ?? 'free';
        exportCount = data['exportCount'] ?? 0;
        aiUsageCount = data['aiFillCount'] ?? 0;
      }

      // Limits depends on plan, so this stays sequential
      int maxProp = 3, maxExports = 3, maxAiFills = 15;
      final limits = await FirebaseService.getPlanLimits(plan);
      if (!mounted) return;
      maxProp = limits['maxProposals']!;
      maxExports = limits['exportsPerMonth']!;
      maxAiFills = limits['aiFillPerMonth']!;

      // Parse proposals from the parallel result
      List<PropSummaryModel> props = [];
      try {
        props = propsSnapshot.docs
            .map((doc) => PropSummaryModel.fromJson(
            doc.id, doc.data() as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Proposals parse failed: $e');
      }

      _hasLoaded = true;
      state = state.copyWith(
        isLoading: false,
        proposals: props,
        plan: plan,
        exportCount: exportCount,
        aiUsageCount: aiUsageCount,
        maxProposals: maxProp == -1 ? 999 : maxProp,
        exportsPerMonth: maxExports == -1 ? 999 : maxExports,
        aiFillsPerMonth: maxAiFills == -1 ? 999 : maxAiFills,
      );
    } catch (e, stack) {
      debugPrint('PropDashboard loadDashboard error: $e\n$stack');
      state = state.copyWith(
          isLoading: false,
          error: 'Failed to load proposal dashboard. Refresh this page to retry.'
      );
    }
  }

  Future<void> deleteProposal(String propId) async {
    String title = 'Untitled';
    try {
      final prop = state.proposals.firstWhere((p) => p.id == propId);
      title = prop.title;
    } catch (_) {}

    try {

      // 1. Server first — only update state if it succeeds
      await FirebaseService.deleteProposal(_uid!, propId);

      // 2. Server succeeded → update local state
      state = state.copyWith(
        proposals: state.proposals.where((p) => p.id != propId).toList(),
      );

      // 3. Notify main dashboard (synchronous, won't fail)
      _ref.read(dashboardControllerProvider.notifier).removeRecentItem(
        id: propId,
        type: 'proposal',
      );

      // 4. Fire-and-forget tracking (don't wait, don't block)
      ClaudeService.trackDocDeleted(
        tool: 'proposal',
        documentId: propId,
        documentTitle: title,
      );
    } catch (e) {
      debugPrint('Delete proposal failed: $e');
      await loadDashboard(force: true); // Rollback
    }
  }

  Future<void> renameProposal(String propId, String newTitle) async {
    try {
      await FirebaseService.updateProposal(_uid!, propId, {
        'title': newTitle,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Server succeeded → update local state
      final updated = state.proposals.map((p) {
        if (p.id == propId) {
          return PropSummaryModel(
            id: p.id,
            title: newTitle,
            thumbnailUrl: p.thumbnailUrl,
            templateId: p.templateId,
            clientName: p.clientName,
            projectScope: p.projectScope,
            updatedAt: DateTime.now(),
            createdAt: p.createdAt,
            items: p.items,
            canvasBackground: p.canvasBackground,
          );
        }
        return p;
      }).toList();

      state = state.copyWith(proposals: updated);

      _ref.read(dashboardControllerProvider.notifier).updateRecentItemTitle(
        id: propId,
        newTitle: newTitle,
      );
    } catch (e) {
      debugPrint('renameProposal error: $e');
    }
  }

  void addProposal(PropSummaryModel prop) {
    state = state.copyWith(proposals: [prop, ...state.proposals]);
    _ref.read(dashboardControllerProvider.notifier).addRecentItem(
      id: prop.id,
      title: prop.title,
      type: 'proposal',
      templateId: prop.templateId ?? 'custom',
    );
  }

  void updateProposal(String propId, {String? newTitle}) {
    final updated = state.proposals.map((p) {
      if (p.id == propId) {
        return PropSummaryModel(
          id: p.id,
          title: newTitle ?? p.title,
          thumbnailUrl: p.thumbnailUrl,
          templateId: p.templateId,
          clientName: p.clientName,
          projectScope: p.projectScope,
          updatedAt: DateTime.now(),
          createdAt: p.createdAt,
          items: p.items,
          canvasBackground: p.canvasBackground,
        );
      }
      return p;
    }).toList();
    state = state.copyWith(proposals: updated);

    if (newTitle != null) {
      _ref.read(dashboardControllerProvider.notifier).updateRecentItemTitle(
        id: propId,
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

final propDashboardControllerProvider =
StateNotifierProvider<PropDashboardController, PropDashboardState>(
      (ref) => PropDashboardController(ref),
);