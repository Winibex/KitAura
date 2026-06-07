// lib/features/settings/view/upgrade_modal.dart
//
// Compact Go Pro modal — fits on screen without scrolling.
// Shows all plan benefits in a clean grid.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';

class UpgradeModal extends StatelessWidget {
  const UpgradeModal({super.key});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 768;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: 24,
      ),
      child: Container(
        width: isMobile ? screenW - 32 : 480,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - 48,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            // Scrollable middle
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _buildFeatureGrid(isMobile),
              ),
            ),
            // Pinned bottom
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0EBE6))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPricing(),
                  const SizedBox(height: 16),
                  _buildCTA(context),
                  const SizedBox(height: 12),
                  _buildFooter(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.prussianBlue, Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.crown, color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Go Pro',
                    style: TextStyle(color: AppColors.white, fontSize: 20,
                        fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
                Text('Everything you need to land interviews.',
                    style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12,
                        fontFamily: AppFonts.openSans)),
              ],
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(LucideIcons.x, color: Color(0x88FFFFFF), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureGrid(bool isMobile) {
    const features = [
      _Feature(LucideIcons.infinity, 'Unlimited Exports', 'No monthly cap'),
      _Feature(LucideIcons.sparkles, 'Unlimited AI', 'Fill, rewrite & design'),
      _Feature(LucideIcons.fileText, 'Unlimited CVs', 'Save as many as you want'),
      _Feature(LucideIcons.mail, 'Unlimited Cover Letters', 'Tailored to every job'),
      _Feature(LucideIcons.briefcase, 'Unlimited Proposals', 'Win more clients'),
      _Feature(LucideIcons.layout, 'All Templates', 'Premium designs included'),
      _Feature(LucideIcons.sparkle, 'AI Design', 'Auto-generate layouts'),
      _Feature(LucideIcons.shield, 'No Watermark', 'Clean professional PDFs'),
    ];

    // On mobile: full-width list. On desktop: 2-column grid.
    if (isMobile) {
      return Column(
        children: features.map((f) => _featureCard(f)).toList(),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: features.map((f) => SizedBox(
        width: 205,
        child: _featureCard(f),
      )).toList(),
    );
  }

  Widget _featureCard(_Feature f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Row(
        children: [
          Icon(f.icon, size: 16, color: AppColors.darkRaspberry),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title,
                    style: const TextStyle(color: AppColors.prussianBlue, fontSize: 12,
                        fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600)),
                Text(f.subtitle,
                    style: const TextStyle(color: AppColors.slateGrey, fontSize: 10,
                        fontFamily: AppFonts.openSans)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricing() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text('\$7',
            style: TextStyle(color: AppColors.prussianBlue, fontSize: 36,
                fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
        Text('/month',
            style: TextStyle(color: AppColors.slateGrey, fontSize: 14,
                fontFamily: AppFonts.openSans)),
      ],
    );
  }

  Widget _buildCTA(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            Navigator.pop(context);
            // TODO: Stripe checkout
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkRaspberry.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text('Start Pro — \$7/month',
                  style: TextStyle(color: AppColors.white, fontSize: 15,
                      fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.shield, size: 12, color: AppColors.slateGrey),
            const SizedBox(width: 4),
            const Text('Cancel anytime',
                style: TextStyle(color: AppColors.slateGrey, fontSize: 11,
                    fontFamily: AppFonts.openSans)),
            const SizedBox(width: 16),
            Icon(LucideIcons.lock, size: 12, color: AppColors.slateGrey),
            const SizedBox(width: 4),
            const Text('Stripe-secured',
                style: TextStyle(color: AppColors.slateGrey, fontSize: 11,
                    fontFamily: AppFonts.openSans)),
          ],
        ),
        const SizedBox(height: 10),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Text('Maybe later',
                style: TextStyle(color: AppColors.slateGrey, fontSize: 12,
                    fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Feature(this.icon, this.title, this.subtitle);
}