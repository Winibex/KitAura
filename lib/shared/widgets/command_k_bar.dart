// lib/shared/widgets/command_k_bar.dart
//
// Floating bottom bar for the AI editor (command-K).
//
// Usage (in any editor view):
//
//   Stack(
//     children: [
//       /* editor canvas */,
//       Positioned(
//         left: 0, right: 0, bottom: 16,
//         child: CommandKBar(
//           canvasController: _canvasController,
//           tool: 'cv',
//           documentId: cvId,
//           documentTitle: title,
//           templateId: templateId,
//         ),
//       ),
//     ],
//   )
//
// Keyboard: Ctrl/Cmd+K to open, Escape to close, Enter to submit.
// Must be wrapped in a Shortcuts widget at the editor level (see editor wiring).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';
import '../ai/claude_service.dart';
import '../canvas/engine/canvas_controller.dart';
import '../canvas/engine/canvas_op_types.dart';

class CommandKBar extends ConsumerStatefulWidget {
  final CanvasController canvasController;
  final String tool; // 'cv' | 'coverLetter' | 'proposal'
  final String? documentId;
  final String? documentTitle;
  final String? templateId;

  const CommandKBar({
    super.key,
    required this.canvasController,
    required this.tool,
    this.documentId,
    this.documentTitle,
    this.templateId,
  });

  @override
  ConsumerState<CommandKBar> createState() => _CommandKBarState();
}

class _CommandKBarState extends ConsumerState<CommandKBar>
    with TickerProviderStateMixin {
  bool _open = false;
  bool _busy = false;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  // Result state — null when nothing to show.
  OpResult? _result;
  String? _error;

  // Tracks async generation completion to update the strip.
  int _pendingGenerations = 0;

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  bool get _isPhone => MediaQuery.of(context).size.width < 600;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── State helpers ─────────────────────────────────────────────────

  void openBar() {
    setState(() {
      _open = true;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  void _closeBar() {
    setState(() {
      _open = false;
      _ctrl.clear();
    });
  }

  void _dismissResult() {
    setState(() {
      _result = null;
      _error = null;
    });
  }

  // ─── Submit ────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final instruction = _ctrl.text.trim();
    if (instruction.isEmpty || _busy) return;

    // Pro paywall check happens server-side, but show upgrade if non-pro
    // and they've hit the soft block locally.
    final isPro = ref.read(dashboardControllerProvider).isPro;
    if (!isPro) {
      // Could enforce client-side count check here. For now, let server
      // be the source of truth and show whatever error it returns.
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      // 1. Build snapshot from the current canvas state.
      final snapshot = widget.canvasController.buildSnapshot();

      // 2. Call the Cloud Function.
      final envelope = await ClaudeService.aiEdit(
        instruction: instruction,
        snapshot: snapshot,
        tool: widget.tool,
        documentId: widget.documentId,
        documentTitle: widget.documentTitle,
        templateId: widget.templateId,
      );

      // 3. Apply the envelope to the canvas.
      final result = await widget.canvasController.applyOps(envelope);

      // 4. Track async generations so we can update the strip when they finish.
      _pendingGenerations = result.pendingGenerations.length;
      if (_pendingGenerations > 0) {
        for (final f in result.pendingGenerations) {
          f.whenComplete(() {
            if (!mounted) return;
            setState(() => _pendingGenerations--);
          });
        }
      }

      setState(() {
        _busy = false;
        _result = result;
        _ctrl.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_result != null || _error != null) _buildResultStrip(),
        const SizedBox(height: 8),
        _open ? _buildOpenBar() : _buildClosedPill(),
      ],
    );
  }

  // ─── Closed pill (default state) ───────────────────────────────────

  Widget _buildClosedPill() {
    return Center(
      child: GestureDetector(
        onTap: openBar,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, _) {
              final glow = 0.15 + (_pulseCtrl.value * 0.1);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.darkRaspberry.withValues(alpha: glow),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.sparkles,
                        size: 14, color: AppColors.white),
                    const SizedBox(width: 8),
                    Text(
                      _isPhone ? 'Ask AI to edit' : 'Ask AI to edit...',
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                    if (!_isPhone) ...[
                      const SizedBox(width: 10),
                      _kbdHint(_shortcutLabel),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Platform-aware modifier label.
  /// macOS shows "⌘J", everything else shows "Ctrl+J".
  String get _shortcutLabel {
    // defaultTargetPlatform works on Flutter Web too — it reads from
    // the browser's user agent. macOS → TargetPlatform.macOS.
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return isMac ? '⌘J' : 'Ctrl+J';
  }

  Widget _kbdHint(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontFamily: AppFonts.openSans,
          fontWeight: FontWeight.w600,
          color: AppColors.white,
        ),
      ),
    );
  }

  // ─── Open bar (input state) ───────────────────────────────────────

  Widget _buildOpenBar() {
    final maxW = _isPhone ? double.infinity : 640.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: _isPhone ? 12 : 0),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.petalFrost),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInputRow(),
              if (_error != null) _buildErrorRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          // Leading sparkle (pulses while busy)
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, _) {
              final scale = _busy ? 1.0 + (_pulseCtrl.value * 0.15) : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.sparkles,
                    size: 14,
                    color: AppColors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _busy
                ? _buildThinkingText()
                : KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    _closeBar();
                  } else if (event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _submit();
                  }
                }
              },
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.prussianBlue,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: _hintText,
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.slateGrey,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Submit
          _iconButton(
            icon: LucideIcons.arrowUp,
            color: AppColors.darkRaspberry,
            enabled: !_busy && _ctrl.text.trim().isNotEmpty,
            onTap: _submit,
            tooltip: 'Submit (Enter)',
          ),
          const SizedBox(width: 4),
          // Close
          _iconButton(
            icon: LucideIcons.x,
            color: AppColors.slateGrey,
            enabled: !_busy,
            onTap: _closeBar,
            tooltip: 'Close (Esc)',
          ),
        ],
      ),
    );
  }

  String get _hintText {
    final examples = [
      'make the heading bold',
      'move section to page 2',
      'write a new summary about my Python experience',
      'change the title color to navy',
      'delete the navy bar at top',
    ];
    // Rotate examples by current time so the hint isn't always the same.
    final idx = DateTime.now().minute % examples.length;
    return 'Try: ${examples[idx]}';
  }

  Widget _buildThinkingText() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, _) {
        return Opacity(
          opacity: 0.6 + (_pulseCtrl.value * 0.4),
          child: const Text(
            'Thinking...',
            style: TextStyle(
              fontSize: 13,
              fontFamily: AppFonts.openSans,
              fontStyle: FontStyle.italic,
              color: AppColors.slateGrey,
            ),
          ),
        );
      },
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    final btn = GestureDetector(
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? color.withValues(alpha: 0.1)
                : AppColors.lavenderBlush,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? color : AppColors.slateGrey,
          ),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: btn);
  }

  Widget _buildErrorRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFFFE4E6))),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertTriangle,
              size: 12, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error ?? '',
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: AppFonts.openSans,
                color: AppColors.error,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(LucideIcons.x,
                size: 12, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  // ─── Result strip ──────────────────────────────────────────────────

  Widget _buildResultStrip() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();

    final maxW = _isPhone ? double.infinity : 640.0;

    // Determine color theme
    final Color bg;
    final Color fg;
    final IconData icon;
    if (result.isRefusal) {
      bg = const Color(0xFFEEF4FF);
      fg = const Color(0xFF1E40AF);
      icon = LucideIcons.info;
    } else if (result.hasFailures) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
      icon = LucideIcons.alertCircle;
    } else if (result.appliedCount == 0) {
      bg = AppColors.lavenderBlush;
      fg = AppColors.slateGrey;
      icon = LucideIcons.info;
    } else {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
      icon = LucideIcons.checkCircle;
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: _isPhone ? 12 : 0),
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resultHeadline(result),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                  if (!result.isRefusal && result.appliedCount > 0)
                    _smallTextButton(
                      label: 'Undo',
                      onTap: () {
                        widget.canvasController.undo();
                        _dismissResult();
                      },
                      color: fg,
                    ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _dismissResult,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        child: Icon(LucideIcons.x, size: 12, color: fg),
                      ),
                    ),
                  ),
                ],
              ),
              // Pending generation indicator
              if (_pendingGenerations > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: fg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _pendingGenerations == 1
                          ? 'Writing content...'
                          : 'Writing content ($_pendingGenerations remaining)...',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: AppFonts.openSans,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ],
              // Warnings + failure detail
              if (result.warnings.isNotEmpty || result.hasFailures) ...[
                const SizedBox(height: 6),
                ...result.warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(left: 21, bottom: 2),
                  child: Text(
                    '• $w',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.openSans,
                      color: fg.withValues(alpha: 0.85),
                    ),
                  ),
                )),
                ...result.failures.map((f) => Padding(
                  padding: const EdgeInsets.only(left: 21, bottom: 2),
                  child: Text(
                    '• ${f.message}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.openSans,
                      color: fg.withValues(alpha: 0.85),
                    ),
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _resultHeadline(OpResult result) {
    if (result.isRefusal) {
      return result.summary.isNotEmpty
          ? result.summary
          : 'I can only edit this document.';
    }
    if (result.appliedCount == 0 && result.hasFailures) {
      return 'Couldn\'t apply that edit.';
    }
    if (result.summary.isNotEmpty) return result.summary;
    final n = result.appliedCount;
    return n == 1 ? 'Made 1 edit.' : 'Made $n edits.';
  }

  Widget _smallTextButton({
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps an editor and listens for the AI editor shortcut (Ctrl/Cmd+J).
///
/// We use J instead of K because most browsers (Edge, Chrome, Firefox) bind
/// Ctrl+K to "focus address bar / search" and that intercept happens above
/// Flutter Web's focus system — we never see the key event.
///
/// We register a global hardware-key handler instead of a Shortcuts widget
/// because Shortcuts only fires when something inside the focus tree
/// matches, which is fragile when text fields steal focus.
class CommandKShortcuts extends StatefulWidget {
  final Widget child;
  final VoidCallback onOpen;
  const CommandKShortcuts({
    super.key,
    required this.child,
    required this.onOpen,
  });

  @override
  State<CommandKShortcuts> createState() => _CommandKShortcutsState();
}

class _CommandKShortcutsState extends State<CommandKShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyJ) {
      widget.onOpen();
      return true; // consume the event so it doesn't bubble
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}