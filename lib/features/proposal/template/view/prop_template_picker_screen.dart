// lib/features/proposal/template/view/prop_template_picker_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../controller/prop_template_controller.dart';
import '../data/prop_template_data.dart';
import 'prop_template_card_widget.dart';
import 'prop_template_preview_modal.dart';
import '../../../../shared/providers/feature_flags_provider.dart';
import '../../../auth/controller/auth_controller.dart';

class PropTemplatePickerScreen extends ConsumerWidget {
  final String? deepLinkTemplateId;
  const PropTemplatePickerScreen({super.key, this.deepLinkTemplateId});

  static final _handledDeepLinks = <String>{};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(propTemplateControllerProvider);
    final ctrl = ref.read(propTemplateControllerProvider.notifier);

    // Deep-link auto-open (one-shot)
    if (deepLinkTemplateId != null &&
        !_handledDeepLinks.contains(deepLinkTemplateId)) {
      _handledDeepLinks.add(deepLinkTemplateId!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final templates =
            ref.read(propTemplateControllerProvider).filteredTemplates;
        final match =
            templates.where((t) => t.id == deepLinkTemplateId).firstOrNull;
        if (match != null) {
          _showPreview(context, ref, match);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Template not found'),
              backgroundColor: AppColors.darkRaspberry,
            ),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.lavenderBlush,
      body: Column(
        children: [
          AppTopBar(
            canBack: true,
            whereToGo: AppRoutes.proposalDashboard,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSizes.pagePadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 28),
                  _buildFilters(state, ctrl, context),
                  const SizedBox(height: 28),
                  _buildGrid(context, state, ref),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Proposal Template',
          style: TextStyle(
            color: AppColors.prussianBlue,
            fontSize: AppSizes.headingLg(context),
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Start with a professionally designed layout or use AI to generate one',
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: 14,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ],
    );
  }

  // ─── FILTERS ──────────────────────────────────────────────────────────

  Widget _buildFilters(
      PropTemplateState state, PropTemplateController ctrl, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: Responsive.isMobile(context) ? double.infinity : 280,
          height: 42,
          child: TextField(
            onChanged: ctrl.setSearch,
            decoration: InputDecoration(
              hintText: 'Search proposal templates...',
              hintStyle:
              const TextStyle(color: AppColors.slateGrey, fontSize: 13),
              prefixIcon: const Icon(LucideIcons.search,
                  size: 16, color: AppColors.slateGrey),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                  const BorderSide(color: AppColors.almondSilk)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                  const BorderSide(color: AppColors.almondSilk)),
              filled: true,
              fillColor: AppColors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: PropTemplateController.categories.map((cat) {
              final isActive = state.activeFilter == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => ctrl.setFilter(cat),
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
                    child: Text(cat,
                        style: TextStyle(
                            color: isActive
                                ? AppColors.white
                                : AppColors.prussianBlue,
                            fontSize: 13,
                            fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── GRID ─────────────────────────────────────────────────────────────

  Widget _buildGrid(BuildContext context, PropTemplateState state, WidgetRef ref) {
    final list = state.filteredTemplates;

    if (state.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(64),
          child:
          CircularProgressIndicator(color: AppColors.darkRaspberry),
        ),
      );
    }

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(64),
          child: Column(
            children: [
              const Icon(LucideIcons.searchX,
                  size: 48, color: AppColors.almondSilk),
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
        int columns;
        if (constraints.maxWidth < 700) {
          columns = 2;
        } else if (constraints.maxWidth < 1000) {
          columns = 3;
        } else {
          columns = 4;
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
          itemCount: list.length,
          itemBuilder: (ctx, i) => PropTemplateCardWidget(
            template: list[i],
            onTap: () => _showPreview(context, ref, list[i]),
          ),
        );
      },
    );
  }

  void _showPreview(BuildContext context, WidgetRef ref, PropTemplateInfo info) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => PropTemplatePreviewModal(
        info: info,
        onUse: () async {
          final guestEnabled = ref.read(guestModeEnabledProvider);
          final uid = await ref.read(authControllerProvider.notifier)
              .ensureAuthForAction(guestModeEnabled: guestEnabled);
          if (uid == null) {
            if (context.mounted) context.go('/');
            return;
          }
          if (context.mounted) context.go('/proposals/edit/${info.id}');
        },
      ),
    );
  }
}