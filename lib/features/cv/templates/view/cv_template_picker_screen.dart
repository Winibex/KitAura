import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kitaura/core/constants/app_routes.dart';
import 'package:kitaura/shared/widgets/app_top_bar.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/responsive.dart';
import '../controller/cv_template_controller.dart';
import '../../../../shared/models/template_model.dart';
import 'cv_template_card_widget.dart';
import 'cv_template_preview_modal.dart';

class CVTemplatePickerScreen extends ConsumerStatefulWidget {
  const CVTemplatePickerScreen({super.key});

  @override
  ConsumerState<CVTemplatePickerScreen> createState() =>
      _CVTemplatePickerScreenState();
}

class _CVTemplatePickerScreenState extends ConsumerState<CVTemplatePickerScreen> {

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templateControllerProvider);

    return Material(
      color: AppColors.lavenderBlush,
      child: Column(
        children: [
          AppTopBar(
            canBack: true,
            whereToGo: AppRoutes.cvDashboard,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSizes.pagePadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildSearchAndFilter(state),
                  const SizedBox(height: 24),
                  _buildGrid(state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Template',
          style: TextStyle(
            color: AppColors.prussianBlue,
            fontSize: AppSizes.headingLg(context),
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Start with a professionally designed layout or begin from scratch',
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: 14,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter(CVTemplateState state) {
    final isMobile = Responsive.isMobile(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar — full width on mobile
        SizedBox(
          width: isMobile ? double.infinity : 280,
          height: 42,
          child: TextField(
            onChanged: (v) =>
                ref.read(templateControllerProvider.notifier).setSearch(v),
            decoration: InputDecoration(
              hintText: 'Search cv templates...',
              prefixIcon: const Icon(LucideIcons.search,
                  size: 16, color: AppColors.slateGrey),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              filled: true,
              fillColor: AppColors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Filter chips — wrap on mobile
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: CVTemplateController.categories.map((cat) {
              final isActive = state.activeFilter == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => ref
                      .read(templateControllerProvider.notifier)
                      .setFilter(cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.darkRaspberry
                          : AppColors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: isActive
                          ? null
                          : Border.all(color: AppColors.almondSilk),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isActive
                            ? AppColors.white
                            : AppColors.prussianBlue,
                        fontSize: 13,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(CVTemplateState state) {
    final templates = state.filteredTemplates;

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns;
        if (constraints.maxWidth < 700) {
          columns = 2;
        } else if (constraints.maxWidth < 1000) {
          columns = 3;
        } else {
          columns = 4;
        }

        if (templates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(
              child: Text(
                'No CV templates match your search',
                style: TextStyle(color: AppColors.slateGrey, fontSize: 14),
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final template = templates[index];
            return CVTemplateCardWidget(
              template: template,
              onTap: () => _showPreviewModal(template),
            );
          },
        );
      },
    );
  }

  // ─── TEMPLATE FLOW ────────────────────────────────────────────────────

  void _showPreviewModal(TemplateModel template) {
    showDialog(
      context: context,
      builder: (_) => CVTemplatePreviewModal(
        template: template,
        onUseTemplate: () {
          // The modal closes itself internally. We just navigate.
          // Defer to next frame so the modal's pop completes first.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/cv/edit/${template.id}');
          });
        },
        onStartBlank: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/cv/edit/blank');
          });
        },
      ),
    );
  }
}
