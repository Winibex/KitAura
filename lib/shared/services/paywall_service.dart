// lib/shared/services/paywall_service.dart
//
// Frontend paywall checks (UI hints). The Cloud Functions are the real
// source of truth — these checks just prevent obvious paywall hits before
// the user clicks through.
//
// NEW PRICING MODEL:
//   - Documents: combined 5 free / 30 pro (CVs + CLs + Proposals together)
//   - AI Content (Compose + Refine): combined 15 free / 100 pro
//   - AI Edit: 7 free / 100 pro + 20/hour burst
//   - Spellcheck: unlimited all tiers

import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';

class PaywallResult {
  final bool allowed;
  final String? message;
  const PaywallResult({required this.allowed, this.message});
}

class PaywallService {
  PaywallService._();

  // ─── Shared helpers ───────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _getSubData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final subDoc = await FirebaseService.getSubscription(uid);
    if (!subDoc.exists) return null;
    return subDoc.data() as Map<String, dynamic>;
  }

  static bool _isPro(Map<String, dynamic> sub) {
    final plan = sub['plan'] ?? 'free';
    return plan == 'pro' || (plan == 'trial' && (sub['trialActive'] ?? false));
  }

  // ─── DOCUMENT CREATION (combined cap) ─────────────────────────────

  /// Combined doc paywall — 5 free / 30 pro across CVs + Letters + Proposals.
  /// Called before creating any document (CV, CL, or Proposal).
  static Future<PaywallResult> canCreateDocument() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }
    if (_isPro(sub)) {
      // Pro still has a 30-doc ceiling.
      final total =
          (sub['cvCount'] ?? 0) +
          (sub['coverLetterCount'] ?? 0) +
          (sub['proposalCount'] ?? 0);
      if (total >= 30) {
        return const PaywallResult(
          allowed: false,
          message:
              "You've reached the 30-document limit. Contact support if you need more.",
        );
      }
      return const PaywallResult(allowed: true);
    }
    final total =
        (sub['cvCount'] ?? 0) +
        (sub['coverLetterCount'] ?? 0) +
        (sub['proposalCount'] ?? 0);
    if (total >= 5) {
      return const PaywallResult(
        allowed: false,
        message:
            "You've reached the 5-document limit on the free plan. Upgrade to Pro for up to 30 documents.",
      );
    }
    return const PaywallResult(allowed: true);
  }

  // Backwards-compatible aliases — existing call sites keep working.
  static Future<PaywallResult> canCreateCV() => canCreateDocument();
  static Future<PaywallResult> canCreateCoverLetter() => canCreateDocument();
  static Future<PaywallResult> canCreateProposal() => canCreateDocument();

  // ─── AI CONTENT (Compose + Refine combined) ───────────────────────

  /// Combined AI content paywall — 15 free / 100 pro.
  /// Used by both AI Compose (Fill) and AI Refine (Rewrite).
  static Future<PaywallResult> canUseAiContent() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }
    final isPro = _isPro(sub);
    final used = (sub['aiFillCount'] ?? 0) + (sub['aiRewriteCount'] ?? 0);
    final max = isPro ? 100 : 15;
    if (used >= max) {
      return PaywallResult(
        allowed: false,
        message: isPro
            ? "You've used all $max AI Compose + Refine calls this month."
            : "You've used all $max AI Compose + Refine calls on the free plan. Upgrade to Pro for $max more."
                  .replaceFirst('$max more', '100 per month'),
      );
    }
    return const PaywallResult(allowed: true);
  }

  // Aliases for old call sites.
  static Future<PaywallResult> canAiFill() => canUseAiContent();
  static Future<PaywallResult> canAiRewrite() => canUseAiContent();

  // ─── AI EDIT (monthly + hourly) ───────────────────────────────────

  static Future<PaywallResult> canUseEditorAi() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }
    final isPro = _isPro(sub);
    final used = sub['editorAiCount'] ?? 0;
    final monthlyMax = isPro ? 100 : 7;

    if (used >= monthlyMax) {
      return PaywallResult(
        allowed: false,
        message: isPro
            ? "You've used all $monthlyMax AI Assistant calls this month."
            : "You've used all $monthlyMax AI Assistant calls on the free plan. Upgrade to Pro for 100 per month.",
      );
    }

    // Hourly burst check (Pro only — free monthly cap is too low for hourly to matter).
    if (isPro) {
      final hourlyCount = sub['editorAiHourlyCount'] ?? 0;
      final resetAtRaw = sub['editorAiHourlyResetAt'];
      if (resetAtRaw != null && hourlyCount >= 20) {
        try {
          final resetAt = (resetAtRaw as dynamic).toDate() as DateTime;
          if (DateTime.now().isBefore(resetAt)) {
            final mins = resetAt.difference(DateTime.now()).inMinutes;
            return PaywallResult(
              allowed: false,
              message:
                  "You've used 20 AI Assistant calls in the last hour. Try again in $mins minutes.",
            );
          }
        } catch (_) {
          // Bad timestamp — let it through; server will catch it.
        }
      }
    }

    // Soft-block check (5 refusals / cycle, all tiers).
    final refusals = sub['editorAiRefusalCount'] ?? 0;
    if (refusals >= 5) {
      return const PaywallResult(
        allowed: false,
        message:
            "AI Assistant is for editing this document only. You've made several off-topic requests — try again next cycle.",
      );
    }

    return const PaywallResult(allowed: true);
  }

  // ─── EXPORTS (unchanged) ──────────────────────────────────────────

  static Future<PaywallResult> canExport() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }
    if (_isPro(sub)) return const PaywallResult(allowed: true);
    final limits = await FirebaseService.getPlanLimits(sub['plan'] ?? 'free');
    final current = sub['exportCount'] ?? 0;
    final max = limits['exportsPerMonth'] ?? 3;
    if (max == 999) return const PaywallResult(allowed: true);
    if (current >= max) {
      return PaywallResult(
        allowed: false,
        message:
            "You've used all $max exports this month. Upgrade to Pro for unlimited.",
      );
    }
    return const PaywallResult(allowed: true);
  }
}
