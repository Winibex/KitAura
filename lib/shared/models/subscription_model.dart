// =============================================================================
// SUBSCRIPTION
// Firestore path: users/{uid}/data/subscription
//
// Tracks the user's plan and metered usage counters.
// Free-tier limits: 3 exports, 10 AI fills, 10 CVs.
// Pro users get unlimited access (counters are still tracked for analytics).
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String plan;                     // 'free' | 'pro'
  final int exportCount;                 // number of PDF exports used
  final int aiUsageCount;                // number of AI fill-ins used
  final int cvCount;                     // number of CVs created
  final DateTime? exportResetDate;       // when the export counter last reset
  final String? stripeCustomerId;        // Stripe customer record
  final String? stripeSubscriptionId;    // active Stripe subscription ID
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;

  const SubscriptionModel({
    this.plan                  = 'free',
    this.exportCount           = 0,
    this.aiUsageCount          = 0,
    this.cvCount               = 0,
    this.exportResetDate,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
  });

  // ---------------------------------------------------------------------------
  // Computed access gates
  // ---------------------------------------------------------------------------

  /// True when the user is on a paid plan.
  bool get isPro => plan == 'pro';

  /// Free users can export up to 3 times; pro users are always allowed.
  bool get canExport => isPro || exportCount < 3;

  /// Free users get 10 AI fill-ins; pro users are always allowed.
  bool get canUseAI => isPro || aiUsageCount < 10;

  /// Free users can hold up to 10 CVs; pro users are always allowed.
  bool get canCreateCV => isPro || cvCount < 10;

  /// Remaining exports for free users; -1 signals "unlimited" for pro.
  int get exportsRemaining => isPro ? -1 : 3 - exportCount;

  /// Remaining AI fill-ins for free users; -1 signals "unlimited" for pro.
  int get aiUsageRemaining => isPro ? -1 : 10 - aiUsageCount;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Converts nullable [DateTime] fields to [Timestamp] only when non-null,
  /// storing null explicitly so Firestore can distinguish "not set" from "zero".
  Map<String, dynamic> toJson() => {
    'plan':         plan,
    'exportCount':  exportCount,
    'aiUsageCount': aiUsageCount,
    'cvCount':      cvCount,
    'exportResetDate': exportResetDate != null
        ? Timestamp.fromDate(exportResetDate!)
        : null,
    'stripeCustomerId':      stripeCustomerId,
    'stripeSubscriptionId':  stripeSubscriptionId,
    'subscriptionStartDate': subscriptionStartDate != null
        ? Timestamp.fromDate(subscriptionStartDate!)
        : null,
    'subscriptionEndDate': subscriptionEndDate != null
        ? Timestamp.fromDate(subscriptionEndDate!)
        : null,
  };

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      plan:         json['plan']         ?? 'free',
      exportCount:  json['exportCount']  ?? 0,
      aiUsageCount: json['aiUsageCount'] ?? 0,
      cvCount:      json['cvCount']      ?? 0,
      exportResetDate:       (json['exportResetDate']       as Timestamp?)?.toDate(),
      stripeCustomerId:       json['stripeCustomerId'],
      stripeSubscriptionId:   json['stripeSubscriptionId'],
      subscriptionStartDate: (json['subscriptionStartDate'] as Timestamp?)?.toDate(),
      subscriptionEndDate:   (json['subscriptionEndDate']   as Timestamp?)?.toDate(),
    );
  }
}