import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

Widget chipInput({
  required TextEditingController controller,
  required String hint,
  required List<String> items,
  required VoidCallback onAdd,
  required ValueChanged<String> onRemove,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSubmitted: (_) => onAdd(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: Size.zero,
              ),
              child: const Icon(LucideIcons.plus,
                  color: AppColors.white, size: 18),
            ),
          ),
        ],
      ),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            return Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.petalFrost,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.prussianBlue,
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onRemove(item),
                    child: const Icon(LucideIcons.x,
                        color: AppColors.slateGrey, size: 14),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ],
  );
}