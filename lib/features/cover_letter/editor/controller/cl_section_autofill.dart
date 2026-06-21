// lib/features/cover_letter/editor/controller/cl_section_autofill.dart
//
// Fills cover letter text sections from the user's saved AiProfileModel.
// NO AI/API call — purely local mapping.
//
// Handles CL-specific section types:
//   senderAddress, dateLine, salutation, closing, signature
//
// recipientAddress and coverLetterBody are LEFT as template placeholders
// (user fills recipient manually, AI Compose generates body).
//
// CRITICAL: Newlines (\n) must NEVER carry inline attributes.

import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import '../../../../shared/models/ai_profile_model.dart';
import '../../../../shared/models/canvas_item.dart';
import '../../../../shared/models/section_type.dart';

class ClSectionAutofill {
  ClSectionAutofill._();

  /// Fills all autofillable CL sections. Returns count of sections filled.
  static int fillAll(List<CanvasItem> items, AiProfileModel profile) {
    int filled = 0;
    for (final item in items) {
      if (!item.isText || item.controller == null) continue;
      if (!_isClAutofillable(item.sectionType)) continue;

      final styles = _extractFirstOpStyle(item.controller!.document);
      final delta = _buildDelta(item.sectionType, profile, styles);
      if (delta != null && delta.isNotEmpty) {
        _applyDelta(item, delta);
        filled++;
      }
    }
    return filled;
  }

  static bool _isClAutofillable(SectionType type) {
    return const {
      SectionType.senderAddress,
      SectionType.dateLine,
      SectionType.salutation,
      SectionType.closing,
      SectionType.signature,
      // recipientAddress → user fills manually
      // coverLetterBody → AI Compose generates
    }.contains(type);
  }

  // ── Style extraction ──────────────────────────────────────────────

  static _Styles _extractFirstOpStyle(Document doc) {
    final ops = doc.toDelta().toJson();
    Map<String, dynamic> bold = {};
    Map<String, dynamic> normal = {};

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String || insert.trim().isEmpty) continue;
      final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
      if (attrs.isEmpty) continue;

      if (attrs['bold'] == true && bold.isEmpty) {
        bold = Map.from(attrs);
      } else if (attrs['bold'] != true && normal.isEmpty) {
        normal = Map.from(attrs);
      }
      if (bold.isNotEmpty && normal.isNotEmpty) break;
    }

    if (normal.isEmpty && bold.isNotEmpty) {
      normal = Map.from(bold);
      normal.remove('bold');
    }
    if (bold.isEmpty && normal.isNotEmpty) {
      bold = Map.from(normal);
      bold['bold'] = true;
    }

    return _Styles(boldAttrs: bold, normalAttrs: normal);
  }

  static void _applyDelta(CanvasItem item, List<Map<String, dynamic>> ops) {
    try {
      item.controller!.document = Document.fromJson(ops);
    } catch (_) {
      item.controller!.clear();
    }
  }

  // ── Build delta per CL section type ───────────────────────────────

  static List<Map<String, dynamic>>? _buildDelta(
      SectionType type,
      AiProfileModel p,
      _Styles styles,
      ) {
    switch (type) {
      case SectionType.senderAddress:
        if (p.fullName.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line(p.fullName, styles.boldAttrs, bold: true));
        if (p.location.isNotEmpty) {
          ops.addAll(_line(p.location, styles.normalAttrs));
        }
        final contact = <String>[];
        if (p.email.isNotEmpty) contact.add(p.email);
        if (p.phone.isNotEmpty) contact.add(p.phone);
        if (contact.isNotEmpty) {
          ops.addAll(_line(contact.join('  |  '), styles.normalAttrs));
        }
        if ((p.linkedIn ?? '').isNotEmpty) {
          ops.addAll(_line(p.linkedIn!, styles.normalAttrs));
        }
        return ops;

      case SectionType.dateLine:
        final now = DateTime.now();
        final formatted = DateFormat('MMMM d, yyyy').format(now);
        return _line(formatted, styles.normalAttrs);

      case SectionType.salutation:
        return _line('Dear Hiring Manager,', styles.normalAttrs);

      case SectionType.closing:
        return _line('Sincerely,', styles.normalAttrs);

      case SectionType.signature:
        if (p.fullName.isEmpty) return null;
        return _line(p.fullName, styles.boldAttrs, bold: true);

    // These are NOT autofilled — user/AI Composes them
      case SectionType.recipientAddress:
      case SectionType.coverLetterBody:
        return null;

      default:
        return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _line(
      String text,
      Map<String, dynamic> attrs, {
        bool bold = false,
      }) {
    final a = Map<String, dynamic>.from(attrs);
    if (bold) a['bold'] = true;
    if (text.isEmpty) {
      return [{'insert': '\n'}];
    }
    return [
      {'insert': text, 'attributes': a},
      {'insert': '\n'},
    ];
  }
}

class _Styles {
  final Map<String, dynamic> boldAttrs;
  final Map<String, dynamic> normalAttrs;
  const _Styles({this.boldAttrs = const {}, this.normalAttrs = const {}});
}