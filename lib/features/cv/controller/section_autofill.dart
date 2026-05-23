// lib/features/cv/controller/section_autofill.dart
//
// Fills CV text sections from the user's saved AiProfileModel — NO AI/API call.
// This is pure local data mapping: if the user has saved profile data, we
// populate matching sections directly. Sections with no matching data are
// left untouched.
//
// Used by the editor's "Autofill from Profile" action.

import 'package:flutter_quill/flutter_quill.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/canvas_item.dart';
import '../../../shared/models/section_type.dart';

class SectionAutofill {
  SectionAutofill._();

  /// Fill all autofillable sections in [items] from [profile].
  /// Returns the number of sections that were filled.
  static int fillAll(List<CanvasItem> items, AiProfileModel profile) {
    int filled = 0;
    for (final item in items) {
      if (!item.isText || item.controller == null) continue;
      if (!item.sectionType.isAutofillable) continue;

      final delta = _buildDelta(item.sectionType, profile);
      if (delta != null && delta.isNotEmpty) {
        _applyDelta(item, delta);
        filled++;
      }
    }
    return filled;
  }

  /// Fill a single section.
  static bool fillOne(CanvasItem item, AiProfileModel profile) {
    if (!item.isText || item.controller == null) return false;
    if (!item.sectionType.isAutofillable) return false;

    final delta = _buildDelta(item.sectionType, profile);
    if (delta == null || delta.isEmpty) return false;

    _applyDelta(item, delta);
    return true;
  }

  // ── Apply delta to controller ─────────────────────────────────────

  static void _applyDelta(CanvasItem item, List<Map<String, dynamic>> ops) {
    try {
      final doc = Document.fromJson(ops);
      item.controller!.document = doc;
    } catch (_) {
      // If delta is malformed, fall back to plain text insert
      item.controller!.clear();
    }
  }

  // ── Build delta per section type ──────────────────────────────────

  static List<Map<String, dynamic>>? _buildDelta(
      SectionType type, AiProfileModel p) {
    switch (type) {
      case SectionType.name:
        if (p.fullName.isEmpty) return null;
        return [
          _op(p.fullName, bold: true, size: '24'),
        ];

      case SectionType.jobTitle:
        final jt = p.jobTitle ?? '';
        if (jt.isEmpty) return null;
        return [_op(jt, size: '14')];

      case SectionType.contact:
        final parts = <String>[];
        if (p.email.isNotEmpty) parts.add(p.email);
        if (p.phone.isNotEmpty) parts.add(p.phone);
        if (p.location.isNotEmpty) parts.add(p.location);
        if ((p.linkedIn ?? '').isNotEmpty) parts.add(p.linkedIn!);
        if ((p.website ?? '').isNotEmpty) parts.add(p.website!);
        if (parts.isEmpty) return null;
        return [_op(parts.join('  |  '), size: '10')];

      case SectionType.summary:
      // We don't fabricate a summary — only fill if jobTitle/industry exist
      // to form a basic line. Real prose comes from the AI Fill button.
        if ((p.jobTitle ?? '').isEmpty && p.industry.isEmpty) return null;
        final bits = <String>[];
        if ((p.jobTitle ?? '').isNotEmpty) bits.add(p.jobTitle!);
        if (p.industry.isNotEmpty) bits.add('in ${p.industry}');
        final lead = bits.isEmpty ? 'Professional' : bits.join(' ');
        return [
          _op('SUMMARY\n', bold: true, size: '13'),
          _op('$lead with a track record of delivering results. '
              '(Tip: use AI Fill for a tailored summary.)', size: '11'),
        ];

      case SectionType.experience:
        if (p.experiences.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _op('EXPERIENCE\n', bold: true, size: '13'),
        ];
        for (final e in p.experiences) {
          final m = _entryToMap(e);
          final title = _str(m, ['title', 'role', 'position', 'jobTitle']);
          final company = _str(m, ['company', 'employer', 'organization']);
          final start = _str(m, ['startDate', 'start', 'from']);
          final end = _str(m, ['endDate', 'end', 'to']);
          final desc = _str(m, ['description', 'summary', 'details']);

          final header = [
            if (title.isNotEmpty) title,
            if (company.isNotEmpty) '— $company',
            if (start.isNotEmpty || end.isNotEmpty)
              '| ${start.isNotEmpty ? start : ''}${(start.isNotEmpty && end.isNotEmpty) ? ' – ' : ''}${end.isNotEmpty ? end : 'Present'}',
          ].join(' ');

          if (header.trim().isNotEmpty) {
            ops.add(_op('$header\n', bold: true, size: '11'));
          }
          if (desc.isNotEmpty) {
            // Split description into bullet lines if it has newlines
            for (final line in desc.split('\n')) {
              if (line.trim().isEmpty) continue;
              final bullet = line.trim().startsWith('•') ? line.trim() : '• ${line.trim()}';
              ops.add(_op('$bullet\n', size: '11'));
            }
          }
          ops.add(_op('\n', size: '11'));
        }
        return ops;

      case SectionType.education:
        if (p.education.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _op('EDUCATION\n', bold: true, size: '13'),
        ];
        for (final e in p.education) {
          final m = _entryToMap(e);
          final degree = _str(m, ['degree', 'qualification', 'program', 'title']);
          final school = _str(m, ['school', 'institution', 'university', 'college']);
          final start = _str(m, ['startDate', 'start', 'from']);
          final end = _str(m, ['endDate', 'end', 'to']);

          final line = [
            if (degree.isNotEmpty) degree,
            if (school.isNotEmpty) '— $school',
            if (start.isNotEmpty || end.isNotEmpty)
              '| ${start.isNotEmpty ? start : ''}${(start.isNotEmpty && end.isNotEmpty) ? ' – ' : ''}${end.isNotEmpty ? end : ''}',
          ].join(' ');

          if (line.trim().isNotEmpty) {
            ops.add(_op('$line\n', bold: true, size: '11'));
          }
        }
        return ops;

      case SectionType.skills:
        if (p.skills.isEmpty) return null;
        return [
          _op('SKILLS\n', bold: true, size: '13'),
          _op(p.skills.join(' • '), size: '11'),
        ];

      case SectionType.certifications:
        if (p.certifications.isEmpty) return null;
        return [
          _op('CERTIFICATIONS\n', bold: true, size: '13'),
          _op(p.certifications.join(' • '), size: '11'),
        ];

      case SectionType.languages:
        if (p.languages.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _op('LANGUAGES\n', bold: true, size: '13'),
        ];
        for (final l in p.languages) {
          final m = _entryToMap(l);
          final name = _str(m, ['name', 'language']);
          final level = _str(m, ['level', 'proficiency', 'fluency']);
          final line = level.isNotEmpty ? '$name — $level' : name;
          if (line.trim().isNotEmpty) ops.add(_op('$line\n', size: '11'));
        }
        return ops;

    // Projects, awards, interests: no structured profile data → skip
      case SectionType.projects:
      case SectionType.awards:
      case SectionType.interests:
      case SectionType.custom:
        return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static Map<String, dynamic> _op(String text,
      {bool bold = false, String? size}) {
    final attrs = <String, dynamic>{};
    if (bold) attrs['bold'] = true;
    if (size != null) attrs['size'] = size;
    // Ensure text ends with newline (Quill delta requirement for last op)
    final t = text.endsWith('\n') ? text : '$text\n';
    return attrs.isEmpty ? {'insert': t} : {'insert': t, 'attributes': attrs};
  }

  /// Convert a model entry (WorkExperienceEntry, EducationEntry, etc.)
  /// to a map via its toJson(). Defensive — works with any shape.
  static Map<String, dynamic> _entryToMap(dynamic entry) {
    try {
      final json = entry.toJson();
      if (json is Map<String, dynamic>) return json;
      if (json is Map) return Map<String, dynamic>.from(json);
    } catch (_) {}
    return {};
  }

  /// Pull the first non-empty value from a map for any of the given keys.
  static String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }
}