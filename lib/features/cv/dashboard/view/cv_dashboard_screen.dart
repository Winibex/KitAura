import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/widgets/app_sidebar.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/go_pro_banners.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../settings/view/upgrade_modal.dart';
import '../controller/cv_dashboard_controller.dart';
import 'cv_card_widget.dart';
import 'empty_state_widget.dart';

class CVDashboardScreen extends ConsumerStatefulWidget {
  const CVDashboardScreen({super.key});

  @override
  ConsumerState<CVDashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<CVDashboardScreen> {

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
    return Material(
      color: AppColors.warmGrey,
      child: ResponsiveBuilder(
        mobile: _buildMobileLayout(),
        desktop: _buildDesktopLayout(),
      ),
    );
  }

  // ─── DESKTOP LAYOUT ───────────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        AppTopBar(
          canBack: false,
          whereToGo: AppRoutes.cvDashboard,
        ),
        Expanded(
          child: Row(
            children: [
              const AppSidebar(),
              Expanded(child: _buildScrollableContent()),
            ],
          ),
        ),
      ],
    );
  }

  // ─── MOBILE LAYOUT ────────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Column(
      children: [
        AppTopBar(
          canBack: false,
          whereToGo: AppRoutes.cvDashboard,
        ),
        Expanded(child: _buildScrollableContent()),
      ],
    );
  }

  // ─── MAIN CONTENT ─────────────────────────────────────────────────────────

  Widget _buildScrollableContent() {
    final state = ref.watch(cvDashboardControllerProvider);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatCards(state),
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
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCards(CvDashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: statCard(
                      icon: LucideIcons.fileText,
                      label: 'Total CVs',
                      value: '${state.cvs.length}',
                      subtext: state.isPro ? 'Unlimited' : '${state.cvs.length} / ${state.maxCvs}',                      subtextColor: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: statCard(
                      icon: LucideIcons.download,
                      label: 'Exports Used',
                      value: state.isPro ? '∞' : '${state.exportCount} / ${state.exportsPerMonth}',
                      subtext: state.isPro ? 'Unlimited' : '${state.exportsPerMonth - state.exportCount} remaining',
                      showProgress: !state.isPro,
                      progressValue: state.isPro ? 0 : state.exportCount / state.exportsPerMonth,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: statCard(
                      icon: LucideIcons.sparkles,
                      label: 'AI Fills Used',
                      value: state.isPro ? '∞' : '${state.aiUsageCount} / ${state.aiFillsPerMonth}',
                      subtext: state.isPro
                          ? 'Unlimited'
                          : '${state.aiFillsPerMonth - state.aiUsageCount} remaining',
                    ),
                  ),
                  const SizedBox(width: 16),
                    Expanded(
                      child: GoProStatCard(
                        onStartTrial: () => showTrialDialog(context, ref),
                        onUpgrade: () => showDialog(
                          context: context,
                          builder: (_) => const UpgradeModal(),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: statCard(
                icon: LucideIcons.fileText,
                label: 'Total CVs',
                value: '${state.cvs.length}',
                subtext: state.isPro ? 'Unlimited' : '${state.cvs.length} / ${state.maxCvs}',
                subtextColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: statCard(
                icon: LucideIcons.download,
                label: 'Exports Used',
                value: state.isPro ? '∞' : '${state.exportCount} / ${state.exportsPerMonth}',
                subtext: state.isPro ? 'Unlimited' : '${state.exportsPerMonth - state.exportCount} remaining',
                showProgress: !state.isPro,
                progressValue: state.isPro ? 0 : state.exportCount / state.exportsPerMonth,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: statCard(
                icon: LucideIcons.sparkles,
                label: 'AI Fills Used',
                value: state.isPro ? '∞' : '${state.aiUsageCount} / ${state.aiFillsPerMonth}',
                subtext: state.isPro
                    ? 'Unlimited'
                    : '${state.aiFillsPerMonth - state.aiUsageCount} remaining',
              ),
            ),
            const SizedBox(width: 16),
              Expanded(
                child: GoProStatCard(
                  onStartTrial: () => showTrialDialog(context, ref),
                  onUpgrade: () => showDialog(
                    context: context,
                    builder: (_) => const UpgradeModal(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ─── CV SECTION ───────────────────────────────────────────────────────────

  Widget _buildCVSection(CvDashboardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My CVs',
              style: TextStyle(
                color: AppColors.prussianBlue,
                fontSize: 22,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              width: 140,
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.cvTemplates),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('New CV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // if (state.isLoading)
        //   _buildShimmerGrid()
        // else
          if (state.cvs.isEmpty)
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

  Widget _buildCVGrid(CvDashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
            childAspectRatio: 0.85,
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
            );
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