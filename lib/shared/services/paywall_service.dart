// lib/shared/services/paywall_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';

class PaywallResult {
  final bool allowed;
  final String? message;
  const PaywallResult({required this.allowed, this.message});
}

class PaywallService {
  PaywallService._();

  static Future<PaywallResult> canCreateCV() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const PaywallResult(allowed: false, message: 'Not signed in');

    final subDoc = await FirebaseService.getSubscription(uid);
    if (!subDoc.exists) return const PaywallResult(allowed: false, message: 'No subscription');
    final sub = subDoc.data() as Map<String, dynamic>;
    final plan = sub['plan'] ?? 'free';

    if (plan == 'pro' || (plan == 'trial' && (sub['trialActive'] ?? false))) {
      return const PaywallResult(allowed: true);
    }

    final limits = await FirebaseService.getPlanLimits(plan);
    final max = limits['maxCvs'] ?? 3;
    if (max == 999) return const PaywallResult(allowed: true);

    // Count from actual collection (not subscription counter)
    final cvs = await FirebaseService.getUserCVs(uid);
    if (cvs.docs.length >= max) {
      return PaywallResult(
        allowed: false,
        message: 'You\'ve reached the limit of $max CVs on the free plan. Upgrade to Pro for unlimited.',
      );
    }
    return const PaywallResult(allowed: true);
  }

  static Future<PaywallResult> canCreateCoverLetter() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const PaywallResult(allowed: false, message: 'Not signed in');

    final subDoc = await FirebaseService.getSubscription(uid);
    if (!subDoc.exists) return const PaywallResult(allowed: false, message: 'No subscription');
    final sub = subDoc.data() as Map<String, dynamic>;
    final plan = sub['plan'] ?? 'free';

    if (plan == 'pro' || (plan == 'trial' && (sub['trialActive'] ?? false))) {
      return const PaywallResult(allowed: true);
    }

    final limits = await FirebaseService.getPlanLimits(plan);
    final max = limits['maxCoverLetters'] ?? 3;
    if (max == 999) return const PaywallResult(allowed: true);

    final cls = await FirebaseService.getUserCoverLetters(uid);
    if (cls.docs.length >= max) {
      return PaywallResult(
        allowed: false,
        message: 'You\'ve reached the limit of $max cover letters on the free plan. Upgrade to Pro for unlimited.',
      );
    }
    return const PaywallResult(allowed: true);
  }

  static Future<PaywallResult> canCreateProposal() async =>
      _checkDocLimit('proposalCount', 'maxProposals', 'proposals');

  static Future<PaywallResult> canExport() async =>
      _checkUsageLimit('exportCount', 'exportsPerMonth', 'exports this month');

  static Future<PaywallResult> canAiFill() async =>
      _checkUsageLimit('aiFillCount', 'aiFillPerMonth', 'AI fills this month');

  static Future<PaywallResult> canAiRewrite() async =>
      _checkUsageLimit('aiRewriteCount', 'aiRewritePerMonth', 'AI rewrites this month');

  static Future<PaywallResult> _checkDocLimit(
      String counterField, String limitField, String label) async
  {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const PaywallResult(allowed: false, message: 'Not signed in');

    final subDoc = await FirebaseService.getSubscription(uid);
    if (!subDoc.exists) return const PaywallResult(allowed: false, message: 'No subscription');

    final sub = subDoc.data() as Map<String, dynamic>;
    final plan = sub['plan'] ?? 'free';

    // Pro/trial users have no limits
    if (plan == 'pro' || (plan == 'trial' && (sub['trialActive'] ?? false))) {
      return const PaywallResult(allowed: true);
    }

    final limits = await FirebaseService.getPlanLimits(plan);
    final current = sub[counterField] ?? 0;
    final max = limits[limitField] ?? 3;

    if (max == 999) return const PaywallResult(allowed: true); // unlimited

    if (current >= max) {
      return PaywallResult(
        allowed: false,
        message: 'You\'ve reached the limit of $max $label on the free plan. Upgrade to Pro for unlimited.',
      );
    }

    return const PaywallResult(allowed: true);
  }

  static Future<PaywallResult> _checkUsageLimit(
      String counterField, String limitField, String label) async
  {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const PaywallResult(allowed: false, message: 'Not signed in');

    final subDoc = await FirebaseService.getSubscription(uid);
    if (!subDoc.exists) return const PaywallResult(allowed: false, message: 'No subscription');

    final sub = subDoc.data() as Map<String, dynamic>;
    final plan = sub['plan'] ?? 'free';

    if (plan == 'pro' || (plan == 'trial' && (sub['trialActive'] ?? false))) {
      return const PaywallResult(allowed: true);
    }

    final limits = await FirebaseService.getPlanLimits(plan);
    final current = sub[counterField] ?? 0;
    final max = limits[limitField] ?? 3;

    if (max == 999) return const PaywallResult(allowed: true);

    if (current >= max) {
      return PaywallResult(
        allowed: false,
        message: 'You\'ve used all $max $label. Upgrade to Pro for unlimited.',
      );
    }

    return const PaywallResult(allowed: true);
  }
}