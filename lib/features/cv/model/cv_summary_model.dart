import 'package:cloud_firestore/cloud_firestore.dart';

class CvSummaryModel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String templateId;
  final DateTime updatedAt;
  final DateTime createdAt;
  final List<dynamic>? items;
  final String? canvasBackground;

  CvSummaryModel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    required this.templateId,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'templateId': templateId,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory CvSummaryModel.fromJson(String id, Map<String, dynamic> json) {
    return CvSummaryModel(
      id: id,
      title: json['title'] ?? 'Untitled CV',
      thumbnailUrl: json['thumbnailUrl'],
      templateId: json['templateId'] ?? 'blank',
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      items: json['items'] as List<dynamic>?,
      canvasBackground: json['canvasBackground'] as String?,
    );
  }
}