// lib/shared/canvas/editor_app_bar.dart
//
// Shared top bar for all canvas-based editors (CV, Proposal).
// Shows: back button, logo, editable title, save status, undo/redo, action buttons.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';

/// Action button data for the right side of the app bar.
class EditorAppBarAction {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;

  const EditorAppBarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.onTap,
  });
}

class EditorAppBar extends StatelessWidget {
  final String title;
  final bool isEditingTitle;
  final TextEditingController titleController;
  final VoidCallback onBack;
  final VoidCallback onTitleTap;
  final ValueChanged<String> onTitleSubmitted;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool showSavedBadge;
  final bool isSaving;
  final List<EditorAppBarAction> actions;

  const EditorAppBar({
    super.key,
    required this.title,
    required this.isEditingTitle,
    required this.titleController,
    required this.onBack,
    required this.onTitleTap,
    required this.onTitleSubmitted,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    this.isSaving = false,
    this.showSavedBadge = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.prussianBlue,
      child: Row(
        children: [
          // Back button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(LucideIcons.arrowLeft,
                    color: AppColors.white, size: 16),
              ),
            ),
          ),
          SizedBox(width: isMobile ? 8 : 12),

          // Logo — hide on mobile
          if (!isMobile) ...[
            Image.asset(AppAssets.logoHorizontalLight, height: 20),
            const SizedBox(width: 16),
          ],

              // Title
            if (isMobile)
            Flexible(
              child: isEditingTitle
                  ? SizedBox(
                width: 120,
                height: 32,
                child: TextField(
                  controller: titleController,
                  autofocus: true,
                  style: const TextStyle(
                    color: AppColors.white, fontSize: 14,
                    fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.white.withValues(alpha: 0.15),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: AppColors.white),
                    ),
                  ),
                  onSubmitted: onTitleSubmitted,
                ),
              )
                  : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(title,
                            style: const TextStyle(color: AppColors.white, fontSize: 14,
                                fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Icon(LucideIcons.pencil, size: 12,
                          color: AppColors.white.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
              ),
            )
            else
            isEditingTitle
            ? SizedBox(
            width: 200,
            height: 32,
            child: TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(
                color: AppColors.white, fontSize: 14,
                fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.white.withValues(alpha: 0.15),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: AppColors.white),
                ),
              ),
              onSubmitted: onTitleSubmitted,
            ),
          )
              : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTitleTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(color: AppColors.white, fontSize: 14,
                          fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.pencil, size: 12,
                      color: AppColors.white.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Saved badge
          if (isSaving)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.dustyRose.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isMobile
                  ? const SizedBox(width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.dustyRose))
                  : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 10, height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.dustyRose)),
                  SizedBox(width: 6),
                  Text('Saving...', style: TextStyle(color: AppColors.dustyRose, fontSize: 11, fontFamily: AppFonts.poppins)),
                ],
              ),
            )
          else if (showSavedBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Saved',
                  style: TextStyle(color: AppColors.success, fontSize: 11, fontFamily: AppFonts.poppins)),
            ),

          const Spacer(),

          // Undo/Redo — compact on mobile
          SizedBox(
            width: 32, height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(LucideIcons.undo2,
                  color: canUndo ? AppColors.white : AppColors.white.withValues(alpha: 0.25),
                  size: isMobile ? 16 : 18),
              tooltip: 'Undo',
              onPressed: canUndo ? onUndo : null,
            ),
          ),
          SizedBox(
            width: 32, height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(LucideIcons.redo2,
                  color: canRedo ? AppColors.white : AppColors.white.withValues(alpha: 0.25),
                  size: isMobile ? 16 : 18),
              tooltip: 'Redo',
              onPressed: canRedo ? onRedo : null,
            ),
          ),
          const SizedBox(width: 4),

          // Actions — icon only on mobile
          ...actions.map((action) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _buildActionButton(action, isMobile),
          )),
        ],
      ),
    );
  }

  Widget _buildActionButton(EditorAppBarAction action, bool isMobile) {
    return MouseRegion(
      cursor: action.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: action.onTap,
        child: Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
          decoration: BoxDecoration(
            color: action.onTap != null ? action.bgColor : AppColors.slateGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 14, color: action.color),
              if (!isMobile) ...[
                const SizedBox(width: 6),
                Text(action.label,
                    style: TextStyle(color: action.color, fontSize: 12,
                        fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}