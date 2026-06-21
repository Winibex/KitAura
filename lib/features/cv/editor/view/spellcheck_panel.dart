// lib/features/cv/view/spellcheck_panel.dart
//
// Floating panel that shows AI Proofread results.
// Appears after user clicks "AI Proofread" button.
// Shows each error with Fix / Ignore buttons + Fix All.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../shared/ai/claude_service.dart';
import '../../../../shared/models/canvas_item.dart';
import '../../../../shared/ai/spellcheck_controller.dart';

class SpellcheckPanel extends ConsumerWidget {
  final List<CanvasItem> items;
  final VoidCallback onClose;

  const SpellcheckPanel({
    super.key,
    required this.items,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spellcheckControllerProvider);
    final ctrl = ref.read(spellcheckControllerProvider.notifier);

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(state, ctrl),
          if (state.isChecking) _buildLoading(),
          if (state.status == SpellcheckStatus.error) _buildError(state),
          if (state.status == SpellcheckStatus.done && !state.hasCorrections)
            _buildNoErrors(),
          if (state.status == SpellcheckStatus.done && state.hasCorrections)
            _buildCorrectionsList(state, ctrl),
        ],
      ),
    );
  }

  Widget _buildHeader(SpellcheckState state, SpellcheckController ctrl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: const BoxDecoration(
        color: AppColors.prussianBlue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.spellCheck, size: 16, color: AppColors.white),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'AI Proofread',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (state.hasCorrections)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.magentaBloom,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${state.count}',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onClose,
            icon: const Icon(LucideIcons.x, size: 16, color: AppColors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.darkRaspberry,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Checking spelling...',
            style: TextStyle(
              color: AppColors.slateGrey,
              fontSize: 12,
              fontFamily: AppFonts.openSans,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(SpellcheckState state) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(LucideIcons.alertCircle, color: AppColors.error, size: 28),
          const SizedBox(height: 8),
          Text(
            state.error ?? 'Something went wrong',
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
              fontFamily: AppFonts.openSans,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoErrors() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(LucideIcons.checkCircle, color: AppColors.success, size: 32),
          SizedBox(height: 10),
          Text(
            'No spelling errors found!',
            style: TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 14,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Your CV looks great.',
            style: TextStyle(
              color: AppColors.slateGrey,
              fontSize: 12,
              fontFamily: AppFonts.openSans,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectionsList(
      SpellcheckState state, SpellcheckController ctrl) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fix All button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton.icon(
                onPressed: () => ctrl.fixAll(items),
                icon: const Icon(LucideIcons.checkCheck, size: 14),
                label: Text(
                  'Fix All (${state.count})',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.petalFrost),

          // Corrections list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: state.corrections.length,
              separatorBuilder: (_, _) =>
              const Divider(height: 1, color: AppColors.petalFrost),
              itemBuilder: (context, index) {
                final c = state.corrections[index];
                return _CorrectionTile(
                  correction: c,
                  onFix: () => ctrl.fixOne(c, items),
                  onDismiss: () => ctrl.dismiss(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CORRECTION TILE ─────────────────────────────────────────────────────

class _CorrectionTile extends StatelessWidget {
  final SpellCorrection correction;
  final VoidCallback onFix;
  final VoidCallback onDismiss;

  const _CorrectionTile({
    required this.correction,
    required this.onFix,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section name
          Text(
            correction.sectionTitle,
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 9,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),

          // Wrong → Correct
          Row(
            children: [
              // Wrong word (red, strikethrough)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  correction.wrong,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontFamily: AppFonts.openSans,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.error,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(LucideIcons.arrowRight,
                    size: 12, color: AppColors.slateGrey),
              ),
              // Correct word (green)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FFF4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  correction.correct,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontFamily: AppFonts.openSans,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // Fix button
              _tinyButton(
                label: 'Fix',
                color: AppColors.darkRaspberry,
                onTap: onFix,
              ),
              const SizedBox(width: 4),
              // Dismiss button
              _tinyButton(
                label: 'Skip',
                color: AppColors.slateGrey,
                onTap: onDismiss,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}