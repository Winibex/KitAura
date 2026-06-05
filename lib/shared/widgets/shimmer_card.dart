// lib/shared/widgets/shimmer_card.dart

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_colors.dart';

// ─── Shared shimmer colors ─────────────────────────────────────────────
// baseColor    = the "resting" skeleton color — must contrast against white bg
// highlightColor = the sweeping flash — slightly lighter than base
final _shimmerBase      = AppColors.lavenderBlush;
final _shimmerHighlight = AppColors.petalFrost;
final _shimmerBlock     = AppColors.petalFrost; // placeholder containers

// ─── CV and CL card shimmer ────────────────────────────────────────────

class TemplateCardShimmerForDashboard extends StatelessWidget {
  const TemplateCardShimmerForDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _shimmerBase,
      highlightColor: _shimmerHighlight,
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
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 140,
                    decoration: BoxDecoration(
                      color: _shimmerBlock,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 100,
                    decoration: BoxDecoration(
                      color: _shimmerBlock,
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
                          color: _shimmerBlock,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Container(
                        height: 24,
                        width: 24,
                        decoration: BoxDecoration(
                          color: _shimmerBlock,
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

// ─── SHIMMER: Stat Cards ───────────────────────────────────────────────

class StatCardShimmer extends StatelessWidget {
  final bool showProgress;

  const StatCardShimmer({
    super.key,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _shimmerBase,
      highlightColor: _shimmerHighlight,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDE8E3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _shimmerBlock,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _shimmerBlock,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: 120,
              height: 28,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            if (showProgress) ...[
              Container(
                width: double.infinity,
                height: 4,
                decoration: BoxDecoration(
                  color: _shimmerBlock,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Container(
              width: 100,
              height: 12,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SHIMMER: Quick Start Cards ────────────────────────────────────────

class QuickStartCardShimmer extends StatelessWidget {
  const QuickStartCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _shimmerBase,
      highlightColor: _shimmerHighlight,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDE8E3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _shimmerBlock,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 40,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _shimmerBlock,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: 90,
              height: 15,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 130,
              height: 12,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SHIMMER: Recent Activity ──────────────────────────────────────────

class RecentActivityShimmer extends StatelessWidget {
  const RecentActivityShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _shimmerBase,
      highlightColor: _shimmerHighlight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDE8E3)),
        ),
        child: Column(
          children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFBF8F6),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Container(
                      height: 11,
                      width: 60,
                      decoration: BoxDecoration(
                        color: _shimmerBlock,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 11,
                      width: 30,
                      decoration: BoxDecoration(
                        color: _shimmerBlock,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 11,
                      width: 50,
                      decoration: BoxDecoration(
                        color: _shimmerBlock,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 11,
                      width: 55,
                      decoration: BoxDecoration(
                        color: _shimmerBlock,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            // 4 row placeholders
            ...List.generate(4, (i) => _buildRowShimmer(isLast: i == 3)),
          ],
        ),
      ),
    );
  }

  Widget _buildRowShimmer({required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF0EBE6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _shimmerBlock,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: _shimmerBlock,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 22,
                width: 55,
                decoration: BoxDecoration(
                  color: _shimmerBlock,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 12,
              width: 60,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 12,
              width: 50,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Container(
              height: 14,
              width: 14,
              decoration: BoxDecoration(
                color: _shimmerBlock,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}