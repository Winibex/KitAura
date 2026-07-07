import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_sizes.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.petalFrost,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.fileText,
              color: AppColors.darkRaspberry,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No CVs yet',
            style: TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 18,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create your first CV to get started',
            style: TextStyle(
              color: AppColors.slateGrey,
              fontSize: 13,
              fontFamily: AppFonts.openSans,
            ),
          ),
          const SizedBox(height: 15),
           Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkRaspberry,
                borderRadius: BorderRadius.circular(10),
              ),
              width: 110,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(LucideIcons.plus, size: 13, color: AppColors.white,),
                  Text(
                    'New CV',
                    style: TextStyle(
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      fontSize: AppSizes.caption(context),
                      color: AppColors.white
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
