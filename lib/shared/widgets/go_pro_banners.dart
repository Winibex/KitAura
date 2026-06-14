// lib/shared/widgets/go_pro_banners.dart
//
// All "Go Pro" / "Start Trial" banner variants in one file.
// Used across: Dashboard, CV Dashboard, CL Dashboard, Settings.
//
// VARIANTS:
//   1. GoProDashboardBanner   — full-width dark bar (main dashboard top)
//   2. GoProStatCard          — small gradient card (stat card row)
//   3. GoProToolBanner        — full-width gradient bar (bottom of tool dashboards)
//   4. GoProTrialBanner       — trial countdown bar (shown during active trial)
//
// LOGIC:
//   - Free + trial not used → shows "Start 7-Day Free Trial" CTA
//   - Free + trial used    → shows "Upgrade to Pro — $8/mo" CTA
//   - Trial active         → shows "Trial: X days remaining" + upgrade CTA
//   - Pro                  → hides all banners

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/utils/responsive.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';
import '../ai/claude_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// SHIMMER CTA BUTTON — reused across all banners
// ═══════════════════════════════════════════════════════════════════════

class _ShimmerCta extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ShimmerCta({
    required this.label,
    required this.onTap,
  });

  @override
  State<_ShimmerCta> createState() => _ShimmerCtaState();
}

class _ShimmerCtaState extends State<_ShimmerCta> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  final Color textColor = AppColors.darkRaspberry;
  final Color bgColor = AppColors.white;
  final Color shimmerColor = const Color(0x33FFFFFF);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Shimmer overlay
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Transform.translate(
                        offset: Offset(
                          (_ctrl.value * 2 - 1) * 200,
                          0,
                        ),
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                shimmerColor,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PULSING ICON — gentle glow animation on the crown
// ═══════════════════════════════════════════════════════════════════════

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Color glowColor;

  const _PulsingIcon({
    required this.icon,
    required this.color,
    required this.glowColor,
  });

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final double size = 22;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final glow = 0.15 + (_ctrl.value * 0.2);
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: widget.glowColor.withValues(alpha: glow),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(widget.icon, size: size, color: widget.color),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FEATURE CHIP — small inline badges like "No credit card" "7 days"
// ═══════════════════════════════════════════════════════════════════════

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withValues(alpha: 0.9)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontSize: 10,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. DASHBOARD BANNER — IMPROVED (full-width, taller, animated)
// ═══════════════════════════════════════════════════════════════════════

class GoProDashboardBanner extends ConsumerWidget {
  final String plan;
  final bool trialActive;
  final int? trialDaysRemaining;
  final VoidCallback onStartTrial;
  final VoidCallback onUpgrade;

  const GoProDashboardBanner({
    super.key,
    required this.plan,
    required this.trialActive,
    required this.trialDaysRemaining,
    required this.onStartTrial,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);

    // Pro → show active banner
    if (state.isPro) return const ProActiveDashboardBanner();

    // Trial → countdown
    if (plan == 'trial' && trialActive) {
      return _TrialCountdownBanner(
        daysRemaining: trialDaysRemaining ?? 0,
        onUpgrade: onUpgrade,
        proPrice: state.proPrice,
      );
    }

    // Free → trial or upgrade
    return _FreeDashboardBanner(
      trialUsed: state.trialUsed,
      onStartTrial: onStartTrial,
      onUpgrade: onUpgrade,
      proPrice: state.proPrice,
    );
  }
}

class _FreeDashboardBanner extends StatelessWidget {
  final bool trialUsed;
  final VoidCallback onStartTrial;
  final VoidCallback onUpgrade;
  final double proPrice;

  const _FreeDashboardBanner({
    required this.trialUsed,
    required this.onStartTrial,
    required this.onUpgrade,
    required this.proPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.prussianBlue, Color(0xFF1A2744)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.prussianBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ResponsiveBuilder(
        mobile: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PulsingIcon(icon: LucideIcons.crown, color: AppColors.white, glowColor: AppColors.darkRaspberry),
            const SizedBox(height: 12),
            Text(trialUsed ? 'Unlock the full KitAura experience' : 'Try KitAura Pro free for 7 days',
                style: TextStyle(color: AppColors.white, fontSize: AppSizes.headingSm(context),
                    fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(trialUsed ? 'Unlimited exports, AI & more' : 'No credit card needed',
                style: TextStyle(color: AppColors.white.withValues(alpha: 0.7),
                    fontSize: AppSizes.caption(context), fontFamily: AppFonts.openSans)),
            const SizedBox(height: 14),
            _ShimmerCta(
                label: trialUsed ?
                ( proPrice != -1 ? 'Upgrade — \$${proPrice.toStringAsFixed(0)}/mo'
                    : 'Unavailable' )
                    : 'Start Free Trial',
                onTap: trialUsed ? onUpgrade : onStartTrial),
          ],
        ),
        desktop: Row(
          children: [
            _PulsingIcon(icon: LucideIcons.crown, color: AppColors.white, glowColor: AppColors.darkRaspberry),
            const SizedBox(width: 20),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trialUsed ? 'Unlock the full KitAura experience' : 'Try KitAura Pro free for 7 days',
                    style: const TextStyle(color: AppColors.white, fontSize: 17,
                        fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(trialUsed ? 'Unlimited exports, AI generation, premium templates & more'
                    : 'Unlimited exports, AI generation & premium templates — no credit card needed',
                    style: TextStyle(color: AppColors.white.withValues(alpha: 0.7),
                        fontSize: 12, fontFamily: AppFonts.openSans, height: 1.4)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (!trialUsed) const _FeatureChip(icon: LucideIcons.creditCard, label: 'No credit card'),
                  const _FeatureChip(icon: LucideIcons.infinity, label: 'Unlimited AI'),
                  const _FeatureChip(icon: LucideIcons.download, label: 'Unlimited exports'),
                  const _FeatureChip(icon: LucideIcons.layout, label: 'All templates'),
                ]),
              ],
            )),
            const SizedBox(width: 20),
            _ShimmerCta(
                label: trialUsed ?
                ( proPrice != -1 ? 'Upgrade — \$${proPrice.toStringAsFixed(0)}/mo'
                    : 'Unavailable' )
                    : 'Start Free Trial',
                onTap: trialUsed ? onUpgrade : onStartTrial),
          ],
        ),
      ),
    );
  }
}

class _TrialCountdownBanner extends StatelessWidget {
  final int daysRemaining;
  final VoidCallback onUpgrade;
  final double proPrice;

  const _TrialCountdownBanner({
    required this.daysRemaining,
    required this.onUpgrade,
    required this.proPrice,

  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A5F), AppColors.prussianBlue],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _PulsingIcon(
            icon: LucideIcons.clock,
            color: AppColors.success,
            glowColor: AppColors.success,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$daysRemaining ${daysRemaining == 1 ? 'day' : 'days'} left in your trial',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 17,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enjoying unlimited features? Keep them forever with Pro',
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
                const SizedBox(height: 10),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: daysRemaining / 7,
                    backgroundColor: AppColors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(AppColors.success),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _ShimmerCta(
              label: proPrice != -1 ? 'Upgrade — \$${proPrice.toStringAsFixed(0)}/mo'
                  : 'Unavailable',
              onTap: onUpgrade),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRO ACTIVE DASHBOARD BANNER — replaces upgrade banner for Pro users
// ═══════════════════════════════════════════════════════════════════════

class ProActiveDashboardBanner extends StatelessWidget {
  const ProActiveDashboardBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => const ProFeaturesDialog(),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.success.withValues(alpha: 0.06),
                AppColors.success.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.2),
            ),
          ),
          child:ResponsiveBuilder(
            mobile: SizedBox(
              height: 65,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 1,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.crown, size: 19, color: AppColors.success),
                    ),
                  ),
                  Flexible(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'KitAura Pro',
                              style: TextStyle(
                                color: AppColors.prussianBlue,
                                fontSize: 17,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 10,),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 9,
                                  fontFamily: AppFonts.poppins,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'You have unlimited access to all features',
                          style: TextStyle(
                            color: AppColors.slateGrey,
                            fontSize: 12,
                            fontFamily: AppFonts.openSans,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    flex: 2,
                    child: Column(
                     mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'See all features',
                              style: TextStyle(
                                color: AppColors.success.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(10)
                              ),
                              child: Icon(LucideIcons.arrowRight, size: 14,
                                  color: AppColors.white,)
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            desktop: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.crown, size: 22, color: AppColors.success),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'KitAura Pro',
                            style: TextStyle(
                              color: AppColors.prussianBlue,
                              fontSize: 17,
                              fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 9,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'You have unlimited access to all features',
                        style: TextStyle(
                          color: AppColors.slateGrey,
                          fontSize: 12,
                          fontFamily: AppFonts.openSans,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'See all features',
                      style: TextStyle(
                        color: AppColors.success.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.arrowRight, size: 14,
                        color: AppColors.success.withValues(alpha: 0.8)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. TOOL BANNER — IMPROVED (taller, animated, feature chips)
// ═══════════════════════════════════════════════════════════════════════

class GoProToolBanner extends ConsumerWidget {
  final String toolLabel;
  final VoidCallback onStartTrial;
  final VoidCallback onUpgrade;
  final double proPrice;

  const GoProToolBanner({
    super.key,
    required this.toolLabel,
    required this.onStartTrial,
    required this.onUpgrade,
    required this.proPrice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    if (state.isPro) return const ProActiveDashboardBanner();

    final trialUsed = state.trialUsed;

    return Container(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.prussianBlue, Color(0xFF3D1A2E), AppColors.darkRaspberry],
          stops: [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkRaspberry.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _PulsingIcon(
            icon: LucideIcons.crown,
            color: AppColors.white,
            glowColor: AppColors.white,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trialUsed
                      ? 'Unlock unlimited $toolLabel'
                      : 'Try unlimited $toolLabel free',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 17,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trialUsed
                      ? 'Unlimited exports, AI generation & all premium templates'
                      : 'Start your 7-day free trial — no credit card required',
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const _FeatureChip(icon: LucideIcons.infinity, label: 'Unlimited exports'),
                    const _FeatureChip(icon: LucideIcons.sparkles, label: 'AI generation'),
                    if (!trialUsed)
                      const _FeatureChip(icon: LucideIcons.creditCard, label: 'No credit card'),
                    if (trialUsed)
                      const _FeatureChip(icon: LucideIcons.layout, label: 'All templates'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _ShimmerCta(
            label: trialUsed ?
            ( proPrice != -1 ? 'Upgrade — \$${proPrice.toStringAsFixed(0)}/mo'
                : 'Unavailable' )
                : 'Start Free Trial',
            onTap: trialUsed ? onUpgrade : onStartTrial,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. STAT CARD — small gradient card in the stat row
// ═══════════════════════════════════════════════════════════════════════

class GoProStatCard extends ConsumerWidget {
  final VoidCallback onStartTrial;
  final VoidCallback onUpgrade;
  final double proPrice;

  const GoProStatCard({
    super.key,
    required this.onStartTrial,
    required this.onUpgrade,
    required this.proPrice,
  });

  @override
  Widget build(BuildContext context,  WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    bool trialUsed = state.trialUsed;

    if (state.isPro) {
      // Simple branded card confirming Pro status
      return ProActiveStatCard();
    }else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.darkRaspberry, Color(0xFFB8496A)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.crown, size: 20, color: AppColors.white),
            const SizedBox(height: 10),
            const Text(
              'Go Pro',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              trialUsed ? 'Unlimited everything' : '7-day free trial',
              style: TextStyle(
                color: AppColors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontFamily: AppFonts.openSans,
              ),
            ),
            const SizedBox(height: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: trialUsed ? onUpgrade : onStartTrial,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    trialUsed ?
                    ( proPrice != -1 ? 'Upgrade — \$${proPrice.toStringAsFixed(0)}/mo'
                        : 'Unavailable' )
                        : 'Start Free Trial',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 11,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TRIAL ACTIVATION DIALOG — shown when user clicks "Start Free Trial"
// ═══════════════════════════════════════════════════════════════════════

// REPLACE your existing TrialActivationDialog in go_pro_banners.dart with this

class TrialActivationDialog extends StatefulWidget {
  final Future<void> Function() onActivate;
  final double proPrice;
  const TrialActivationDialog({super.key, required this.onActivate, required this.proPrice});

  @override
  State<TrialActivationDialog> createState() => _TrialActivationDialogState();
}

class _TrialActivationDialogState extends State<TrialActivationDialog>
    with SingleTickerProviderStateMixin
{
  bool _isLoading = false;
  String? _error;
  late final AnimationController _iconCtrl;

  @override
  void initState() {
    super.initState();
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Gradient header ───────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.prussianBlue, Color(0xFF2D1B3D), AppColors.darkRaspberry],
                  stops: [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Close button
                  Align(
                    alignment: Alignment.topRight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(LucideIcons.x, size: 14, color: AppColors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Animated icon
                  AnimatedBuilder(
                    animation: _iconCtrl,
                    builder: (_, _) {
                      final scale = 1.0 + (_iconCtrl.value * 0.08);
                      final glow = 0.15 + (_iconCtrl.value * 0.15);
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: glow),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Transform.scale(
                          scale: scale,
                          child: const Icon(LucideIcons.sparkles, size: 30, color: AppColors.white),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Start Your Free Trial',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 22,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '7 days of unlimited Pro access\nNo credit card required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontFamily: AppFonts.openSans,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Trial badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.clock, size: 13,
                            color: AppColors.white.withValues(alpha: 0.9)),
                        const SizedBox(width: 6),
                        Text(
                          '7 days free · then \$${widget.proPrice.toStringAsFixed(0)}/mo · cancel anytime',
                          style: TextStyle(
                            color: AppColors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Features list ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
              child: Column(
                children: [
                  _featureRow(LucideIcons.infinity, 'Unlimited exports',
                      'Download as many PDFs as you need'),
                  _featureRow(LucideIcons.sparkles, 'Unlimited AI generation',
                      'AI Fill, Rewrite & Spellcheck — no limits'),
                  _featureRow(LucideIcons.fileText, 'Unlimited documents',
                      'Create unlimited CVs & cover letters'),
                  _featureRow(LucideIcons.layout, 'All premium templates',
                      'Access every template including exclusives'),
                  _featureRow(LucideIcons.ban, 'No watermarks',
                      'Clean, professional exports every time'),
                ],
              ),
            ),

            // ── Error ────────────────────────────────────────────
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontFamily: AppFonts.openSans,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // ── CTA button ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: MouseRegion(
                  cursor: _isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _isLoading ? null : _activate,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? null
                            : const LinearGradient(
                          colors: [AppColors.darkRaspberry, Color(0xFFAD2B5A)],
                        ),
                        color: _isLoading ? AppColors.slateGrey : null,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _isLoading
                            ? null
                            : [
                          BoxShadow(
                            color: AppColors.darkRaspberry.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.white,
                          ),
                        )
                            : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.zap, size: 16, color: AppColors.white),
                            SizedBox(width: 8),
                            Text(
                              'Activate Free Trial',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Footer ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'Maybe later',
                    style: TextStyle(
                      color: AppColors.slateGrey,
                      fontSize: 12,
                      fontFamily: AppFonts.openSans,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: AppColors.darkRaspberry),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.prussianBlue,
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.slateGrey,
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activate() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      await widget.onActivate();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER — Show trial activation dialog from anywhere
// ═══════════════════════════════════════════════════════════════════════

/// Shows the trial activation dialog.
/// Returns true if trial was activated, false/null otherwise.
/// [onSuccess] is called after successful activation to refresh UI state.
Future<bool?> showTrialActivationDialog(
    BuildContext context, {
      required Future<void> Function() onActivate,
      double proPrice = 7.0,
    })
{
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TrialActivationDialog(onActivate: onActivate, proPrice: proPrice),
  );
}

Future<void> showTrialDialog(BuildContext context, WidgetRef ref) async {
  final activated = await showTrialActivationDialog(
    context,
    onActivate: () => ClaudeService.activateTrial(),
    proPrice: ref.read(dashboardControllerProvider).proPrice,
  );

  if (activated == true) {
    // Refresh dashboard to show trial state
    ref.read(dashboardControllerProvider.notifier).loadDashboard(force: true);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Trial activated! Enjoy 7 days of unlimited access.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRO ACTIVE STAT CARD — replaces GoProStatCard when user is Pro
// ═══════════════════════════════════════════════════════════════════════

class ProActiveStatCard extends StatelessWidget {
  const ProActiveStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => const ProFeaturesDialog(),
        ),
        child: Container(
          padding: EdgeInsets.all(AppSizes.cardPadding(context)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.success.withValues(alpha: 0.08),
                AppColors.success.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Badge row
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: const Icon(LucideIcons.crown, size: 16, color: AppColors.success),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  "Pro Plan",
                  style: TextStyle(
                    fontSize: AppSizes.headingSm(context),
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold,
                    color: AppColors.prussianBlue,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
               "Unlimited Everything",
                style: TextStyle(
                  fontSize: AppSizes.caption(context),
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              // See features link
              if (!Responsive.isMobile(context))
              Row(
                children: [
                  Text(
                    'See all features',
                    style: TextStyle(
                      color: AppColors.success.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.arrowRight,
                    size: 12,
                    color: AppColors.success.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRO FEATURES DIALOG — beautiful popup showing all Pro benefits
// ═══════════════════════════════════════════════════════════════════════

class ProFeaturesDialog extends StatelessWidget {
  const ProFeaturesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header with gradient ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D4E3A), Color(0xFF16A34A)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.crown, size: 24, color: AppColors.white),
                        ),
                        const Spacer(),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(LucideIcons.x, size: 14, color: AppColors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Your Pro Plan',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 22,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Everything you need to create standout documents',
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                          fontFamily: AppFonts.openSans,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        
              // ── Features list ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                child: Column(
                  children: [
                    _featureRow(
                      LucideIcons.infinity,
                      'Unlimited Exports',
                      'Download as many PDFs as you need',
                    ),
                    _featureRow(
                      LucideIcons.sparkles,
                      'Unlimited AI Generation',
                      'AI Fill and AI Rewrite with no limits',
                    ),
                    _featureRow(
                      LucideIcons.fileText,
                      'Unlimited Documents',
                      'Create unlimited CVs, cover letters & proposals',
                    ),
                    _featureRow(
                      LucideIcons.layout,
                      'All Premium Templates',
                      'Access every template including Pro exclusives',
                    ),
                    _featureRow(
                      LucideIcons.paintbrush,
                      'AI Design',
                      'Auto-generate complete document layouts',
                    ),
                    _featureRow(
                      LucideIcons.ban,
                      'No Watermarks',
                      'Clean, professional exports every time',
                    ),
                    _featureRow(
                      LucideIcons.spellCheck,
                      'AI Spellcheck',
                      'Catch every typo before you submit',
                    ),
                    _featureRow(
                      LucideIcons.headphones,
                      'Priority Support',
                      'Get help faster when you need it',
                    ),
                  ],
                ),
              ),
        
              // ── Footer ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Got it!',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.success),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.prussianBlue,
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.slateGrey,
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.check, size: 16, color: AppColors.success),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SETTINGS BILLING CTA — reusable banner for Plan & Billing tab
// ═══════════════════════════════════════════════════════════════════════

class SettingsBillingCta extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;
  final List<Color> gradientColors;

  const SettingsBillingCta({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
    this.gradientColors = const [AppColors.prussianBlue, Color(0xFF1E293B)],
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(16),
      ),
      child: isMobile
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: AppSizes.headingMd(context),
                  fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold,
                  color: AppColors.white)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(fontSize: AppSizes.caption(context),
                  color: AppColors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: _ctaButton(),
          ),
        ],
      )
          : Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 20, fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.bold, color: AppColors.white)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(fontSize: 13,
                        color: AppColors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _ctaButton(),
        ],
      ),
    );
  }

  Widget _ctaButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(buttonLabel,
                style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w700, color: AppColors.darkRaspberry)),
          ),
        ),
      ),
    );
  }
}