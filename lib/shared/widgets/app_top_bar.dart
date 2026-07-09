// lib/shared/widgets/app_top_bar.dart
//
// Top navigation bar — logo, notification, upgrade button, avatar popup.
// Used by: dashboard, cv_templates, settings, and all future main screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kitaura/features/dashboard/controller/dashboard_controller.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../core/constants/app_routes.dart';
import '../../features/auth/controller/auth_controller.dart';
import '../../features/settings/view/upgrade_modal.dart';
import '../../shared/widgets/user_popup_menu.dart';
import '../providers/feature_flags_provider.dart';
import 'go_pro_banners.dart';

class AppTopBar extends ConsumerStatefulWidget {
  final bool canBack;
  final String whereToGo;
  final bool showMenuButton;
  final VoidCallback? onMenuTap;

  const AppTopBar({
    super.key,
    required this.canBack,
    required this.whereToGo,
    this.showMenuButton = false,
    this.onMenuTap,
  });

  @override
  ConsumerState<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends ConsumerState<AppTopBar> {
  @override
  void initState() {
    super.initState();
    // Ensure subscription data is loaded regardless of which screen the user
    // lands on. Fires once on mount. The controller's _hasLoaded flag
    // guarantees no duplicate Firebase reads if another screen already loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    final bool isPro = state.isPro;
    final trialEnabled =
        ref.watch(featureFlagsProvider).value?.trialEnabled ?? true;
    final bool effectiveTrialUsed = state.trialUsed || !trialEnabled;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.prussianBlue,
      ),
      child: Row(
        children: [
          if (widget.canBack) ...[
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft,
                  color: AppColors.white, size: 20),
              onPressed: () => context.go(widget.whereToGo),
            ),
          ],
          if (widget.showMenuButton)
            IconButton(
              icon: const Icon(LucideIcons.menu, color: AppColors.white, size: 20),
              onPressed: widget.onMenuTap,
            ),
          const SizedBox(width: 20),
          Image.asset(AppAssets.logoHorizontalLight, height: 24),
          const Spacer(),

          // Upgrade button
          if (isPro)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.crown, size: 13, color: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    'Pro',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  final canTrial =
                      !effectiveTrialUsed && state.plan == 'free';
                  if (canTrial) {
                    showTrialDialog(context, ref);
                  } else {
                    showDialog(context: context, builder: (_) => const UpgradeModal());
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.darkRaspberry,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        effectiveTrialUsed ? LucideIcons.crown : LucideIcons.sparkles,
                        size: 13,
                        color: AppColors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        effectiveTrialUsed ? 'Upgrade to Pro' : 'Start Free Trial',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),

          // Avatar popup
          UserPopupMenu(
            onSettings: () => context.go(AppRoutes.settings),
            onStartTrial: () => showTrialDialog(context, ref),
            onUpgrade: () => showDialog(
              context: context,
              builder: (_) => const UpgradeModal(),
            ),
            onSignOut: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.auth);
            },
          ),
        ],
      ),
    );
  }
}