// lib/features/cover_letter/view/cl_template_preview_modal.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../shared/widgets/template_thumbnail.dart';
import '../data/cl_template_data.dart';

class ClTemplatePreviewModal extends StatelessWidget {
  final ClTemplateInfo info;
  final VoidCallback onUse;

  const ClTemplatePreviewModal({
    super.key,
    required this.info,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final modalWidth = screenSize.width > 1000 ? 900.0 : screenSize.width * 0.95;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: modalWidth,
          maxHeight: screenSize.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Expanded(
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _buildPreview()),
                    Expanded(flex: 2, child: _buildDetails(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.petalFrost)),
      ),
      child: Row(
        children: [
          Text(
            info.label,
            style: const TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 18,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          if (info.isPremium)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.magentaBloom,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.crown, size: 10, color: AppColors.white),
                  SizedBox(width: 4),
                  Text('PRO',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(LucideIcons.x, size: 20, color: AppColors.slateGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      color: const Color(0xFFE8E0D8),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: AspectRatio(
          aspectRatio: 595 / 842,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) => TemplateThumbnail(
                assetPath: info.assetPath,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this template',
            style: TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            info.description,
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 13,
              fontFamily: AppFonts.openSans,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lavenderBlush,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.sparkles, size: 14, color: AppColors.darkRaspberry),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI will help you write compelling content tailored to the job',
                    style: TextStyle(
                      color: AppColors.prussianBlue,
                      fontSize: 11,
                      fontFamily: AppFonts.openSans,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onUse,
              icon: const Icon(LucideIcons.fileText, size: 16),
              label: const Text('Use this template'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}