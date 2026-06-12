// lib/features/proposal/dashboard/model/prop_summary_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class PropSummaryModel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String? templateId;
  final String? clientName;
  final String? projectScope;
  final DateTime updatedAt;
  final DateTime createdAt;
  final List<dynamic>? items;
  final String? canvasBackground;

  PropSummaryModel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.templateId,
    this.clientName,
    this.projectScope,
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

  factory PropSummaryModel.fromJson(String id, Map<String, dynamic> json) {
    return PropSummaryModel(
      id: id,
      title: json['title'] ?? 'Untitled Proposal',
      thumbnailUrl: json['thumbnailUrl'],
      templateId: json['templateId'],
      clientName: json['clientName'],
      projectScope: json['projectScope'],
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      items: json['items'] as List<dynamic>?,
      canvasBackground: json['canvasBackground'] as String?,
    );
  }
}