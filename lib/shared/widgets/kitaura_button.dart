// lib/shared/widgets/kitaura_button.dart

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

enum KitauraButtonVariant { primary, secondary, ghost }

class KitauraButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final KitauraButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final double? width;

  const KitauraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = KitauraButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.height = 48,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case KitauraButtonVariant.primary:
        return _buildPrimary();
      case KitauraButtonVariant.secondary:
        return _buildSecondary();
      case KitauraButtonVariant.ghost:
        return _buildGhost();
    }
  }

  Widget _buildPrimary() {
    return SizedBox(
      height: height,
      width: width,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkRaspberry,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _buildChild(AppColors.white),
      ),
    );
  }

  Widget _buildSecondary() {
    return SizedBox(
      height: height,
      width: width,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkRaspberry,
          side: const BorderSide(color: AppColors.darkRaspberry),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _buildChild(AppColors.darkRaspberry),
      ),
    );
  }

  Widget _buildGhost() {
    return SizedBox(
      height: height,
      width: width,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        child: _buildChild(AppColors.darkRaspberry),
      ),
    );
  }

  Widget _buildChild(Color color) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          color: color,
          strokeWidth: 2,
        ),
      );
    }
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      );
    }
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: color,
      ),
    );
  }
}