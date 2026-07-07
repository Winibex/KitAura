// lib/shared/services/paywall_service.dart
//
// Frontend paywall checks (UI hints). Cloud Functions are the real
// source of truth — these checks prevent obvious paywall hits before
// the user clicks through.
//
// PRICING MODEL:
//   - Documents: combined guest 3 / free 5 / pro 30
//   - AI Content (Compose + Refine): combined guest 15 / free 30 / pro 100
//   - AI Edit: guest 7 / free 15 / pro 100 + 20/hour burst
//   - Spellcheck: unlimited all tiers
//   - All limits admin-editable via config/limits
//
// PLAN HIERARCHY:
//   guest → anonymous Firebase user (lazy registration)
//   free  → signed-up user
//   trial → 7-day free trial (treated as pro)
//   pro   → paid (deferred)

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

  static bool _isGuest(Map<String, dynamic> sub) {
    return sub['plan'] == 'guest';
  }

  static String _planKey(Map<String, dynamic> sub) {
    return sub['plan'] ?? 'free';
  }

  /// Returns user-appropriate upgrade nudge based on plan.
  static String _upgradeNudge(Map<String, dynamic> sub) {
    if (_isGuest(sub)) return 'Sign up for free to get higher limits.';
    return 'Upgrade to Pro for higher limits.';
  }

  // ─── DOCUMENT CREATION (combined cap) ─────────────────────────────

  static Future<PaywallResult> canCreateDocument() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }

    final plan = _planKey(sub);
    final limits = await FirebaseService.getPlanLimits(plan);
    final maxDocs = limits['maxDocs'] ?? 5;
    final total =
        (sub['cvCount'] ?? 0) +
            (sub['coverLetterCount'] ?? 0) +
            (sub['proposalCount'] ?? 0);

    if (maxDocs == 999) return const PaywallResult(allowed: true);

    if (total >= maxDocs) {
      return PaywallResult(
        allowed: false,
        message: _isGuest(sub)
            ? "You've reached the $maxDocs-document limit. Sign up for free to create more documents."
            : _isPro(sub)
            ? "You've reached the $maxDocs-document limit. Contact support if you need more."
            : "You've reached the $maxDocs-document limit on the free plan. Upgrade to Pro for more documents.",
      );
    }
    return const PaywallResult(allowed: true);
  }

  // Backwards-compatible aliases.
  static Future<PaywallResult> canCreateCV() => canCreateDocument();
  static Future<PaywallResult> canCreateCoverLetter() => canCreateDocument();
  static Future<PaywallResult> canCreateProposal() => canCreateDocument();

  // ─── AI CONTENT (Compose + Refine combined) ───────────────────────

  static Future<PaywallResult> canUseAiContent() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }

    final plan = _planKey(sub);
    final limits = await FirebaseService.getPlanLimits(plan);
    final max = limits['aiFillPerMonth'] ?? 15;
    final used = (sub['aiFillCount'] ?? 0) + (sub['aiRewriteCount'] ?? 0);

    if (max == 999) return const PaywallResult(allowed: true);

    if (used >= max) {
      return PaywallResult(
        allowed: false,
        message: _isGuest(sub)
            ? "You've used all $max AI Compose + Refine calls. Sign up for free to get more."
            : _isPro(sub)
            ? "You've used all $max AI Compose + Refine calls this month."
            : "You've used all $max AI calls on the free plan. Upgrade to Pro for 100 per month.",
      );
    }
    return const PaywallResult(allowed: true);
  }

  // Aliases for old call sites.
  static Future<PaywallResult> canAiFill() => canUseAiContent();
  static Future<PaywallResult> canAiRewrite() => canUseAiContent();

  // ─── AI EDIT (monthly + hourly + refusal) ─────────────────────────

  static Future<PaywallResult> canUseEditorAi() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }

    final plan = _planKey(sub);
    final limits = await FirebaseService.getPlanLimits(plan);
    final monthlyMax = limits['aiEditPerMonth'] ?? 7;
    final used = sub['editorAiCount'] ?? 0;

    if (monthlyMax != 999 && used >= monthlyMax) {
      return PaywallResult(
        allowed: false,
        message: _isGuest(sub)
            ? "You've used all $monthlyMax AI Assistant calls. Sign up for free to get more."
            : _isPro(sub)
            ? "You've used all $monthlyMax AI Assistant calls this month."
            : "You've used all $monthlyMax AI Assistant calls on the free plan. Upgrade to Pro for 100 per month.",
      );
    }

    // Hourly burst check (Pro only — other tiers' monthly cap is too low).
    if (_isPro(sub)) {
      final hourlyCount = sub['editorAiHourlyCount'] ?? 0;
      final burstLimit = limits['aiEditHourlyBurst'] ?? 20;
      final resetAtRaw = sub['editorAiHourlyResetAt'];
      if (burstLimit != 999 && resetAtRaw != null && hourlyCount >= burstLimit) {
        try {
          final resetAt = (resetAtRaw as dynamic).toDate() as DateTime;
          if (DateTime.now().isBefore(resetAt)) {
            final mins = resetAt.difference(DateTime.now()).inMinutes;
            return PaywallResult(
              allowed: false,
              message:
              "You've used $burstLimit AI Assistant calls in the last hour. Try again in $mins minutes.",
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

  // ─── EXPORTS ──────────────────────────────────────────────────────

  static Future<PaywallResult> canExport() async {
    final sub = await _getSubData();
    if (sub == null) {
      return const PaywallResult(allowed: false, message: 'Not signed in');
    }
    if (_isPro(sub)) return const PaywallResult(allowed: true);

    final plan = _planKey(sub);
    final limits = await FirebaseService.getPlanLimits(plan);
    final current = sub['exportCount'] ?? 0;
    final max = limits['exportsPerMonth'] ?? 3;

    if (max == 999) return const PaywallResult(allowed: true);

    if (current >= max) {
      return PaywallResult(
        allowed: false,
        message: _isGuest(sub)
            ? "You've used all $max exports. Sign up for free to get more."
            : "You've used all $max exports this month. Upgrade to Pro for unlimited.",
      );
    }
    return const PaywallResult(allowed: true);
  }
}