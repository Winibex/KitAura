import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

Widget addItemButton(String label, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.almondSilk, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.plus,
              color: AppColors.darkRaspberry, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkRaspberry,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}