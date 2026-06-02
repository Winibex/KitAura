// lib/features/cv/controller/section_autofill.dart
//
// Fills CV text sections from the user's saved AiProfileModel — NO AI/API call.
// Extracts color/font/size attributes from the EXISTING template delta
// before replacing text, preserving template styling.

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

      // Single-line sections: extract from first op directly
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
  )
  {
    switch (type) {
      case SectionType.name:
        if (p.fullName.isEmpty) return null;
        return [_styledOp(p.fullName, styles.headingAttrs)];

      case SectionType.jobTitle:
        final jt = p.jobTitle ?? '';
        if (jt.isEmpty) return null;
        return [_styledOp(jt, styles.headingAttrs)];

      case SectionType.contact:
        final parts = <String>[];
        if (p.email.isNotEmpty) parts.add(p.email);
        if (p.phone.isNotEmpty) parts.add(p.phone);
        if (p.location.isNotEmpty) parts.add(p.location);
        if ((p.linkedIn ?? '').isNotEmpty) parts.add(p.linkedIn!);
        if ((p.website ?? '').isNotEmpty) parts.add(p.website!);
        if (parts.isEmpty) return null;
        return [_styledOp(parts.join('  |  '), styles.bodyAttrs)];

      case SectionType.summary:
        if ((p.jobTitle ?? '').isEmpty && p.industry.isEmpty) return null;
        final bits = <String>[];
        if ((p.jobTitle ?? '').isNotEmpty) bits.add(p.jobTitle!);
        if (p.industry.isNotEmpty) bits.add('in ${p.industry}');
        final lead = bits.isEmpty ? 'Professional' : bits.join(' ');
        return [
          _styledOp('SUMMARY', styles.headingAttrs, forceBold: true),
          _styledOp(
            '$lead with a track record of delivering results.',
            styles.bodyAttrs,
          ),
        ];

      case SectionType.experience:
        if (p.experiences.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('EXPERIENCE', styles.headingAttrs, forceBold: true),
        ];
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
              '| ${s.isNotEmpty ? s : ''}${(s.isNotEmpty &&
                  (end.isNotEmpty || isCur)) ? ' – ' : ''}${isCur
                  ? 'Present'
                  : end}',
          ].join(' ');
          if (header
              .trim()
              .isNotEmpty) {
            ops.add(_styledOp(header, styles.titleAttrs, forceBold: true));
          }
          if (desc.isNotEmpty){
            for (final line in desc.split('\n')) {
              if (line
                  .trim()
                  .isEmpty) {
                continue;
              }
              ops.add(
                _styledOp(
                  line.trim().startsWith('•')
                      ? line.trim()
                      : '• ${line.trim()}',
                  styles.bodyAttrs,
                ),
              );
            }
        }
          ops.add(_styledOp('', styles.bodyAttrs));
        }
        return ops;

      case SectionType.education:
        if (p.education.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('EDUCATION', styles.headingAttrs, forceBold: true),
        ];
        for (final e in p.education) {
          final m = _entryToMap(e);
          final d = _str(m, ['degree', 'qualification', 'program', 'title']);
          final s = _str(m, ['school', 'institution', 'university', 'college']);
          final st = _str(m, ['startDate', 'start', 'from']);
          final en = _str(m, ['endDate', 'end', 'to']);
          final line = [
            if (d.isNotEmpty) d,
            if (s.isNotEmpty) '— $s',
            if (st.isNotEmpty || en.isNotEmpty)
              '| ${st.isNotEmpty ? st : ''}${(st.isNotEmpty && en.isNotEmpty) ? ' – ' : ''}${en.isNotEmpty ? en : ''}',
          ].join(' ');
          if (line.trim().isNotEmpty) {
            ops.add(_styledOp(line, styles.titleAttrs, forceBold: true));
          }
        }
        return ops;

      case SectionType.skills:
        if (p.skills.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('SKILLS', styles.headingAttrs, forceBold: true),
        ];
        for (final skill in p.skills) {
          ops.add(_styledOp('• $skill', styles.bodyAttrs));
        }
        return ops;

      case SectionType.certifications:
        if (p.certifications.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('CERTIFICATIONS', styles.headingAttrs, forceBold: true),
        ];
        for (final cert in p.certifications) {
          if (cert.name.isEmpty) continue;
          final parts = <String>[cert.name];
          if ((cert.institute ?? '').isNotEmpty) {
            parts.add('by ${cert.institute}');
          }
          ops.add(_styledOp('• ${parts.join(' ')}', styles.bodyAttrs));
        }
        return ops;

      case SectionType.languages:
        if (p.languages.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('LANGUAGES', styles.headingAttrs, forceBold: true),
        ];
        for (final l in p.languages) {
          final m = _entryToMap(l);
          final name = _str(m, ['name', 'language']);
          final level = _str(m, ['level', 'proficiency', 'fluency']);
          final line = level.isNotEmpty ? '$name — $level' : name;
          if (line.trim().isNotEmpty) {
            ops.add(_styledOp(line, styles.bodyAttrs));
          }
        }
        return ops;

      case SectionType.projects:
        if (p.projects.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('PROJECTS', styles.headingAttrs, forceBold: true),
        ];
        for (final proj in p.projects) {
          if (proj.name.isEmpty) continue;
          final header = <String>[proj.name];
          if (proj.startDate.isNotEmpty || proj.endDate.isNotEmpty) {
            header.add(
              '| ${proj.startDate}${proj.startDate.isNotEmpty && proj.endDate.isNotEmpty ? ' – ' : ''}${proj.endDate}',
            );
          }
          ops.add(
            _styledOp(header.join(' '), styles.titleAttrs, forceBold: true),
          );
          if (proj.description.isNotEmpty) {
            ops.add(_styledOp(proj.description, styles.bodyAttrs));
          }
          if (proj.techStack.isNotEmpty) {
            ops.add(
              _styledOp('Tech: ${proj.techStack.join(', ')}', styles.bodyAttrs),
            );
          }
          if (proj.url != null && proj.url!.isNotEmpty) {
            ops.add(_styledOp(proj.url!, styles.bodyAttrs));
          }
          ops.add(_styledOp('', styles.bodyAttrs));
        }
        return ops;

      case SectionType.awards:
        if (p.awards.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('AWARDS & HONORS', styles.headingAttrs, forceBold: true),
        ];
        for (final award in p.awards) {
          if (award.title.isEmpty) continue;
          final parts = <String>[award.title];
          if ((award.issuer ?? '').isNotEmpty) parts.add('— ${award.issuer}');
          if ((award.date ?? '').isNotEmpty) parts.add('| ${award.date}');
          ops.add(
            _styledOp(parts.join(' '), styles.titleAttrs, forceBold: true),
          );
          if ((award.description ?? '').isNotEmpty) {
            ops.add(_styledOp(award.description!, styles.bodyAttrs));
          }
        }
        return ops;

      case SectionType.volunteer:
        if (p.volunteerExperience.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp(
            'VOLUNTEER EXPERIENCE',
            styles.headingAttrs,
            forceBold: true,
          ),
        ];
        for (final vol in p.volunteerExperience) {
          if (vol.role.isEmpty) continue;
          final header = <String>[vol.role];
          if (vol.organization.isNotEmpty) header.add('— ${vol.organization}');
          if (vol.startDate.isNotEmpty || vol.endDate.isNotEmpty) {
            header.add(
              '| ${vol.startDate}${vol.startDate.isNotEmpty && vol.endDate.isNotEmpty ? ' – ' : ''}${vol.endDate}',
            );
          }
          ops.add(
            _styledOp(header.join(' '), styles.titleAttrs, forceBold: true),
          );
          if (vol.description.isNotEmpty) {
            ops.add(_styledOp(vol.description, styles.bodyAttrs));
          }
          ops.add(_styledOp('', styles.bodyAttrs));
        }
        return ops;

      case SectionType.references:
        if (p.references.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('REFERENCES', styles.headingAttrs, forceBold: true),
        ];
        for (final ref in p.references) {
          if (ref.name.isEmpty) continue;
          ops.add(_styledOp(ref.name, styles.titleAttrs, forceBold: true));
          final details = <String>[];
          if ((ref.relationship ?? '').isNotEmpty) {
            details.add(ref.relationship!);
          }
          if ((ref.company ?? '').isNotEmpty) details.add(ref.company!);
          if (details.isNotEmpty) {
            ops.add(_styledOp(details.join(' — '), styles.bodyAttrs));
          }
          final contact = <String>[];
          if ((ref.email ?? '').isNotEmpty) contact.add(ref.email!);
          if ((ref.phone ?? '').isNotEmpty) contact.add(ref.phone!);
          if (contact.isNotEmpty) {
            ops.add(_styledOp(contact.join('  |  '), styles.bodyAttrs));
          }
          ops.add(_styledOp('', styles.bodyAttrs));
        }
        return ops;

      case SectionType.hobbies:
        if (p.hobbies.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp(
            'HOBBIES & INTERESTS',
            styles.headingAttrs,
            forceBold: true,
          ),
        ];
        ops.add(_styledOp(p.hobbies.join(' • '), styles.bodyAttrs));
        return ops;

      case SectionType.socialLinks:
        if (p.socialLinks.isEmpty) return null;
        final ops = <Map<String, dynamic>>[
          _styledOp('SOCIAL LINKS', styles.headingAttrs, forceBold: true),
        ];
        for (final link in p.socialLinks.toDisplayList()) {
          ops.add(_styledOp(link, styles.bodyAttrs));
        }
        return ops;

      case SectionType.interests:
        if (p.hobbies.isEmpty) return null;
        return [
          _styledOp('INTERESTS', styles.headingAttrs, forceBold: true),
          _styledOp(p.hobbies.join(' • '), styles.bodyAttrs),
        ];

      case SectionType.senderAddress:
      case SectionType.recipientAddress:
      case SectionType.dateLine:
      case SectionType.salutation:
      case SectionType.coverLetterBody:
      case SectionType.closing:
      case SectionType.signature:
      // Cover letter sections — not autofillable from CV profile.
      // They get filled by AI Design or manually.
        return null;

      case SectionType.custom:
        return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static Map<String, dynamic> _styledOp(
    String text,
    Map<String, dynamic> templateAttrs, {
    bool forceBold = false,
  })
  {
    final attrs = Map<String, dynamic>.from(templateAttrs);
    if (forceBold) attrs['bold'] = true;
    final t = text.endsWith('\n') ? text : '$text\n';
    return attrs.isEmpty ? {'insert': t} : {'insert': t, 'attributes': attrs};
  }

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
