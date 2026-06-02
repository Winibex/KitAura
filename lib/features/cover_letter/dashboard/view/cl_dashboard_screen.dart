// lib/features/cover_letter/dashboard/view/cl_dashboard_screen.dart

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
    return Material(
      color: AppColors.lavenderBlush,
      child: ResponsiveBuilder(
        mobile: _buildMobileLayout(),
        desktop: _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        AppTopBar(
          whereToGo: AppRoutes.clDashboard,
          canBack: false,
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

  Widget _buildMobileLayout() {
    return Column(
      children: [
        AppTopBar(
          whereToGo: AppRoutes.clDashboard,
          canBack: false,
        ),
        Expanded(child: _buildScrollableContent()),
      ],
    );
  }

  Widget _buildScrollableContent() {
    final state = ref.watch(clDashboardControllerProvider);
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
                _buildCLSection(state),
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

  // ─── STAT CARDS ───────────────────────────────────────────────────────

  Widget _buildStatCards(ClDashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
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
            label: 'AI Fills Used',
            value: state.isPro ? '∞' : '${state.aiUsageCount} / ${state.aiFillsPerMonth}',
            subtext: state.isPro
                ? 'Unlimited'
                : '${state.aiFillsPerMonth - state.aiUsageCount} remaining',
          ),
          _buildGoProCard(),
        ];

        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              Row(children: [Expanded(child: cards[0]), const SizedBox(width: 16), Expanded(child: cards[1])]),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: cards[2]), const SizedBox(width: 16), Expanded(child: cards[3])]),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 16),
            Expanded(child: cards[1]),
            const SizedBox(width: 16),
            Expanded(child: cards[2]),
            const SizedBox(width: 16),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }

  Widget _buildGoProCard() {
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
              const Text('Go Pro',
                  style: TextStyle(color: AppColors.white, fontSize: 18,
                      fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text('Unlimited everything',
                  style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11, fontFamily: AppFonts.openSans)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => showDialog(context: context, builder: (_) => const UpgradeModal()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(999)),
                  child: const Text('Upgrade — \$7/mo',
                      style: TextStyle(color: AppColors.darkRaspberry, fontSize: 11,
                          fontFamily: AppFonts.poppins, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── COVER LETTER SECTION ─────────────────────────────────────────────

  Widget _buildCLSection(ClDashboardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('My Cover Letters',
                style: TextStyle(color: AppColors.prussianBlue, fontSize: 22,
                    fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.clTemplates),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('New Cover Letter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (state.isLoading)
          _buildShimmerGrid()
        else if (state.coverLetters.isEmpty)
          _buildEmptyState()
        else
          RepaintBoundary(child: _buildCLGrid(state)),
      ],
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85,
      ),
      itemCount: 4,
      itemBuilder: (_, _) => const CvCardShimmer(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildCLGrid(ClDashboardState state) {
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
            crossAxisCount: columns, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85,
          ),
          itemCount: state.coverLetters.length + 1,
          itemBuilder: (context, index) {
            if (index == state.coverLetters.length) return _buildNewCLCard();
            final cl = state.coverLetters[index];
            return ClCardWidget(
              cl: cl,
              onTap: () => context.push('/cover-letters/edit/${cl.id}'),
              onDelete: () => ref.read(clDashboardControllerProvider.notifier).deleteCL(cl.id),
              onRename: (t) => ref.read(clDashboardControllerProvider.notifier).renameCL(cl.id, t),
            );
          },
        );
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

  // ─── UPGRADE BANNER ───────────────────────────────────────────────────

  Widget _buildUpgradeBanner(ClDashboardState state) {
    if (state.isPro) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft, end: Alignment.centerRight,
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
                Text('Unlock unlimited cover letters',
                    style: TextStyle(color: AppColors.white, fontSize: 20,
                        fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Unlimited exports · AI Design · Priority generation',
                    style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 13, fontFamily: AppFonts.openSans)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () => showDialog(context: context, builder: (_) => const UpgradeModal()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: const Text('Upgrade to Pro — \$7/mo',
                  style: TextStyle(color: AppColors.darkRaspberry, fontSize: 14,
                      fontFamily: AppFonts.poppins, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}