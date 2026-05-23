import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

Widget statCard({
  required IconData icon,
  required String label,
  required String value,
  required String subtext,
  Color subtextColor = AppColors.slateGrey,
  bool showProgress = false,
  double progressValue = 0,
})
{
  return Container(
    height: 130,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x060F172A),
          blurRadius: 8,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: AppColors.petalFrost,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.darkRaspberry, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.slateGrey,
                  fontSize: 11,
                  fontFamily: AppFonts.openSans,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.prussianBlue,
                fontSize: 24,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (showProgress) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progressValue,
                  backgroundColor: AppColors.petalFrost,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.darkRaspberry,
                  ),
                  minHeight: 4,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              subtext,
              style: TextStyle(
                color: subtextColor,
                fontSize: 11,
                fontFamily: AppFonts.openSans,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}