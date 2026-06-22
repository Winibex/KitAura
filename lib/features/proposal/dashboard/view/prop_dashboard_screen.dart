// lib/features/proposal/dashboard/view/prop_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/widgets/responsive_scaffold.dart';
import '../../../../shared/widgets/go_pro_banners.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../dashboard/controller/dashboard_controller.dart';
import '../../../settings/view/upgrade_modal.dart';
import '../controller/prop_dashboard_controller.dart';
import '../model/prop_summary_model.dart';
import 'prop_card_widget.dart';

class PropDashboardScreen extends ConsumerStatefulWidget {
  const PropDashboardScreen({super.key});

  @override
  ConsumerState<PropDashboardScreen> createState() =>
      _PropDashboardScreenState();
}

class _PropDashboardScreenState extends ConsumerState<PropDashboardScreen> {

  static final List<PropSummaryModel> _skeletonProps = List.generate(
    6,
        (i) => PropSummaryModel(
      id: 'skeleton_$i',
      title: 'Placeholder proposal title',
      templateId: 'custom',
      clientName: 'Client Name',
      projectScope: 'Project Scope',
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      canvasBackground: '#FFFFFF',
      items: const [],
    ),
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(propDashboardControllerProvider.notifier).loadDashboard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      child: _buildScrollableContent(),
    );
  }

  Widget _buildScrollableContent() {
    final state = ref.watch(propDashboardControllerProvider);
    final dashboardState = ref.watch(dashboardControllerProvider);

    return Skeletonizer(
      enabled: state.isLoading,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSizes.pagePadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatCards(state, dashboardState.proPrice),
                  const SizedBox(height: 24),
                  _buildProposalSection(state),
                  const SizedBox(height: 24),
                  GoProToolBanner(
                    toolLabel: 'proposals',
                    onStartTrial: () => showTrialDialog(context, ref),
                    onUpgrade: () => showDialog(
                      context: context,
                      builder: (_) => const UpgradeModal(),
                    ),
                    proPrice: dashboardState.proPrice,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STAT CARDS ───────────────────────────────────────────────────────

  Widget _buildStatCards(PropDashboardState state, final proPrice) {
    final statCards = [
      statCard(
        icon: LucideIcons.fileText,
        label: 'Proposals',
        value: '${state.proposals.length}',
        subtext: state.isPro
            ? 'Unlimited'
            : '${state.proposals.length} / ${state.maxProposals}',
        subtextColor: AppColors.success,
      ),
      statCard(
        icon: LucideIcons.download,
        label: 'Exports Used',
        value: state.isPro
            ? '∞'
            : '${state.exportCount} / ${state.exportsPerMonth}',
        subtext: state.isPro
            ? 'Unlimited'
            : '${state.exportsPerMonth - state.exportCount} remaining',
        showProgress: !state.isPro,
        progressValue:
        state.isPro ? 0 : state.exportCount / state.exportsPerMonth,
      ),
      statCard(
        icon: LucideIcons.sparkles,
        label: 'AI Composes Used',
        value: state.isPro
            ? '∞'
            : '${state.aiUsageCount} / ${state.aiFillsPerMonth}',
        subtext: state.isPro
            ? 'Unlimited'
            : '${state.aiFillsPerMonth - state.aiUsageCount} remaining',
      ),
      GoProStatCard(
        onStartTrial: () => showTrialDialog(context, ref),
        onUpgrade: () => showDialog(
          context: context,
          builder: (_) => const UpgradeModal(),
        ),
        proPrice: proPrice,
      ),
    ];

    return ResponsiveBuilder(
      mobile: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: AppSizes.md,
        mainAxisSpacing: AppSizes.md,
        childAspectRatio: AppSizes.statAspectRatio(context),
        children: statCards,
      ),
      tablet: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: AppSizes.md,
        mainAxisSpacing: AppSizes.md,
        childAspectRatio: AppSizes.statAspectRatio(context),
        children: statCards,
      ),
      desktop: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        crossAxisSpacing: AppSizes.md,
        mainAxisSpacing: AppSizes.md,
        childAspectRatio: AppSizes.statAspectRatio(context),
        children: statCards,
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  // ─── PROPOSAL SECTION ─────────────────────────────────────────────────

  Widget _buildProposalSection(PropDashboardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Proposals',
              style: TextStyle(
                color: AppColors.prussianBlue,
                fontSize: AppSizes.headingMd(context),
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!state.isLoading)
              SizedBox(
                width: AppSizes.proposalPrimaryButtonWidth(context),
                child: ElevatedButton.icon(
                  onPressed: () => context.go(AppRoutes.proposalTemplates),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('New Proposal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkRaspberry,
                    foregroundColor: AppColors.white,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: TextStyle(
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      fontSize: AppSizes.body(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (state.isLoading)
          RepaintBoundary(child: _buildSkeletonGrid())
        else if (state.proposals.isEmpty)
          _buildEmptyState()
        else
          RepaintBoundary(child: _buildProposalGrid(state)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: AppColors.petalFrost, shape: BoxShape.circle),
              child: const Icon(LucideIcons.fileText,
                  color: AppColors.darkRaspberry, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('No proposals yet',
                style: TextStyle(
                    color: AppColors.prussianBlue,
                    fontSize: 18,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Create your first proposal to get started',
                style: TextStyle(
                    color: AppColors.slateGrey,
                    fontSize: 13,
                    fontFamily: AppFonts.openSans)),
            const SizedBox(height: 15),
            SizedBox(
              width: AppSizes.proposalSecondaryButtonWidth(context),
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.proposalTemplates),
                icon: const Icon(LucideIcons.plus, size: 13),
                label: const Text('New Proposal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: TextStyle(
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.caption(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
        AppSizes.docGridColumns(context, constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSizes.sm,
            mainAxisSpacing: AppSizes.sm,
            childAspectRatio: 0.75,
          ),
          itemCount: _skeletonProps.length,
          itemBuilder: (context, index) => PropCardWidget(
            prop: _skeletonProps[index],
            onTap: () {},
            onDelete: () {},
            onRename: (_) {},
          ),
        );
      },
    );
  }

  Widget _buildProposalGrid(PropDashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
        AppSizes.docGridColumns(context, constraints.maxWidth);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSizes.sm,
            mainAxisSpacing: AppSizes.sm,
            childAspectRatio: 0.75,
          ),
          itemCount: state.proposals.length + 1,
          itemBuilder: (context, index) {
            if (index == state.proposals.length) return _buildNewPropCard();
            final prop = state.proposals[index];
            return PropCardWidget(
              prop: prop,
              onTap: () => context.go('/proposals/edit/${prop.id}'),
              onDelete: () => ref
                  .read(propDashboardControllerProvider.notifier)
                  .deleteProposal(prop.id),
              onRename: (t) => ref
                  .read(propDashboardControllerProvider.notifier)
                  .renameProposal(prop.id, t),
            );
          },
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
      },
    );
  }

  Widget _buildNewPropCard() {
    return GestureDetector(
      onTap: () => context.go(AppRoutes.proposalTemplates),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.almondSilk, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.plus, color: AppColors.magentaBloom, size: 36),
              SizedBox(height: 8),
              Text('New Proposal',
                  style: TextStyle(
                      color: AppColors.slateGrey,
                      fontSize: 14,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}