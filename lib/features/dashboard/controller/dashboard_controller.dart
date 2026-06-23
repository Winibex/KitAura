// lib/features/dashboard/controller/dashboard_controller.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/services/firebase_service.dart';

class DashboardState {
  final bool isLoading;
  final String? error;

  final String displayName;
  final String plan;

  final bool trialActive;
  final bool trialUsed;
  final int? trialDaysRemaining;

  final double proPrice;

  final int exportCount;
  final int aiFillCount;
  final int aiRewriteCount;
  final int totalAiFills;

  final int cvCount;
  final int coverLetterCount;
  final int proposalCount;
  final int totalCvsCreated;

  final int totalExports;

  final int loginCount;
  final DateTime? lastActiveAt;
  final List<RecentItem> recentItems;

  // Limits from Firebase config/limits
  final int maxExports;
  final int maxAiFills;
  final int maxAiRewrites;
  final int maxDocs;

  const DashboardState({
    this.isLoading = false,
    this.error,
    this.displayName = '',
    this.plan = 'free',
    this.trialActive = false,
    this.trialUsed = false,
    this.proPrice = 8.0,
    this.trialDaysRemaining,
    this.exportCount = 0,
    this.aiFillCount = 0,
    this.aiRewriteCount = 0,
    this.cvCount = 0,
    this.coverLetterCount = 0,
    this.proposalCount = 0,
    this.totalExports = 0,
    this.totalAiFills = 0,
    this.totalCvsCreated = 0,
    this.loginCount = 0,
    this.lastActiveAt,
    this.recentItems = const [],
    this.maxExports = 3,
    this.maxAiFills = 15,
    this.maxAiRewrites = 15,
    this.maxDocs = 5,
  });

  bool get isPro => plan == 'pro' || (plan == 'trial' && trialActive);

  /// Total documents across all tools
  int get totalDocuments => cvCount + coverLetterCount + proposalCount;

  String get proPriceLabel => '\$${proPrice.toStringAsFixed(proPrice % 1 == 0 ? 0 : 2)}/mo';
  String get proPriceFullLabel => '\$${proPrice.toStringAsFixed(proPrice % 1 == 0 ? 0 : 2)}/month';

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    String? displayName,
    String? plan,
    bool? trialActive,
    bool? trialUsed,
    double? proPrice,
    int? trialDaysRemaining,
    int? exportCount,
    int? aiFillCount,
    int? aiRewriteCount,
    int? cvCount,
    int? coverLetterCount,
    int? proposalCount,
    int? totalExports,
    int? totalAiFills,
    int? totalCvsCreated,
    int? loginCount,
    DateTime? lastActiveAt,
    List<RecentItem>? recentItems,
    int? maxExports,
    int? maxAiRewrites,
    int? maxAiFills,
    int? maxDocs,
  })
  {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      displayName: displayName ?? this.displayName,
      plan: plan ?? this.plan,
      trialActive: trialActive ?? this.trialActive,
      trialUsed: trialUsed ?? this.trialUsed,
      proPrice: proPrice ?? this.proPrice,
      trialDaysRemaining: trialDaysRemaining ?? this.trialDaysRemaining,
      exportCount: exportCount ?? this.exportCount,
      aiFillCount: aiFillCount ?? this.aiFillCount,
      aiRewriteCount: aiRewriteCount ?? this.aiRewriteCount,
      cvCount: cvCount ?? this.cvCount,
      coverLetterCount: coverLetterCount ?? this.coverLetterCount,
      proposalCount: proposalCount ?? this.proposalCount,
      totalExports: totalExports ?? this.totalExports,
      totalAiFills: totalAiFills ?? this.totalAiFills,
      totalCvsCreated: totalCvsCreated ?? this.totalCvsCreated,
      loginCount: loginCount ?? this.loginCount,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      recentItems: recentItems ?? this.recentItems,
      maxExports: maxExports ?? this.maxExports,
      maxAiRewrites: maxAiRewrites ?? this.maxAiRewrites,
      maxAiFills: maxAiFills ?? this.maxAiFills,
      maxDocs: maxDocs ?? this.maxDocs,
    );
  }
}

class RecentItem {
  final String id;
  final String title;
  final String type;
  final String templateId;
  final DateTime updatedAt;

  const RecentItem({
    required this.id,
    required this.title,
    required this.type,
    required this.templateId,
    required this.updatedAt,
  });

  String get timeAgo {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  String get typeLabel {
    switch (type) {
      case 'cv':          return 'CV';
      case 'proposal':    return 'Proposal';
      case 'coverLetter': return 'Cover Letter';
      case 'linkedin':    return 'LinkedIn';
      default:            return 'Document';
    }
  }
}

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController() : super(const DashboardState(isLoading: true));

  bool _hasLoaded = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> loadDashboard({bool force = false}) async {
    if (_hasLoaded && !force) {
      if (state.isLoading) state = state.copyWith(isLoading: false);
      return;
    }
    if (_uid == null) return;
    debugPrint("Loading Main Dashboard");
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final name = user?.displayName ?? user?.email?.split('@').first ?? 'User';

      // ── Load subscription (new field names) ─────────────────────────
      final subDoc = await FirebaseService.getSubscription(_uid!);
      if (subDoc.exists) {
        final data = subDoc.data() as Map<String, dynamic>;

        // Trial days remaining
        int? trialDays;
        if (data['plan'] == 'trial' && data['trialEndDate'] != null) {
          final endDate = (data['trialEndDate'] as dynamic).toDate() as DateTime;
          trialDays = endDate.difference(DateTime.now()).inDays.clamp(0, 999);
        }

        state = state.copyWith(
          plan: data['plan'] ?? 'free',
          trialActive: data['trialActive'] ?? false,
          trialUsed: data['trialUsed'] ?? false,
          trialDaysRemaining: trialDays,
          exportCount: data['exportCount'] ?? 0,
          aiFillCount: data['aiFillCount'] ?? 0,
          aiRewriteCount: data['aiRewriteCount'] ?? 0,
          cvCount: data['cvCount'] ?? 0,
          coverLetterCount: data['coverLetterCount'] ?? 0,
          proposalCount: data['proposalCount'] ?? 0,
        );
      }

      // ── Load analytics summary ──────────────────────────────────────
      final analyticsDoc = await FirebaseService.getAnalyticsSummary(_uid!);
      if (analyticsDoc.exists) {
        final data = analyticsDoc.data() as Map<String, dynamic>;
        state = state.copyWith(
          totalExports: data['totalExports'] ?? 0,
          totalAiFills: data['totalAiFills'] ?? 0,
          totalCvsCreated: data['totalCvsCreated'] ?? 0,
          loginCount: data['loginCount'] ?? 0,
        );
      }

      // ── Load CVs (count from actual collection, not subscription) ───
      final recentItems = <RecentItem>[];
      int actualCvCount = 0;
      try {
        final cvsSnapshot = await FirebaseService.getUserCVs(_uid!);
        actualCvCount = cvsSnapshot.docs.length;
        for (final doc in cvsSnapshot.docs.take(4)) {
          final data = doc.data() as Map<String, dynamic>;
          recentItems.add(RecentItem(
            id: doc.id,
            title: data['title'] ?? 'Untitled CV',
            type: 'cv',
            templateId: data['templateId'] ?? 'blank',
            updatedAt: (data['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Recent CVs load error: $e');
      }

      // Load limits from config/limits
      int maxExports = 3, maxAiFills = 15, maxAiRewrites = 15, maxDocs = 5;
      final limits = await FirebaseService.getPlanLimits(state.plan);
      final proPrice = await FirebaseService.getProPrice();
      maxExports = limits['exportsPerMonth']!;
      maxAiFills = limits['aiFillPerMonth']!;
      maxAiRewrites = limits['aiRewritePerMonth']!;
      maxDocs = limits['maxDocs']!;

      // Load recent cover letters too
      int actualClCount = 0;
      try {
        final clsSnapshot = await FirebaseService.getUserCoverLetters(_uid!);
        actualClCount = clsSnapshot.docs.length;
        for (final doc in clsSnapshot.docs.take(4)) {
          final data = doc.data() as Map<String, dynamic>;
          recentItems.add(RecentItem(
            id: doc.id,
            title: data['title'] ?? 'Untitled Cover Letter',
            type: 'coverLetter',
            templateId: data['templateId'] ?? 'custom',
            updatedAt: (data['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Recent CLs load error: $e');
      }

      // Load recent proposals too
      int actualPropCount = 0;
      try {
        final propsSnapshot = await FirebaseService.getUserProposals(_uid!);
        actualPropCount = propsSnapshot.docs.length;
        for (final doc in propsSnapshot.docs.take(4)) {
          final data = doc.data() as Map<String, dynamic>;
          recentItems.add(RecentItem(
            id: doc.id,
            title: data['title'] ?? 'Untitled Proposal',
            type: 'proposal',
            templateId: data['templateId'] ?? 'custom',
            updatedAt: (data['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Recent proposals load error: $e');
      }

      // Sort recent items by date
      recentItems.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _hasLoaded = true;
      state = state.copyWith(
        isLoading: false,
        displayName: name,
        recentItems: recentItems.take(5).toList(),
        cvCount: actualCvCount,
        coverLetterCount: actualClCount,
        maxExports: maxExports == -1 ? 999 : maxExports,
        maxAiFills: maxAiFills == -1 ? 999 : maxAiFills,
        maxAiRewrites: maxAiRewrites == -1 ? 999 : maxAiRewrites,
        maxDocs: maxDocs == -1 ? 999 : maxDocs,
        proPrice: proPrice,
        proposalCount: actualPropCount,
      );
    } catch (e, stack) {
      debugPrint('Dashboard load error: $e\n$stack');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Add a newly created document to recent items + increment count.
  /// Called by CV/CL/Proposal controllers after successful create.
  void addRecentItem({
    required String id,
    required String title,
    required String type, // 'cv' | 'coverLetter' | 'proposal'
    required String templateId,
  })
  {
    final newItem = RecentItem(
      id: id,
      title: title,
      type: type,
      templateId: templateId,
      updatedAt: DateTime.now(),
    );

    // Prepend new item, keep only top 5
    final updatedRecent = [newItem, ...state.recentItems].take(5).toList();

    // Increment the right counter
    state = state.copyWith(
      recentItems: updatedRecent,
      cvCount: type == 'cv' ? state.cvCount + 1 : state.cvCount,
      coverLetterCount: type == 'coverLetter'
          ? state.coverLetterCount + 1
          : state.coverLetterCount,
      proposalCount: type == 'proposal'
          ? state.proposalCount + 1
          : state.proposalCount,
    );
  }

  /// Remove a deleted document from recent items + decrement count.
  void removeRecentItem({
    required String id,
    required String type,
  })
  {
    final updatedRecent =
    state.recentItems.where((item) => item.id != id).toList();

    state = state.copyWith(
      recentItems: updatedRecent,
      cvCount: type == 'cv' ? (state.cvCount - 1).clamp(0, 9999) : state.cvCount,
      coverLetterCount: type == 'coverLetter'
          ? (state.coverLetterCount - 1).clamp(0, 9999)
          : state.coverLetterCount,
      proposalCount: type == 'proposal'
          ? (state.proposalCount - 1).clamp(0, 9999)
          : state.proposalCount,
    );
  }

  /// Update a renamed document in recent items.
  void updateRecentItemTitle({
    required String id,
    required String newTitle,
  })
  {
    final updatedRecent = state.recentItems.map((item) {
      if (item.id == id) {
        return RecentItem(
          id: item.id,
          title: newTitle,
          type: item.type,
          templateId: item.templateId,
          updatedAt: DateTime.now(),
        );
      }
      return item;
    }).toList();

    state = state.copyWith(recentItems: updatedRecent);
  }

  /// Bump AI Compose or AI Refine counter (called after each AI call).
  void incrementAiUsage({bool isRewrite = false}) {
    state = state.copyWith(
      aiFillCount: isRewrite ? state.aiFillCount : state.aiFillCount + 1,
      aiRewriteCount: isRewrite ? state.aiRewriteCount + 1 : state.aiRewriteCount,
    );
  }

  /// Bump export count (called after each PDF download).
  void incrementExportCount() {
    state = state.copyWith(exportCount: state.exportCount + 1);
  }
}

final dashboardControllerProvider =
StateNotifierProvider<DashboardController, DashboardState>(
      (ref) => DashboardController(),
);