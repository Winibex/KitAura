// lib/features/proposal/template/view/prop_template_card_widget.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../shared/widgets/template_thumbnail.dart';
import '../data/prop_template_data.dart';

class PropTemplateCardWidget extends StatelessWidget {
  final PropTemplateInfo template;
  final VoidCallback onTap;

  const PropTemplateCardWidget({
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
          child: TemplateThumbnail(
            assetPath: template.assetPath,
            width: double.infinity,
            height: 500,
            borderRadius: 0,
            showShadow: false,
          ),
        ),
        if (template.isPremium)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.dustyMauve,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock,
                      color: AppColors.white, size: 10),
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
      ],
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
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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