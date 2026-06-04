// lib/features/cover_letter/templates/view/cl_template_preview_modal.dart
//
// Matches CV template preview modal design exactly.
// Same structure, same colors, same layout.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../shared/widgets/template_thumbnail.dart';
import '../data/cl_template_data.dart';

class ClTemplatePreviewModal extends StatefulWidget {
  final ClTemplateInfo info;
  final VoidCallback onUse;

  const ClTemplatePreviewModal({
    super.key,
    required this.info,
    required this.onUse,
  });

  @override
  State<ClTemplatePreviewModal> createState() => _ClTemplatePreviewModalState();
}

class _ClTemplatePreviewModalState extends State<ClTemplatePreviewModal> {
  bool _loading = true;
  List<Map<String, dynamic>> _pages = [];

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    try {
      final raw = await rootBundle.loadString(widget.info.assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final items = (json['items'] as List?) ?? [];
      final bg = json['canvasBackground'] ?? '#FFFFFF';

      // CL templates are single page but handle multi-page just in case
      double maxY = 842;
      for (final item in items) {
        final y = (item['y'] ?? 0).toDouble();
        final h = (item['h'] ?? 0).toDouble();
        if (y + h > maxY) maxY = y + h;
      }
      final pageCount = (maxY / 842).ceil().clamp(1, 10);

      final pages = <Map<String, dynamic>>[];
      for (int p = 0; p < pageCount; p++) {
        final pageTop = p * 842.0;
        final pageBottom = (p + 1) * 842.0;
        final pageItems = items.where((item) {
          final iy = (item['y'] ?? 0).toDouble();
          final ih = (item['h'] ?? 0).toDouble();
          return iy < pageBottom && (iy + ih) > pageTop;
        }).map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          map['y'] = (map['y'] as num).toDouble() - pageTop;
          return map;
        }).toList();
        pages.add({'canvasBackground': bg, 'items': pageItems});
      }

      if (mounted) setState(() { _pages = pages; _loading = false; });
    } catch (e) {
      debugPrint('CL preview load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: screenW < 800 ? screenW - 40 : 900,
        height: screenH * 0.88,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 40, offset: const Offset(0, 16)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              // Left — Preview
              Expanded(flex: 55, child: _buildLeftPanel()),
              // Right — Info
              Expanded(flex: 45, child: _buildRightPanel()),
            ],
          ),
        ),
      ),
    );
  }

  // ─── LEFT PANEL ─────────────────────────────────────────────────────

  Widget _buildLeftPanel() {
    return Container(
      color: const Color(0xFFF5F0EC),
      child: Column(
        children: [
          // Page bar (brand color)
          if (_pages.length > 1)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.prussianBlue,
              child: Row(
                children: [
                  Text('Page ${_currentPage + 1} of ${_pages.length}',
                      style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w500, color: AppColors.white)),
                  const Spacer(),
                  _pageNavBtn(LucideIcons.chevronLeft, _currentPage > 0,
                          () => setState(() => _currentPage--)),
                  const SizedBox(width: 4),
                  _pageNavBtn(LucideIcons.chevronRight, _currentPage < _pages.length - 1,
                          () => setState(() => _currentPage++)),
                ],
              ),
            ),
          // Preview
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _loading
                    ? const CircularProgressIndicator(color: AppColors.darkRaspberry)
                    : AspectRatio(
                  aspectRatio: 595 / 842,
                  child: _pages.isNotEmpty
                      ? TemplateThumbnail.fromJson(
                    json: _pages[_currentPage],
                    width: 595, height: 842,
                    borderRadius: 4, showShadow: true,
                  )
                      : const SizedBox(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageNavBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.white.withValues(alpha: 0.15)
                : AppColors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14,
              color: enabled ? AppColors.white : AppColors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  // ─── RIGHT PANEL ────────────────────────────────────────────────────

  Widget _buildRightPanel() {
    return Column(
      children: [
        // Close button
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0EC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.x, size: 16, color: AppColors.slateGrey),
                ),
              ),
            ),
          ),
        ),
        // Content (no scroll — Spacer pushes CTA to bottom)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(widget.info.label,
                    style: const TextStyle(fontSize: 26, fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
                const SizedBox(height: 8),

                // Badges
                Row(
                  children: [
                    _badge(
                      widget.info.category[0].toUpperCase() + widget.info.category.substring(1),
                      AppColors.petalFrost, AppColors.darkRaspberry,
                    ),
                    if (widget.info.isPremium) ...[
                      const SizedBox(width: 8),
                      _badge('Pro', AppColors.dustyMauve, AppColors.white),
                    ],
                  ],
                ),
                const SizedBox(height: 20),

                // Description
                Text(widget.info.description,
                    style: const TextStyle(fontSize: 14, fontFamily: AppFonts.openSans,
                        color: AppColors.slateGrey, height: 1.6)),
                const SizedBox(height: 24),

                // Features
                _featureItem(LucideIcons.sparkles, 'AI content generation ready'),
                _featureItem(LucideIcons.move, 'Fully customizable layout'),
                _featureItem(LucideIcons.download, 'PDF export included'),
                _featureItem(LucideIcons.type, 'Multiple font options'),

                // Page thumbnails (if multi-page)
                if (_pages.length > 1) ...[
                  const SizedBox(height: 24),
                  const Text('PAGES',
                      style: TextStyle(fontSize: 10, fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w600, color: AppColors.slateGrey,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, idx) {
                        final isActive = idx == _currentPage;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => setState(() => _currentPage = idx),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 70,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isActive ? AppColors.darkRaspberry : const Color(0xFFDDD5CB),
                                  width: isActive ? 2 : 1,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: TemplateThumbnail.fromJson(
                                      json: _pages[idx], width: 70, height: 98,
                                      borderRadius: 5, showShadow: false,
                                    ),
                                  ),
                                  Positioned(bottom: 3, right: 5,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isActive ? AppColors.darkRaspberry : Colors.black54,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text('${idx + 1}',
                                          style: const TextStyle(fontSize: 8,
                                              fontWeight: FontWeight.w600, color: AppColors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const Spacer(),

                // CTA
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () { Navigator.pop(context); widget.onUse(); },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkRaspberry,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Use This Template',
                        style: TextStyle(fontSize: 15, fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text('or Start from Scratch',
                          style: TextStyle(fontSize: 12, fontFamily: AppFonts.openSans,
                              fontWeight: FontWeight.w400,
                              color: AppColors.slateGrey.withValues(alpha: 0.7))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontFamily: AppFonts.poppins,
          fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _featureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.success),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 13, fontFamily: AppFonts.openSans,
              fontWeight: FontWeight.w500, color: AppColors.prussianBlue)),
        ],
      ),
    );
  }
}