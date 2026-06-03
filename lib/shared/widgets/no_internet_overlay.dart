// lib/shared/widgets/no_internet_overlay.dart
//
// Full-screen overlay when internet is lost.
// Debug: ConnectivityService.simulateOffline() to test without disabling WiFi.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../services/connectivity_service.dart';

class NoInternetOverlay extends StatefulWidget {
  final Widget child;
  const NoInternetOverlay({super.key, required this.child});

  @override
  State<NoInternetOverlay> createState() => _NoInternetOverlayState();
}

class _NoInternetOverlayState extends State<NoInternetOverlay>
    with SingleTickerProviderStateMixin {
  late bool _isOnline;
  StreamSubscription<bool>? _sub;
  bool _isChecking = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.isOnline;
    _sub = ConnectivityService.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _isChecking = true);
    await ConnectivityService.checkConnectivity();
    // Small delay so user sees the spinner
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isOnline)
          Positioned.fill(child: _buildOverlay()),
      ],
    );
  }

  Widget _buildOverlay() {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B1120), // Deep navy
              Color(0xFF0F172A), // Prussian blue
              Color(0xFF1A0E2E), // Hint of purple
            ],
          ),
        ),
        child: Stack(
          children: [
            // Background decorative elements
            ..._buildBackgroundDots(),
            // Main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIconSection(),
                  const SizedBox(height: 32),
                  _buildTextSection(),
                  const SizedBox(height: 40),
                  _buildRetryButton(),
                  const SizedBox(height: 24),
                  _buildHelpText(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBackgroundDots() {
    // Decorative floating dots in background
    final rng = Random(42);
    return List.generate(20, (i) {
      final x = rng.nextDouble();
      final y = rng.nextDouble();
      final size = 2.0 + rng.nextDouble() * 4;
      final opacity = 0.03 + rng.nextDouble() * 0.08;
      return Positioned(
        left: x * 1400,
        top: y * 800,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.white.withValues(alpha: opacity),
          ),
        ),
      );
    });
  }

  Widget _buildIconSection() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Container(
              width: 140 * _pulseAnim.value,
              height: 140 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.darkRaspberry.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            // Middle pulse ring
            Container(
              width: 110 * _pulseAnim.value,
              height: 110 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.darkRaspberry.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            // Icon circle
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.darkRaspberry.withValues(alpha: 0.3),
                    AppColors.magentaBloom.withValues(alpha: 0.15),
                  ],
                ),
                border: Border.all(
                  color: AppColors.darkRaspberry.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                LucideIcons.wifiOff,
                color: AppColors.white,
                size: 36,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextSection() {
    return Column(
      children: [
        const Text(
          'No Internet Connection',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 26,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            'We can\'t reach the internet right now.\nCheck your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.55),
              fontSize: 15,
              fontFamily: AppFonts.openSans,
              height: 1.6,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRetryButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isChecking ? null : _retry,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkRaspberry.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _isChecking
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
          )
              : const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.refreshCw, color: AppColors.white, size: 18),
              SizedBox(width: 10),
              Text(
                'Try Again',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpText() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.info, size: 14, color: AppColors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text(
            'Connected to WiFi but no internet? Try restarting your router.',
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontFamily: AppFonts.openSans,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}