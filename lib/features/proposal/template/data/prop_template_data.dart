// lib/features/proposal/template/data/prop_template_data.dart

import 'dart:convert';
import 'package:flutter/services.dart';

class PropTemplateInfo {
  final String id;
  final String label;
  final String category;
  final String assetPath;
  final bool isPremium;
  final int sortOrder;
  final String description;

  const PropTemplateInfo({
    required this.id,
    required this.label,
    required this.category,
    required this.assetPath,
    required this.sortOrder,
    required this.description,
    this.isPremium = false,
  });
}

class PropTemplateData {
  PropTemplateData._();

  static const List<PropTemplateInfo> templates = [
    PropTemplateInfo(
      id: 'prop_business',
      label: 'Business Proposal',
      category: 'business',
      assetPath: 'assets/prop_templates/prop_business.json',
      isPremium: false,
      sortOrder: 1,
      description: 'Clean corporate layout with structured sections for '
          'executive summary, scope of work, timeline, and pricing. '
          'Ideal for B2B proposals, consulting engagements, and partnerships.',
    ),
    PropTemplateInfo(
      id: 'prop_project',
      label: 'Project Proposal',
      category: 'project',
      assetPath: 'assets/prop_templates/prop_project.json',
      isPremium: false,
      sortOrder: 2,
      description: 'Technical project-focused layout with objectives, '
          'deliverables, milestones, and budget breakdown. '
          'Best for IT, engineering, and development projects.',
    ),
    PropTemplateInfo(
      id: 'prop_freelance',
      label: 'Freelance Proposal',
      category: 'freelance',
      assetPath: 'assets/prop_templates/prop_freelance.json',
      isPremium: false,
      sortOrder: 3,
      description: 'Personal-brand focused proposal for independent '
          'professionals. Highlights your expertise, process, and pricing. '
          'Perfect for designers, developers, writers, and consultants.',
    ),
    PropTemplateInfo(
      id: 'prop_product',
      label: 'Product Catalog',
      category: 'product',
      assetPath: 'assets/prop_templates/prop_product.json',
      isPremium: false,
      sortOrder: 4,
      description: 'Product quotation with detailed specs, quantities, '
          'unit pricing, and totals. Includes warranty and delivery terms. '
          'Ideal for manufacturers, distributors, and suppliers.',
    ),
    PropTemplateInfo(
      id: 'prop_service',
      label: 'Service Agreement',
      category: 'service',
      assetPath: 'assets/prop_templates/prop_service.json',
      isPremium: false,
      sortOrder: 5,
      description: 'Ongoing service contract with SLA tables, pricing tiers, '
          'and clear responsibilities. Perfect for maintenance, support, '
          'and managed service providers.',
    ),
    PropTemplateInfo(
      id: 'prop_creative',
      label: 'Creative Proposal',
      category: 'creative',
      assetPath: 'assets/prop_templates/prop_creative.json',
      isPremium: true,
      sortOrder: 6,
      description: 'Bold modern design with vibrant accents and striking '
          'typography. For agencies, creative studios, and marketing teams. '
          'Makes a memorable first impression.',
    ),
    PropTemplateInfo(
      id: 'prop_executive',
      label: 'Executive Proposal',
      category: 'executive',
      assetPath: 'assets/prop_templates/prop_executive.json',
      isPremium: true,
      sortOrder: 7,
      description: 'Premium dark-themed layout with gold accents. '
          'Designed for C-suite presentations, enterprise deals, and '
          'high-value engagements. Conveys authority and professionalism.',
    ),
    PropTemplateInfo(
      id: 'prop_sales',
      label: 'Sales Proposal',
      category: 'sales',
      assetPath: 'assets/prop_templates/prop_sales.json',
      isPremium: true,
      sortOrder: 8,
      description: 'Client-facing sales pitch with ROI analysis, social proof, '
          'and implementation timeline. Sidebar layout with bold CTA sections. '
          'Built to close deals.',
    ),
  ];

  static PropTemplateInfo? getInfo(String templateId) {
    try {
      return templates.firstWhere((t) => t.id == templateId);
    } catch (_) {
      return null;
    }
  }

  static String? getAssetPath(String templateId) =>
      getInfo(templateId)?.assetPath;

  static String? getDescription(String templateId) =>
      getInfo(templateId)?.description;

  static bool isTemplateId(String id) =>
      templates.any((t) => t.id == id);

  static Future<Map<String, dynamic>> loadTemplateJson(
      String templateId) async {
    final path = getAssetPath(templateId);
    if (path == null) {
      throw Exception('Unknown proposal template: $templateId');
    }
    final jsonStr = await rootBundle.loadString(path);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  static List<String> get categories {
    final set = <String>{'all'};
    for (final t in templates) {
      set.add(t.category);
    }
    return set.toList();
  }

  /// Maps an item's `title` (within a template) to a content shape hint that
  /// tells the AI exactly what structure to generate for that slot. Avoids
  /// the AI guessing from the title.
  ///
  /// Shapes:
  ///   - "prose"     → 1-2 short paragraphs as lines
  ///   - "phases"    → multiple entries with bold label + 1-line body
  ///   - "clauses"   → multiple entries (clause label + 1-line body), 4-7 max
  ///   - "bullets"   → one entry, each line starts with "• "
  ///   - "numbered"  → one entry, each line starts with "1. " etc.
  ///   - "oneLiner"  → single short sentence, no labels
  ///   - "titleLine" → bold project title line + muted subtitle line
  static const Map<String, Map<String, String>> contentShapes = {
    'prop_business': {
      'Executive Summary': 'prose',
      'Problem Statement': 'prose',
      'Proposed Solution': 'phases',
      'Terms':             'clauses',
    },
    'prop_project': {
      'Project Overview': 'prose',
      'Objectives':       'numbered',
      'Scope':            'bullets',
      'About Us':         'prose',
      'Contact':          'oneLiner',
    },
    'prop_service': {
      'Scope':                     'bullets',
      'Provider Responsibilities': 'bullets',
      'Client Responsibilities':   'bullets',
      'Terms':                     'bullets',
    },
    'prop_product': {
      'Specs':    'bullets',
      'Delivery': 'bullets',
      'Terms':    'bullets',
    },
    'prop_freelance': {
      'Project Title':  'titleLine',
      'Understanding':  'prose',
      'Approach':       'phases',
      'Payment Note':   'oneLiner',
      'Next Steps':     'numbered',
    },
    'prop_creative': {
      'Challenge':  'prose',
      'Vision':     'phases',       // intro + "Core concept" label/body
      'Strategy':   'phases',       // 01 Discover, 02 Create, 03 Launch
      'Why Us':     'prose',
    },
    'prop_executive': {
      'Executive Summary':  'prose',
      'Situation Analysis': 'phases',
      'Solution':           'phases',
      'Payment Terms':      'oneLiner',
      'Risk':               'clauses',
      'Credentials':        'prose',
      'Terms':              'bullets',
    },
    'prop_sales': {
      'Overview':   'prose',      // intro + "What sets us apart" + 3 differentiators
      'Social Proof': 'prose',
      'Guarantee':  'bullets',
      'Next Steps': 'numbered',
    },
  };

  /// Looks up the content shape for a given template + item title.
  /// Returns null if no shape is declared (AI uses default behavior).
  static String? getContentShape(String templateId, String itemTitle) {
    return contentShapes[templateId]?[itemTitle];
  }
}