// lib/features/cv/editor/controller/section_autofill.dart
//
// Fills CV text sections from the user's saved AiProfileModel — NO AI/API call.
// Extracts color/font/size attributes from the EXISTING template delta
// before replacing text, preserving template styling.
//
// CRITICAL: Newlines (\n) must NEVER carry inline attributes.
// flutter_quill asserts `after.isPlain` on newline ops.

import 'package:flutter_quill/flutter_quill.dart';
import '../../../../shared/models/ai_profile_model.dart';
import '../../../../shared/models/canvas_item.dart';
import '../../../../shared/models/section_type.dart';

class SectionAutofill {
  SectionAutofill._();

  static int fillAll(List<CanvasItem> items, AiProfileModel profile) {
    int filled = 0;
    for (final item in items) {
      if (!item.isText || item.controller == null) continue;
      if (!item.sectionType.isAutofillable) continue;

      final _TemplateStyles styles;
      if (item.sectionType == SectionType.name ||
          item.sectionType == SectionType.jobTitle ||
          item.sectionType == SectionType.contact) {
        styles = _extractFirstOpStyle(item.controller!.document);
      } else {
        styles = _extractTemplateStyles(item.controller!.document);
      }

      final delta = _buildDelta(item.sectionType, profile, styles);
      if (delta != null && delta.isNotEmpty) {
        _applyDelta(item, delta);
        filled++;
      }
    }
    return filled;
  }

  static bool fillOne(CanvasItem item, AiProfileModel profile) {
    if (!item.isText || item.controller == null) return false;
    if (!item.sectionType.isAutofillable) return false;

    final _TemplateStyles styles;
    if (item.sectionType == SectionType.name ||
        item.sectionType == SectionType.jobTitle ||
        item.sectionType == SectionType.contact) {
      styles = _extractFirstOpStyle(item.controller!.document);
    } else {
      styles = _extractTemplateStyles(item.controller!.document);
    }

    final delta = _buildDelta(item.sectionType, profile, styles);
    if (delta == null || delta.isEmpty) return false;
    _applyDelta(item, delta);
    return true;
  }

  // ── Style extraction ──────────────────────────────────────────────

  static _TemplateStyles _extractFirstOpStyle(Document doc) {
    final ops = doc.toDelta().toJson();
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String || insert.trim().isEmpty) continue;
      final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
      return _TemplateStyles(
        headingAttrs: attrs,
        titleAttrs: attrs,
        bodyAttrs: attrs,
      );
    }
    return const _TemplateStyles();
  }

  static _TemplateStyles _extractTemplateStyles(Document doc) {
    final ops = doc.toDelta().toJson();
    Map<String, dynamic> heading = {}, title = {}, body = {};
    bool fH = false, fT = false, fB = false;

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String || insert.trim().isEmpty) continue;
      final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
      if (attrs.isEmpty) continue;
      final isBold = attrs['bold'] == true;

      if (isBold && !fH) {
        heading = Map.from(attrs);
        fH = true;
      } else if (isBold && !fT) {
        title = Map.from(attrs);
        fT = true;
      } else if (!isBold && !fB && insert.trim().length > 3) {
        body = Map.from(attrs);
        fB = true;
      }
      if (fH && fT && fB) break;
    }

    if (!fT) title = Map.from(heading);
    if (!fB) {
      body = Map.from(title);
      body.remove('bold');
    }

    return _TemplateStyles(
      headingAttrs: heading,
      titleAttrs: title,
      bodyAttrs: body,
    );
  }

  static void _applyDelta(CanvasItem item, List<Map<String, dynamic>> ops) {
    try {
      item.controller!.document = Document.fromJson(ops);
    } catch (_) {
      item.controller!.clear();
    }
  }

  // ── Build delta per section type ──────────────────────────────────

  static List<Map<String, dynamic>>? _buildDelta(
    SectionType type,
    AiProfileModel p,
    _TemplateStyles styles,
  ) {
    switch (type) {
      case SectionType.name:
        if (p.fullName.isEmpty) return null;
        return _line(p.fullName, styles.headingAttrs);

      case SectionType.jobTitle:
        final jt = p.jobTitle ?? '';
        if (jt.isEmpty) return null;
        return _line(jt, styles.headingAttrs);

      case SectionType.contact:
        final parts = <String>[];
        if (p.email.isNotEmpty) parts.add(p.email);
        if (p.phone.isNotEmpty) parts.add(p.phone);
        if (p.location.isNotEmpty) parts.add(p.location);
        if ((p.linkedIn ?? '').isNotEmpty) parts.add(p.linkedIn!);
        if ((p.website ?? '').isNotEmpty) parts.add(p.website!);
        if (parts.isEmpty) return null;
        return _line(parts.join('  |  '), styles.bodyAttrs);

      case SectionType.summary:
        if ((p.jobTitle ?? '').isEmpty && p.industry.isEmpty) return null;
        final bits = <String>[];
        if ((p.jobTitle ?? '').isNotEmpty) bits.add(p.jobTitle!);
        if (p.industry.isNotEmpty) bits.add('in ${p.industry}');
        final lead = bits.isEmpty ? 'Professional' : bits.join(' ');
        return [
          ..._line('SUMMARY', styles.headingAttrs, bold: true),
          ..._line(
            '$lead with a track record of delivering results.',
            styles.bodyAttrs,
          ),
        ];

      case SectionType.experience:
        if (p.experiences.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('EXPERIENCE', styles.headingAttrs, bold: true));
        for (final e in p.experiences) {
          final m = _entryToMap(e);
          final t = _str(m, ['title', 'role', 'position', 'jobTitle']);
          final c = _str(m, ['company', 'employer', 'organization']);
          final s = _str(m, ['startDate', 'start', 'from']);
          final end = _str(m, ['endDate', 'end', 'to']);
          final isCur = m['isCurrentRole'] == true;
          final desc = _str(m, ['description', 'summary', 'details']);
          final header = [
            if (t.isNotEmpty) t,
            if (c.isNotEmpty) '— $c',
            if (s.isNotEmpty || end.isNotEmpty)
              '| ${s.isNotEmpty ? s : ''}${(s.isNotEmpty && (end.isNotEmpty || isCur)) ? ' – ' : ''}${isCur ? 'Present' : end}',
          ].join(' ');
          if (header.trim().isNotEmpty) {
            ops.addAll(_line(header, styles.titleAttrs, bold: true));
          }
          if (desc.isNotEmpty) {
            for (final dl in desc.split('\n')) {
              if (dl.trim().isEmpty) continue;
              final bullet = dl.trim().startsWith('•')
                  ? dl.trim()
                  : '• ${dl.trim()}';
              ops.addAll(_line(bullet, styles.bodyAttrs));
            }
          }
          ops.addAll(_emptyLine());
        }
        return ops;

      case SectionType.education:
        if (p.education.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('EDUCATION', styles.headingAttrs, bold: true));
        for (final e in p.education) {
          final m = _entryToMap(e);
          final d = _str(m, ['degree', 'qualification', 'program', 'title']);
          final s = _str(m, ['school', 'institution', 'university', 'college']);
          final st = _str(m, ['startDate', 'start', 'from']);
          final en = _str(m, ['endDate', 'end', 'to']);
          final text = [
            if (d.isNotEmpty) d,
            if (s.isNotEmpty) '— $s',
            if (st.isNotEmpty || en.isNotEmpty)
              '| ${st.isNotEmpty ? st : ''}${(st.isNotEmpty && en.isNotEmpty) ? ' – ' : ''}${en.isNotEmpty ? en : ''}',
          ].join(' ');
          if (text.trim().isNotEmpty) {
            ops.addAll(_line(text, styles.titleAttrs, bold: true));
          }
        }
        return ops;

      case SectionType.skills:
        if (p.skills.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('SKILLS', styles.headingAttrs, bold: true));
        for (final skill in p.skills) {
          ops.addAll(_line('• $skill', styles.bodyAttrs));
        }
        return ops;

      case SectionType.certifications:
        if (p.certifications.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('CERTIFICATIONS', styles.headingAttrs, bold: true));
        for (final cert in p.certifications) {
          if (cert.name.isEmpty) continue;
          final parts = <String>[cert.name];
          if ((cert.institute ?? '').isNotEmpty) {
            parts.add('by ${cert.institute}');
          }
          ops.addAll(_line('• ${parts.join(' ')}', styles.bodyAttrs));
        }
        return ops;

      case SectionType.languages:
        if (p.languages.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('LANGUAGES', styles.headingAttrs, bold: true));
        for (final l in p.languages) {
          final m = _entryToMap(l);
          final name = _str(m, ['name', 'language']);
          final level = _str(m, ['level', 'proficiency', 'fluency']);
          final text = level.isNotEmpty ? '$name — $level' : name;
          if (text.trim().isNotEmpty) ops.addAll(_line(text, styles.bodyAttrs));
        }
        return ops;

      case SectionType.projects:
        if (p.projects.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('PROJECTS', styles.headingAttrs, bold: true));
        for (final proj in p.projects) {
          if (proj.name.isEmpty) continue;
          final header = <String>[proj.name];
          if (proj.startDate.isNotEmpty || proj.endDate.isNotEmpty) {
            header.add(
              '| ${proj.startDate}${proj.startDate.isNotEmpty && proj.endDate.isNotEmpty ? ' – ' : ''}${proj.endDate}',
            );
          }
          ops.addAll(_line(header.join(' '), styles.titleAttrs, bold: true));
          if (proj.description.isNotEmpty) {
            ops.addAll(_line(proj.description, styles.bodyAttrs));
          }
          if (proj.techStack.isNotEmpty) {
            ops.addAll(
              _line('Tech: ${proj.techStack.join(', ')}', styles.bodyAttrs),
            );
          }
          if (proj.url != null && proj.url!.isNotEmpty) {
            ops.addAll(_line(proj.url!, styles.bodyAttrs));
          }
          ops.addAll(_emptyLine());
        }
        return ops;

      case SectionType.awards:
        if (p.awards.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('AWARDS & HONORS', styles.headingAttrs, bold: true));
        for (final award in p.awards) {
          if (award.title.isEmpty) continue;
          final parts = <String>[award.title];
          if ((award.issuer ?? '').isNotEmpty) parts.add('— ${award.issuer}');
          if ((award.date ?? '').isNotEmpty) parts.add('| ${award.date}');
          ops.addAll(_line(parts.join(' '), styles.titleAttrs, bold: true));
          if ((award.description ?? '').isNotEmpty) {
            ops.addAll(_line(award.description!, styles.bodyAttrs));
          }
        }
        return ops;

      case SectionType.volunteer:
        if (p.volunteerExperience.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(
          _line('VOLUNTEER EXPERIENCE', styles.headingAttrs, bold: true),
        );
        for (final vol in p.volunteerExperience) {
          if (vol.role.isEmpty) continue;
          final header = <String>[vol.role];
          if (vol.organization.isNotEmpty) header.add('— ${vol.organization}');
          if (vol.startDate.isNotEmpty || vol.endDate.isNotEmpty) {
            header.add(
              '| ${vol.startDate}${vol.startDate.isNotEmpty && vol.endDate.isNotEmpty ? ' – ' : ''}${vol.endDate}',
            );
          }
          ops.addAll(_line(header.join(' '), styles.titleAttrs, bold: true));
          if (vol.description.isNotEmpty) {
            ops.addAll(_line(vol.description, styles.bodyAttrs));
          }
          ops.addAll(_emptyLine());
        }
        return ops;

      case SectionType.references:
        if (p.references.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('REFERENCES', styles.headingAttrs, bold: true));
        for (final ref in p.references) {
          if (ref.name.isEmpty) continue;
          ops.addAll(_line(ref.name, styles.titleAttrs, bold: true));
          final details = <String>[];
          if ((ref.relationship ?? '').isNotEmpty) {
            details.add(ref.relationship!);
          }
          if ((ref.company ?? '').isNotEmpty) details.add(ref.company!);
          if (details.isNotEmpty) {
            ops.addAll(_line(details.join(' — '), styles.bodyAttrs));
          }
          final contact = <String>[];
          if ((ref.email ?? '').isNotEmpty) contact.add(ref.email!);
          if ((ref.phone ?? '').isNotEmpty) contact.add(ref.phone!);
          if (contact.isNotEmpty) {
            ops.addAll(_line(contact.join('  |  '), styles.bodyAttrs));
          }
          ops.addAll(_emptyLine());
        }
        return ops;

      case SectionType.hobbies:
        if (p.hobbies.isEmpty) return null;
        return [
          ..._line('HOBBIES & INTERESTS', styles.headingAttrs, bold: true),
          ..._line(p.hobbies.join(' • '), styles.bodyAttrs),
        ];

      case SectionType.socialLinks:
        if (p.socialLinks.isEmpty) return null;
        final ops = <Map<String, dynamic>>[];
        ops.addAll(_line('SOCIAL LINKS', styles.headingAttrs, bold: true));
        for (final link in p.socialLinks.toDisplayList()) {
          ops.addAll(_line(link, styles.bodyAttrs));
        }
        return ops;

      case SectionType.interests:
        if (p.hobbies.isEmpty) return null;
        return [
          ..._line('INTERESTS', styles.headingAttrs, bold: true),
          ..._line(p.hobbies.join(' • '), styles.bodyAttrs),
        ];

      case SectionType.senderAddress:
      case SectionType.recipientAddress:
      case SectionType.dateLine:
      case SectionType.salutation:
      case SectionType.coverLetterBody:
      case SectionType.closing:
      case SectionType.signature:
        return null;

      case SectionType.custom:
        return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Creates ops for one styled line + a PLAIN newline.
  /// Quill requires \n ops to have NO inline attributes.
  static List<Map<String, dynamic>> _line(
    String text,
    Map<String, dynamic> attrs, {
    bool bold = false,
  }) {
    final a = Map<String, dynamic>.from(attrs);
    if (bold) a['bold'] = true;
    if (text.isEmpty) {
      return [
        {'insert': '\n'},
      ];
    }
    return [
      {'insert': text, 'attributes': a},
      {'insert': '\n'},
    ];
  }

  /// Empty line — just a plain newline for spacing.
  static List<Map<String, dynamic>> _emptyLine() => [
    {'insert': '\n'},
  ];

  static Map<String, dynamic> _entryToMap(dynamic entry) {
    try {
      final json = entry.toJson();
      if (json is Map<String, dynamic>) return json;
      if (json is Map) return Map<String, dynamic>.from(json);
    } catch (_) {}
    return {};
  }

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

class _TemplateStyles {
  final Map<String, dynamic> headingAttrs;
  final Map<String, dynamic> titleAttrs;
  final Map<String, dynamic> bodyAttrs;
  const _TemplateStyles({
    this.headingAttrs = const {},
    this.titleAttrs = const {},
    this.bodyAttrs = const {},
  });
}
