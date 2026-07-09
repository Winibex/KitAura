// lib/shared/widgets/announcement_banner.dart
//
// Consumer-facing announcement banner. Mounts anywhere in the app and
// self-hides when there's nothing to show. On dismiss or CTA click, it
// writes lastSeenAnnouncementId so the banner stays hidden until the
// admin publishes a new announcement (fresh id).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../models/announcement_model.dart';
import '../providers/announcement_provider.dart';
import '../services/firebase_service.dart';

class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcement = ref.watch(shouldShowAnnouncementProvider);
    if (announcement == null) return const SizedBox.shrink();

    final palette = _paletteFor(announcement.severity);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(palette.icon, size: 18, color: palette.fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (announcement.title.isNotEmpty)
                  Text(
                    announcement.title,
                    style: TextStyle(
                      color: palette.fg,
                      fontFamily: AppFonts.poppins,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (announcement.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    announcement.body,
                    style: TextStyle(
                      color: palette.fg.withValues(alpha: 0.9),
                      fontFamily: AppFonts.openSans,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                if (announcement.linkUrl != null &&
                    announcement.linkUrl!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _handleCtaTap(announcement),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            announcement.linkLabel?.isNotEmpty == true
                                ? announcement.linkLabel!
                                : 'Learn more',
                            style: TextStyle(
                              color: palette.fg,
                              fontFamily: AppFonts.poppins,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(LucideIcons.arrowRight,
                              size: 14, color: palette.fg),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _dismiss(announcement),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.x, size: 16, color: palette.fg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCtaTap(AnnouncementModel a) async {
    final url = a.linkUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    // Treat clicking the CTA as an acknowledgement.
    if (a.id != null) {
      await FirebaseService.markAnnouncementSeen(a.id!);
    }
  }

  Future<void> _dismiss(AnnouncementModel a) async {
    if (a.id == null) return;
    await FirebaseService.markAnnouncementSeen(a.id!);
  }

  _Palette _paletteFor(String severity) {
    switch (severity) {
      case 'critical':
        return const _Palette(
          bg: AppColors.darkRaspberry,
          fg: AppColors.white,
          border: AppColors.darkRaspberry,
          icon: LucideIcons.alertOctagon,
        );
      case 'warn':
        return const _Palette(
          bg: AppColors.dustyRose,
          fg: AppColors.prussianBlue,
          border: AppColors.dustyMauve,
          icon: LucideIcons.alertTriangle,
        );
      case 'info':
      default:
        return const _Palette(
          bg: AppColors.petalFrost,
          fg: AppColors.prussianBlue,
          border: AppColors.almondSilk,
          icon: LucideIcons.info,
        );
    }
  }
}

class _Palette {
  final Color bg;
  final Color fg;
  final Color border;
  final IconData icon;
  const _Palette({
    required this.bg,
    required this.fg,
    required this.border,
    required this.icon,
  });
}