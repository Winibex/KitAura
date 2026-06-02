// lib/shared/models/cover_letter_model.dart
//
// Full cover letter document data — stored at users/{uid}/coverLetters/{clId}.
// Canvas JSON content stored as 'items' list (same format as CVs).

import 'package:cloud_firestore/cloud_firestore.dart';

class CoverLetterModel {
  final String id;
  final String userId;
  final String title;
  final String? thumbnailUrl;
  final String canvasBackground;
  final String? templateId;

  // Cover-letter-specific fields
  final String? targetCompany;
  final String? targetRole;
  final String? hiringManagerName;
  final String? jobDescription;

  final String status; // 'draft' | 'complete'
  final bool isArchived;
  final DateTime? lastExportedAt;
  final int exportCount;
  final List<Map<String, dynamic>> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CoverLetterModel({
    this.id = '',
    required this.userId,
    this.title = 'Untitled Cover Letter',
    this.thumbnailUrl,
    this.canvasBackground = '#FFFFFF',
    this.templateId,
    this.targetCompany,
    this.targetRole,
    this.hiringManagerName,
    this.jobDescription,
    this.status = 'draft',
    this.isArchived = false,
    this.lastExportedAt,
    this.exportCount = 0,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'title': title,
    'thumbnailUrl': thumbnailUrl,
    'canvasBackground': canvasBackground,
    'templateId': templateId,
    'targetCompany': targetCompany,
    'targetRole': targetRole,
    'hiringManagerName': hiringManagerName,
    'jobDescription': jobDescription,
    'status': status,
    'isArchived': isArchived,
    'lastExportedAt':
    lastExportedAt != null ? Timestamp.fromDate(lastExportedAt!) : null,
    'exportCount': exportCount,
    'items': items,
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory CoverLetterModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return CoverLetterModel(
      id: id ?? '',
      userId: json['userId'] ?? '',
      title: json['title'] ?? 'Untitled Cover Letter',
      thumbnailUrl: json['thumbnailUrl'],
      canvasBackground: json['canvasBackground'] ?? '#FFFFFF',
      templateId: json['templateId'],
      targetCompany: json['targetCompany'],
      targetRole: json['targetRole'],
      hiringManagerName: json['hiringManagerName'],
      jobDescription: json['jobDescription'],
      status: json['status'] ?? 'draft',
      isArchived: json['isArchived'] ?? false,
      lastExportedAt: (json['lastExportedAt'] as Timestamp?)?.toDate(),
      exportCount: json['exportCount'] ?? 0,
      items: List<Map<String, dynamic>>.from(json['items'] ?? []),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  CoverLetterModel copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    String? canvasBackground,
    String? templateId,
    String? targetCompany,
    String? targetRole,
    String? hiringManagerName,
    String? jobDescription,
    String? status,
    bool? isArchived,
    DateTime? lastExportedAt,
    int? exportCount,
    List<Map<String, dynamic>>? items,
  }) {
    return CoverLetterModel(
      id: id ?? this.id,
      userId: userId,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      canvasBackground: canvasBackground ?? this.canvasBackground,
      templateId: templateId ?? this.templateId,
      targetCompany: targetCompany ?? this.targetCompany,
      targetRole: targetRole ?? this.targetRole,
      hiringManagerName: hiringManagerName ?? this.hiringManagerName,
      jobDescription: jobDescription ?? this.jobDescription,
      status: status ?? this.status,
      isArchived: isArchived ?? this.isArchived,
      lastExportedAt: lastExportedAt ?? this.lastExportedAt,
      exportCount: exportCount ?? this.exportCount,
      items: items ?? this.items,
      createdAt: createdAt,
    );
  }
}