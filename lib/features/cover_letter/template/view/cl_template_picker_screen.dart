// lib/features/cover_letter/view/cl_template_picker_screen.dart
//
// Matches cv_template_picker_screen.dart design — same layout, Riverpod state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../controller/cl_template_controller.dart';
import '../data/cl_template_data.dart';
import 'cl_template_card_widget.dart';
import 'cl_template_preview_modal.dart';

class ClTemplatePickerScreen extends ConsumerWidget {
  const ClTemplatePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clTemplateControllerProvider);
    final ctrl = ref.read(clTemplateControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.lavenderBlush,
      body: Column(
        children: [
          // ── Top bar (matches CV picker) ──────────────────────────────
          AppTopBar(
            canBack: true,
            whereToGo: AppRoutes.clDashboard,
          ),
          // ── Content ─────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 28),
                  _buildFilters(state, ctrl),
                  const SizedBox(height: 28),
                  _buildGrid(context, state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a Cover Letter Template',
                style: TextStyle(
                  color: AppColors.prussianBlue,
                  fontSize: 26,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Start with a professionally designed layout or use AI to generate one',
                style: TextStyle(
                  color: AppColors.slateGrey,
                  fontSize: 14,
                  fontFamily: AppFonts.openSans,
                ),
              ),
            ],
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _showAiDesignDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkRaspberry,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.sparkles, size: 16, color: AppColors.white),
                  SizedBox(width: 8),
                  Text(
                    'AI Design',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAiDesignDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(LucideIcons.sparkles, size: 20, color: AppColors.darkRaspberry),
            SizedBox(width: 8),
            Text('AI Design',
                style: TextStyle(fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
          ],
        ),
        content: const Text(
          'AI Design will generate a complete cover letter tailored to your target role and company. This feature is coming soon!',
          style: TextStyle(fontFamily: AppFonts.openSans, color: AppColors.slateGrey),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─── FILTERS ──────────────────────────────────────────────────────────

  Widget _buildFilters(ClTemplateState state, ClTemplateController ctrl) {
    return Row(
      children: [
        // Search bar
        Expanded(
          flex: 2,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.petalFrost),
            ),
            child: TextField(
              onChanged: ctrl.setSearch,
              decoration: const InputDecoration(
                hintText: 'Search cover letter templates...',
                hintStyle: TextStyle(
                  color: AppColors.slateGrey,
                  fontSize: 13,
                  fontFamily: AppFonts.openSans,
                ),
                prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.slateGrey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const Spacer(),
        // Category chips
        ...ClTemplateController.categories.map((cat) {
          final isActive = state.activeFilter == cat;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => ctrl.setFilter(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.darkRaspberry : AppColors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isActive ? AppColors.darkRaspberry : AppColors.petalFrost,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      color: isActive ? AppColors.white : AppColors.prussianBlue,
                      fontSize: 12,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ─── GRID ─────────────────────────────────────────────────────────────

  Widget _buildGrid(BuildContext context, ClTemplateState state) {
    final list = state.filteredTemplates;

    if (state.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(64),
          child: CircularProgressIndicator(color: AppColors.darkRaspberry),
        ),
      );
    }

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(64),
          child: Column(
            children: [
              Icon(LucideIcons.searchX, size: 48, color: AppColors.almondSilk),
              const SizedBox(height: 16),
              const Text(
                'No templates match your search',
                style: TextStyle(
                  color: AppColors.slateGrey,
                  fontSize: 14,
                  fontFamily: AppFonts.openSans,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        int columns = 4;
        if (constraints.maxWidth < 500) columns = 1;
        if (constraints.maxWidth < 700) columns = 2;
        if (constraints.maxWidth < 1000) columns = 3;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: list.length,
          itemBuilder: (ctx, i) => ClTemplateCardWidget(
            template: list[i],
            onTap: () => _showPreview(context, list[i]),
          ),
        );
      },
    );
  }

  void _showPreview(BuildContext context, ClTemplateInfo info) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => ClTemplatePreviewModal(
        info: info,
        onUse: () {
          Navigator.pop(context);
          context.go('/cover-letters/edit/${info.id}');
        },
      ),
    );
  }
}