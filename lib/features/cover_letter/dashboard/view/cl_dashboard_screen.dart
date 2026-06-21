// lib/features/cover_letter/dashboard/view/cl_dashboard_screen.dart

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
import '../controller/cl_dashboard_controller.dart';
import 'cl_card_widget.dart';

class ClDashboardScreen extends ConsumerStatefulWidget {
  const ClDashboardScreen({super.key});

  @override
  ConsumerState<ClDashboardScreen> createState() => _ClDashboardScreenState();
}

class _ClDashboardScreenState extends ConsumerState<ClDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(clDashboardControllerProvider.notifier).loadDashboard();
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
    final state = ref.watch(clDashboardControllerProvider);
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
                  _buildCLSection(state),
                  const SizedBox(height: 24),
                    GoProToolBanner(
                      toolLabel: 'cover letters',  // or 'cover letters' for CL dashboard
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

  Widget _buildStatCards(ClDashboardState state, final proPrice) {
    final statCards = [
      statCard(
        icon: LucideIcons.mail,
        label: 'Cover Letters',
        value: '${state.coverLetters.length}',
        subtext: state.isPro
            ? 'Unlimited'
            : '${state.coverLetters.length} / ${state.maxCoverLetters}',
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

    return ResponsiveBuilder(
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
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  // ─── COVER LETTER SECTION ─────────────────────────────────────────────

  Widget _buildCLSection(ClDashboardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('My Cover Letters',
              style: TextStyle(
                color: AppColors.prussianBlue,
                fontSize: AppSizes.headingMd(context),
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
              ),),
            SizedBox(
              width: AppSizes.coverLetterPrimaryButtonWidth(context),
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.clTemplates),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('New Cover Letter'),
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
          if (state.coverLetters.isEmpty)
          _buildEmptyState()
        else
          RepaintBoundary(child: _buildCLGrid(state)),
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
              width: 64, height: 64,
              decoration: const BoxDecoration(color: AppColors.petalFrost, shape: BoxShape.circle),
              child: const Icon(LucideIcons.mail, color: AppColors.darkRaspberry, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('No cover letters yet',
                style: TextStyle(color: AppColors.prussianBlue, fontSize: 18,
                    fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Create your first cover letter to get started',
                style: TextStyle(color: AppColors.slateGrey, fontSize: 13, fontFamily: AppFonts.openSans)),
            const SizedBox(height: 15),
            SizedBox(
              width: AppSizes.coverLetterSecondaryButtonWidth(context),
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.clTemplates),
                icon: const Icon(LucideIcons.plus, size: 13),
                label: const Text('New Cover Letter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle:TextStyle(fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600, fontSize: AppSizes.caption(context),),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCLGrid(ClDashboardState state) {
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
          itemCount: state.coverLetters.length + 1,
          itemBuilder: (context, index) {
            if (index == state.coverLetters.length) return _buildNewCLCard();
            final cl = state.coverLetters[index];
            return ClCardWidget(
              cl: cl,
              onTap: () => context.go('/cover-letters/edit/${cl.id}'),
              onDelete: () => ref.read(clDashboardControllerProvider.notifier).deleteCL(cl.id),
              onRename: (t) => ref.read(clDashboardControllerProvider.notifier).renameCL(cl.id, t),
            );
          },
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
      },
    );
  }

  Widget _buildNewCLCard() {
    return GestureDetector(
      onTap: () => context.go(AppRoutes.clTemplates),
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
              Text('New Cover Letter',
                  style: TextStyle(color: AppColors.slateGrey, fontSize: 14,
                      fontFamily: AppFonts.poppins, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}