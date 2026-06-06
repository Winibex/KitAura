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
import 'go_pro_banners.dart';

class AppTopBar extends ConsumerWidget {
  final bool canBack;
  final String whereToGo;

  const AppTopBar({
    super.key,
    required this.canBack,
    required this.whereToGo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);

    // Ensure subscription data is loaded regardless of which screen the user lands on
    if (!state.isLoading && state.plan == 'free' && state.loginCount == 0) {
      // State is at defaults — hasn't loaded yet
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(dashboardControllerProvider.notifier).loadDashboard();
      });
    }

    bool isPro = state.isPro;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.prussianBlue,
      ),
      child: Row(
        children: [
          if(canBack)...[
              IconButton(
                icon: const Icon(LucideIcons.arrowLeft,
                    color: AppColors.white, size: 20),
                onPressed: () => context.go(whereToGo),
              ),
          ],
          SizedBox(width: 20,),
          Image.asset(AppAssets.logoHorizontalLight, height: 24),
          const Spacer(),

          // Notification bell
          IconButton(
            icon: const Icon(LucideIcons.bell, color: AppColors.white, size: 20),
            onPressed: () {
              // TODO: notifications
            },
          ),
          const SizedBox(width: 12),

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
                  final canTrial = !state.trialUsed && state.plan == 'free';
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
                        state.trialUsed ? LucideIcons.crown : LucideIcons.sparkles,
                        size: 13,
                        color: AppColors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.trialUsed ? 'Upgrade to Pro' : 'Start Free Trial',
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