// =============================================================================
// MONTHLY ANALYTICS
// Firestore path: users/{uid}/analytics/{YYYY-MM}
//
// Per-month breakdown of user activity. One document per calendar month,
// keyed by ISO month string (e.g. "2024-03"). Enables charting trends over
// time without reading the full transaction log.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyAnalyticsModel {
  final String month;           // ISO format: "YYYY-MM"
  final int exports;
  final int aiFills;
  final int cvsCreated;
  final int logins;
  final List<String> exportedCvIds; // IDs of CVs exported this month
  final DateTime updatedAt;

  MonthlyAnalyticsModel({
    required this.month,
    this.exports     = 0,
    this.aiFills     = 0,
    this.cvsCreated  = 0,
    this.logins      = 0,
    this.exportedCvIds = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'month':          month,
    'exports':        exports,
    'aiFills':        aiFills,
    'cvsCreated':     cvsCreated,
    'logins':         logins,
    'exportedCvIds':  exportedCvIds,
    'updatedAt':      Timestamp.fromDate(updatedAt),
  };

  factory MonthlyAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return MonthlyAnalyticsModel(
      month:         json['month']    ?? '',
      exports:       json['exports']  ?? 0,
      aiFills:       json['aiFills']  ?? 0,
      cvsCreated:    json['cvsCreated'] ?? 0,
      logins:        json['logins']   ?? 0,
      exportedCvIds: List<String>.from(json['exportedCvIds'] ?? []),
      updatedAt:    (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}