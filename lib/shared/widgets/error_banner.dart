// Error message banner with red background.
// Used by: auth, settings, editor, any screen that shows errors.

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 13),
      ),
    );
  }
}