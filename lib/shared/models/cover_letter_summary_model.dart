// lib/shared/models/cover_letter_summary_model.dart
//
// Lightweight summary for list views (cover letter dashboard cards).

import 'package:cloud_firestore/cloud_firestore.dart';

class CoverLetterSummaryModel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String? targetCompany;
  final String? targetRole;
  final String status;
  final DateTime? updatedAt;

  const CoverLetterSummaryModel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.targetCompany,
    this.targetRole,
    this.status = 'draft',
    this.updatedAt,
  });

  factory CoverLetterSummaryModel.fromJson(Map<String, dynamic> json, String id) {
    return CoverLetterSummaryModel(
      id: id,
      title: json['title'] ?? 'Untitled Cover Letter',
      thumbnailUrl: json['thumbnailUrl'],
      targetCompany: json['targetCompany'],
      targetRole: json['targetRole'],
      status: json['status'] ?? 'draft',
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}