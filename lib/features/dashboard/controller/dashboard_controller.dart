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
  final int? trialDaysRemaining;
  final int exportCount;
  final int aiFillCount;
  final int aiRewriteCount;
  final int cvCount;
  final int coverLetterCount;
  final int proposalCount;
  final int totalExports;
  final int totalAiFills;
  final int totalCvsCreated;
  final int loginCount;
  final DateTime? lastActiveAt;
  final List<RecentItem> recentItems;
  // Limits from Firebase config/limits
  final int maxExports;
  final int maxAiFills;

  const DashboardState({
    this.isLoading = false,
    this.error,
    this.displayName = '',
    this.plan = 'free',
    this.trialActive = false,
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
  });

  bool get isPro => plan == 'pro' || (plan == 'trial' && trialActive);

  /// Total documents across all tools
  int get totalDocuments => cvCount + coverLetterCount + proposalCount;

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    String? displayName,
    String? plan,
    bool? trialActive,
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
    int? maxAiFills,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      displayName: displayName ?? this.displayName,
      plan: plan ?? this.plan,
      trialActive: trialActive ?? this.trialActive,
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
      maxAiFills: maxAiFills ?? this.maxAiFills,
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
  DashboardController() : super(const DashboardState());

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> loadDashboard() async {
    if (_uid == null) return;
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

      // ── Load recent CVs ─────────────────────────────────────────────
      final recentItems = <RecentItem>[];
      try {
        final cvsSnapshot = await FirebaseService.getUserCVs(_uid!);
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
      int maxExports = 3, maxAiFills = 15;
      final limits = await FirebaseService.getPlanLimits(state.plan);
      maxExports = limits['exportsPerMonth']!;
      maxAiFills = limits['aiFillPerMonth']!;

      // Load recent cover letters too
      try {
        final clsSnapshot = await FirebaseService.getUserCoverLetters(_uid!);
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

      // Sort recent items by date
      recentItems.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      state = state.copyWith(
        isLoading: false,
        displayName: name,
        recentItems: recentItems.take(5).toList(),
        maxExports: maxExports == -1 ? 999 : maxExports,
        maxAiFills: maxAiFills == -1 ? 999 : maxAiFills,
      );
    } catch (e, stack) {
      debugPrint('Dashboard load error: $e\n$stack');
      state = state.copyWith(isLoading: false);
    }
  }
}

final dashboardControllerProvider =
StateNotifierProvider<DashboardController, DashboardState>(
      (ref) => DashboardController(),
);