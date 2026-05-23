// lib/features/dashboard/controller/dashboard_controller.dart
//
// Loads platform-wide overview data: subscription usage, recent documents
// across all tools, and analytics summary.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/services/firebase_service.dart';

class DashboardState {
  final bool isLoading;
  final String? error;
  final String displayName;
  final String plan;
  final int exportCount;
  final int aiUsageCount;
  final int cvCount;
  final int totalExports;
  final int totalAiFills;
  final int totalCvsCreated;
  final int loginCount;
  final DateTime? lastActiveAt;
  final List<RecentItem> recentItems;

  const DashboardState({
    this.isLoading = false,
    this.error,
    this.displayName = '',
    this.plan = 'free',
    this.exportCount = 0,
    this.aiUsageCount = 0,
    this.cvCount = 0,
    this.totalExports = 0,
    this.totalAiFills = 0,
    this.totalCvsCreated = 0,
    this.loginCount = 0,
    this.lastActiveAt,
    this.recentItems = const [],
  });

  bool get isPro => plan == 'pro';

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    String? displayName,
    String? plan,
    int? exportCount,
    int? aiUsageCount,
    int? cvCount,
    int? totalExports,
    int? totalAiFills,
    int? totalCvsCreated,
    int? loginCount,
    DateTime? lastActiveAt,
    List<RecentItem>? recentItems,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      displayName: displayName ?? this.displayName,
      plan: plan ?? this.plan,
      exportCount: exportCount ?? this.exportCount,
      aiUsageCount: aiUsageCount ?? this.aiUsageCount,
      cvCount: cvCount ?? this.cvCount,
      totalExports: totalExports ?? this.totalExports,
      totalAiFills: totalAiFills ?? this.totalAiFills,
      totalCvsCreated: totalCvsCreated ?? this.totalCvsCreated,
      loginCount: loginCount ?? this.loginCount,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      recentItems: recentItems ?? this.recentItems,
    );
  }
}

class RecentItem {
  final String id;
  final String title;
  final String type; // 'cv', 'proposal', 'coverLetter', 'linkedin'
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
      case 'cv': return 'CV';
      case 'proposal': return 'Proposal';
      case 'coverLetter': return 'Cover Letter';
      case 'linkedin': return 'LinkedIn';
      default: return 'Document';
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

      // Load subscription
      final subDoc = await FirebaseService.getSubscription(_uid!);
      if (subDoc.exists) {
        final data = subDoc.data() as Map<String, dynamic>;
        state = state.copyWith(
          plan: data['plan'] ?? 'free',
          exportCount: data['exportCount'] ?? 0,
          aiUsageCount: data['aiUsageCount'] ?? 0,
          cvCount: data['cvCount'] ?? 0,
        );
      }

      // Load analytics summary
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

      // Load recent CVs (limit 4)
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

      state = state.copyWith(
        isLoading: false,
        displayName: name,
        recentItems: recentItems,
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