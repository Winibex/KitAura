// lib/shared/widgets/guest_save_modal.dart
//
// Shown after a successful PDF export for anonymous users.
// Mandatory dismiss — user must interact (Create Account or No Thanks).
// Step 12 will upgrade "Create Account" to inline linkWithCredential.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import 'guest_signup_modal.dart';

class GuestSaveModal extends StatelessWidget {
  /// e.g. 'CV', 'Cover Letter', 'Proposal'
  final String documentType;

  const GuestSaveModal({super.key, required this.documentType});

  /// Shows the modal only if user is anonymous. No-op for signed-in users.
  /// Call after successful PDF download.
  static Future<void> showIfGuest(BuildContext context, String documentType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => GuestSaveModal(documentType: documentType),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                LucideIcons.checkCircle,
                size: 30,
                color: Color(0xFF43A047),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Your $documentType is ready!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
                color: AppColors.prussianBlue,
              ),
            ),
            const SizedBox(height: 12),

            // Subtitle
            const Text(
              'Your download has started. Want to keep your work safe?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // Benefits
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lavenderBlush,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  _BenefitRow(
                    icon: LucideIcons.shield,
                    text: 'Your documents stay safe in the cloud',
                  ),
                  SizedBox(height: 10),
                  _BenefitRow(
                    icon: LucideIcons.monitor,
                    text: 'Access from any device, anytime',
                  ),
                  SizedBox(height: 10),
                  _BenefitRow(
                    icon: LucideIcons.sparkles,
                    text: 'Get more AI calls and exports',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Warning
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.petalFrost,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.almondSilk.withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 14, color: AppColors.dustyRose),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Without an account, your work may be lost if you clear browser data.',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.prussianBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Primary CTA
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await GuestSignupModal.show(context);
                },
                icon: const Icon(LucideIcons.userPlus, size: 18),
                label: const Text('Create Free Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Dismiss
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  "No thanks, I'll take the risk",
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slateGrey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.darkRaspberry),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: AppFonts.openSans,
              color: AppColors.prussianBlue,
            ),
          ),
        ),
      ],
    );
  }
}