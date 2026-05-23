// lib/features/settings/view/upgrade_modal.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';

class UpgradeModal extends StatelessWidget {
  const UpgradeModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 40, offset: const Offset(0, 16)),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Dark header ────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      // Close button
                      Align(
                        alignment: Alignment.topRight,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(LucideIcons.x, size: 20, color: Color(0x88FFFFFF)),
                          ),
                        ),
                      ),
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
                          ),
                        ),
                        child: const Icon(LucideIcons.crown, size: 26, color: AppColors.white),
                      ).animate().scale(begin: const Offset(0.6, 0.6), duration: 400.ms, curve: Curves.easeOut),
                      const SizedBox(height: 16),
                      const Text(
                        'Go Pro',
                        style: TextStyle(fontSize: 28, fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.bold, color: AppColors.white),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Everything you need to land interviews.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, fontFamily: AppFonts.openSans,
                            color: Color(0xAAFFFFFF), height: 1.4),
                      ),
                    ],
                  ),
                ),

                // ── Feature grid ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      // Feature items in a 2-column grid
                      Row(
                        children: [
                          Expanded(child: _featureCard(LucideIcons.infinity, 'Unlimited Exports', 'No monthly cap')),
                          const SizedBox(width: 12),
                          Expanded(child: _featureCard(LucideIcons.sparkles, 'Unlimited AI', 'Generate any section')),
                        ],
                      ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _featureCard(LucideIcons.eyeOff, 'No Watermark', 'Clean professional PDFs')),
                          const SizedBox(width: 12),
                          Expanded(child: _featureCard(LucideIcons.layout, 'All Templates', 'Premium designs included')),
                        ],
                      ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _featureCard(LucideIcons.fileText, 'Unlimited CVs', 'Save as many as you want')),
                          const SizedBox(width: 12),
                          Expanded(child: _featureCard(LucideIcons.zap, 'Priority AI', 'Faster generation speed')),
                        ],
                      ).animate().fadeIn(delay: 300.ms, duration: 300.ms),

                      const SizedBox(height: 28),

                      // Price
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            '\$7',
                            style: TextStyle(fontSize: 40, fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.bold, color: AppColors.prussianBlue, height: 1),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text('/month', style: TextStyle(fontSize: 15,
                                fontFamily: AppFonts.openSans, color: AppColors.slateGrey)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // CTA button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Stripe checkout coming soon!'),
                                backgroundColor: AppColors.darkRaspberry,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.darkRaspberry,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Start Pro — \$7/month',
                              style: TextStyle(fontSize: 16, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700)),
                        ),
                      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
                      const SizedBox(height: 16),

                      // Trust signals
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.shield, size: 13, color: AppColors.slateGrey),
                          SizedBox(width: 4),
                          Text('Cancel anytime', style: TextStyle(fontSize: 12, color: AppColors.slateGrey)),
                          SizedBox(width: 20),
                          Icon(LucideIcons.lock, size: 13, color: AppColors.slateGrey),
                          SizedBox(width: 4),
                          Text('Stripe-secured', style: TextStyle(fontSize: 12, color: AppColors.slateGrey)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text('Maybe later',
                              style: TextStyle(fontSize: 13, color: AppColors.slateGrey)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _featureCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.darkRaspberry),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.slateGrey)),
        ],
      ),
    );
  }
}