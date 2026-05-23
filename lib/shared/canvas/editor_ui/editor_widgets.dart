// lib/shared/canvas/editor_widgets.dart
//
// Small reusable widgets shared by all canvas editor panels.
// Used by: editor_left_panel, editor_right_panel, cv_editor_screen, proposal_editor_screen.

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';

/// Section label (e.g. "ADD ELEMENTS", "LAYERS", "ROTATION")
class EditorSectionLabel extends StatelessWidget {
  final String text;
  const EditorSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.slateGrey,
        fontFamily: AppFonts.poppins,
        letterSpacing: 1,
      ),
    );
  }
}

/// Small icon button for adding elements to canvas (Text, Line, Rect, etc.)
class EditorAddButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const EditorAddButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.lavenderBlush,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.petalFrost),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.darkRaspberry),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9,
                      fontFamily: AppFonts.poppins,
                      color: AppColors.prussianBlue)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small layer reorder button (Front, Up, Down, Back)
class EditorLayerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const EditorLayerButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.lavenderBlush,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.petalFrost),
            ),
            child: Icon(icon, size: 14, color: AppColors.darkRaspberry),
          ),
        ),
      ),
    );
  }
}

/// Color display row with label + clickable color swatch
class EditorColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const EditorColorRow({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontFamily: AppFonts.openSans,
                color: AppColors.prussianBlue)),
        const Spacer(),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 28,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: AppColors.almondSilk),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Slider row with label + slider
class EditorSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const EditorSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontFamily: AppFonts.openSans,
                color: AppColors.prussianBlue)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.darkRaspberry,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Flip action button (Horizontal / Vertical)
class EditorActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const EditorActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 13, color: AppColors.prussianBlue),
      label: Text(label,
          style:
          const TextStyle(fontSize: 10, color: AppColors.prussianBlue)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.petalFrost),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      ),
    );
  }
}

/// Panel toggle button (shown when a panel is closed)
class EditorPanelToggle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const EditorPanelToggle({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 16, color: AppColors.prussianBlue),
      ),
    );
  }
}