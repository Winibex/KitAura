// lib/shared/widgets/app_sidebar.dart
//
// Left navigation sidebar — auto-highlights active page from URL.
// Used by: dashboard, and any screen that uses the main layout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../core/constants/app_routes.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';
import '../../features/settings/view/upgrade_modal.dart';
import 'go_pro_banners.dart';

enum AppPage { dashboard, cvDashboard, cvTemplates, proposal, coverLetter, linkedin, settings }

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final active = _pageFromRoute(location);

    return Container(
      width: 240,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          right: BorderSide(color: AppColors.petalFrost, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _sectionLabel('TOOLS'),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: LucideIcons.layoutDashboard,
                    label: 'Dashboard',
                    isActive: active == AppPage.dashboard,
                    onTap: () {
                      // Close drawer if open (mobile)
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      context.go(AppRoutes.dashboard);
                    },
                  ),
                  _SidebarItem(
                    icon: LucideIcons.filePlus,
                    label: 'Create CV',
                    isActive: active == AppPage.cvDashboard,
                    onTap: () {
                      // Close drawer if open (mobile)
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      context.go(AppRoutes.cvDashboard);
                    },
                  ),
                  _SidebarItem(
                    icon: LucideIcons.mail,
                    label: 'Cover Letter',
                    isActive: active == AppPage.coverLetter,
                    onTap: () {
                      // Close drawer if open (mobile)
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      context.go(AppRoutes.clDashboard);
                    },
                  ),
                  _SidebarItem(
                    icon: LucideIcons.fileText,
                    label: 'Create Proposal',
                    isActive: active == AppPage.proposal,
                    onTap: () {
                      // Close drawer if open (mobile)
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      context.go(AppRoutes.proposalDashboard);
                    },
                  ),
                  _SidebarItem(
                    icon: LucideIcons.linkedin,
                    label: 'LinkedIn Summary',
                    isActive: active == AppPage.linkedin,
                    onTap: () {
                      // Close drawer if open (mobile)
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      context.go(AppRoutes.linkedin);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.petalFrost),
                  const SizedBox(height: 8),
                  _sectionLabel('ACCOUNT'),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: LucideIcons.settings,
                    label: 'Settings',
                    isActive: active == AppPage.settings,
                    onTap: () => context.go(AppRoutes.settings),
                  ),
                  Builder(builder: (context) {
                    final state = ref.watch(dashboardControllerProvider);
                    if (state.isPro) return const SizedBox.shrink();
                    final canTrial = !state.trialUsed && state.plan == 'free';
                    return _SidebarItem(
                      icon: canTrial ? LucideIcons.sparkles : LucideIcons.crown,
                      label: canTrial ? 'Start Free Trial' : 'Upgrade to Pro',
                      isActive: false,
                      isUpgrade: true,
                      onTap: canTrial
                          ? () => showTrialDialog(context, ref)
                          : () => showDialog(
                        context: context,
                        builder: (_) => const UpgradeModal(),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static AppPage _pageFromRoute(String route) {
    if (route.startsWith('/dashboard'))     return AppPage.dashboard;
    if (route.startsWith('/cv/templates'))  return AppPage.cvTemplates;
    if (route.startsWith('/cv'))            return AppPage.cvDashboard;
    if (route.startsWith('/proposals'))     return AppPage.proposal;
    if (route.startsWith('/cover-letters')) return AppPage.coverLetter;
    if (route.startsWith('/linkedin'))      return AppPage.linkedin;
    if (route.startsWith('/settings'))      return AppPage.settings;
    return AppPage.dashboard;
  }

  static Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.slateGrey,
        fontSize: 10,
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

// ─── SIDEBAR ITEM ────────────────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isUpgrade;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isUpgrade = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.lavenderBlush : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? const Border(
            left: BorderSide(color: AppColors.darkRaspberry, width: 3),
          )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? AppColors.darkRaspberry
                  : isUpgrade
                  ? AppColors.magentaBloom
                  : AppColors.slateGrey,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.darkRaspberry
                    : isUpgrade
                    ? AppColors.darkRaspberry
                    : AppColors.prussianBlue,
                fontSize: 14,
                fontFamily: AppFonts.poppins,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}