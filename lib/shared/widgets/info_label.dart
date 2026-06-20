// lib/shared/widgets/info_label.dart
//
// Reusable form field label with optional info icon.
// - Desktop/web: hover the icon → tooltip appears.
// - Mobile/touch: tap the icon → popover shows the help text, tap outside to dismiss.
// Same widget, both behaviors — no platform branching needed at the call site.
//
// Usage:
//   InfoLabel(
//     'Your Company',
//     info: 'The name shown on your proposal as the sender.',
//     required: true,
//   )
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

class InfoLabel extends StatelessWidget {
  final String label;
  final String? info;
  final bool required;
  const InfoLabel(
      this.label, {
        super.key,
        this.info,
        this.required = false,
      });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: RichText(
              text: TextSpan(
                text: label,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.prussianBlue,
                  letterSpacing: 0.1,
                ),
                children: required
                    ? const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: AppColors.darkRaspberry,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]
                    : null,
              ),
            ),
          ),
          if (info != null && info!.isNotEmpty) ...[
            const SizedBox(width: 5),
            _InfoIcon(text: info!),
          ],
        ],
      ),
    );
  }
}

class _InfoIcon extends StatefulWidget {
  final String text;
  const _InfoIcon({required this.text});
  @override
  State<_InfoIcon> createState() => _InfoIconState();
}

class _InfoIconState extends State<_InfoIcon> {
  OverlayEntry? _entry;

  void _showPopover() {
    if (_entry != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.of(context).size;

    // Prefer below the icon; flip above if not enough room.
    final showBelow = pos.dy + size.height + 110 < screen.height;
    final top = showBelow ? pos.dy + size.height + 6 : pos.dy - 110;
    // Keep the popover on screen horizontally.
    const popW = 240.0;
    var left = pos.dx + size.width / 2 - popW / 2;
    if (left < 12) left = 12;
    if (left + popW > screen.width - 12) left = screen.width - popW - 12;

    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hidePopover,
              child: const SizedBox(),
            ),
          ),
          Positioned(
            top: top,
            left: left,
            width: popW,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.prussianBlue,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hidePopover() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hidePopover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.help,
      child: Tooltip(
        message: widget.text,
        textStyle: const TextStyle(
          fontSize: 11.5,
          fontFamily: AppFonts.openSans,
          color: AppColors.white,
          height: 1.4,
        ),
        decoration: BoxDecoration(
          color: AppColors.prussianBlue,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        preferBelow: true,
        waitDuration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _showPopover,
          child: const Icon(
            LucideIcons.info,
            size: 13,
            color: AppColors.slateGrey,
          ),
        ),
      ),
    );
  }
}