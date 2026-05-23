// Labeled text field with optional password toggle.
// Used by: auth, settings, ai_setup, any form screen.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

class KitauraTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final bool? obscure;
  final VoidCallback? onToggleObscure;

  const KitauraTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.obscure,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 13,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure ?? false,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            suffixIcon: obscure != null
                ? IconButton(
              icon: Icon(
                obscure! ? LucideIcons.eyeOff : LucideIcons.eye,
                color: AppColors.slateGrey,
                size: 18,
              ),
              onPressed: onToggleObscure,
            )
                : null,
          ),
        ),
      ],
    );
  }
}