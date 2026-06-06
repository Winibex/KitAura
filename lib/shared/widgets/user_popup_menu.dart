// lib/shared/widgets/user_popup_menu.dart
//
// Drop-in widget: wrap your existing avatar GestureDetector with this.
// Shows a polished popup with user info, plan badge, quick links, sign out.
//
// USAGE in cv_dashboard_screen.dart:
//
//   Replace your _buildAvatarButton() with:
//
//   UserPopupMenu(
//     profile: _profile,          // UserProfileModel?
//     subscription: _subscription, // SubscriptionModel?
//     onSettings: () => context.push(AppRoutes.settings),
//     onUpgrade: () => showDialog(context: context, builder: (_) => const UpgradeModal()),
//     onSignOut: () async {
//       await ref.read(authControllerProvider.notifier).signOut();
//       if (mounted) context.go(AppRoutes.auth);
//     },
//   )

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';

class UserPopupMenu extends ConsumerStatefulWidget {
  final VoidCallback onSettings;
  final VoidCallback onUpgrade;
  final VoidCallback onSignOut;
  final VoidCallback onStartTrial;

  const UserPopupMenu({
    super.key,
    required this.onSettings,
    required this.onUpgrade,
    required this.onSignOut,
    required this.onStartTrial,
  });

  @override
  ConsumerState<UserPopupMenu> createState() => _UserPopupMenuState();
}

class _UserPopupMenuState extends ConsumerState<UserPopupMenu> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (ctx) => _buildOverlay(ctx, user),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _overlayController.toggle(),
            child: _buildAvatar(user),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(User? user) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.petalFrost,
        border: Border.all(color: AppColors.almondSilk, width: 2),
      ),
      child: user?.photoURL != null
          ? ClipOval(child: Image.network(user!.photoURL!, width: 36, height: 36,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _initials(user.displayName)))
          : _initials(user?.displayName),
    );
  }

  Widget _initials(String? name) {
    final i = (name ?? 'U').split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    return Center(child: Text(i, style: const TextStyle(
        fontSize: 13, fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.w700, color: AppColors.darkRaspberry)));
  }

  Widget _buildOverlay(BuildContext ctx, User? user) {
    final dashState = ref.watch(dashboardControllerProvider);
    final isPro = dashState.isPro;
    final trialUsed = dashState.trialUsed;
    final plan = dashState.plan;

    return Stack(
      children: [
        // Dismiss layer
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _overlayController.hide(),
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),

        // Popup positioned below avatar
        Positioned(
          width: 280,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: Material(
              elevation: 16,
              borderRadius: BorderRadius.circular(16),
              shadowColor: Colors.black26,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEDE8E3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // User info header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFBF8F6),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.petalFrost,
                              border: Border.all(color: AppColors.almondSilk, width: 2),
                            ),
                            child: user?.photoURL != null
                                ? ClipOval(child: Image.network(user!.photoURL!,
                                width: 44, height: 44, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _initials(user.displayName)))
                                : _initials(user?.displayName),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? 'User',
                                  style: const TextStyle(
                                    fontSize: 14, fontFamily: AppFonts.poppins,
                                    fontWeight: FontWeight.w600, color: AppColors.prussianBlue,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  user?.email ?? '',
                                  style: const TextStyle(fontSize: 11, color: AppColors.slateGrey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isPro
                                  ? (plan == 'trial'
                                  ? AppColors.dustyMauve
                                  : AppColors.success)
                                  : AppColors.petalFrost,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isPro
                                  ? (plan == 'trial' ? 'TRIAL' : 'PRO')
                                  : 'FREE',
                              style: TextStyle(
                                fontSize: 9, fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w700, letterSpacing: 1,
                                color: isPro ? AppColors.white : AppColors.darkRaspberry,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFEDE8E3)),

                    // Menu items
                    _menuItem(LucideIcons.settings, 'Settings', () {
                      _overlayController.hide();
                      widget.onSettings();
                    }),
                    _menuItem(LucideIcons.user, 'Edit Profile', () {
                      _overlayController.hide();
                      widget.onSettings();
                    }),
                    if (!isPro) ...[
                      if (!trialUsed)
                        _menuItem(LucideIcons.sparkles, 'Start Free Trial', () {
                          _overlayController.hide();
                          widget.onStartTrial();
                        }, accent: true)
                      else
                        _menuItem(LucideIcons.crown, 'Upgrade to Pro', () {
                          _overlayController.hide();
                          widget.onUpgrade();
                        }, accent: true),
                    ],
                    if (isPro)
                      _menuItem(LucideIcons.crown, 'Manage Subscription', () {
                        _overlayController.hide();
                        widget.onSettings();
                      }),
                    _menuItem(LucideIcons.helpCircle, 'Help & Support', () {
                      _overlayController.hide();
                      // TODO: open help
                    }),

                    const Divider(height: 1, color: Color(0xFFEDE8E3)),

                    // Sign out
                    _menuItem(LucideIcons.logOut, 'Sign Out', () {
                      _overlayController.hide();
                      widget.onSignOut();
                    }, isDestructive: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap,
      {bool accent = false, bool isDestructive = false}) {
    final color = isDestructive
        ? AppColors.error
        : accent
        ? AppColors.darkRaspberry
        : AppColors.prussianBlue;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 16, color: accent ? AppColors.magentaBloom : color),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13, fontFamily: AppFonts.poppins,
                  fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
              if (accent) ...[
                const Spacer(),
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.magentaBloom,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}