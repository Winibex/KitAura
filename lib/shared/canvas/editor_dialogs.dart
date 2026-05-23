// lib/shared/canvas/editor_dialogs.dart
//
// Reusable dialogs for canvas editors (CV, Proposal).
// - Color picker dialog
// - Icon picker dialog

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

class EditorDialogs {
  EditorDialogs._();

  /// Shows a color picker dialog. Returns the selected color or null if cancelled.
  static Future<Color?> showColorPicker({
    required BuildContext context,
    required String title,
    required Color currentColor,
    bool enableAlpha = true,
  }) async
  {
    Color selected = currentColor;

    return showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w600,
            color: AppColors.prussianBlue,
          ),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selected,
            onColorChanged: (c) => selected = c,
            enableAlpha: enableAlpha,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.slateGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  /// Shows an icon picker dialog. Returns the selected IconData or null if cancelled.
  static Future<IconData?> showIconPicker({
    required BuildContext context,
    required Color iconColor,
  })
  {
    const icons = <IconData>[
      Icons.star, Icons.favorite, Icons.phone, Icons.email,
      Icons.location_on, Icons.work, Icons.school, Icons.person,
      Icons.link, Icons.language, Icons.code, Icons.build,
      Icons.check_circle, Icons.arrow_forward, Icons.lightbulb,
      Icons.emoji_events, Icons.bar_chart, Icons.calendar_today,
    ];

    return showDialog<IconData>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pick an Icon',
            style: TextStyle(
                fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600)),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: icons
              .map((ic) => GestureDetector(
            onTap: () => Navigator.pop(ctx, ic),
            child: Icon(ic, size: 32, color: iconColor),
          ))
              .toList(),
        ),
      ),
    );
  }

  /// Shows a confirmation dialog for page deletion.
  static Future<bool> confirmDeletePage({
    required BuildContext context,
    required int pageNumber,
  }) async
  {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Page?',
            style: TextStyle(
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
                color: AppColors.prussianBlue)),
        content: Text(
            'Delete page $pageNumber and all its contents?',
            style: const TextStyle(
                fontFamily: AppFonts.openSans, color: AppColors.slateGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.slateGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}