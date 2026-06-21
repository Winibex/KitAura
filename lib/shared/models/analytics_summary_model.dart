// =============================================================================
// ANALYTICS SUMMARY
// Firestore path: users/{uid}/analytics/summary
//
// Lifetime aggregate metrics for a single user. Updated incrementally on
// each significant event (login, export, AI Compose, CV creation).
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsSummaryModel {
  final DateTime? lastLoginAt;
  final int loginCount;
  final int totalExports;
  final int totalAiFills;
  final int totalCvsCreated;
  final DateTime? lastActiveAt;
  final String? signupSource;  // 'email' | 'google' | etc.
  final String? device;        // device type recorded at signup
  final String? browser;       // browser/platform recorded at signup

  const AnalyticsSummaryModel({
    this.lastLoginAt,
    this.loginCount       = 0,
    this.totalExports     = 0,
    this.totalAiFills     = 0,
    this.totalCvsCreated  = 0,
    this.lastActiveAt,
    this.signupSource,
    this.device,
    this.browser,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'lastLoginAt':    lastLoginAt  != null ? Timestamp.fromDate(lastLoginAt!)  : null,
    'loginCount':     loginCount,
    'totalExports':   totalExports,
    'totalAiFills':   totalAiFills,
    'totalCvsCreated': totalCvsCreated,
    'lastActiveAt':   lastActiveAt != null ? Timestamp.fromDate(lastActiveAt!) : null,
    'signupSource':   signupSource,
    'device':         device,
    'browser':        browser,
  };

  factory AnalyticsSummaryModel.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummaryModel(
      lastLoginAt:     (json['lastLoginAt']  as Timestamp?)?.toDate(),
      loginCount:       json['loginCount']   ?? 0,
      totalExports:     json['totalExports'] ?? 0,
      totalAiFills:     json['totalAiFills'] ?? 0,
      totalCvsCreated:  json['totalCvsCreated'] ?? 0,
      lastActiveAt:    (json['lastActiveAt'] as Timestamp?)?.toDate(),
      signupSource:     json['signupSource'],
      device:           json['device'],
      browser:          json['browser'],
    );
  }
}