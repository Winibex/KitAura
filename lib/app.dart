import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'features/settings/view/settings_screen.dart';
import 'features/auth/view/verify_email_screen.dart';
import 'features/auth/view/reset_password_screen.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../shared/widgets/no_internet_overlay.dart';

final _router = GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    GoRoute(path: AppRoutes.auth, builder: (_, _) => const AuthScreen()),
    GoRoute(
      path: AppRoutes.verifyEmail,
      builder: (_, _) => const VerifyEmailScreen(),
    ),
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
  ],
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final isAuthRoute =
        state.matchedLocation == AppRoutes.auth;
    final isVerify = state.matchedLocation == AppRoutes.verifyEmail;

    if (isLoggedIn && isAuthRoute) {
      return user.emailVerified ? AppRoutes.dashboard : AppRoutes.verifyEmail;
    }
    if (!isLoggedIn && !isAuthRoute && state.matchedLocation != AppRoutes.resetPassword) {
      return AppRoutes.auth;
    }
    if (isLoggedIn && !user.emailVerified && !isVerify && !isAuthRoute) {
      return AppRoutes.verifyEmail;
    }
    return null;
  },
);

class KitAuraApp extends ConsumerWidget {
  const KitAuraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
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
    );
  }
}
