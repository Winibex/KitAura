// lib/shared/widgets/auth_screen_wrapper.dart

import 'package:flutter/material.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../core/utils/responsive.dart';

class AuthScreenWrapper extends StatelessWidget {
  final Widget child;
  final bool showBranding;

  const AuthScreenWrapper({
    super.key,
    required this.child,
    this.showBranding = true,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    if (!isMobile) {
      // Desktop: just center the card on lavenderBlush
      return Scaffold(
        backgroundColor: AppColors.lavenderBlush,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      );
    }

    // Mobile: dark gradient header + card
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.prussianBlue,
              Color(0xFF2D1B3D),
              AppColors.darkRaspberry,
              Color(0xFFD4748A),
              Color(0xFFFFE4EC),
              Color(0xFFFFF1F5),
            ],
            stops: [0.0, 0.12, 0.25, 0.4, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (showBranding) ...[
                  const SizedBox(height: 32),
                  Image.asset(AppAssets.logoStackedLight, height: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'Build your career story.',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'AI-powered CVs that get you hired.',
                    style: TextStyle(
                      color: AppColors.almondSilk,
                      fontSize: 13,
                      fontFamily: AppFonts.openSans,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}