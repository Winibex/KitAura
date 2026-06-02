// lib/features/cover_letter/dashboard/model/cl_summary_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ClSummaryModel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String? templateId;
  final String? targetCompany;
  final String? targetRole;
  final DateTime updatedAt;
  final DateTime createdAt;
  final List<dynamic>? items;
  final String? canvasBackground;

  ClSummaryModel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.templateId,
    this.targetCompany,
    this.targetRole,
    required this.updatedAt,
    required this.createdAt,
    this.items,
    this.canvasBackground,
  });

  String get timeAgo {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays > 0) return '${diff.inDays} days ago';
    if (diff.inHours > 0) return '${diff.inHours} hours ago';
    return 'Just now';
  }

  factory ClSummaryModel.fromJson(String id, Map<String, dynamic> json) {
    return ClSummaryModel(
      id: id,
      title: json['title'] ?? 'Untitled Cover Letter',
      thumbnailUrl: json['thumbnailUrl'],
      templateId: json['templateId'],
      targetCompany: json['targetCompany'],
      targetRole: json['targetRole'],
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      items: json['items'] as List<dynamic>?,
      canvasBackground: json['canvasBackground'] as String?,
    );
  }
}