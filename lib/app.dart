import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/view/auth_screen.dart';
import 'features/cover_letter/dashboard/view/cl_dashboard_screen.dart';
import 'features/cover_letter/editor/view/cl_editor_screen.dart';
import 'features/cover_letter/template/view/cl_template_picker_screen.dart';
import 'features/cv/dashboard/view/cv_dashboard_screen.dart';
import 'features/cv/editor/view/cv_editor_screen.dart';
import 'features/cv/templates/view/cv_template_picker_screen.dart';
import 'features/dashboard/view/dashboard_screen.dart';
import 'features/linkedin/view/linkedin_screen.dart';
import 'features/proposal/dashboard/view/prop_dashboard_screen.dart';
import 'features/proposal/editor/view/prop_editor_screen.dart';
import 'features/proposal/template/view/prop_template_picker_screen.dart';
import 'features/settings/view/settings_screen.dart';
import 'shared/providers/feature_flags_provider.dart';
import 'features/auth/view/reset_password_screen.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../shared/widgets/no_internet_overlay.dart';

/// Synchronous flag for the GoRouter redirect.
/// Updated on every KitAuraApp rebuild via ref.watch.
class _GuestMode {
  static bool enabled = true; // safe default: guest mode on
}

/// Routes accessible without any Firebase auth when guest mode is on.
bool _isGuestRoute(String location) {
  const allowed = {
    '/dashboard', '/cv', '/cv/templates',
    '/cover-letters', '/cover-letters/templates',
    '/proposals', '/proposals/templates',
  };
  if (allowed.contains(location)) return true;
  // Template deep-links (Step 4 will add these routes)
  if (location.startsWith('/cv/templates/')) return true;
  if (location.startsWith('/cover-letters/templates/')) return true;
  if (location.startsWith('/proposals/templates/')) return true;
  return false;
}

final _router = GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    GoRoute(path: AppRoutes.auth, builder: (_, _) => const AuthScreen()),

    GoRoute(
      path: AppRoutes.resetPassword,
      builder: (_, _) => const ResetPasswordScreen(),
    ),

    GoRoute(
      path: AppRoutes.dashboard,
      builder: (_, _) => const DashboardScreen(),
    ),

    // CV routes
    GoRoute(
      path: AppRoutes.cvDashboard,
      builder: (_, _) => const CVDashboardScreen(),
    ),
    GoRoute(
      path: AppRoutes.cvTemplates,
      builder: (_, _) => const CVTemplatePickerScreen(),
    ),
    GoRoute(
      path: AppRoutes.cvTemplatePreview,
      builder: (_, state) => CVTemplatePickerScreen(
        deepLinkTemplateId: state.pathParameters['templateId'],
      ),
    ),
    GoRoute(
      path: '/cv/edit/:docId',
      builder: (ctx, state) {
        final docId = state.pathParameters['docId']!;
        return CvEditorScreen(docId: docId);
      },
    ),
    // Cover Letter routes
    GoRoute(
      path: AppRoutes.clDashboard,
      builder: (_, _) => const ClDashboardScreen(),
    ),
    GoRoute(
      path: AppRoutes.clTemplates,
      builder: (_, _) => const ClTemplatePickerScreen(),
    ),
    GoRoute(
      path: AppRoutes.clTemplatePreview,
      builder: (_, state) => ClTemplatePickerScreen(
        deepLinkTemplateId: state.pathParameters['templateId'],
      ),
    ),
    GoRoute(
      path: '/cover-letters/edit/:docId',
      builder: (context, state) {
        final docId = state.pathParameters['docId']!;
        return ClEditorScreen(docId: docId);
      },
    ),
    GoRoute(
      path: AppRoutes.linkedin,
      builder: (_, _) => const LinkedInScreen(),
    ),
    // Settings
    GoRoute(
      path: AppRoutes.settings,
      builder: (_, _) => const SettingsScreen(),
    ),
    // Proposal routes
    GoRoute(
      path: AppRoutes.proposalDashboard,
      builder: (_, _) => const PropDashboardScreen(),
    ),
    // Route:
    GoRoute(
      path: AppRoutes.proposalTemplates,
      builder: (_, _) => const PropTemplatePickerScreen(),
    ),
    GoRoute(
      path: AppRoutes.proposalTemplatePreview,
      builder: (_, state) => PropTemplatePickerScreen(
        deepLinkTemplateId: state.pathParameters['templateId'],
      ),
    ),
    GoRoute(
      path: '/proposals/edit/:docId',
      builder: (context, state) {
        final docId = state.pathParameters['docId']!;
        return PropEditorScreen(docId: docId);
      },
    ),
  ],
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final location = state.matchedLocation;
    final isAuthRoute = location == AppRoutes.auth;
    final isResetPassword = location == AppRoutes.resetPassword;

    // Signed-in user (real or anonymous) on login page → dashboard
    if (isLoggedIn && isAuthRoute) return AppRoutes.dashboard;

    // Not signed in
    if (!isLoggedIn) {
      // Auth pages always accessible
      if (isAuthRoute || isResetPassword) return null;

      // Guest mode: allow browsing dashboards + template pickers
      if (_GuestMode.enabled && _isGuestRoute(location)) return null;

      // Everything else → login
      return AppRoutes.auth;
    }

    // Signed in (real or anonymous) → allow all routes
    return null;
  },
);

class KitAuraApp extends ConsumerWidget {
  const KitAuraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep guest-mode flag in sync for the GoRouter redirect
    _GuestMode.enabled = ref.watch(guestModeEnabledProvider);

    return SkeletonizerConfig(
      data: SkeletonizerConfigData(
        effect: ShimmerEffect(
          baseColor: AppColors.petalFrost,
          highlightColor: AppColors.lavenderBlush,
          duration: const Duration(milliseconds: 1200),
        ),
        justifyMultiLineText: true,
      ),
      child: MaterialApp.router(
        title: 'Kitaura',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        builder: (context, child) {
          return NoInternetOverlay(child: child ?? const SizedBox.shrink());
        },
      ),
    );
  }
}
