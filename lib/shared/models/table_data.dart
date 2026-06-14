// lib/shared/models/table_data.dart
//
// Data model for tableSection canvas items.
// Stores headers, rows, and styling. Plain text cells (no Quill).

import 'package:flutter/material.dart';

class TableData {
  List<String> headers;
  List<List<String>> rows;

  // Styling
  Color headerBgColor;
  Color headerTextColor;
  Color cellTextColor;
  Color borderColor;
  double fontSize;
  bool showHeader;

  TableData({
    required this.headers,
    required this.rows,
    this.headerBgColor = const Color(0xFF0F172A), // prussianBlue
    this.headerTextColor = const Color(0xFFFFFFFF),
    this.cellTextColor = const Color(0xFF333333),
    this.borderColor = const Color(0xFFE0E0E0),
    this.fontSize = 10,
    this.showHeader = true,
  });

  int get columnCount => headers.length;
  int get rowCount => rows.length;

  // ─── MUTATIONS ──────────────────────────────────────────────────

  void addRow() {
    rows.add(List.filled(columnCount, ''));
  }

  void removeRow(int index) {
    if (index >= 0 && index < rows.length) {
      rows.removeAt(index);
    }
  }

  void addColumn([String header = '']) {
    headers.add(header);
    for (final row in rows) {
      row.add('');
    }
  }

  void removeColumn(int index) {
    if (index >= 0 && index < headers.length && headers.length > 1) {
      headers.removeAt(index);
      for (final row in rows) {
        if (index < row.length) row.removeAt(index);
      }
    }
  }

  void setCell(int row, int col, String value) {
    if (row >= 0 && row < rows.length && col >= 0 && col < columnCount) {
      rows[row][col] = value;
    }
  }

  void setHeader(int col, String value) {
    if (col >= 0 && col < headers.length) {
      headers[col] = value;
    }
  }

  // ─── JSON ───────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'headers': headers,
    'rows': rows.map((r) => {'cells': List<String>.from(r)}).toList(),
    'headerBgColor': '#${headerBgColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'headerTextColor': '#${headerTextColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'cellTextColor': '#${cellTextColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'borderColor': '#${borderColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'fontSize': fontSize,
    'showHeader': showHeader,
  };

  factory TableData.fromJson(Map<String, dynamic> json) {
    return TableData(
      headers: List<String>.from(json['headers'] ?? []),
      rows: (json['rows'] as List?)?.map<List<String>>((r) {
        if (r is Map) {
          return List<String>.from((r['cells'] as List?) ?? const []);
        }
        return List<String>.from(r as List); // legacy List<List<String>> (assets)
      }).toList() ??
          [],
      headerBgColor: _parseColor(json['headerBgColor'], const Color(0xFF0F172A)),
      headerTextColor: _parseColor(json['headerTextColor'], const Color(0xFFFFFFFF)),
      cellTextColor: _parseColor(json['cellTextColor'], const Color(0xFF333333)),
      borderColor: _parseColor(json['borderColor'], const Color(0xFFE0E0E0)),
      fontSize: (json['fontSize'] ?? 10).toDouble(),
      showHeader: json['showHeader'] ?? true,
    );
  }

  TableData copyWith({
    List<String>? headers,
    List<List<String>>? rows,
    Color? headerBgColor,
    Color? headerTextColor,
    Color? cellTextColor,
    Color? borderColor,
    double? fontSize,
    bool? showHeader,
  }) {
    return TableData(
      headers: headers ?? List.from(this.headers),
      rows: rows ?? this.rows.map((r) => List<String>.from(r)).toList(),
      headerBgColor: headerBgColor ?? this.headerBgColor,
      headerTextColor: headerTextColor ?? this.headerTextColor,
      cellTextColor: cellTextColor ?? this.cellTextColor,
      borderColor: borderColor ?? this.borderColor,
      fontSize: fontSize ?? this.fontSize,
      showHeader: showHeader ?? this.showHeader,
    );
  }

  // ─── FACTORY PRESETS ────────────────────────────────────────────

  /// Pricing table preset (Item | Description | Amount)
  factory TableData.pricing() => TableData(
    headers: ['Item', 'Description', 'Amount'],
    rows: [
      ['Service Item 1', 'Description of deliverable', '\$0.00'],
      ['Service Item 2', 'Description of deliverable', '\$0.00'],
      ['Service Item 3', 'Description of deliverable', '\$0.00'],
      ['Total', '', '\$0.00'],
    ],
  );

  /// Deliverables table preset (Deliverable | Description | Timeline)
  factory TableData.deliverables() => TableData(
    headers: ['Deliverable', 'Description', 'Timeline'],
    rows: [
      ['Deliverable 1', 'Detailed description', 'Week 1-2'],
      ['Deliverable 2', 'Detailed description', 'Week 3-4'],
      ['Deliverable 3', 'Detailed description', 'Week 5-6'],
    ],
  );

  /// Milestones table preset (Milestone | Date | Status)
  factory TableData.milestones() => TableData(
    headers: ['Milestone', 'Date', 'Status'],
    rows: [
      ['Project Kickoff', 'TBD', 'Pending'],
      ['Phase 1 Complete', 'TBD', 'Pending'],
      ['Review & Feedback', 'TBD', 'Pending'],
      ['Final Delivery', 'TBD', 'Pending'],
    ],
  );

  /// Generic empty table
  factory TableData.empty({int cols = 3, int rows = 3}) => TableData(
    headers: List.generate(cols, (i) => 'Column ${i + 1}'),
    rows: List.generate(rows, (_) => List.filled(cols, '')),
  );

  // ─── HELPERS ────────────────────────────────────────────────────

  static Color _parseColor(dynamic value, Color fallback) {
    if (value == null) return fallback;
    final hex = value.toString().replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return fallback;
  }
}