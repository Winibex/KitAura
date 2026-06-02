import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';

class EmptyStateWidget extends StatelessWidget {
  final VoidCallback onCreateCV;

  const EmptyStateWidget({
    super.key,
    required this.onCreateCV,
  });

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
            'Create your first CV from the sidebar',
            style: TextStyle(
              color: AppColors.slateGrey,
              fontSize: 13,
              fontFamily: AppFonts.openSans,
            ),
          ),
        ],
      ),
    );
  }
}