// Horizontal pill/chip selector with active state.
// Used by: ai_setup, proposal_setup, cover_letter_setup, settings preferences.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

Widget pillSelector({
  required List<String> options,
  required List<String> labels,
  required String selected,
  required ValueChanged<String> onSelect,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: List.generate(options.length, (i) {
      final isActive = selected == options[i];
      return GestureDetector(
        onTap: () => onSelect(options[i]),
        child: AnimatedContainer(
          duration: 150.ms,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.darkRaspberry : AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: isActive ? null : Border.all(color: AppColors.almondSilk),
          ),
          child: Text(
            labels[i],
            style: TextStyle(
              color: isActive ? AppColors.white : AppColors.prussianBlue,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }),
  );
}
