// lib/features/dashboard/view/dashboard_screen.dart
//
// Platform overview — shows usage stats, quick-start cards for each tool,
// recent activity across all tools, and upgrade CTA.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_routes.dart';
import '../../../shared/widgets/app_sidebar.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../settings/view/upgrade_modal.dart';
import '../controller/dashboard_controller.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: Row(
              children: [
                const AppSidebar(),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final state = ref.watch(dashboardControllerProvider);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.darkRaspberry),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGreeting(state),
          const SizedBox(height: 28),
          _buildStatCards(state),
          const SizedBox(height: 32),
          _buildQuickStart(),
          const SizedBox(height: 32),
          _buildRecentActivity(state),
          const SizedBox(height: 32),
          if (!state.isPro) _buildUpgradeBanner(),
          const SizedBox(height: 40),
        ],
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
                style: const TextStyle(
                  fontSize: 26,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final cards = [
          _StatCardData(
            icon: LucideIcons.fileText,
            label: 'Documents',
            value: '${state.cvCount}',
            subtitle: '${state.totalCvsCreated} total created',
            color: AppColors.magentaBloom,
          ),
          _StatCardData(
            icon: LucideIcons.download,
            label: 'Exports',
            value: state.isPro ? '∞' : '${state.exportCount} / 3',
            subtitle: state.isPro ? 'Unlimited' : '${3 - state.exportCount} remaining',
            color: AppColors.dustyRose,
            progress: state.isPro ? null : state.exportCount / 3,
          ),
          _StatCardData(
            icon: LucideIcons.sparkles,
            label: 'AI Fills',
            value: state.isPro ? '∞' : '${state.aiUsageCount} / 10',
            subtitle: state.isPro ? 'Unlimited' : '${10 - state.aiUsageCount} remaining',
            color: AppColors.dustyMauve,
            progress: state.isPro ? null : state.aiUsageCount / 10,
          ),
          _StatCardData(
            icon: LucideIcons.logIn,
            label: 'Sessions',
            value: '${state.loginCount}',
            subtitle: 'Total logins',
            color: AppColors.slateGrey,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: [
              Row(children: [
                Expanded(child: _buildStatCard(cards[0])),
                const SizedBox(width: 16),
                Expanded(child: _buildStatCard(cards[1])),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _buildStatCard(cards[2])),
                const SizedBox(width: 16),
                Expanded(child: _buildStatCard(cards[3])),
              ]),
            ],
          );
        }

        return Row(
          children: cards.map((c) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: c == cards.last ? 0 : 16),
              child: _buildStatCard(c),
            ),
          )).toList(),
        );
      },
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  Widget _buildStatCard(_StatCardData data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 18),
              ),
              const Spacer(),
              Text(
                data.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 28,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.bold,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 4),
          if (data.progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: data.progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: const Color(0xFFF0EBE6),
                valueColor: AlwaysStoppedAnimation(
                  data.progress! >= 1.0 ? AppColors.error : data.color,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            data.subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
          ),
        ],
      ),
    );
  }

  // ─── QUICK START CARDS ─────────────────────────────────────────────────

  Widget _buildQuickStart() {
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
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 700;
            final cards = [
              _QuickStartData(
                icon: LucideIcons.filePlus,
                title: 'Create CV',
                subtitle: 'Professional resume builder',
                color: AppColors.darkRaspberry,
                onTap: () => context.push(AppRoutes.cvTemplates),
              ),
              _QuickStartData(
                icon: LucideIcons.fileText,
                title: 'Write Proposal',
                subtitle: 'Win more clients',
                color: AppColors.dustyMauve,
                onTap: () {}, // TODO
                comingSoon: true,
              ),
              _QuickStartData(
                icon: LucideIcons.mail,
                title: 'Cover Letter',
                subtitle: 'Stand out from the crowd',
                color: AppColors.magentaBloom,
                onTap: () {}, // TODO
                comingSoon: true,
              ),
              _QuickStartData(
                icon: LucideIcons.linkedin,
                title: 'LinkedIn Summary',
                subtitle: 'Optimize your profile',
                color: AppColors.dustyRose,
                onTap: () {}, // TODO
                comingSoon: true,
              ),
            ];

            if (isNarrow) {
              return Column(
                children: [
                  Row(children: [
                    Expanded(child: _buildQuickStartCard(cards[0])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildQuickStartCard(cards[1])),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _buildQuickStartCard(cards[2])),
                    const SizedBox(width: 12),
                    Expanded(child: _buildQuickStartCard(cards[3])),
                  ]),
                ],
              );
            }

            return Row(
              children: cards.map((c) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: c == cards.last ? 0 : 12),
                  child: _buildQuickStartCard(c),
                ),
              )).toList(),
            );
          },
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  Widget _buildQuickStartCard(_QuickStartData data) {
    return MouseRegion(
      cursor: data.comingSoon ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: data.comingSoon ? null : data.onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDE8E3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(data.icon, color: data.color, size: 20),
                  ),
                  const Spacer(),
                  if (data.comingSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBE6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Soon',
                        style: TextStyle(fontSize: 10, color: AppColors.slateGrey,
                            fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    Icon(LucideIcons.arrowRight, size: 16, color: data.color),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: data.comingSoon
                      ? AppColors.slateGrey
                      : AppColors.prussianBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── RECENT ACTIVITY ───────────────────────────────────────────────────

  Widget _buildRecentActivity(DashboardState state) {
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
            if (state.recentItems.isNotEmpty)
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

        if (state.recentItems.isEmpty)
          Container(
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
                    onPressed: () => context.push(AppRoutes.cvTemplates),
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
          )
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
                  child: const Row(
                    children: [
                      Expanded(flex: 4, child: Text('Document', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Type', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Template', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Last edited', style: _headerStyle)),
                      SizedBox(width: 40),
                    ],
                  ),
                ),
                // Rows
                ...state.recentItems.map((item) => _buildRecentRow(item)),
              ],
            ),
          ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 300.ms);
  }

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontFamily: AppFonts.poppins,
    fontWeight: FontWeight.w600,
    color: AppColors.slateGrey,
    letterSpacing: 0.5,
  );

  Widget _buildRecentRow(RecentItem item) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => context.push('/cv/${item.id}'),
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
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.petalFrost,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(LucideIcons.fileText,
                          size: 14, color: AppColors.darkRaspberry),
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

  // ─── UPGRADE BANNER ────────────────────────────────────────────────────

  Widget _buildUpgradeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.crown, color: AppColors.white, size: 22),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlock the full KitAura experience',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Unlimited exports · Unlimited AI · No watermark · All CV templates',
                  style: TextStyle(fontSize: 13, color: Color(0xAAFFFFFF)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => const UpgradeModal(),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Upgrade — \$7/mo',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkRaspberry,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
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

  _StatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.progress,
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