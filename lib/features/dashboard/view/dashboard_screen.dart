// lib/features/dashboard/view/dashboard_screen.dart
//
// Platform overview — shows usage stats, quick-start cards for each tool,
// recent activity across all tools, and upgrade CTA.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../../shared/widgets/template_thumbnail.dart';
import '../../cv/templates/data/cv_template_data.dart';
import '../../settings/view/upgrade_modal.dart';
import '../controller/dashboard_controller.dart';
import '../../../shared/widgets/announcement_banner.dart';

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

    // Compact empty state — for guests and signed-in users with no docs.
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user?.isAnonymous ?? (user == null);
    final hasNoDocs = state.totalDocuments == 0;

    // Guests: render immediately, no need to wait for the controller
    // (unauthed guests have no user doc to load anyway).
    if (isGuest) {
      return _buildEmptyStateContent(state, isGuest: true);
    }
    // Signed-in users with no docs: wait for the controller to finish
    // to avoid flashing the empty state before real data arrives.
    if (!state.isLoading && hasNoDocs) {
      return _buildEmptyStateContent(state, isGuest: false);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSizes.pagePadding(context)),
      child: Skeletonizer(
        enabled: state.isLoading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AnnouncementBanner(),
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

  // ═══════════════════════════════════════════════════════════════════
  //  COMPACT EMPTY STATE (guests + first-time signed-in users)
  // ═══════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════
  //  COMPACT EMPTY STATE (guests + first-time signed-in users)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildEmptyStateContent(DashboardState state, {required bool isGuest}) {
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.pagePadding(context),
        vertical: isMobile ? 16 : 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEmptyHeader(isGuest, state),
          const SizedBox(height: 20),
          _buildPrimaryStartCard(),
          const SizedBox(height: 24),
          _buildToolRow(),
          const SizedBox(height: 28),
          _buildTemplateCarousel(),
          if (isGuest) ...[
            const SizedBox(height: 24),
            _buildGuestSaveStrip(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────

  Widget _buildEmptyHeader(bool isGuest, DashboardState state) {
    final name = state.displayName;
    final showName = !isGuest && name.isNotEmpty && name != 'Guest';
    final title = showName ? 'Welcome, $name' : 'Welcome to KitAura';
    final subtitle = isGuest
        ? "Try any tool below \u2014 no signup required to get started."
        : "Let's create your first document.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.prussianBlue,
            fontSize: AppSizes.headingLg(context),
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: Responsive.isMobile(context) ? 13 : 14,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  // ─── Primary "Start with a CV" card ─────────────────────────────

  Widget _buildPrimaryStartCard() {
    final isMobile = Responsive.isMobile(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(AppRoutes.cvTemplates),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.prussianBlue,
                Color(0xFF1E2745),
                Color(0xFF3D1A2E),
              ],
              stops: [0.0, 0.6, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.prussianBlue.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Decorative shapes on the right (desktop only)
                if (!isMobile) ...[
                  Positioned(
                    top: -30,
                    right: -30,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.darkRaspberry.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -50,
                    right: 80,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.magentaBloom.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    right: 180,
                    child: Transform.rotate(
                      angle: 0.4,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.petalFrost.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: EdgeInsets.all(isMobile ? 20 : 28),
                  child: isMobile
                      ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _startCardIcon(),
                      const SizedBox(height: 14),
                      _startCardText(),
                      const SizedBox(height: 14),
                      _startCardChips(),
                      const SizedBox(height: 16),
                      _startCardCta(),
                    ],
                  )
                      : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _startCardIcon(),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _startCardText(),
                            const SizedBox(height: 12),
                            _startCardChips(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      _startCardCta(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _startCardIcon() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.darkRaspberry.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: const Icon(LucideIcons.sparkles, size: 24, color: AppColors.white),
    );
  }

  Widget _startCardText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Start with a CV',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick a template and let AI fill in the details.',
          style: TextStyle(
            color: AppColors.white.withValues(alpha: 0.75),
            fontSize: 12.5,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ],
    );
  }

  Widget _startCardChips() {
    final chips = [
      ('11 templates', LucideIcons.layout),
      ('AI-powered', LucideIcons.zap),
      ('PDF export', LucideIcons.download),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips
          .map(
            (c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(c.$2, size: 11, color: AppColors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 5),
              Text(
                c.$1,
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontSize: 10.5,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      )
          .toList(),
    );
  }

  Widget _startCardCta() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.white.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose template',
            style: TextStyle(
              color: AppColors.darkRaspberry,
              fontSize: 12,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(LucideIcons.arrowRight, size: 13, color: AppColors.darkRaspberry),
        ],
      ),
    );
  }

  // ─── Tool row (CL, Proposal, LinkedIn) ──────────────────────────

  Widget _buildToolRow() {
    final tools = [
      _EmptyToolData(
        icon: LucideIcons.mail,
        title: 'Cover Letter',
        subtitle: 'Personalized for every job',
        color: AppColors.magentaBloom,
        onTap: () => context.go(AppRoutes.clTemplates),
      ),
      _EmptyToolData(
        icon: LucideIcons.briefcase,
        title: 'Proposal',
        subtitle: 'Win more clients',
        color: AppColors.dustyMauve,
        onTap: () => context.go(AppRoutes.proposalTemplates),
      ),
      _EmptyToolData(
        icon: LucideIcons.linkedin,
        title: 'LinkedIn Content',
        subtitle: 'Optimize your profile',
        color: AppColors.dustyRose,
        onTap: () => context.go(AppRoutes.linkedin),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OR START WITH',
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: 10,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        ResponsiveBuilder(
          mobile: Column(
            children: tools
                .map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildToolTile(t),
            ))
                .toList(),
          ),
          desktop: Row(
            children: tools
                .map((t) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: t == tools.last ? 0 : 12,
                ),
                child: _buildToolTile(t),
              ),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildToolTile(_EmptyToolData data) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.petalFrost, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.prussianBlue.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, size: 19, color: data.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        color: AppColors.prussianBlue,
                        fontSize: 13,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      style: const TextStyle(
                        color: AppColors.slateGrey,
                        fontSize: 11,
                        fontFamily: AppFonts.openSans,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(LucideIcons.arrowRight, size: 15, color: data.color),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Template carousel ──────────────────────────────────────────

  Widget _buildTemplateCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'POPULAR TEMPLATES',
              style: TextStyle(
                color: AppColors.slateGrey,
                fontSize: 10,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => context.go(AppRoutes.cvTemplates),
                child: Row(
                  children: [
                    Text(
                      'View all',
                      style: TextStyle(
                        color: AppColors.darkRaspberry,
                        fontSize: 11,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.arrowRight,
                      size: 12,
                      color: AppColors.darkRaspberry,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: _AutoScrollingTemplateStrip(
            templates: CvTemplateData.all,
            onTemplateTap: (id) => context.go('/cv/templates/$id'),
          ),
        ),
      ],
    );
  }

  // ─── Guest "save your work" strip ───────────────────────────────

  Widget _buildGuestSaveStrip() {
    final isMobile = Responsive.isMobile(context);

    final benefits = [
      ('Never lose your work', LucideIcons.save),
      ('Access from any device', LucideIcons.smartphone),
      ('More templates & AI', LucideIcons.sparkles),
    ];

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.lavenderBlush,
            AppColors.petalFrost.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.petalFrost,
          width: 1.5,
        ),
      ),
      child: isMobile
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _guestStripHeader(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: benefits.map(_guestStripChip).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _guestStripCta(),
          ),
        ],
      )
          : Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              LucideIcons.userPlus,
              size: 18,
              color: AppColors.darkRaspberry,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "You're browsing as a guest",
                  style: TextStyle(
                    color: AppColors.prussianBlue,
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: benefits.map(_guestStripChip).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _guestStripCta(),
        ],
      ),
    );
  }

  Widget _guestStripHeader() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.darkRaspberry.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            LucideIcons.userPlus,
            size: 17,
            color: AppColors.darkRaspberry,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            "You're browsing as a guest",
            style: TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _guestStripChip((String, IconData) data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.$2, size: 10, color: AppColors.darkRaspberry),
          const SizedBox(width: 4),
          Text(
            data.$1,
            style: const TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 10.5,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guestStripCta() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(AppRoutes.auth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.darkRaspberry,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkRaspberry.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Sign up',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 6),
              Icon(LucideIcons.arrowRight, size: 13, color: AppColors.white),
            ],
          ),
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

class _EmptyToolData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _EmptyToolData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

// ─── Auto-scrolling template carousel ─────────────────────────────

class _AutoScrollingTemplateStrip extends StatefulWidget {
  final List<CvTemplateInfo> templates;
  final void Function(String templateId) onTemplateTap;

  const _AutoScrollingTemplateStrip({
    required this.templates,
    required this.onTemplateTap,
  });

  @override
  State<_AutoScrollingTemplateStrip> createState() =>
      _AutoScrollingTemplateStripState();
}

class _AutoScrollingTemplateStripState
    extends State<_AutoScrollingTemplateStrip>
    with SingleTickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  Ticker? _ticker;
  bool _paused = false;
  bool _disposed = false;

  static const double _thumbWidth = 150.0;
  static const double _gap = 14.0;
  static const double _pxPerFrame = 0.4;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    if (_disposed || _paused || !_scrollCtrl.hasClients) return;

    final position = _scrollCtrl.position;
    if (!position.hasContentDimensions) return; // layout hasn't run yet — try again next frame

    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;

    final next = _scrollCtrl.offset + _pxPerFrame;
    // Loop: when we reach the end of the first copy, jump back by the width
    // of one copy (invisible reset).
    final copyWidth = widget.templates.length * (_thumbWidth + _gap);
    if (next >= copyWidth) {
      _scrollCtrl.jumpTo(next - copyWidth);
    } else {
      _scrollCtrl.jumpTo(next);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Duplicate the list so the scroll loop feels seamless.
    final doubled = [...widget.templates, ...widget.templates];

    return MouseRegion(
      onEnter: (_) => setState(() => _paused = true),
      onExit: (_) => setState(() => _paused = false),
      child: ListView.builder(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: doubled.length,
        itemBuilder: (context, i) {
          final t = doubled[i];
          return Padding(
            padding: EdgeInsets.only(right: _gap),
            child: _CarouselTemplateCard(
              template: t,
              width: _thumbWidth,
              onTap: () => widget.onTemplateTap(t.id),
            ),
          );
        },
      ),
    );
  }
}

class _CarouselTemplateCard extends StatefulWidget {
  final CvTemplateInfo template;
  final double width;
  final VoidCallback onTap;

  const _CarouselTemplateCard({
    required this.template,
    required this.width,
    required this.onTap,
  });

  @override
  State<_CarouselTemplateCard> createState() => _CarouselTemplateCardState();
}

class _CarouselTemplateCardState extends State<_CarouselTemplateCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..translateByDouble(0, _hovering ? -4 : 0, 0, 1),
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.prussianBlue.withValues(
                  alpha: _hovering ? 0.16 : 0.08,
                ),
                blurRadius: _hovering ? 16 : 10,
                offset: Offset(0, _hovering ? 8 : 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                // Thumbnail
                TemplateThumbnail(
                  assetPath: widget.template.assetPath,
                  width: widget.width,
                  height: 212,
                  borderRadius: 0,
                  showShadow: false,
                ),
                // Pro badge
                if (widget.template.isPremium)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.dustyMauve,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.lock, color: AppColors.white, size: 8),
                          SizedBox(width: 3),
                          Text(
                            'Pro',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 9,
                              fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Hover overlay
                if (_hovering)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.prussianBlue.withValues(alpha: 0.85),
                          ],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.template.label,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.darkRaspberry,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Use template',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 9.5,
                                    fontFamily: AppFonts.poppins,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  LucideIcons.arrowRight,
                                  size: 10,
                                  color: AppColors.white,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}