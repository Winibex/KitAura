import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/services/firebase_service.dart';
import '../model/cv_summary_model.dart';

// Dashboard state
class DashboardState {
  final bool isLoading;
  final String? error;
  final List<CvSummaryModel> cvs;
  final int exportCount;
  final int aiUsageCount;
  final String plan;

  DashboardState({
    this.isLoading = false,
    this.error,
    this.cvs = const [],
    this.exportCount = 0,
    this.aiUsageCount = 0,
    this.plan = 'free',
  });

  bool get isPro => plan == 'pro';
  bool get canExport => isPro || exportCount < 3;
  bool get canCreateCV => isPro || cvs.length < 10;

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    List<CvSummaryModel>? cvs,
    int? exportCount,
    int? aiUsageCount,
    String? plan,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      cvs: cvs ?? this.cvs,
      exportCount: exportCount ?? this.exportCount,
      aiUsageCount: aiUsageCount ?? this.aiUsageCount,
      plan: plan ?? this.plan,
    );
  }
}

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController() : super(DashboardState());

  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> loadDashboard() async {
    debugPrint('loadDashboard called');
    if (_uid == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Load subscription data
      final subDoc = await FirebaseService.getSubscription(_uid!);
      if (subDoc.exists) {
        final data = subDoc.data() as Map<String, dynamic>;
        state = state.copyWith(
          plan: data['plan'] ?? 'free',
          exportCount: data['exportCount'] ?? 0,
          aiUsageCount: data['aiUsageCount'] ?? 0,
        );
      }

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

      // Show dummy CVs if user has none
      if (cvs.isEmpty) {
        debugPrint('No CVs found, showing dummy CVs');
      }else{
        debugPrint('CVs loaded successfully');
      }

      state = state.copyWith(isLoading: false, cvs: cvs);
    } catch (e, stack) {
      debugPrint('loadDashboard error: $e\n$stack');
      state = state.copyWith(
        isLoading: false,
      );
    }
  }



  Future<void> deleteCV(String cvId) async {
    try {
      await FirebaseService.deleteCV(_uid!, cvId);
      await FirebaseService.decrementCvCount(_uid!);
      final updated = state.cvs.where((cv) => cv.id != cvId).toList();
      state = state.copyWith(cvs: updated);
    } catch (e) {
      debugPrint('deleteCV error: $e');
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
final dashboardControllerProvider =
StateNotifierProvider<DashboardController, DashboardState>(
      (ref) => DashboardController(),
);