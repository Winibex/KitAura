// lib/features/cv_templates/view/cv_template_card_widget.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../shared/widgets/template_thumbnail.dart';
import '../data/cv_template_data.dart';
import '../../../shared/models/template_model.dart';

class CVTemplateCardWidget extends StatelessWidget {
  final TemplateModel template;
  final VoidCallback onTap;

  const CVTemplateCardWidget({
    super.key,
    required this.template,
    required this.onTap,
  });

  static const BoxDecoration _cardDecoration = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.all(Radius.circular(14)),
    boxShadow: [
      BoxShadow(
        color: Color(0x100F172A),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: _cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPreview()),
              _buildInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildTemplatePreview(),
        ),
        // Premium lock
        if (template.isPremium)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.dustyMauve,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock, color: AppColors.white, size: 10),
                  SizedBox(width: 4),
                  Text(
                    'Pro',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 10,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Popular badge for Classic Navy
        if (template.id == 'classic_navy')
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.magentaBloom,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Popular',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 10,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTemplatePreview() {
    if (template.id == 'blank') return _buildBlankPreview();

    // All templates have asset paths in CvTemplateData — use TemplateThumbnail
    final assetPath = CvTemplateData.getAssetPath(template.id);
    if (assetPath != null) {
      return TemplateThumbnail(
        assetPath: assetPath,
        width: double.infinity,
        height: 500,
        borderRadius: 0,
        showShadow: false,
      );
    }

    // Fallback: unknown template → blank-ish preview
    return Container(
      color: AppColors.lavenderBlush,
      child: const Center(
        child: Icon(LucideIcons.fileText, color: AppColors.almondSilk, size: 40),
      ),
    );
  }

  Widget _buildBlankPreview() {
    return Container(
      color: AppColors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.almondSilk,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Icon(
                LucideIcons.plus,
                color: AppColors.almondSilk,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start from scratch',
              style: TextStyle(
                color: AppColors.slateGrey,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              template.label,
              style: const TextStyle(
                color: AppColors.prussianBlue,
                fontSize: 13,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              template.category[0].toUpperCase() +
                  template.category.substring(1),
              style: const TextStyle(
                color: AppColors.darkRaspberry,
                fontSize: 10,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}