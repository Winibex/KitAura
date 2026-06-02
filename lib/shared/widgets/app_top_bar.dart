// lib/shared/widgets/app_top_bar.dart
//
// Top navigation bar — logo, notification, upgrade button, avatar popup.
// Used by: dashboard, cv_templates, settings, and all future main screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../core/constants/app_routes.dart';
import '../../features/auth/controller/auth_controller.dart';
import '../../features/settings/view/upgrade_modal.dart';
import '../../shared/widgets/user_popup_menu.dart';

class AppTopBar extends ConsumerWidget {
  /// Optional: pass subscription/profile data for the avatar popup.
  /// If null, the popup falls back to FirebaseAuth data.
  final dynamic profile;
  final dynamic subscription;
  final bool canBack;
  final String whereToGo;

  const AppTopBar({
    super.key,
    this.profile,
    this.subscription,
    required this.canBack,
    required this.whereToGo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => const UpgradeModal(),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.darkRaspberry,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Upgrade to Pro',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Avatar popup
          UserPopupMenu(
            profile: profile,
            subscription: subscription,
            onSettings: () => context.go(AppRoutes.settings),
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