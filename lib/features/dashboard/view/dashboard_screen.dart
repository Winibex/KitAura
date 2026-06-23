// lib/features/dashboard/view/dashboard_screen.dart
//
// Platform overview — shows usage stats, quick-start cards for each tool,
// recent activity across all tools, and upgrade CTA.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import '../../../shared/widgets/go_pro_banners.dart';
import '../../settings/view/upgrade_modal.dart';
import '../controller/dashboard_controller.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {

  static final List<RecentItem> _skeletonRecentItems = List.generate(
    4,
        (i) => RecentItem(
      id: 'skeleton_$i',
      title: 'Placeholder document title',
      type: 'cv',
      templateId: 'classic_navy',
      updatedAt: DateTime.now().subtract(Duration(hours: i + 1)),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final state = ref.watch(dashboardControllerProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSizes.pagePadding(context)),
      child: Skeletonizer(
        enabled: state.isLoading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreeting(state),
            const SizedBox(height: 28),
            _buildStatCards(state),
            const SizedBox(height: 32),
            _buildQuickStart(state),
            const SizedBox(height: 32),
            ResponsiveBuilder(
              mobile: _buildRecentItemsMobile(state),
              desktop: _buildRecentActivity(state), // your existing table
            ),
            const SizedBox(height: 32),
            GoProDashboardBanner(
                plan: state.plan,
                trialActive: state.trialActive,
                trialDaysRemaining: state.trialDaysRemaining,
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
    );
  }

  // ─── GREETING ──────────────────────────────────────────────────────────

  Widget _buildGreeting(DashboardState state) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, ${state.displayName} 👋',
                style: TextStyle(
                  fontSize: AppSizes.headingLg(context),
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Here\'s your workspace overview',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  // ─── STAT CARDS ────────────────────────────────────────────────────────

  Widget _buildStatCards(DashboardState state) {
    final statCards = [
      _StatCardData(
        icon: LucideIcons.fileText,
        label: 'Documents',
        value: state.isPro
            ? '${state.totalDocuments} / ∞'
            : '${state.totalDocuments} / ${state.maxDocs}',
        subtitle: state.isPro
            ? 'Unlimited'
            : '${state.maxDocs - state.totalDocuments} remaining',
        color: AppColors.magentaBloom,
        progress: state.isPro ? null : state.totalDocuments / state.maxDocs,
        detailLineHeaders: const ['CV', 'CL', 'Proposal'],
        detailLineData: [
          '${state.cvCount}',
          '${state.coverLetterCount}',
          '${state.proposalCount}',
        ],
      ),
      _StatCardData(
        icon: LucideIcons.download,
        label: 'Exports',
        value: state.isPro ? '${state.exportCount} / ∞' : '${state.exportCount} / ${state.maxExports}',
        subtitle: state.isPro ? 'Unlimited' : '${state.maxExports - state.exportCount} remaining',
        color: AppColors.dustyRose,
        progress: state.isPro ? null : state.exportCount / state.maxExports,
      ),
      _StatCardData(
        icon: LucideIcons.sparkles,
        label: 'AI Use',
        value: state.isPro
            ? '${state.aiFillCount + state.aiRewriteCount} / ∞'
            : '${state.aiFillCount + state.aiRewriteCount} / ${state.maxAiFills}',
        subtitle: state.isPro
            ? 'Unlimited'
            : '${state.maxAiFills - (state.aiFillCount + state.aiRewriteCount)} remaining',
        color: AppColors.dustyMauve,
        progress: state.isPro
            ? null
            : (state.aiFillCount + state.aiRewriteCount) / state.maxAiFills,
        detailLineHeaders: state.isPro
            ? null
            : ['Compose', 'Refine'],
        detailLineData: state.isPro
            ? null
            : ['${state.aiFillCount}', '${state.aiRewriteCount}'],
      ),
      _StatCardData(
        icon: LucideIcons.logIn,
        label: 'Sessions',
        value: '${state.loginCount}',
        subtitle: 'Total logins',
        color: AppColors.slateGrey,
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
        children: statCards.map(_buildStatCard).toList(),
      ),
      tablet: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: AppSizes.md,
        mainAxisSpacing: AppSizes.md,
        childAspectRatio: AppSizes.statAspectRatio(context),
        children: statCards.map(_buildStatCard).toList(),
      ),
      desktop: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        crossAxisSpacing: AppSizes.md,
        mainAxisSpacing: AppSizes.md,
        childAspectRatio: AppSizes.statAspectRatio(context),
        children: statCards.map(_buildStatCard).toList(),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);

  }

  Widget _buildStatCard(_StatCardData data) {
    return Container(
      padding: EdgeInsets.all(AppSizes.cardPadding(context)),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Skeleton.ignore(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Icon(data.icon, color: data.color, size: 16),
                ),
              ),
              SizedBox(width: 10,),
              Flexible(
                child: Text(
                  data.label,
                  style: TextStyle(
                    fontSize: AppSizes.caption(context),
                    fontFamily: AppFonts.openSans,
                    color: AppColors.slateGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: TextStyle(
                fontSize: AppSizes.statValue(context),
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
                color: AppColors.prussianBlue,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (data.progress != null) ...[
            Skeleton.ignore(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: data.progress!.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: const Color(0xFFF0EBE6),
                  valueColor: AlwaysStoppedAnimation(
                    data.progress! >= 1.0 ? AppColors.error : data.color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            data.subtitle,
            style: TextStyle(
              fontSize: AppSizes.caption(context),
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (data.detailLineHeaders != null && data.detailLineHeaders!.isNotEmpty &&
              data.detailLineData != null && data.detailLineData!.isNotEmpty) ...[
            const Spacer(),
            Row(
              children: [
                for (int i = 0; i < data.detailLineHeaders!.length; i++) ...[
                  if (i > 0)
                    Text(
                      ' · ',
                      style: TextStyle(
                        fontSize: Responsive.isMobile(context) ? 8 : 10,
                        color: AppColors.slateGrey,
                      ),
                    ),
                  Text(
                    '${data.detailLineHeaders![i]}: ',
                    style: TextStyle(
                      fontSize: Responsive.isMobile(context) ? 8 : 10,
                      fontFamily: AppFonts.openSans,
                      color: AppColors.darkRaspberry,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    data.detailLineData![i],
                    style: TextStyle(
                      fontSize: Responsive.isMobile(context) ? 8 : 10,
                      fontFamily: AppFonts.openSans,
                      color: AppColors.prussianBlue,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  //  ─── QUICK START CARDS ─────────────────────────────────────────────────

  Widget _buildQuickStart(DashboardState state) {
    final quickStatCards = [
      _QuickStartData(
        icon: LucideIcons.filePlus,
        title: 'Create CV',
        subtitle: 'Professional resume builder',
        color: AppColors.darkRaspberry,
        onTap: () => context.go(AppRoutes.cvTemplates),
      ),
      _QuickStartData(
        icon: LucideIcons.fileText,
        title: 'Write Proposal',
        subtitle: 'Win more clients',
        color: AppColors.dustyMauve,
        onTap: () => context.go(AppRoutes.proposalTemplates),
        comingSoon: false,
      ),
      _QuickStartData(
        icon: LucideIcons.mail,
        title: 'Cover Letter',
        subtitle: 'Stand out from the crowd',
        color: AppColors.magentaBloom,
        onTap: () => context.go(AppRoutes.clTemplates),
        comingSoon: false,
      ),
      _QuickStartData(
        icon: LucideIcons.linkedin,
        title: 'LinkedIn Summary',
        subtitle: 'Optimize your profile',
        color: AppColors.dustyRose,
        onTap: () => context.go(AppRoutes.linkedin),
        comingSoon: false,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Start',
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w700,
            color: AppColors.prussianBlue,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Jump into a tool and start creating',
          style: TextStyle(
            fontSize: 13,
            fontFamily: AppFonts.openSans,
            color: AppColors.slateGrey,
          ),
        ),
        const SizedBox(height: 16),
        ResponsiveBuilder(
          mobile: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: AppSizes.md,
            mainAxisSpacing: AppSizes.md,
            childAspectRatio: AppSizes.statAspectRatio(context),
            children: quickStatCards.map(_buildQuickStartCard).toList(),
          ),
          tablet: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: AppSizes.md,
            mainAxisSpacing: AppSizes.md,
            childAspectRatio: AppSizes.statAspectRatio(context),
            children: quickStatCards.map(_buildQuickStartCard).toList(),
          ),
          desktop: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: AppSizes.md,
            mainAxisSpacing: AppSizes.md,
            childAspectRatio: AppSizes.statAspectRatio(context),
            children: quickStatCards.map(_buildQuickStartCard).toList(),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  Widget _buildQuickStartCard(_QuickStartData data) {
    return MouseRegion(
      cursor: data.comingSoon ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: data.onTap,
        child: Container(
          padding: EdgeInsets.all(AppSizes.cardPadding(context)),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(color: const Color(0xFFEDE8E3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Skeleton.ignore(
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.petalFrost,
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      ),
                      child: Icon(data.icon, size: 16, color: AppColors.darkRaspberry),
                    ),
                  ),
                  const Spacer(),
                  if (data.comingSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.petalFrost,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Soon', style: TextStyle(
                          fontSize: Responsive.isMobile(context) ? 8 : 10,
                          color: AppColors.slateGrey)),
                    )
                  else
                    Icon(LucideIcons.arrowRight, size: 14, color: AppColors.slateGrey),
                ],
              ),
              const Spacer(),
              Text(data.title, style: TextStyle(
                  fontSize: AppSizes.body(context), fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600, color: AppColors.prussianBlue),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(data.subtitle, style: TextStyle(
                  fontSize: AppSizes.caption(context), fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }

  // ─── RECENT ACTIVITY ───────────────────────────────────────────────────

  Widget _buildEmptyState(){
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.fileText,
                color: AppColors.darkRaspberry, size: 24),
          ),
          const SizedBox(height: 16),
          const Text(
            'No documents yet',
            style: TextStyle(
              fontSize: 16,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Create your first CV to get started',
            style: TextStyle(fontSize: 13, color: AppColors.slateGrey),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 150,
            child: ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.cvTemplates),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Create CV'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentItemsMobile(DashboardState state) {
    final items = state.isLoading ? _skeletonRecentItems : state.recentItems;
    if (items.isEmpty) return _buildEmptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent Activity', style: TextStyle(
                fontSize: AppSizes.headingMd(context), fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
            const Spacer(),
            Text('View all →', style: TextStyle(
                fontSize: AppSizes.caption(context), fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w500, color: AppColors.darkRaspberry)),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(color: const Color(0xFFEDE8E3)),
          ),
          child: InkWell(
            onTap: () {
              if (item.type == 'cv') {
                context.go('/cv/edit/${item.id}');
              } else if (item.type == 'coverLetter') {
                context.go('/cover-letters/edit/${item.id}');
              } else if (item.type == 'proposal') {
                context.go('/proposals/edit/${item.id}');
              }
            },
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_iconForType(item.type),
                      size: 16, color: AppColors.darkRaspberry),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: TextStyle(fontSize: AppSizes.body(context),
                              fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600,
                              color: AppColors.prussianBlue),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${item.typeLabel} · ${item.timeAgo}',
                          style: TextStyle(fontSize: AppSizes.caption(context),
                              fontFamily: AppFonts.openSans, color: AppColors.slateGrey)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.petalFrost,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(item.templateId,
                            style: TextStyle(
                              fontSize: AppSizes.caption(context),
                              color: AppColors.darkRaspberry,
                              fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.w500,
                            ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.slateGrey),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildRecentActivity(DashboardState state) {
    final items = state.isLoading ? _skeletonRecentItems : state.recentItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 18,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w700,
                color: AppColors.prussianBlue,
              ),
            ),
            const Spacer(),
            if (!state.isLoading && state.recentItems.isNotEmpty)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go(AppRoutes.cvDashboard),
                  child: const Text(
                    'View all →',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkRaspberry,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          _buildEmptyState()
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDE8E3)),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFBF8F6),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: ResponsiveBuilder(
                    mobile: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text('Document', style: _tableHeaderStyle(context))),
                          Expanded(flex: 2, child: Text('Type', style: _tableHeaderStyle(context))),
                          Expanded(flex: 2, child: Text('Edited', style: _tableHeaderStyle(context))),
                          const SizedBox(width: 24), // arrow space
                        ],
                      ),
                    ),
                    desktop: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text('Document', style: _tableHeaderStyle(context))),
                          Expanded(flex: 2, child: Text('Type', style: _tableHeaderStyle(context))),
                          Expanded(flex: 2, child: Text('Template', style: _tableHeaderStyle(context))),
                          Expanded(flex: 2, child: Text('Last edited', style: _tableHeaderStyle(context))),
                          const SizedBox(width: 32),
                        ],
                      ),
                    ),
                  )
                ),
                // Rows
                ...items.map((item) => _buildRecentRow(item)),
              ],
            ),
          ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 300.ms);
  }

  TextStyle _tableHeaderStyle(BuildContext context) => TextStyle(
    fontSize: AppSizes.caption(context),
    fontFamily: AppFonts.poppins,
    fontWeight: FontWeight.w500,
    color: AppColors.slateGrey,
  );

  IconData _iconForType(String type) {
    switch (type) {
      case 'coverLetter': return LucideIcons.mail;
      case 'proposal':    return LucideIcons.fileText;
      case 'linkedin':    return LucideIcons.linkedin;
      default:            return LucideIcons.fileText; // cv
    }
  }

  Widget _buildRecentRow(RecentItem item) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () {
          switch (item.type) {
            case 'cv':
              context.go('/cv/edit/${item.id}');
              break;
            case 'coverLetter':
              context.go('/cover-letters/edit/${item.id}');
              break;
            case 'proposal':
              context.go('/proposals/edit/${item.id}');
              break;
            default:
              context.go('/cv/edit/${item.id}');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0EBE6))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Skeleton.ignore(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.petalFrost,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_iconForType(item.type),
                            size: 14, color: AppColors.darkRaspberry),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w500,
                          color: AppColors.prussianBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Skeleton.leaf(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.petalFrost,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        item.typeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w500,
                          color: AppColors.darkRaspberry,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.templateId,
                  style: const TextStyle(fontSize: 12, color: AppColors.slateGrey),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.timeAgo,
                  style: const TextStyle(fontSize: 12, color: AppColors.slateGrey),
                ),
              ),
              SizedBox(
                width: 40,
                child: Icon(LucideIcons.arrowRight,
                    size: 14, color: AppColors.slateGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── DATA CLASSES ────────────────────────────────────────────────────────

class _StatCardData {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final double? progress;
  final List<String>? detailLineHeaders;
  final List<String>? detailLineData;

  const _StatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.progress,
    this.detailLineHeaders,
    this.detailLineData
  });
}

class _QuickStartData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool comingSoon;

  _QuickStartData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.comingSoon = false,
  });
}