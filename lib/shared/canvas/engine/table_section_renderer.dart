// lib/shared/canvas/engine/table_section_renderer.dart
//
// Renders a TableData as a styled table widget on the canvas.
// Read-only — editing is done via TableEditorDialog on double-tap.

import 'package:flutter/material.dart';
import '../../models/table_data.dart';

class TableSectionRenderer extends StatelessWidget {
  final TableData data;
  final double width;
  final double height;

  const TableSectionRenderer({
    super.key,
    required this.data,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (data.headers.isEmpty) {
      return _buildEmpty();
    }

    return SizedBox(
      width: width,
      height: height,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: _buildTable(),
      ),
    );
  }

  Widget _buildTable() {
    final colCount = data.columnCount;
    if (colCount == 0) return const SizedBox();

    // Calculate equal column widths
    final colWidths = <int, TableColumnWidth>{};
    for (int i = 0; i < colCount; i++) {
      colWidths[i] = const FlexColumnWidth();
    }

    final rows = <TableRow>[];

    // Header row
    if (data.showHeader) {
      rows.add(TableRow(
        decoration: BoxDecoration(color: data.headerBgColor),
        children: data.headers.map((h) {
          return _cell(
            h,
            style: TextStyle(
              color: data.headerTextColor,
              fontSize: data.fontSize,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          );
        }).toList(),
      ));
    }

    // Data rows
    for (int r = 0; r < data.rowCount; r++) {
      final isEven = r % 2 == 0;
      rows.add(TableRow(
        decoration: BoxDecoration(
          color: isEven ? Colors.white : const Color(0xFFF9F7F5),
        ),
        children: List.generate(colCount, (c) {
          final value = c < data.rows[r].length ? data.rows[r][c] : '';
          return _cell(
            value,
            style: TextStyle(
              color: data.cellTextColor,
              fontSize: data.fontSize,
              fontFamily: 'OpenSans',
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          );
        }),
      ));
    }

    return Table(
      border: TableBorder.all(color: data.borderColor, width: 0.5),
      columnWidths: colWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  Widget _cell(String text, {required TextStyle style, required EdgeInsets padding}) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: style,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        'Empty Table',
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 11,
          fontFamily: 'OpenSans',
        ),
      ),
    );
  }
}