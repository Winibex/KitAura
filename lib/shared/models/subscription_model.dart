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
  final int editorAiCount;
  final int editorAiRefusalCount;

  // NEW — hourly burst tracking for AI editor
  // editorAiHourlyCount resets to 0 when editorAiHourlyResetAt passes.
  // The Cloud Function handles the reset when the next call comes in.
  final int editorAiHourlyCount;
  final DateTime? editorAiHourlyResetAt;

  // Document counts (lifetime — used by Cloud Functions for fast paywall checks)
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
    this.editorAiCount = 0,
    this.editorAiRefusalCount = 0,
    this.editorAiHourlyCount = 0,
    this.editorAiHourlyResetAt,
    this.cvCount = 0,
    this.coverLetterCount = 0,
    this.proposalCount = 0,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
  });

  // ── Plan state ──────────────────────────────────────────────────
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

  bool get isCycleExpired =>
      cycleEndDate != null && DateTime.now().isAfter(cycleEndDate!);

  // ── Combined counters (used by new paywall model) ───────────────

  /// Total AI Compose + AI Refine calls used this cycle.
  /// The two share a single bucket per the new pricing model.
  int get combinedAiContentCount => aiFillCount + aiRewriteCount;

  /// Total documents across CVs, Cover Letters, and Proposals.
  /// Used for the combined doc paywall (5 free / 30 pro).
  int get combinedDocCount => cvCount + coverLetterCount + proposalCount;

  /// True if the hourly AI editor burst limit has been reached AND the
  /// hourly window hasn't expired yet. Auto-resets when the next Cloud
  /// Function call comes in past the reset timestamp.
  bool isEditorAiHourlyBlocked(int hourlyLimit) {
    if (hourlyLimit < 0) return false; // -1 = unlimited
    if (editorAiHourlyResetAt == null) return false;
    final windowStillOpen = DateTime.now().isBefore(editorAiHourlyResetAt!);
    return windowStillOpen && editorAiHourlyCount >= hourlyLimit;
  }

  // ── Paywall checks (frontend UI hints — server enforces real limits) ─
  bool get canUseAI => isPro || combinedAiContentCount < 15;
  bool get canUseDesign => isPro || aiDesignCount < 5;
  bool get canExport => isPro || exportCount < 3;

  /// Combined doc cap (5 free / 30 pro).
  bool get canCreateDocument =>
      isPro ? combinedDocCount < 30 : combinedDocCount < 5;

  /// AI Edit: monthly cap (7 free / 100 pro) PLUS hourly burst (20/hr pro).
  bool get canUseEditorAI => isPro
      ? (editorAiCount < 100 && !isEditorAiHourlyBlocked(20))
      : editorAiCount < 7;

  /// True once 5 off-topic refusals have hit this cycle.
  bool get isEditorAiSoftBlocked => editorAiRefusalCount >= 5;

  // ── Serialization ───────────────────────────────────────────────
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
      editorAiCount: json['editorAiCount'] as int? ?? 0,
      editorAiRefusalCount: json['editorAiRefusalCount'] as int? ?? 0,
      editorAiHourlyCount: json['editorAiHourlyCount'] as int? ?? 0,
      editorAiHourlyResetAt: (json['editorAiHourlyResetAt'] as Timestamp?)
          ?.toDate(),
      cvCount: json['cvCount'] as int? ?? 0,
      coverLetterCount: json['coverLetterCount'] as int? ?? 0,
      proposalCount: json['proposalCount'] as int? ?? 0,
      stripeCustomerId: json['stripeCustomerId'] as String?,
      stripeSubscriptionId: json['stripeSubscriptionId'] as String?,
      subscriptionStartDate: (json['subscriptionStartDate'] as Timestamp?)
          ?.toDate(),
      subscriptionEndDate: (json['subscriptionEndDate'] as Timestamp?)
          ?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
    'plan': plan,
    'trialStartDate': trialStartDate != null
        ? Timestamp.fromDate(trialStartDate!)
        : null,
    'trialEndDate': trialEndDate != null
        ? Timestamp.fromDate(trialEndDate!)
        : null,
    'trialActive': trialActive,
    'trialUsed': trialUsed,
    'cycleStartDate': cycleStartDate != null
        ? Timestamp.fromDate(cycleStartDate!)
        : null,
    'cycleEndDate': cycleEndDate != null
        ? Timestamp.fromDate(cycleEndDate!)
        : null,
    'lastResetDate': lastResetDate != null
        ? Timestamp.fromDate(lastResetDate!)
        : null,
    'aiFillCount': aiFillCount,
    'aiRewriteCount': aiRewriteCount,
    'aiDesignCount': aiDesignCount,
    'exportCount': exportCount,
    'spellcheckCount': spellcheckCount,
    'editorAiCount': editorAiCount,
    'editorAiRefusalCount': editorAiRefusalCount,
    'editorAiHourlyCount': editorAiHourlyCount,
    'editorAiHourlyResetAt': editorAiHourlyResetAt != null
        ? Timestamp.fromDate(editorAiHourlyResetAt!)
        : null,
    'cvCount': cvCount,
    'coverLetterCount': coverLetterCount,
    'proposalCount': proposalCount,
    'stripeCustomerId': stripeCustomerId,
    'stripeSubscriptionId': stripeSubscriptionId,
    'subscriptionStartDate': subscriptionStartDate != null
        ? Timestamp.fromDate(subscriptionStartDate!)
        : null,
    'subscriptionEndDate': subscriptionEndDate != null
        ? Timestamp.fromDate(subscriptionEndDate!)
        : null,
  };
}
