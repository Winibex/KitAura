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
import '../../../../shared/widgets/shimmer_card.dart';
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
        ref.read(dashboardControllerProvider.notifier).loadDashboard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.lavenderBlush,
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
    final state = ref.watch(dashboardControllerProvider);
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
                _buildUpgradeBanner(state),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCards(DashboardState state) {
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
                  Expanded(child: _buildGoproCard()),
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
            Expanded(child: _buildGoproCard()),
          ],
        );
      },
    );
  }

  Widget _buildGoproCard() {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(LucideIcons.crown, color: AppColors.white, size: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Go Pro',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Unlimited everything',
                style: TextStyle(
                  color: Color(0xAAFFFFFF),
                  fontSize: 11,
                  fontFamily: AppFonts.openSans,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => const UpgradeModal(),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Upgrade — \$7/mo',
                    style: TextStyle(
                      color: AppColors.darkRaspberry,
                      fontSize: 11,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── CV SECTION ───────────────────────────────────────────────────────────

  Widget _buildCVSection(DashboardState state) {
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
        if (state.isLoading)
          _buildShimmerGrid()
        else if (state.cvs.isEmpty)
          SizedBox(
            height: 300,
            child: EmptyStateWidget(
              onCreateCV: () => context.push(AppRoutes.cvTemplates),
            ),
          )
        else
          RepaintBoundary(child: _buildCVGrid(state)),
      ],
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: 4,
      itemBuilder: (_, _) => const CvCardShimmer(),
    );
  }

  Widget _buildCVGrid(DashboardState state) {
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
              onTap: () => context.push('/cv/edit/${state.cvs[index].id}'),
              onDelete: () {
                ref.read(dashboardControllerProvider.notifier)
                    .deleteCV(state.cvs[index].id);
              },
              onRename: (newTitle) {
                ref.read(dashboardControllerProvider.notifier)
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

  // ─── UPGRADE BANNER ───────────────────────────────────────────────────────

  Widget _buildUpgradeBanner(DashboardState state) {
    if (state.isPro) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.crown, color: AppColors.white, size: 22),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlock unlimited CVs',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Remove watermarks · Unlimited exports · Priority AI generation',
                  style: TextStyle(
                    color: Color(0xAAFFFFFF),
                    fontSize: 13,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () => showDialog(
              context: context,
              builder: (_) => const UpgradeModal(),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'Upgrade to Pro — \$7/mo',
                style: TextStyle(
                  color: AppColors.darkRaspberry,
                  fontSize: 14,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}