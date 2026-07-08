// lib/features/settings/view/settings_screen.dart
//
// SaaS-style settings: left sidebar nav + right content area.
// Sections: Profile, Account Security, Plan & Billing, Preferences, Career Profile.


import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../shared/providers/ai_profiles_provider.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_routes.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/client_profile_model.dart';
import '../../../shared/widgets/client_wizard_modal.dart';
import '../../../shared/widgets/go_pro_banners.dart';
import '../../../shared/widgets/guest_signup_modal.dart';
import '../../ai_setup/view/ai_setup_panel.dart';
import '../../auth/controller/auth_controller.dart';
import '../controller/settings_controller.dart';
import 'upgrade_modal.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsTab _activeTab = SettingsTab.profile;

  // UI-only editing state (text controllers live with the view; their values
  // get pushed to the controller on save).
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  /// Tracks the last feedback id we showed so we don't double-fire on rebuild.
  int _lastFeedbackId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser != null) {
        ref.read(settingsControllerProvider.notifier).loadAll();
      }
    });
  }

  /// Pushes the loaded profile into the text controllers. Called from build()
  /// when state.profile changes (via ref.listen).
  void _syncProfileToControllers(SettingsState s) {
    final p = s.profile;
    if (p == null) return;
    // Avoid overwriting unsaved user edits — only sync when current text
    // matches the previous backing value (i.e. user hasn't touched it).
    if (_nameCtrl.text.isEmpty) _nameCtrl.text = p.displayName;
    if (_phoneCtrl.text.isEmpty) _phoneCtrl.text = p.phone ?? '';
    if (_locationCtrl.text.isEmpty) _locationCtrl.text = p.location ?? '';
    if (_bioCtrl.text.isEmpty) _bioCtrl.text = p.bio ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 768;
    final state = ref.watch(settingsControllerProvider);

    // Sync profile data into text controllers once it arrives.
    ref.listen<SettingsState>(settingsControllerProvider, (prev, next) {
      if (prev?.profile != next.profile) {
        _syncProfileToControllers(next);
      }
      // Show feedback snackbar once per emit.
      final fb = next.feedback;
      if (fb != null && fb.id != _lastFeedbackId) {
        _lastFeedbackId = fb.id;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fb.message),
            backgroundColor: fb.isError ? AppColors.error : AppColors.success,
          ),
        );
        ref.read(settingsControllerProvider.notifier).acknowledgeFeedback();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: (state.isLoading && FirebaseAuth.instance.currentUser != null)
                ? const Center(child: CircularProgressIndicator(color: AppColors.darkRaspberry))
                : isMobile
                ? _buildMobileLayout()
                : _buildDesktopLayout(),
          ),
        ],
      ),
    );
  }

  // ─── GUEST HELPERS ────────────────────────────────────────────────────

  bool get _isGuest {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous;
  }

  Widget _withGuestOverlay(Widget content, {String message = 'Sign in to edit your profile'}) {
    return Stack(
      children: [
        IgnorePointer(
          child: Opacity(opacity: 0.25, child: content),
        ),
        Positioned.fill(
          child: Center(
            child: Container(
              width: 340,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.almondSilk),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.petalFrost,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.lock, size: 22, color: AppColors.darkRaspberry),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      color: AppColors.prussianBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a free account to save your\ndetails and access them from any device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.openSans,
                      color: AppColors.slateGrey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final linked = await GuestSignupModal.show(context);
                        if (linked && mounted) setState(() {});
                      },
                      icon: const Icon(LucideIcons.logIn, size: 16),
                      label: const Text('Create Account'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.darkRaspberry,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
                child: _buildActiveContent(),
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
    final state = ref.watch(settingsControllerProvider);
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
                  state.profile?.displayName ?? 'User',
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
                    color: state.subscription.plan == 'pro'
                        ? AppColors.success
                        : state.subscription.plan == 'trial'
                        ? AppColors.dustyMauve
                        : AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    state.subscription.plan == 'pro'
                        ? 'PRO'
                        : state.subscription.plan == 'trial'
                        ? 'TRIAL'
                        : _isGuest
                        ? 'GUEST'
                        : 'FREE',
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: state.subscription.isPro
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
    BuildContext buildContext = context;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _navSectionLabel('GENERAL'),
        _navItem(SettingsTab.profile, LucideIcons.user, 'Profile'),
        _navItem(SettingsTab.security, LucideIcons.shield, 'Account Security'),
        _navItem(SettingsTab.preferences, LucideIcons.sliders, 'Preferences'),
        const SizedBox(height: 16),
        _navSectionLabel('WORKSPACE'),
        _navItem(SettingsTab.aiProfile, LucideIcons.sparkles, 'Career Profile'),
        _navItem(SettingsTab.clientProfiles, LucideIcons.users, 'Client Profiles'),
        _navItem(SettingsTab.billing, LucideIcons.creditCard, 'Plan & Billing'),
        const SizedBox(height: 24),
        // Sign out at bottom
        _isGuest
            ? _navAction(LucideIcons.logIn, 'Create Account', AppColors.darkRaspberry, () async {
          final linked = await GuestSignupModal.show(context);
          if (linked && mounted) {
            ref.read(settingsControllerProvider.notifier).loadAll();
            setState(() {});
          }
        })
            : _navAction(LucideIcons.logOut, 'Sign Out', AppColors.slateGrey, () async {
          await ref.read(authControllerProvider.notifier).signOut();
          if (buildContext.mounted) {
            buildContext.go(AppRoutes.auth);
          }
        }),
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
        return _isGuest
            ? _withGuestOverlay(_profileContent(), message: 'Sign in to edit your profile')
            : _profileContent();
      case SettingsTab.security:
        return _isGuest
            ? _withGuestOverlay(_securityContent(), message: 'Sign in to manage security')
            : _securityContent();
      case SettingsTab.billing:
        return _billingContent();
      case SettingsTab.preferences:
        return _preferencesContent();
      case SettingsTab.aiProfile:
        return _aiProfileContent();
      case SettingsTab.clientProfiles:
        return _clientProfilesContent();
    }
  }

  // ─── PROFILE TAB ──────────────────────────────────────────────────────

  Widget _profileContent() {
    final user = FirebaseAuth.instance.currentUser;
    final state = ref.watch(settingsControllerProvider);

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
                    state.profile?.displayName ?? 'User',
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                      color: AppColors.prussianBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.profile?.email ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.openSans,
                      color: AppColors.slateGrey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Member since ${_fmtDate(state.profile?.createdAt)}',
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
            _fieldReadOnly('Email', state.profile?.email ?? ''),
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
                  onPressed: state.isSaving
                      ? null
                      : () => ref.read(settingsControllerProvider.notifier).saveProfile(
                    displayName: _nameCtrl.text,
                    phone: _phoneCtrl.text,
                    location: _locationCtrl.text,
                    bio: _bioCtrl.text,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkRaspberry,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: state.isSaving
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
    final state = ref.watch(settingsControllerProvider);
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
              state.profile?.email ?? '',
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
                LucideIcons.link,
                'Link Google Account',
                'Connect your Google account for faster sign-in',
                trailing: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => ref.read(settingsControllerProvider.notifier).linkGoogleAccount(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.darkRaspberry,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Link',
                          style: TextStyle(fontSize: 12, color: AppColors.white,
                              fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ),
            ],
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
    final state = ref.watch(settingsControllerProvider);
    final sub = state.subscription;
    final isTrial = sub.plan == 'trial' && (sub.trialActive);
    final isPro = sub.plan == 'pro';
    final isFree = !isTrial && !isPro;

    // Calculate trial days remaining
    int trialDaysRemaining = 0;
    if (isTrial && sub.trialEndDate != null) {
      trialDaysRemaining = sub.trialEndDate!.difference(DateTime.now()).inDays.clamp(0, 999);
    }

    // Cycle reset date
    final cycleEnd = sub.cycleEndDate;
    final cycleResetLabel = cycleEnd != null ? _fmtDate(cycleEnd) : 'Unknown';

    return Column(
      key: const ValueKey('billing'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentHeader('Plan & Billing', 'Manage your subscription and usage'),
        const SizedBox(height: 28),

        // ── Current Plan Card ─────────────────────────────────────
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
                    color: isPro
                        ? AppColors.success
                        : isTrial
                        ? AppColors.dustyMauve
                        : AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPro
                        ? 'PRO — \$7/mo'
                        : isTrial
                        ? 'TRIAL — $trialDaysRemaining days left'
                        : 'FREE',
                    style: TextStyle(
                      fontSize: 12, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700,
                      color: isFree ? AppColors.darkRaspberry : AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Plan details
            if (isTrial) ...[
              _planDetailRow(LucideIcons.clock, 'Trial Started',
                  sub.trialStartDate != null ? _fmtDate(sub.trialStartDate!) : 'Unknown'),
              const SizedBox(height: 10),
              _planDetailRow(LucideIcons.calendarX, 'Trial Ends',
                  sub.trialEndDate != null ? _fmtDate(sub.trialEndDate!) : 'Unknown'),
              const SizedBox(height: 10),
              // Trial progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: trialDaysRemaining / 7,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF0EBE6),
                  valueColor: AlwaysStoppedAnimation(
                    trialDaysRemaining <= 2 ? AppColors.error : AppColors.success,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$trialDaysRemaining of 7 days remaining',
                style: const TextStyle(fontSize: 11, color: AppColors.slateGrey,
                    fontFamily: AppFonts.openSans),
              ),
            ],
            if (isFree) ...[
              _planDetailRow(LucideIcons.refreshCw, 'Usage Resets On', cycleResetLabel),
              const SizedBox(height: 10),
              _planDetailRow(LucideIcons.sparkles, 'Trial Available',
                  _isGuest ? 'Sign up to activate' : (sub.trialUsed) ? 'Already used' : 'Yes — 7 days free'),
            ],
            if (isPro) ...[
              _planDetailRow(LucideIcons.calendar, 'Billing Cycle', cycleResetLabel),
              if (sub.subscriptionStartDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _planDetailRow(LucideIcons.calendarCheck, 'Member Since',
                      _fmtDate(sub.subscriptionStartDate!)),
                ),
            ],

            const SizedBox(height: 20),
            const Divider(color: Color(0xFFF0EBE6)),
            const SizedBox(height: 16),

            // Usage stats
            const Text('Usage This Cycle',
                style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
            const SizedBox(height: 12),
            _usageBar('PDF Exports', LucideIcons.download,
                sub.exportCount, (isPro || isTrial) ? -1 : 3, AppColors.magentaBloom),
            const SizedBox(height: 12),
            _usageBar('AI Composes', LucideIcons.sparkles,
                sub.aiFillCount, (isPro || isTrial) ? -1 : 15, AppColors.dustyMauve),
            const SizedBox(height: 12),
            _usageBar('AI Refines', LucideIcons.pencil,
                sub.aiRewriteCount, (isPro || isTrial) ? -1 : 15, AppColors.dustyRose),
            const SizedBox(height: 12),
            _usageBar('Spellchecks', LucideIcons.spellCheck,
                sub.spellcheckCount, -1, AppColors.slateGrey),
          ],
        )),
        const SizedBox(height: 20),

        // ── Upgrade / Trial CTA ───────────────────────────────────
        if (isFree) ...[
          if (!(sub.trialUsed))
            SettingsBillingCta(
              title: _isGuest ? 'Sign Up to Unlock Pro Trial' : 'Try KitAura Pro Free',
              subtitle: _isGuest
                  ? 'Create a free account first, then start your 7-day trial.'
                  : '7 days unlimited access. No credit card required.',
              buttonLabel: _isGuest ? 'Create Account' : 'Start Free Trial',
              onTap: _isGuest
                  ? () async {
                final linked = await GuestSignupModal.show(context);
                if (linked && mounted) {
                  ref.read(settingsControllerProvider.notifier).loadAll();
                  setState(() {});
                }
              }
                  : () => showTrialDialog(context, ref),
              gradientColors: const [AppColors.prussianBlue, Color(0xFF2D1B3D), AppColors.darkRaspberry],
            )
          else
            SettingsBillingCta(
              title: 'Upgrade to Pro',
              subtitle: 'Unlimited exports, AI, templates. No watermark.',
              buttonLabel: 'Upgrade — \$7/mo',
              onTap: () => showDialog(context: context, builder: (_) => const UpgradeModal()),
            ),
        ],
        if (isTrial)
          SettingsBillingCta(
            title: 'Keep Pro Forever',
            subtitle: 'Your trial ends in $trialDaysRemaining days. Upgrade to keep unlimited access.',
            buttonLabel: 'Upgrade — \$7/mo',
            onTap: () => showDialog(context: context, builder: (_) => const UpgradeModal()),
          ),
        if (isPro)
          _card(child: _settingsRow(
            LucideIcons.creditCard,
            'Manage Billing',
            'Update payment method, view invoices',
            trailing: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {/* TODO: Stripe portal */},
                child: const Icon(LucideIcons.externalLink, size: 16,
                    color: AppColors.darkRaspberry),
              ),
            ),
          )),

        const SizedBox(height: 20),

        // ── Plan History ──────────────────────────────────────────
        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plan History',
                style: TextStyle(fontSize: 15, fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
            const SizedBox(height: 16),
            _historyItem(
              'Account Created',
              _fmtDate(state.profile?.createdAt),
              LucideIcons.userPlus,
              AppColors.success,
            ),
            if (sub.trialUsed)
              _historyItem(
                'Trial Activated',
                sub.trialStartDate != null ? _fmtDate(sub.trialStartDate!) : 'Unknown',
                LucideIcons.sparkles,
                AppColors.dustyMauve,
              ),
            if (isTrial)
              _historyItem(
                'Trial Expires',
                sub.trialEndDate != null ? _fmtDate(sub.trialEndDate!) : 'Unknown',
                LucideIcons.calendarX,
                AppColors.error,
              ),
            if (isPro && sub.subscriptionStartDate != null)
              _historyItem(
                'Upgraded to Pro',
                _fmtDate(sub.subscriptionStartDate!),
                LucideIcons.crown,
                AppColors.success,
              ),
          ],
        )),
      ],
    );
  }

  Widget _planDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.slateGrey),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.slateGrey,
                fontFamily: AppFonts.openSans)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
      ],
    );
  }

  Widget _historyItem(String title, String date, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
          ),
          Text(date,
              style: const TextStyle(fontSize: 11, color: AppColors.slateGrey,
                  fontFamily: AppFonts.openSans)),
        ],
      ),
    );
  }

  // ─── PREFERENCES TAB ──────────────────────────────────────────────────

  Widget _preferencesContent() {
    final state = ref.watch(settingsControllerProvider);
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
                state.preferences.emailNotifications, (v) {
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
            _settingsRow(LucideIcons.type, 'Default Font', state.preferences.defaultFont ?? 'Poppins'),
            const Divider(color: Color(0xFFF0EBE6), height: 32),
            _settingsRow(LucideIcons.layout, 'Default Template', state.preferences.defaultTemplate ?? 'None'),
          ],
        )),
      ],
    );
  }

  // ─── Career Profile TAB ───────────────────────────────────────────────────

  Widget _aiProfileContent() {
    final state = ref.watch(settingsControllerProvider);
    return Column(
      key: const ValueKey('ai'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with create button
        Row(
          children: [
            Expanded(child: _contentHeader('Career Profiles', 'Manage profiles used for AI content generation')),
            const SizedBox(width: 16),
            SizedBox(
              height: 40,
              width: 150,
              child: ElevatedButton.icon(
                onPressed: () => _openProfileEditor(null),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('New Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (state.loadingAiProfiles && !_isGuest)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: AppColors.darkRaspberry),
            ),
          )
        else if (state.aiProfiles.isEmpty)
          _buildEmptyProfileState()
        else
          ...state.aiProfiles.map((profile) => _buildProfileCard(profile)),
      ],
    );
  }

  Widget _buildEmptyProfileState() {
    return _card(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.userPlus, size: 24, color: AppColors.darkRaspberry),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Career Profiles yet',
            style: TextStyle(fontSize: 16, fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600, color: AppColors.prussianBlue),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a profile so AI can generate personalized content for your CVs and cover letters.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _openProfileEditor(null),
              icon: const Icon(LucideIcons.plus, size: 15),
              label: const Text('Create Your First Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProfileCard(AiProfileModel profile) {
    final isDefault = profile.isDefault;
    final expCount = profile.experiences.length;
    final eduCount = profile.education.length;
    final skillCount = profile.skills.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDefault ? AppColors.success.withValues(alpha: 0.4) : const Color(0xFFEDE8E3),
          width: isDefault ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDefault
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.petalFrost,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'P',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                      color: isDefault ? AppColors.success : AppColors.darkRaspberry,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w600,
                            color: AppColors.prussianBlue,
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'DEFAULT',
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((profile.jobTitle ?? '').isNotEmpty) profile.jobTitle!,
                        if (profile.industry.isNotEmpty) profile.industry,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.slateGrey,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Actions menu
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 18, color: AppColors.slateGrey),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (action) => _handleProfileAction(action, profile),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit',
                      child: Row(children: [
                        Icon(LucideIcons.pencil, size: 14, color: AppColors.prussianBlue),
                        SizedBox(width: 10),
                        Text('Edit', style: TextStyle(fontSize: 13)),
                      ])),
                  if (!isDefault)
                    const PopupMenuItem(value: 'default',
                        child: Row(children: [
                          Icon(LucideIcons.star, size: 14, color: AppColors.success),
                          SizedBox(width: 10),
                          Text('Set as Default', style: TextStyle(fontSize: 13)),
                        ])),
                  const PopupMenuItem(value: 'duplicate',
                      child: Row(children: [
                        Icon(LucideIcons.copy, size: 14, color: AppColors.prussianBlue),
                        SizedBox(width: 10),
                        Text('Duplicate', style: TextStyle(fontSize: 13)),
                      ])),
                  if (ref.read(settingsControllerProvider).aiProfiles.length > 1)
                    const PopupMenuItem(value: 'delete',
                        child: Row(children: [
                          Icon(LucideIcons.trash2, size: 14, color: AppColors.error),
                          SizedBox(width: 10),
                          Text('Delete', style: TextStyle(fontSize: 13, color: AppColors.error)),
                        ])),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Stats row
          Row(
            children: [
              _profileStat(LucideIcons.briefcase, '$expCount exp'),
              const SizedBox(width: 16),
              _profileStat(LucideIcons.graduationCap, '$eduCount edu'),
              const SizedBox(width: 16),
              _profileStat(LucideIcons.sparkles, '$skillCount skills'),
              const SizedBox(width: 16),
              _profileStat(LucideIcons.type, profile.experienceLevel),
            ],
          ),

          // Skills preview
          if (profile.skills.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: profile.skills.take(5).map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.petalFrost,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s,
                    style: const TextStyle(fontSize: 10, fontFamily: AppFonts.poppins,
                        color: AppColors.prussianBlue)),
              )).toList(),
            ),
            if (profile.skills.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${profile.skills.length - 5} more',
                  style: const TextStyle(fontSize: 10, color: AppColors.slateGrey),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _profileStat(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.slateGrey),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey)),
      ],
    );
  }

  void _openProfileEditor(String? profileId) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (dialogContext) => AiSetupPanel(
        toolType: AiToolType.cv,
        profileId: profileId,
        onContinue: () {
          Navigator.pop(dialogContext);
          ref.read(settingsControllerProvider.notifier).loadAiProfiles();
          ref.invalidate(aiProfilesProvider);
        },
        onSkip: () => Navigator.pop(dialogContext),
        onClose: () => Navigator.pop(dialogContext),
      ),
    );
  }

  void _handleProfileAction(String action, AiProfileModel profile) async {
    final ctrl = ref.read(settingsControllerProvider.notifier);
    switch (action) {
      case 'edit':
        _openProfileEditor(profile.id);
        break;
      case 'default':
        await ctrl.setDefaultAiProfile(profile);
        ref.invalidate(aiProfilesProvider);
        break;
      case 'duplicate':
        await ctrl.duplicateAiProfile(profile);
        ref.invalidate(aiProfilesProvider);
        break;
      case 'delete':
        _confirmDeleteAiProfile(profile);
        break;
    }
  }

  void _confirmDeleteAiProfile(AiProfileModel profile) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 30, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(LucideIcons.trash2, size: 24, color: AppColors.error),
              ),
              const SizedBox(height: 20),
              const Text('Delete Profile?',
                  style: TextStyle(fontSize: 18, fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
              const SizedBox(height: 8),
              Text('Delete "${profile.name}"? This cannot be undone.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontFamily: AppFonts.openSans,
                      color: AppColors.slateGrey)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 44,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(settingsControllerProvider.notifier).deleteAiProfile(profile);
                    ref.invalidate(aiProfilesProvider);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.error,
                      foregroundColor: AppColors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(height: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.slateGrey, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CLIENT PROFILES TAB ──────────────────────────────────────────────

  Widget _clientProfilesContent() {
    final state = ref.watch(settingsControllerProvider);
    return Column(
      key: const ValueKey('clients'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _contentHeader('Client Profiles',
                'Saved clients used to generate proposals')),
            const SizedBox(width: 16),
            SizedBox(
              height: 40, width: 150,
              child: ElevatedButton.icon(
                onPressed: () => _openClientWizard(null),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('New Client'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (state.loadingClientProfiles && !_isGuest)
          const Center(child: Padding(padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: AppColors.darkRaspberry)))
        else if (state.clientProfiles.isEmpty)
          _buildEmptyClientState()
        else
          ...state.clientProfiles.map((c) => _buildClientCard(c)),
      ],
    );
  }

  Widget _buildEmptyClientState() {
    return _card(child: Column(children: [
      const SizedBox(height: 20),
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: AppColors.petalFrost, borderRadius: BorderRadius.circular(14)),
        child: const Icon(LucideIcons.users, size: 24, color: AppColors.darkRaspberry),
      ),
      const SizedBox(height: 16),
      const Text('No client profiles yet',
          style: TextStyle(fontSize: 16, fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
      const SizedBox(height: 6),
      const Text('Add a client so AI can tailor proposals to their project and needs.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey, height: 1.5)),
      const SizedBox(height: 20),
      SizedBox(height: 40, child: ElevatedButton.icon(
        onPressed: () => _openClientWizard(null),
        icon: const Icon(LucideIcons.plus, size: 15),
        label: const Text('Add Your First Client'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkRaspberry, foregroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600),
        ),
      )),
      const SizedBox(height: 20),
    ]));
  }

  Widget _buildClientCard(ClientProfileModel client) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8E3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.petalFrost, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(
              client.clientName.isNotEmpty ? client.clientName[0].toUpperCase() : 'C',
              style: const TextStyle(fontSize: 16, fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w700, color: AppColors.darkRaspberry),
            )),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client.clientName,
                    style: const TextStyle(fontSize: 15, fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600, color: AppColors.prussianBlue),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text([
                  if ((client.clientCompany ?? '').isNotEmpty) client.clientCompany!,
                  if (client.projectTitle.isNotEmpty) client.projectTitle,
                ].join(' · '),
                    style: const TextStyle(fontSize: 12, fontFamily: AppFonts.openSans,
                        color: AppColors.slateGrey),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical, size: 18, color: AppColors.slateGrey),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (a) => _handleClientAction(a, client),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [
                Icon(LucideIcons.pencil, size: 14, color: AppColors.prussianBlue),
                SizedBox(width: 10), Text('Edit', style: TextStyle(fontSize: 13))])),
              const PopupMenuItem(value: 'duplicate', child: Row(children: [
                Icon(LucideIcons.copy, size: 14, color: AppColors.prussianBlue),
                SizedBox(width: 10), Text('Duplicate', style: TextStyle(fontSize: 13))])),
              const PopupMenuItem(value: 'delete', child: Row(children: [
                Icon(LucideIcons.trash2, size: 14, color: AppColors.error),
                SizedBox(width: 10), Text('Delete', style: TextStyle(fontSize: 13, color: AppColors.error))])),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openClientWizard(ClientProfileModel? existing) async {
    final result = await ClientWizardModal.show(context, existing: existing);
    if (result == null) return; // cancelled
    if (!mounted) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .saveClientProfile(client: result, existing: existing);
  }

  void _handleClientAction(String action, ClientProfileModel client) async {
    final ctrl = ref.read(settingsControllerProvider.notifier);
    switch (action) {
      case 'edit':
        _openClientWizard(client);
        break;
      case 'duplicate':
        await ctrl.duplicateClientProfile(client);
        break;
      case 'delete':
        await ctrl.deleteClientProfile(client);
        break;
    }
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
      case SettingsTab.aiProfile: return 'Career Profile';
      case SettingsTab.clientProfiles: return 'Clients';
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