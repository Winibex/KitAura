// lib/features/settings/view/settings_screen.dart
//
// SaaS-style settings: left sidebar nav + right content area.
// Sections: Profile, Account Security, Plan & Billing, Preferences, AI Profile.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_routes.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/subscription_model.dart';
import '../../../shared/models/user_preferences_model.dart';
import '../../../shared/models/user_profile_model.dart';
import '../../../shared/services/firebase_service.dart';
import '../../auth/controller/auth_controller.dart';
import 'upgrade_modal.dart';

enum SettingsTab { profile, security, billing, preferences, aiProfile }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsTab _activeTab = SettingsTab.profile;
  bool _isLoading = true;

  // Data
  UserProfileModel? _profile;
  SubscriptionModel? _subscription;
  UserPreferencesModel? _preferences;
  AiProfileModel? _aiProfile;

  // Editing state
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final results = await Future.wait([
        FirebaseService.getUserProfile(uid),
        FirebaseService.getSubscription(uid),
        FirebaseService.getPreferences(uid),
        FirebaseService.getAiProfile(uid),
      ]);

      if (mounted) {
        final profileDoc = results[0];
        final subDoc = results[1];
        final prefDoc = results[2];
        final aiDoc = results[3];

        setState(() {
          _profile = profileDoc.exists
              ? UserProfileModel.fromJson(profileDoc.data() as Map<String, dynamic>)
              : null;
          _subscription = subDoc.exists
              ? SubscriptionModel.fromJson(subDoc.data() as Map<String, dynamic>)
              : const SubscriptionModel();
          _preferences = prefDoc.exists
              ? UserPreferencesModel.fromJson(prefDoc.data() as Map<String, dynamic>)
              : const UserPreferencesModel();
          _aiProfile = aiDoc.exists
              ? AiProfileModel.fromJson(aiDoc.data() as Map<String, dynamic>)
              : const AiProfileModel();

          _nameCtrl.text = _profile?.displayName ?? '';
          _phoneCtrl.text = _profile?.phone ?? '';
          _locationCtrl.text = _profile?.location ?? '';
          _bioCtrl.text = _profile?.bio ?? '';

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Settings load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSaving = true);

    try {
      final updates = <String, dynamic>{
        'displayName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'bio': _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      };
      await FirebaseService.updateUserProfile(uid, updates);
      if (_nameCtrl.text.trim().isNotEmpty) {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(_nameCtrl.text.trim());
      }
      if (mounted) {
        setState(() {
          _profile = _profile?.copyWith(
            displayName: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            location: _locationCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
          );
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    await ref.read(authControllerProvider.notifier).signOut();
    router.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.darkRaspberry))
                : isMobile
                ? _buildMobileLayout()
                : _buildDesktopLayout(),
          ),
        ],
      ),
    );
  }

  // ─── TOP BAR ──────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: AppColors.prussianBlue,
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context.go(AppRoutes.dashboard),
              child: Row(
                children: [
                  const Icon(LucideIcons.arrowLeft, color: AppColors.white, size: 16),
                  const SizedBox(width: 12),
                  Image.asset(AppAssets.logoHorizontalLight, height: 20),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Container(width: 1, height: 28, color: AppColors.white.withValues(alpha: 0.15)),
          const SizedBox(width: 20),
          const Text(
            'Settings',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── DESKTOP LAYOUT (sidebar + content) ───────────────────────────────

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 260,
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(right: BorderSide(color: Color(0xFFEDE8E3))),
          ),
          child: Column(
            children: [
              // User card at top
              _buildSidebarUserCard(),
              const Divider(color: Color(0xFFEDE8E3), height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  child: _buildSidebarNav(),
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: AnimatedSwitcher(
                  duration: 200.ms,
                  child: _buildActiveContent(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── MOBILE LAYOUT ────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Horizontal tab scroller
        Container(
          height: 48,
          color: AppColors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: SettingsTab.values.map((tab) {
                final active = tab == _activeTab;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = tab),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: active ? AppColors.darkRaspberry : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        _tabLabel(tab),
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: AppFonts.poppins,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          color: active ? AppColors.darkRaspberry : AppColors.slateGrey,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFEDE8E3)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildActiveContent(),
          ),
        ),
      ],
    );
  }

  // ─── SIDEBAR COMPONENTS ───────────────────────────────────────────────

  Widget _buildSidebarUserCard() {
    final user = FirebaseAuth.instance.currentUser;
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _avatar(user, 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profile?.displayName ?? 'User',
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: AppColors.prussianBlue,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (_subscription?.isPro ?? false)
                        ? AppColors.darkRaspberry
                        : AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    (_subscription?.isPro ?? false) ? 'PRO' : 'FREE',
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: (_subscription?.isPro ?? false)
                          ? AppColors.white
                          : AppColors.darkRaspberry,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNav() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _navSectionLabel('GENERAL'),
        _navItem(SettingsTab.profile, LucideIcons.user, 'Profile'),
        _navItem(SettingsTab.security, LucideIcons.shield, 'Account Security'),
        _navItem(SettingsTab.preferences, LucideIcons.sliders, 'Preferences'),
        const SizedBox(height: 16),
        _navSectionLabel('WORKSPACE'),
        _navItem(SettingsTab.aiProfile, LucideIcons.sparkles, 'AI Profile'),
        _navItem(SettingsTab.billing, LucideIcons.creditCard, 'Plan & Billing'),
        const SizedBox(height: 24),
        // Sign out at bottom
        _navAction(LucideIcons.logOut, 'Sign Out', AppColors.slateGrey, _signOut),
      ],
    );
  }

  Widget _navSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontFamily: AppFonts.poppins,
          fontWeight: FontWeight.w600,
          color: AppColors.slateGrey,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _navItem(SettingsTab tab, IconData icon, String label) {
    final active = tab == _activeTab;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: 150.ms,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.lavenderBlush : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18,
                  color: active ? AppColors.darkRaspberry : AppColors.slateGrey),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.darkRaspberry : AppColors.prussianBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CONTENT ROUTER ───────────────────────────────────────────────────

  Widget _buildActiveContent() {
    switch (_activeTab) {
      case SettingsTab.profile:
        return _profileContent();
      case SettingsTab.security:
        return _securityContent();
      case SettingsTab.billing:
        return _billingContent();
      case SettingsTab.preferences:
        return _preferencesContent();
      case SettingsTab.aiProfile:
        return _aiProfileContent();
    }
  }

  // ─── PROFILE TAB ──────────────────────────────────────────────────────

  Widget _profileContent() {
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentHeader('Profile', 'Manage your personal information'),
        const SizedBox(height: 28),

        // Avatar section
        _card(child: Row(
          children: [
            _avatar(user, 72),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _profile?.displayName ?? 'User',
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                      color: AppColors.prussianBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _profile?.email ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.openSans,
                      color: AppColors.slateGrey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Member since ${_fmtDate(_profile?.createdAt)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.slateGrey),
                  ),
                ],
              ),
            ),
          ],
        )),
        const SizedBox(height: 20),

        // Editable fields
        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personal Information',
                style: TextStyle(
                    fontSize: 15, fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
            const SizedBox(height: 20),
            _field('Display Name', _nameCtrl, 'Your full name'),
            const SizedBox(height: 16),
            _fieldReadOnly('Email', _profile?.email ?? ''),
            const SizedBox(height: 16),
            _field('Phone', _phoneCtrl, '+92 300 1234567'),
            const SizedBox(height: 16),
            _field('Location', _locationCtrl, 'Lahore, Pakistan'),
            const SizedBox(height: 16),
            _fieldMultiline('Bio', _bioCtrl, 'A short description about yourself'),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkRaspberry,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                      : const Text('Save Changes', style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        )),
      ],
    );
  }

  // ─── SECURITY TAB ─────────────────────────────────────────────────────

  Widget _securityContent() {
    final user = FirebaseAuth.instance.currentUser;
    final isGoogle = user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    return Column(
      key: const ValueKey('security'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentHeader('Account Security', 'Manage your login and security settings'),
        const SizedBox(height: 28),

        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _settingsRow(
              LucideIcons.mail,
              'Email Address',
              _profile?.email ?? '',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  user?.emailVerified == true ? 'Verified' : 'Unverified',
                  style: TextStyle(
                    fontSize: 11, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600,
                    color: user?.emailVerified == true ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ),
            const Divider(color: Color(0xFFF0EBE6), height: 32),
            _settingsRow(
              LucideIcons.key,
              'Sign-in Method',
              isGoogle ? 'Google Account' : 'Email & Password',
              trailing: Icon(
                isGoogle ? Icons.g_mobiledata : LucideIcons.lock,
                size: 20,
                color: AppColors.slateGrey,
              ),
            ),
            if (!isGoogle) ...[
              const Divider(color: Color(0xFFF0EBE6), height: 32),
              _settingsRow(
                LucideIcons.keyRound,
                'Change Password',
                'Update your password',
                trailing: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => context.push(AppRoutes.resetPassword),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.almondSilk),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Change', style: TextStyle(fontSize: 12, color: AppColors.darkRaspberry, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        )),
        const SizedBox(height: 20),

        // Danger zone
        _card(
          borderColor: AppColors.error.withValues(alpha: 0.15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.alertTriangle, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  const Text('Danger Zone',
                      style: TextStyle(fontSize: 14, fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w600, color: AppColors.error)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Permanently delete your account and all associated data. This action cannot be undone.',
                style: TextStyle(fontSize: 13, color: AppColors.slateGrey, height: 1.5),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: _confirmDeleteAccount,
                  icon: const Icon(LucideIcons.trash2, size: 14, color: AppColors.error),
                  label: const Text('Delete Account',
                      style: TextStyle(color: AppColors.error, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── BILLING TAB ──────────────────────────────────────────────────────

  Widget _billingContent() {
    final sub = _subscription ?? const SubscriptionModel();

    return Column(
      key: const ValueKey('billing'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentHeader('Plan & Billing', 'Manage your subscription and usage'),
        const SizedBox(height: 28),

        // Current plan
        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Current Plan',
                    style: TextStyle(fontSize: 15, fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: sub.isPro ? AppColors.darkRaspberry : AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sub.isPro ? 'PRO — \$7/mo' : 'FREE',
                    style: TextStyle(
                      fontSize: 12, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700,
                      color: sub.isPro ? AppColors.white : AppColors.darkRaspberry,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _usageBar('PDF Exports', LucideIcons.download, sub.exportCount, sub.isPro ? -1 : 3, AppColors.magentaBloom),
            const SizedBox(height: 16),
            _usageBar('AI Fills', LucideIcons.sparkles, sub.aiUsageCount, sub.isPro ? -1 : 10, AppColors.dustyMauve),
            const SizedBox(height: 16),
            _usageBar('Saved CVs', LucideIcons.fileText, sub.cvCount, sub.isPro ? -1 : 10, AppColors.dustyRose),
          ],
        )),
        const SizedBox(height: 20),

        // Upgrade CTA or billing management
        if (!sub.isPro) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upgrade to Pro',
                          style: TextStyle(fontSize: 20, fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.bold, color: AppColors.white)),
                      SizedBox(height: 6),
                      Text('Unlimited exports, AI fills, CVs. No watermark.',
                          style: TextStyle(fontSize: 13, color: Color(0xAAFFFFFF))),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => showDialog(context: context, builder: (_) => const UpgradeModal()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Upgrade — \$7/mo',
                          style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.w700, color: AppColors.darkRaspberry)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          _card(child: _settingsRow(
            LucideIcons.creditCard,
            'Manage Billing',
            'Update payment method, view invoices',
            trailing: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {/* TODO: Stripe portal */},
                child: const Icon(LucideIcons.externalLink, size: 16, color: AppColors.darkRaspberry),
              ),
            ),
          )),
        ],
      ],
    );
  }

  // ─── PREFERENCES TAB ──────────────────────────────────────────────────

  Widget _preferencesContent() {
    return Column(
      key: const ValueKey('preferences'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentHeader('Preferences', 'Customize your KitAura experience'),
        const SizedBox(height: 28),

        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toggleRow('Email Notifications', 'Receive product updates and tips',
                _preferences?.emailNotifications ?? true, (v) {
                  // TODO: save preference
                  setState(() {});
                }),
            const Divider(color: Color(0xFFF0EBE6), height: 32),
            _settingsRow(LucideIcons.palette, 'Theme', 'Light', trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.almondSilk),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Light', style: TextStyle(fontSize: 12, color: AppColors.prussianBlue)),
            )),
            const Divider(color: Color(0xFFF0EBE6), height: 32),
            _settingsRow(LucideIcons.type, 'Default Font', _preferences?.defaultFont ?? 'Poppins'),
            const Divider(color: Color(0xFFF0EBE6), height: 32),
            _settingsRow(LucideIcons.layout, 'Default Template', _preferences?.defaultTemplate ?? 'None'),
          ],
        )),
      ],
    );
  }

  // ─── AI PROFILE TAB ───────────────────────────────────────────────────

  Widget _aiProfileContent() {
    final ai = _aiProfile ?? const AiProfileModel();

    return Column(
      key: const ValueKey('ai'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentHeader('AI Profile', 'The data AI uses to generate your CV content'),
        const SizedBox(height: 28),

        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoField('Target Job Title', ai.jobTitle ?? 'Not set'),
            const Divider(color: Color(0xFFF0EBE6), height: 24),
            _infoField('Experience Level', ai.experienceLevel.toUpperCase()),
            const Divider(color: Color(0xFFF0EBE6), height: 24),
            _infoField('Industry', ai.industry.isEmpty ? 'Not set' : ai.industry),
            const Divider(color: Color(0xFFF0EBE6), height: 24),
            _infoField('Writing Tone', ai.tone),
            const Divider(color: Color(0xFFF0EBE6), height: 24),
            const Text('Skills',
                style: TextStyle(fontSize: 12, color: AppColors.slateGrey, fontFamily: AppFonts.poppins)),
            const SizedBox(height: 8),
            ai.skills.isEmpty
                ? const Text('No skills added', style: TextStyle(fontSize: 13, color: AppColors.slateGrey))
                : Wrap(
              spacing: 6, runSpacing: 6,
              children: ai.skills.map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.petalFrost,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s, style: const TextStyle(fontSize: 12, color: AppColors.prussianBlue, fontFamily: AppFonts.poppins)),
              )).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'To update your AI profile, use the AI Setup wizard when creating a new CV.',
              style: TextStyle(fontSize: 12, color: AppColors.slateGrey, fontStyle: FontStyle.italic),
            ),
          ],
        )),
      ],
    );
  }

  // ─── SHARED WIDGETS ───────────────────────────────────────────────────

  Widget _contentHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
            fontSize: 24, fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(
            fontSize: 14, fontFamily: AppFonts.openSans, color: AppColors.slateGrey)),
      ],
    );
  }

  Widget _card({required Widget child, Color? borderColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? const Color(0xFFEDE8E3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 14, fontFamily: AppFonts.openSans),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.slateGrey, fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEDE8E3))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEDE8E3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.darkRaspberry)),
          ),
        ),
      ],
    );
  }

  Widget _fieldReadOnly(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F5F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEDE8E3)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(value, style: const TextStyle(fontSize: 14, color: AppColors.slateGrey))),
              const Icon(LucideIcons.lock, size: 14, color: AppColors.slateGrey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldMultiline(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl, maxLines: 3,
          style: const TextStyle(fontSize: 14, fontFamily: AppFonts.openSans),
          decoration: InputDecoration(
            hintText: hint, hintStyle: const TextStyle(color: AppColors.slateGrey, fontSize: 13),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEDE8E3))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEDE8E3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.darkRaspberry)),
          ),
        ),
      ],
    );
  }

  Widget _settingsRow(IconData icon, String title, String subtitle, {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.slateGrey),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.slateGrey)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.slateGrey)),
            ],
          ),
        ),
        Switch(
          value: value, onChanged: onChanged,
          activeTrackColor: AppColors.darkRaspberry,
        ),
      ],
    );
  }

  Widget _usageBar(String label, IconData icon, int used, int limit, Color color) {
    final unlimited = limit == -1;
    final progress = unlimited ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final atLimit = !unlimited && used >= limit;

    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
            const Spacer(),
            Text(unlimited ? '$used used' : '$used / $limit',
                style: TextStyle(fontSize: 12, fontFamily: AppFonts.openSans,
                    fontWeight: FontWeight.w600, color: atLimit ? AppColors.error : AppColors.slateGrey)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: unlimited ? 0 : progress, minHeight: 5,
            backgroundColor: const Color(0xFFF0EBE6),
            valueColor: AlwaysStoppedAnimation(atLimit ? AppColors.error : color),
          ),
        ),
      ],
    );
  }

  Widget _infoField(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.slateGrey, fontFamily: AppFonts.poppins)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
      ],
    );
  }

  Widget _avatar(User? user, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.petalFrost,
        border: Border.all(color: AppColors.almondSilk, width: 2),
      ),
      child: user?.photoURL != null
          ? ClipOval(child: Image.network(user!.photoURL!, width: size, height: size,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _initials(user.displayName, size)))
          : _initials(user?.displayName, size),
    );
  }

  Widget _initials(String? name, double size) {
    final i = (name ?? 'U').split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    return Center(child: Text(i, style: TextStyle(
        fontSize: size * 0.35, fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.w700, color: AppColors.darkRaspberry)));
  }

  String _tabLabel(SettingsTab t) {
    switch (t) {
      case SettingsTab.profile: return 'Profile';
      case SettingsTab.security: return 'Security';
      case SettingsTab.billing: return 'Plan & Billing';
      case SettingsTab.preferences: return 'Preferences';
      case SettingsTab.aiProfile: return 'AI Profile';
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Unknown';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _confirmDeleteAccount() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Account?', style: TextStyle(fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold, color: AppColors.error)),
      content: const Text('This will permanently delete your account, all CVs, and all data. This action cannot be undone.',
          style: TextStyle(fontFamily: AppFonts.openSans, color: AppColors.slateGrey, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.slateGrey))),
        ElevatedButton(onPressed: () { Navigator.pop(ctx); /* TODO */ },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Forever')),
      ],
    ));
  }
}