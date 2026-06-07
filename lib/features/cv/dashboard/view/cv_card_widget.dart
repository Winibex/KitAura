// lib/features/dashboard/view/cv_card_widget.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_sizes.dart';
import '../model/cv_summary_model.dart';
import '../../../../shared/widgets/template_thumbnail.dart';

class CvCardWidget extends StatelessWidget {
  final CvSummaryModel cv;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;

  const CvCardWidget({
    super.key,
    required this.cv,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  // Static decorations — not rebuilt on every build()
  static const BoxDecoration _cardDecoration = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.all(Radius.circular(14)),
    boxShadow: [
      BoxShadow(
        color: Color(0x120F172A),
        blurRadius: 12,
        offset: Offset(0, 2),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: _cardDecoration,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildThumbnail()),
                _buildInfo(context),
              ],
            ),
            // 3-dot menu at top right
            Positioned(
              top: 8,
              right: 8,
              child: Container(padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
                  decoration: BoxDecoration(
                    color: AppColors.darkRaspberry,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: _buildMenu(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F0EB),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: (cv.items != null && cv.items!.isNotEmpty)
          ? TemplateThumbnail.fromJson(
        json: {
          'canvasBackground': cv.canvasBackground ?? '#FFFFFF',
          'items': cv.items,
        },
        width: double.infinity,
        height: 300,
        borderRadius: 0,
        showShadow: false,
      )
          : _buildBlankPreview(),
    );
  }

  Widget _buildBlankPreview() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.fileText, color: AppColors.almondSilk, size: 32),
          SizedBox(height: 8),
          Text(
            'Untitled',
            style: TextStyle(
              color: AppColors.almondSilk,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cv.title,
            style: const TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Updated ${cv.timeAgo}',
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 11,
              fontFamily: AppFonts.openSans,
            ),
          ),
          const SizedBox(height: 10),
              // Template tag
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.petalFrost,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cv.templateId,
                  style: const TextStyle(
                    color: AppColors.darkRaspberry,
                    fontSize: 10,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return SizedBox(
      width: AppSizes.icons(context),
      height: AppSizes.icons(context),
      child: PopupMenuButton<String>(
        icon: const Icon(LucideIcons.moreHorizontal, color: AppColors.petalFrost, size: 16),
        padding: EdgeInsets.zero,
        iconSize: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        color: AppColors.white,
        elevation: 4,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 160),
        onSelected: (value) {
          if (value == 'rename') {
            _showRenameDialog(context);
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'rename',
            height: 36,
            child: Row(
              children: [
                const Icon(LucideIcons.pencil, size: 14, color: AppColors.slateGrey),
                const SizedBox(width: 8),
                const Text('Rename', style: TextStyle(fontSize: 13, color: AppColors.prussianBlue)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            height: 36,
            child: Row(
              children: [
                const Icon(LucideIcons.trash2, size: 14, color: AppColors.error),
                const SizedBox(width: 8),
                const Text('Delete', style: TextStyle(fontSize: 13, color: AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: cv.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Rename CV',
          style: TextStyle(
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
            color: AppColors.prussianBlue,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'CV title',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.slateGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                onRename(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}