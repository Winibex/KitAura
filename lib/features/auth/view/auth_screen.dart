import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/form_field_widget.dart';
import '../controller/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSignIn = true;

  // Separate controllers per form — no cross-contamination
  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  final _signUpName = TextEditingController();
  final _signUpEmail = TextEditingController();
  final _signUpPassword = TextEditingController();
  final _signUpConfirm = TextEditingController();

  bool _obscureSignInPw = true;
  bool _obscureSignUpPw = true;
  bool _obscureSignUpConfirm = true;

  @override
  void dispose() {
    _signInEmail.dispose();
    _signInPassword.dispose();
    _signUpName.dispose();
    _signUpEmail.dispose();
    _signUpPassword.dispose();
    _signUpConfirm.dispose();
    super.dispose();
  }

  // ── Navigation listener — controller drives nav, not UI callbacks ────

  void _handleNavigation(AuthState state) {
    if (!mounted) return;
    switch (state.navigate) {
      case AuthNav.dashboard:
        context.go(AppRoutes.dashboard);
      case AuthNav.verifyEmail:
        context.go(AppRoutes.verifyEmail);
      case AuthNav.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for navigation signals from controller
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      _handleNavigation(next);
    });

    return Scaffold(
      body: ResponsiveBuilder(
        mobile: _buildMobileLayout(),
        desktop: _buildDesktopLayout(),
      ),
    );
  }

  // ── Layouts ──────────────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(flex: 45, child: _buildLeftPanel()),
        Expanded(flex: 55, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Container(
      decoration: _gradientDecoration,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildFormCard(),
          ),
        ),
      ),
    );
  }

  // ── Left branding panel ──────────────────────────────────────────────

  Widget _buildLeftPanel() {
    return Container(
      color: AppColors.prussianBlue,
      padding: const EdgeInsets.all(60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(AppAssets.logoStackedLight, height: 80),
          const SizedBox(height: 40),
          const Text(
            'Build your career story.',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 38,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'AI-powered CVs that get you hired.',
            style: TextStyle(
              color: AppColors.almondSilk,
              fontSize: 16,
              fontFamily: AppFonts.openSans,
            ),
          ),
          const SizedBox(height: 40),
          _buildFeature(LucideIcons.sparkles, 'AI writes your content'),
          const SizedBox(height: 12),
          _buildFeature(LucideIcons.move, 'Design freely on canvas'),
          const SizedBox(height: 12),
          _buildFeature(LucideIcons.fileDown, 'Export as professional PDF'),
          const Spacer(),
          const Text(
            'Trusted by professionals worldwide',
            style: TextStyle(
              color: AppColors.slateGrey,
              fontSize: 13,
              fontFamily: AppFonts.openSans,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.magentaBloom, size: 18),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 15,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ],
    );
  }

  Widget _buildRightPanel() {
    return Container(
      decoration: _gradientDecoration,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          child: _buildFormCard(),
        ),
      ),
    );
  }

  // ── Form card ────────────────────────────────────────────────────────

  static const _gradientDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFD4E5), Color(0xFFFFE4EC), Color(0xFFFFF1F5)],
    ),
  );

  Widget _buildFormCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.only(left: 32, right: 32, bottom: 32, top: 32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.prussianBlue.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabSwitcher(),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.1, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _isSignIn ? _buildSignInForm() : _buildSignUpForm(),
          ),
        ],
      ),
    );
  }

  // ── Tab switcher ─────────────────────────────────────────────────────

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.petalFrost,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTab(AppStrings.signIn, _isSignIn, () {
            setState(() => _isSignIn = true);
            ref.read(authControllerProvider.notifier).clearError();
          })),
          Expanded(child: _buildTab(AppStrings.signUp, !_isSignIn, () {
            setState(() => _isSignIn = false);
            ref.read(authControllerProvider.notifier).clearError();
          })),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.darkRaspberry : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AppColors.white : AppColors.slateGrey,
            fontSize: 13,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Sign In Form ─────────────────────────────────────────────────────

  Widget _buildSignInForm() {
    final authState = ref.watch(authControllerProvider);

    return Column(
      key: const ValueKey('signin'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Welcome back',
          style: TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 28,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sign in to continue building',
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: 14,
            fontFamily: AppFonts.openSans,
          ),
        ),
        const SizedBox(height: 20),

        KitauraTextField(
          label: 'Email address',
          controller: _signInEmail,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        KitauraTextField(
          label: 'Password',
          controller: _signInPassword,
          hint: '••••••••',
          obscure: _obscureSignInPw,
          onToggleObscure: () =>
              setState(() => _obscureSignInPw = !_obscureSignInPw),
        ),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push(AppRoutes.resetPassword),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
            child: const Text(
              'Forgot password?',
              style: TextStyle(color: AppColors.darkRaspberry, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),

        if (authState.error != null) ...[
          ErrorBanner(message: authState.error!),
          const SizedBox(height: 12),
        ],

        _AuthButton(
          label: 'Sign In',
          isLoading: authState.isLoading,
          onPressed: () {
            ref.read(authControllerProvider.notifier).signInWithEmail(
              _signInEmail.text.trim(),
              _signInPassword.text,
            );
          },
        ),
        const SizedBox(height: 14),

        _buildDivider(),
        const SizedBox(height: 14),

        _GoogleButton(
          isLoading: authState.isLoading,
          onPressed: () {
            ref.read(authControllerProvider.notifier).signInWithGoogle();
          },
        ),
      ],
    );
  }

  // ── Sign Up Form ─────────────────────────────────────────────────────

  Widget _buildSignUpForm() {
    final authState = ref.watch(authControllerProvider);

    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Create your account',
          style: TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 28,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Start crafting your CV in minutes',
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: 14,
            fontFamily: AppFonts.openSans,
          ),
        ),
        const SizedBox(height: 20),

        KitauraTextField(
          label: 'Full name',
          controller: _signUpName,
          hint: 'Ada Lovelace',
        ),
        const SizedBox(height: 14),

        KitauraTextField(
          label: 'Email address',
          controller: _signUpEmail,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        KitauraTextField(
          label: 'Password',
          controller: _signUpPassword,
          hint: '••••••••',
          obscure: _obscureSignUpPw,
          onToggleObscure: () =>
              setState(() => _obscureSignUpPw = !_obscureSignUpPw),
        ),
        const SizedBox(height: 14),

        KitauraTextField(
          label: 'Confirm password',
          controller: _signUpConfirm,
          hint: '••••••••',
          obscure: _obscureSignUpConfirm,
          onToggleObscure: () =>
              setState(() => _obscureSignUpConfirm = !_obscureSignUpConfirm),
        ),
        const SizedBox(height: 20),

        if (authState.error != null) ...[
          ErrorBanner(message: authState.error!),
          const SizedBox(height: 12),
        ],

        _AuthButton(
          label: 'Create Account',
          isLoading: authState.isLoading,
          onPressed: () {
            ref.read(authControllerProvider.notifier).signUpWithEmail(
              _signUpEmail.text.trim(),
              _signUpPassword.text,
              _signUpConfirm.text,
              _signUpName.text.trim(),
            );
          },
        ),
        const SizedBox(height: 10),

        const Text(
          'By signing up, you agree to our Terms & Privacy Policy',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.slateGrey, fontSize: 12),
        ),
        const SizedBox(height: 14),

        _buildDivider(),
        const SizedBox(height: 14),

        _GoogleButton(
          isLoading: authState.isLoading,
          onPressed: () {
            ref.read(authControllerProvider.notifier).signInWithGoogle();
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Shared widgets ───────────────────────────────────────────────────

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.almondSilk)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('or',
              style: TextStyle(color: AppColors.slateGrey, fontSize: 13)),
        ),
        Expanded(child: Divider(color: AppColors.almondSilk)),
      ],
    );
  }
}

/// Error message banner.


/// Primary action button with loading state.
class _AuthButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;
  const _AuthButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            color: AppColors.white,
            strokeWidth: 2,
          ),
        )
            : Text(label),
      ),
    );
  }
}

/// Google sign-in button.
class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  const _GoogleButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.almondSilk),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.g_mobiledata, color: AppColors.prussianBlue),
            SizedBox(width: 8),
            Text(
              'Continue with Google',
              style: TextStyle(
                color: AppColors.prussianBlue,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}