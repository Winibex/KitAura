// lib/features/cover_letter/data/cl_template_data.dart
//
// Cover letter template registry — same pattern as cv_template_data.dart.

import 'dart:convert';
import 'package:flutter/services.dart';

class ClTemplateInfo {
  final String id;
  final String label;
  final String category;
  final String assetPath;
  final bool isPremium;
  final int sortOrder;
  final String description;

  const ClTemplateInfo({
    required this.id,
    required this.label,
    required this.category,
    required this.assetPath,
    required this.sortOrder,
    required this.description,
    this.isPremium = false,
  });
}

class ClTemplateData {
  ClTemplateData._();

  static const List<ClTemplateInfo> templates = [
    ClTemplateInfo(
      id: 'cl_professional',
      label: 'Professional',
      category: 'professional',
      assetPath: 'assets/cl_templates/cl_professional.json',
      isPremium: false,
      sortOrder: 1,
      description: 'Traditional business letter format. Best for corporate, '
          'finance, legal, and conservative industries. ATS-friendly.',
    ),
    ClTemplateInfo(
      id: 'cl_modern',
      label: 'Modern',
      category: 'modern',
      assetPath: 'assets/cl_templates/cl_modern.json',
      isPremium: false,
      sortOrder: 2,
      description: 'Clean modern design with subtle blue accent. '
          'Best for tech, marketing, product roles. Balances ATS-friendliness '
          'with modern aesthetics.',
    ),
    ClTemplateInfo(
      id: 'cl_creative',
      label: 'Creative Bold',
      category: 'creative',
      assetPath: 'assets/cl_templates/cl_creative.json',
      isPremium: true,
      sortOrder: 3,
      description: 'Bold pink sidebar with striking typography. '
          'For creative directors, designers, artists, and agencies. '
          'Showcases personality and creative flair.',
    ),
    ClTemplateInfo(
      id: 'cl_executive',
      label: 'Executive',
      category: 'executive',
      assetPath: 'assets/cl_templates/cl_executive.json',
      isPremium: true,
      sortOrder: 4,
      description: 'Sophisticated formal letterhead with gold accent. '
          'For C-suite, VP, and senior leadership roles. '
          'Conveys authority and gravitas.',
    ),
    ClTemplateInfo(
      id: 'cl_tech',
      label: 'Tech Engineer',
      category: 'tech',
      assetPath: 'assets/cl_templates/cl_tech.json',
      isPremium: false,
      sortOrder: 5,
      description: 'Engineer-focused format with GitHub/portfolio prominence. '
          'Conversational tone perfect for software engineering, '
          'devops, and technical roles.',
    ),
  ];

  /// Returns metadata for a template by its ID.
  static ClTemplateInfo? getInfo(String templateId) {
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

  /// True if the given ID matches a known cover letter template.
  static bool isTemplateId(String id) =>
      templates.any((t) => t.id == id);

  /// Loads the JSON content of a template from assets.
  static Future<Map<String, dynamic>> loadTemplateJson(String templateId) async {
    final path = getAssetPath(templateId);
    if (path == null) {
      throw Exception('Unknown cover letter template: $templateId');
    }
    final jsonStr = await rootBundle.loadString(path);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// All unique categories for filter chips.
  static List<String> get categories {
    final set = <String>{'all'};
    for (final t in templates) {
      set.add(t.category);
    }
    return set.toList();
  }
}