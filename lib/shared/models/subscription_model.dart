// lib/shared/models/subscription_model.dart
//
// Mirrors users/{uid}/data/subscription in Firestore.
// All counters are written server-side by Cloud Functions only.

import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String plan; // 'free' | 'trial' | 'pro'

  // Trial
  final DateTime? trialStartDate;
  final DateTime? trialEndDate;
  final bool trialActive;
  final bool trialUsed;

  // Billing cycle (per-user)
  final DateTime? cycleStartDate;
  final DateTime? cycleEndDate;
  final DateTime? lastResetDate;

  // Monthly usage counters (reset each cycle)
  final int aiFillCount;
  final int aiRewriteCount;
  final int aiDesignCount;
  final int exportCount;
  final int spellcheckCount;

  // Document counts (lifetime)
  final int cvCount;
  final int coverLetterCount;
  final int proposalCount;

  // Stripe
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;

  const SubscriptionModel({
    this.plan = 'free',
    this.trialStartDate,
    this.trialEndDate,
    this.trialActive = false,
    this.trialUsed = false,
    this.cycleStartDate,
    this.cycleEndDate,
    this.lastResetDate,
    this.aiFillCount = 0,
    this.aiRewriteCount = 0,
    this.aiDesignCount = 0,
    this.exportCount = 0,
    this.spellcheckCount = 0,
    this.cvCount = 0,
    this.coverLetterCount = 0,
    this.proposalCount = 0,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
  });

  // ── Computed ───────────────────────────────────────────────────────

  bool get isPro => plan == 'pro' || (plan == 'trial' && trialActive);
  bool get isFree => !isPro;

  bool get isTrialExpired =>
      plan == 'trial' &&
          trialEndDate != null &&
          DateTime.now().isAfter(trialEndDate!);

  bool get canStartTrial => plan == 'free' && !trialUsed;

  int? get trialDaysRemaining {
    if (plan != 'trial' || trialEndDate == null) return null;
    final days = trialEndDate!.difference(DateTime.now()).inDays;
    return days.clamp(0, 999);
  }

  /// Check if cycle has expired (frontend hint — server does the actual reset)
  bool get isCycleExpired =>
      cycleEndDate != null && DateTime.now().isAfter(cycleEndDate!);

  // ── Paywall checks (uses hardcoded fallback limits) ────────────────
  // Ideally read from config/limits, but these are safe client-side checks.
  // The server enforces the real limits — these just control the UI.

  bool get canUseAI => isPro || aiFillCount < 15;
  bool get canUseRewrite => isPro || aiRewriteCount < 15;
  bool get canUseDesign => isPro || aiDesignCount < 5;
  bool get canExport => isPro || exportCount < 3;
  bool get canCreateCV => isPro || cvCount < 3;
  bool get canCreateCoverLetter => isPro || coverLetterCount < 3;
  bool get canCreateProposal => isPro || proposalCount < 3;

  // ── Serialization ─────────────────────────────────────────────────

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      plan: json['plan'] as String? ?? 'free',
      trialStartDate: (json['trialStartDate'] as Timestamp?)?.toDate(),
      trialEndDate: (json['trialEndDate'] as Timestamp?)?.toDate(),
      trialActive: json['trialActive'] as bool? ?? false,
      trialUsed: json['trialUsed'] as bool? ?? false,
      cycleStartDate: (json['cycleStartDate'] as Timestamp?)?.toDate(),
      cycleEndDate: (json['cycleEndDate'] as Timestamp?)?.toDate(),
      lastResetDate: (json['lastResetDate'] as Timestamp?)?.toDate(),
      aiFillCount: json['aiFillCount'] as int? ?? 0,
      aiRewriteCount: json['aiRewriteCount'] as int? ?? 0,
      aiDesignCount: json['aiDesignCount'] as int? ?? 0,
      exportCount: json['exportCount'] as int? ?? 0,
      spellcheckCount: json['spellcheckCount'] as int? ?? 0,
      cvCount: json['cvCount'] as int? ?? 0,
      coverLetterCount: json['coverLetterCount'] as int? ?? 0,
      proposalCount: json['proposalCount'] as int? ?? 0,
      stripeCustomerId: json['stripeCustomerId'] as String?,
      stripeSubscriptionId: json['stripeSubscriptionId'] as String?,
      subscriptionStartDate: (json['subscriptionStartDate'] as Timestamp?)?.toDate(),
      subscriptionEndDate: (json['subscriptionEndDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
    'plan': plan,
    'trialStartDate': trialStartDate != null ? Timestamp.fromDate(trialStartDate!) : null,
    'trialEndDate': trialEndDate != null ? Timestamp.fromDate(trialEndDate!) : null,
    'trialActive': trialActive,
    'trialUsed': trialUsed,
    'cycleStartDate': cycleStartDate != null ? Timestamp.fromDate(cycleStartDate!) : null,
    'cycleEndDate': cycleEndDate != null ? Timestamp.fromDate(cycleEndDate!) : null,
    'lastResetDate': lastResetDate != null ? Timestamp.fromDate(lastResetDate!) : null,
    'aiFillCount': aiFillCount,
    'aiRewriteCount': aiRewriteCount,
    'aiDesignCount': aiDesignCount,
    'exportCount': exportCount,
    'spellcheckCount': spellcheckCount,
    'cvCount': cvCount,
    'coverLetterCount': coverLetterCount,
    'proposalCount': proposalCount,
    'stripeCustomerId': stripeCustomerId,
    'stripeSubscriptionId': stripeSubscriptionId,
    'subscriptionStartDate': subscriptionStartDate != null ? Timestamp.fromDate(subscriptionStartDate!) : null,
    'subscriptionEndDate': subscriptionEndDate != null ? Timestamp.fromDate(subscriptionEndDate!) : null,
  };
}