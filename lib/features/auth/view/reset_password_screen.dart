// =============================================================================
// reset_password_screen.dart
//
// A self-contained screen for requesting a password-reset email.
//
// Flow:
//   1. User enters their email address and taps "Send Reset Link".
//   2. [AuthController.sendPasswordResetEmail] is called.
//   3. On success  → _emailSent flips to true, showing a confirmation UI.
//   4. On failure  → authState.error is displayed above the input field.
//   5. After success, a "Back to Sign In" button returns the user to the auth screen.
// =============================================================================

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

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _emailController = TextEditingController();

  /// Tracks whether the reset email was successfully sent.
  /// When true, the form is replaced with a confirmation message.
  bool _emailSent = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _emailController.dispose(); // prevent memory leak
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Delegates to [AuthController] and flips [_emailSent] on success.
  Future<void> _sendResetEmail() async {
    final success = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordResetEmail(_emailController.text.trim());

    // Guard: widget may have been disposed while the async call was in flight.
    if (!mounted) return;

    if (success) setState(() => _emailSent = true);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
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
            // Icon bubble (no logo — wrapper shows it)
            Container(
              width: isMobile ? 56 : 80,
              height: isMobile ? 56 : 80,
              decoration: const BoxDecoration(
                color: AppColors.petalFrost,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.keyRound,
                  color: AppColors.darkRaspberry,
                  size: isMobile ? 28 : 36),
            ),
            SizedBox(height: isMobile ? 16 : 24),

            Text(
              _emailSent ? 'Check your inbox' : 'Reset your password',
              style: TextStyle(
                color: AppColors.prussianBlue,
                fontSize: isMobile ? 20 : 24,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _emailSent
                  ? 'We sent a reset link to\n${_emailController.text.trim()}'
                  : "Enter your email and we'll send you a reset link.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.slateGrey, fontSize: 14,
                  fontFamily: AppFonts.openSans, height: 1.5),
            ),
            const SizedBox(height: 24),

            if (_emailSent) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.checkCircle, color: AppColors.success, size: 18),
                    SizedBox(width: 12),
                    Expanded(child: Text(
                      "Reset link sent. Check your spam folder if you don't see it.",
                      style: TextStyle(color: AppColors.prussianBlue, fontSize: 13),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.auth),
                  child: const Text('Back to Sign In'),
                ),
              ),
            ],

            if (!_emailSent) ...[
              if (authState.error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(authState.error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Email address',
                    style: TextStyle(color: AppColors.prussianBlue, fontSize: 13,
                        fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: authState.isLoading ? null : _sendResetEmail,
                  child: authState.isLoading
                      ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                      : const Text('Send Reset Link'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(AppRoutes.auth),
                child: const Text('← Back to Sign In',
                    style: TextStyle(color: AppColors.slateGrey, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}