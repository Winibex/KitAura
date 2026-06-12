// lib/shared/canvas/engine/table_editor_dialog.dart
//
// Modal dialog for editing a tableSection's data.
// Opened on double-tap of a tableSection on canvas.
// Supports: edit cells, edit headers, add/remove rows/columns, styling.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../models/table_data.dart';

class TableEditorDialog extends StatefulWidget {
  final TableData initialData;
  final String title;

  const TableEditorDialog({
    super.key,
    required this.initialData,
    this.title = 'Edit Table',
  });

  /// Shows the dialog and returns the edited TableData, or null if cancelled.
  static Future<TableData?> show(
      BuildContext context, {
        required TableData initialData,
        String title = 'Edit Table',
      }) {
    return showDialog<TableData>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => TableEditorDialog(
        initialData: initialData,
        title: title,
      ),
    );
  }

  @override
  State<TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends State<TableEditorDialog> {
  late TableData _data;

  // Controllers for all cells — rebuilt on structural changes
  List<TextEditingController> _headerControllers = [];
  List<List<TextEditingController>> _cellControllers = [];

  @override
  void initState() {
    super.initState();
    _data = widget.initialData.copyWith();
    _buildControllers();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _buildControllers() {
    _disposeControllers();
    _headerControllers = _data.headers
        .map((h) => TextEditingController(text: h))
        .toList();
    _cellControllers = _data.rows
        .map((row) => row.map((c) => TextEditingController(text: c)).toList())
        .toList();
  }

  void _disposeControllers() {
    for (final c in _headerControllers) {
      c.dispose();
    }
    for (final row in _cellControllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    _headerControllers = [];
    _cellControllers = [];
  }

  void _syncDataFromControllers() {
    for (int i = 0; i < _headerControllers.length; i++) {
      _data.headers[i] = _headerControllers[i].text;
    }
    for (int r = 0; r < _cellControllers.length; r++) {
      for (int c = 0; c < _cellControllers[r].length; c++) {
        _data.rows[r][c] = _cellControllers[r][c].text;
      }
    }
  }

  void _addRow() {
    _syncDataFromControllers();
    setState(() {
      _data.addRow();
      _buildControllers();
    });
  }

  void _removeRow(int index) {
    if (_data.rowCount <= 1) return;
    _syncDataFromControllers();
    setState(() {
      _data.removeRow(index);
      _buildControllers();
    });
  }

  void _addColumn() {
    _syncDataFromControllers();
    setState(() {
      _data.addColumn('New Column');
      _buildControllers();
    });
  }

  void _removeColumn(int index) {
    if (_data.columnCount <= 1) return;
    _syncDataFromControllers();
    setState(() {
      _data.removeColumn(index);
      _buildControllers();
    });
  }

  void _save() {
    _syncDataFromControllers();
    Navigator.of(context).pop(_data);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final dialogW = screenW < 700 ? screenW - 40 : 660.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: dialogW,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0EBE6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
                color: AppColors.prussianBlue,
              ),
            ),
          ),
          // Add column button
          _actionButton(
            icon: LucideIcons.columns,
            label: 'Column',
            onTap: _addColumn,
          ),
          const SizedBox(width: 8),
          // Add row button
          _actionButton(
            icon: LucideIcons.rows,
            label: 'Row',
            onTap: _addRow,
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F0EC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.x, size: 14, color: AppColors.slateGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.petalFrost,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.darkRaspberry),
              const SizedBox(width: 4),
              Text(
                '+ $label',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkRaspberry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CONTENT ───────────────────────────────────────────────────

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          if (_data.showHeader) ...[
            const Text(
              'HEADERS',
              style: TextStyle(
                fontSize: 10,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
                color: AppColors.slateGrey,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            _buildHeaderRow(),
            const SizedBox(height: 20),
          ],
          // Data rows
          const Text(
            'ROWS',
            style: TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.slateGrey,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._buildDataRows(),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        ...List.generate(_data.columnCount, (col) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: col < _data.columnCount - 1 ? 8 : 0),
              child: Stack(
                children: [
                  _cellInput(
                    controller: _headerControllers[col],
                    isHeader: true,
                  ),
                  if (_data.columnCount > 1)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: _removeButton(
                        onTap: () => _removeColumn(col),
                        tooltip: 'Remove column',
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(width: 32), // space for row delete buttons alignment
      ],
    );
  }

  List<Widget> _buildDataRows() {
    return List.generate(_data.rowCount, (row) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            ...List.generate(_data.columnCount, (col) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: col < _data.columnCount - 1 ? 8 : 0),
                  child: _cellInput(
                    controller: _cellControllers[row][col],
                    isHeader: false,
                  ),
                ),
              );
            }),
            const SizedBox(width: 4),
            _removeButton(
              onTap: _data.rowCount > 1 ? () => _removeRow(row) : null,
              tooltip: 'Remove row',
            ),
          ],
        ),
      );
    });
  }

  Widget _cellInput({
    required TextEditingController controller,
    required bool isHeader,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(
        fontSize: 12,
        fontFamily: AppFonts.openSans,
        fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
        color: AppColors.prussianBlue,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isHeader ? AppColors.darkRaspberry.withValues(alpha: 0.3) : AppColors.almondSilk,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isHeader ? AppColors.darkRaspberry.withValues(alpha: 0.3) : AppColors.almondSilk,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.darkRaspberry),
        ),
        filled: true,
        fillColor: isHeader ? AppColors.petalFrost.withValues(alpha: 0.5) : AppColors.white,
      ),
    );
  }

  Widget _removeButton({VoidCallback? onTap, String? tooltip}) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: enabled ? const Color(0xFFFEE2E2) : const Color(0xFFF5F0EC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              LucideIcons.trash2,
              size: 11,
              color: enabled ? const Color(0xFFDC2626) : AppColors.almondSilk,
            ),
          ),
        ),
      ),
    );
  }

  // ─── FOOTER ────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0EBE6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.almondSilk),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slateGrey,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _save,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.darkRaspberry,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Save Table',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}