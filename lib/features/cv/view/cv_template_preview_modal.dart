// lib/features/cv_templates/view/cv_template_preview_modal.dart
//
// Full preview modal shown when user taps a template card.
// Left: large CV page preview. Right: info + page thumbnails.
// Supports multi-page cv_templates with page navigation.
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../shared/widgets/template_thumbnail.dart';
import '../../../shared/models/template_model.dart';
import '../data/cv_template_data.dart';

class CVTemplatePreviewModal extends StatefulWidget {
  final TemplateModel template;
  final VoidCallback onUseTemplate;
  final VoidCallback onStartBlank;

  const CVTemplatePreviewModal({
    super.key,
    required this.template,
    required this.onUseTemplate,
    required this.onStartBlank,
  });

  @override
  State<CVTemplatePreviewModal> createState() => _CVTemplatePreviewModalState();
}

class _CVTemplatePreviewModalState extends State<CVTemplatePreviewModal> {
  int _currentPage = 0;
  List<Map<String, dynamic>> _pages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplatePages();
  }

  Future<void> _loadTemplatePages() async {
    // Load from JSON asset via CvTemplateData
    final templateData = await CvTemplateData.loadTemplateJson(widget.template.id);

    // Split items into pages (A4 = 842px per page)
    final items = templateData['items'] as List<dynamic>? ?? [];
    final bg = templateData['canvasBackground'] as String? ?? '#FFFFFF';

    // Find max Y to determine page count
    double maxY = 842;
    for (final item in items) {
      final y = (item['y'] as num? ?? 0).toDouble();
      final h = (item['h'] as num? ?? 0).toDouble();
      if (y + h > maxY) maxY = y + h;
    }

    final pageCount = ((maxY / 842).ceil()).clamp(1, 10);
    final pages = <Map<String, dynamic>>[];

    for (int p = 0; p < pageCount; p++) {
      final pageTop = p * 842.0;
      final pageBottom = (p + 1) * 842.0;

      // Filter items that overlap with this page
      final pageItems = items.where((item) {
        final iy = (item['y'] as num? ?? 0).toDouble();
        final ih = (item['h'] as num? ?? 0).toDouble();
        return iy < pageBottom && (iy + ih) > pageTop;
      }).map((item) {
        // Adjust Y position relative to page
        final map = Map<String, dynamic>.from(item as Map);
        map['y'] = (map['y'] as num).toDouble() - pageTop;
        return map;
      }).toList();

      pages.add({
        'canvasBackground': bg,
        'items': pageItems,
      });
    }

    if (mounted) {
      setState(() {
        _pages = pages;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final isMobile = screenW < 800;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: isMobile ? screenW - 40 : 900,
        height: screenH * 0.88,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
        ),
      ),
    );
  }

  // ─── DESKTOP LAYOUT ───────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left — Large CV preview
        Expanded(
          flex: 55,
          child: Container(
            color: const Color(0xFFF5F0EC),
            child: Column(
              children: [
                // Page indicator bar
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEDE8E3),
                    border: Border(bottom: BorderSide(color: Color(0xFFDDD5CB))),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Page ${_currentPage + 1} of ${_pages.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w500,
                          color: AppColors.slateGrey,
                        ),
                      ),
                      const Spacer(),
                      if (_pages.length > 1) ...[
                        _pageNavBtn(LucideIcons.chevronLeft, _currentPage > 0,
                                () => setState(() => _currentPage--)),
                        const SizedBox(width: 4),
                        _pageNavBtn(LucideIcons.chevronRight,
                            _currentPage < _pages.length - 1,
                                () => setState(() => _currentPage++)),
                      ],
                    ],
                  ),
                ),
                // CV preview
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _loading
                          ? const CircularProgressIndicator(
                          color: AppColors.darkRaspberry)
                          : AspectRatio(
                        aspectRatio: 595 / 842,
                        child: _pages.isNotEmpty
                            ? TemplateThumbnail.fromJson(
                          json: _pages[_currentPage],
                          width: 595,
                          height: 842,
                          borderRadius: 4,
                          showShadow: true,
                        )
                            : const SizedBox(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right — Info + page thumbnails + CTA
        Expanded(
          flex: 45,
          child: _buildInfoPanel(),
        ),
      ],
    );
  }

  // ─── MOBILE LAYOUT ────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Close bar
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                widget.template.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.prussianBlue,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.x, size: 20),
              ),
            ],
          ),
        ),
        // Preview
        Expanded(
          flex: 55,
          child: Container(
            color: const Color(0xFFF5F0EC),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator(color: AppColors.darkRaspberry)
                  : AspectRatio(
                aspectRatio: 595 / 842,
                child: _pages.isNotEmpty
                    ? TemplateThumbnail.fromJson(
                  json: _pages[_currentPage],
                  width: 595,
                  height: 842,
                  borderRadius: 4,
                )
                    : const SizedBox(),
              ),
            ),
          ),
        ),
        // Page thumbnails + CTA
        Expanded(
          flex: 45,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildInfoContent(),
          ),
        ),
      ],
    );
  }

  // ─── INFO PANEL ───────────────────────────────────────────────────────

  Widget _buildInfoPanel() {
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0EC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.x,
                      size: 16, color: AppColors.slateGrey),
                ),
              ),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: _buildInfoContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Template name
        Text(
          widget.template.label,
          style: const TextStyle(
            fontSize: 26,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
            color: AppColors.prussianBlue,
          ),
        ),
        const SizedBox(height: 8),

        // Category + page count badges
        Row(
          children: [
            _badge(
              widget.template.category[0].toUpperCase() +
                  widget.template.category.substring(1),
              AppColors.petalFrost,
              AppColors.darkRaspberry,
            ),
            const SizedBox(width: 8),
            _badge(
              '${_pages.length} ${_pages.length == 1 ? 'page' : 'pages'}',
              const Color(0xFFF0EBE6),
              AppColors.slateGrey,
            ),
            if (widget.template.isPremium) ...[
              const SizedBox(width: 8),
              _badge('Pro', AppColors.dustyMauve, AppColors.white),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Description
        Text(
          CvTemplateData.getDescription(widget.template.id),
          style: const TextStyle(
            fontSize: 14,
            fontFamily: AppFonts.openSans,
            color: AppColors.slateGrey,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),

        // Features
        _featureItem(LucideIcons.sparkles, 'AI content generation ready'),
        _featureItem(LucideIcons.move, 'Fully customizable layout'),
        _featureItem(LucideIcons.download, 'PDF export included'),
        _featureItem(LucideIcons.type, 'Multiple font options'),
        const SizedBox(height: 24),

        // Page thumbnails (if multi-page)
        if (_pages.length > 1) ...[
          const Text(
            'PAGES',
            style: TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.slateGrey,
              letterSpacing: 1.5,
            ),
          ),
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
                          color: isActive
                              ? AppColors.darkRaspberry
                              : const Color(0xFFDDD5CB),
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: TemplateThumbnail.fromJson(
                              json: _pages[idx],
                              width: 70,
                              height: 98,
                              borderRadius: 5,
                              showShadow: false,
                            ),
                          ),
                          // Page number
                          Positioned(
                            bottom: 3,
                            right: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.darkRaspberry
                                    : Colors.black54,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.white,
                                ),
                              ),
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
          const SizedBox(height: 24),
        ],

        // CTA buttons
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onUseTemplate();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkRaspberry,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Use This Template',
              style: TextStyle(
                fontSize: 15,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onStartBlank();
            },
            child: const Text(
              'or Start from Scratch',
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppFonts.poppins,
                color: AppColors.slateGrey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── HELPER WIDGETS ───────────────────────────────────────────────────

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontFamily: AppFonts.poppins,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _featureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.success),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: AppFonts.openSans,
              fontWeight: FontWeight.w500,
              color: AppColors.prussianBlue,
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled ? AppColors.white : const Color(0xFFE8E0D8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon,
              size: 14,
              color: enabled ? AppColors.prussianBlue : AppColors.slateGrey),
        ),
      ),
    );
  }
}