// lib/shared/widgets/shimmer_card.dart

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_colors.dart';

class ShimmerCard extends StatelessWidget {
  final double height;
  final double? width;
  final double borderRadius;

  const ShimmerCard({
    super.key,
    this.height = 300,
    this.width,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.petalFrost,
      highlightColor: AppColors.white,
      child: Container(
        height: height,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: AppColors.petalFrost,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

// CV card shimmer — matches exact CV card layout
class CvCardShimmer extends StatelessWidget {
  const CvCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.petalFrost,
      highlightColor: AppColors.white,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail placeholder
            Container(
              height: 200,
              decoration: const BoxDecoration(
                color: AppColors.petalFrost,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
            ),
            // Info placeholder
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 140,
                    decoration: BoxDecoration(
                      color: AppColors.petalFrost,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 100,
                    decoration: BoxDecoration(
                      color: AppColors.petalFrost,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        height: 24,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppColors.petalFrost,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Container(
                        height: 24,
                        width: 24,
                        decoration: BoxDecoration(
                          color: AppColors.petalFrost,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}