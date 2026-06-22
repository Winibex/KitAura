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
import '../controller/cv_dashboard_controller.dart';
import '../model/cv_summary_model.dart';
import 'cv_card_widget.dart';
import 'empty_state_widget.dart';

class CVDashboardScreen extends ConsumerStatefulWidget {
  const CVDashboardScreen({super.key});

  @override
  ConsumerState<CVDashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<CVDashboardScreen> {

  static final List<CvSummaryModel> _skeletonCvs = List.generate(
    6,
        (i) => CvSummaryModel(
      id: 'skeleton_$i',
      title: 'Placeholder CV title',
      templateId: 'classic_navy',
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
        ref.read(cvDashboardControllerProvider.notifier).loadDashboard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      child: _buildScrollableContent(),
    );
  }

  // ─── MAIN CONTENT ─────────────────────────────────────────────────────────

  Widget _buildScrollableContent() {
    final state = ref.watch(cvDashboardControllerProvider);
    final dashboardState = ref.watch(dashboardControllerProvider);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSizes.pagePadding(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatCards(state, dashboardState.proPrice),
                const SizedBox(height: 24),
                _buildCVSection(state),
                const SizedBox(height: 24),
                  GoProToolBanner(
                    toolLabel: 'CVs',  // or 'cover letters' for CL dashboard
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
    );
  }

  Widget _buildStatCards(CvDashboardState state, final proPrice) {

    final statCards = [
      statCard(
        icon: LucideIcons.fileText,
        label: 'Total CVs',
        value: '${state.cvs.length}',
        subtext: state.isPro ? 'Unlimited' : '${state.cvs.length} / ${state.maxCvs}',
        subtextColor: AppColors.success,
      ),
      statCard(
        icon: LucideIcons.download,
        label: 'Exports Used',
        value: state.isPro ? '∞' : '${state.exportCount} / ${state.exportsPerMonth}',
        subtext: state.isPro ? 'Unlimited' : '${state.exportsPerMonth - state.exportCount} remaining',
        showProgress: !state.isPro,
        progressValue: state.isPro ? 0 : state.exportCount / state.exportsPerMonth,
      ),
      statCard(
        icon: LucideIcons.sparkles,
        label: 'AI Composes Used',
        value: state.isPro ? '∞' : '${state.aiUsageCount} / ${state.aiFillsPerMonth}',
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

    return Skeletonizer(
      enabled: state.isLoading,
      child: ResponsiveBuilder(
        mobile: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: AppSizes.md,
          mainAxisSpacing: AppSizes.md,
          childAspectRatio: AppSizes.statAspectRatio(context),
          children: statCards.toList(),
        ),
        tablet: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: AppSizes.md,
          mainAxisSpacing: AppSizes.md,
          childAspectRatio: AppSizes.statAspectRatio(context),
          children: statCards.toList(),
        ),
        desktop: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          crossAxisSpacing: AppSizes.md,
          mainAxisSpacing: AppSizes.md,
          childAspectRatio: AppSizes.statAspectRatio(context),
          children: statCards.toList(),
        ),
      )
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  // ─── CV SECTION ───────────────────────────────────────────────────────────

  Widget _buildCVSection(CvDashboardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My CVs',
              style: TextStyle(
                color: AppColors.prussianBlue,
                fontSize: AppSizes.headingMd(context),
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!state.isLoading)
            SizedBox(
              width: 140,
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.cvTemplates),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('New CV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle:TextStyle(fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600, fontSize: AppSizes.body(context),),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (state.isLoading)
          RepaintBoundary(child: _buildSkeletonGrid())
        else if (state.cvs.isEmpty)
          SizedBox(
            height: 300,
            child: EmptyStateWidget(
              onCreateCV: () => context.go(AppRoutes.cvTemplates),
            ),
          )
        else
          RepaintBoundary(child: _buildCVGrid(state)),
      ],
    );
  }

  Widget _buildSkeletonGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = AppSizes.docGridColumns(context, constraints.maxWidth);
        return Skeletonizer(
          enabled: true,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppSizes.sm,
              mainAxisSpacing: AppSizes.sm,
              childAspectRatio: 0.75,
            ),
            itemCount: _skeletonCvs.length,
            itemBuilder: (context, index) => CvCardWidget(
              cv: _skeletonCvs[index],
              onTap: () {},
              onDelete: () {},
              onRename: (_) {},
            ),
          ),
        );
      },
    );
  }

  Widget _buildCVGrid(CvDashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = AppSizes.docGridColumns(context, constraints.maxWidth);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSizes.sm,
            mainAxisSpacing: AppSizes.sm,
            childAspectRatio: 0.75,
          ),
          itemCount: state.cvs.length + 1,
          itemBuilder: (context, index) {
            if (index == state.cvs.length) {
              return _buildNewCVCard();
            }
            return CvCardWidget(
              cv: state.cvs[index],
              onTap: () => context.go('/cv/edit/${state.cvs[index].id}'),
              onDelete: () {
                ref.read(cvDashboardControllerProvider.notifier)
                    .deleteCV(state.cvs[index].id);
              },
              onRename: (newTitle) {
                ref.read(cvDashboardControllerProvider.notifier)
                    .renameCV(state.cvs[index].id, newTitle);
              },
            ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
          },
        );
      },
    );
  }

  Widget _buildNewCVCard() {
    return InkWell(
      onTap: () => context.go(AppRoutes.cvTemplates),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.almondSilk,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, color: AppColors.magentaBloom, size: 36),
            SizedBox(height: 8),
            Text(
              'New CV',
              style: TextStyle(
                color: AppColors.slateGrey,
                fontSize: 14,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

}