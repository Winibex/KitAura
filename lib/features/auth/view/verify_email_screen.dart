// =============================================================================
// verify_email_screen.dart
//
// Shown immediately after sign-up (or on app launch for unverified users).
// Prompts the user to click the verification link in their inbox, and
// automatically navigates to the dashboard once verified.
//
// Key behaviours:
//   • Sends the verification email on mount.
//   • Polls Firebase for verification status with exponential back-off.
//   • Enforces a 60-second cooldown between manual resend attempts.
//   • Stops polling after [_maxPollFailures] consecutive errors.
//   • Cancels all timers on dispose to prevent setState-after-dispose errors.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/auth_screen_wrapper.dart';
import '../controller/auth_controller.dart';

// =============================================================================
// Widget
// =============================================================================

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  // ---------------------------------------------------------------------------
  // Timers & counters
  // ---------------------------------------------------------------------------

  Timer? _pollingTimer;   // fires to check email verification status
  Timer? _cooldownTimer;  // counts down the resend cooldown period

  /// Seconds remaining before the user may resend the verification email.
  /// Starts at 60 on send; counts down to 0 via [_cooldownTimer].
  int _resendCooldown = 0;

  /// True while a resend request is in flight.
  bool _isResending = false;

  /// Number of consecutive polling failures (network errors, etc.).
  /// Polling stops once this reaches [_maxPollFailures].
  int _pollFailures = 0;

  /// Maximum allowed consecutive poll failures before backing off completely.
  static const _maxPollFailures = 10;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _sendVerification(); // trigger the initial email on mount
    _startPolling();     // begin checking for verification in the background
  }

  @override
  void dispose() {
    // Always cancel timers to avoid setState calls on a dead widget.
    _pollingTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Email sending & cooldown
  // ---------------------------------------------------------------------------

  /// Sends the verification email and starts the 60-second resend cooldown.
  Future<void> _sendVerification() async {
    await ref.read(authControllerProvider.notifier).sendEmailVerification();
    if (!mounted) return;
    setState(() => _resendCooldown = 60);
    _startCooldownTimer();
  }

  /// Decrements [_resendCooldown] every second until it reaches zero.
  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Safety check: cancel if the widget was disposed mid-countdown.
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 0) {
        timer.cancel();
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Polling with exponential back-off
  // ---------------------------------------------------------------------------

  /// Resets the failure counter and kicks off the recursive polling loop.
  void _startPolling() {
    _pollFailures = 0;
    _schedulePoll();
  }

  /// Schedules the next poll with an exponentially increasing delay.
  ///
  /// Back-off schedule (capped at 15 s):
  ///   failures 0–1  → 3 s  (fast initial checks)
  ///   failures 2–3  → 6 s
  ///   failures 4–5  → 12 s
  ///   failures 6+   → 15 s (steady-state)
  ///
  /// The failure counter only increments on actual errors (network, auth).
  /// A successful call that returns "not yet verified" resets [_pollFailures]
  /// so transient errors don't permanently slow the polling.
  void _schedulePoll() {
    if (!mounted || _pollFailures >= _maxPollFailures) return;

    final delay = _pollFailures < 2
        ? 3
        : (_pollFailures < 4 ? 6 : (_pollFailures < 6 ? 12 : 15));

    _pollingTimer?.cancel();
    _pollingTimer = Timer(Duration(seconds: delay), () async {
      if (!mounted) return;

      try {
        final verified = await ref
            .read(authControllerProvider.notifier)
            .checkEmailVerified();

        if (!mounted) return;

        if (verified) {
          // Email verified — navigate to the dashboard immediately.
          context.go(AppRoutes.dashboard);
          return;
        }

        // The call succeeded but the user hasn't clicked the link yet.
        // Reset failure count so the delay doesn't increase on the next poll.
        _pollFailures = 0;
      } catch (_) {
        // Increment failure count to apply back-off on the next schedule.
        _pollFailures++;
      }

      _schedulePoll(); // tail-recursive: schedule the next poll
    });
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  /// Resends the verification email if the cooldown has expired.
  /// Also resets the polling loop so checks resume promptly after a resend.
  Future<void> _resendEmail() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() => _isResending = true);
    await _sendVerification();

    if (!mounted) return;

    setState(() {
      _isResending  = false;
      _pollFailures = 0; // reset back-off — user just acted, so poll quickly
    });

    _schedulePoll();
  }

  /// Signs the user out and navigates back to the auth screen.
  /// Cancels both timers first to avoid any callbacks firing post-navigation.
  Future<void> _signOut() async {
    _pollingTimer?.cancel();
    _cooldownTimer?.cancel();

    // Capture the router before the async gap to avoid using context after
    // the widget may have been unmounted.
    final router = GoRouter.of(context);
    await ref.read(authControllerProvider.notifier).signOut();
    router.go(AppRoutes.auth);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  // REPLACE entire build():
  @override
  Widget build(BuildContext context) {
    final userEmail = ref.watch(authStateProvider).asData?.value?.email ?? '';
    final isMobile = Responsive.isMobile(context);

    return AuthScreenWrapper(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: EdgeInsets.all(isMobile ? 24 : 40),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.prussianBlue.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isMobile ? 56 : 80,
              height: isMobile ? 56 : 80,
              decoration: const BoxDecoration(
                color: AppColors.petalFrost,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.mail,
                  color: AppColors.darkRaspberry,
                  size: isMobile ? 28 : 36),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text('Verify your email',
                style: TextStyle(color: AppColors.prussianBlue,
                    fontSize: isMobile ? 20 : 24,
                    fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('We sent a verification link to\n$userEmail',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slateGrey, fontSize: 14,
                    fontFamily: AppFonts.openSans, height: 1.5)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.petalFrost,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.almondSilk),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.info, color: AppColors.dustyMauve, size: 18),
                  SizedBox(width: 12),
                  Expanded(child: Text(
                    'Click the link in the email to verify your account. This page will update automatically.',
                    style: TextStyle(color: AppColors.prussianBlue, fontSize: 13,
                        fontFamily: AppFonts.openSans, height: 1.4),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _resendCooldown > 0 || _isResending ? null : _resendEmail,
                child: _isResending
                    ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                    : Text(_resendCooldown > 0
                    ? 'Resend in ${_resendCooldown}s'
                    : 'Resend verification email'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _signOut,
              child: const Text('Sign out and use a different account',
                  style: TextStyle(color: AppColors.slateGrey, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}