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
      description: 'Technical project-focused layout with sections for '
          'objectives, deliverables, milestones, and budget breakdown. '
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
      id: 'prop_creative',
      label: 'Creative Proposal',
      category: 'creative',
      assetPath: 'assets/prop_templates/prop_creative.json',
      isPremium: true,
      sortOrder: 4,
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
      sortOrder: 5,
      description: 'Premium dark-themed layout with gold accents. '
          'Designed for C-suite presentations, enterprise deals, and '
          'high-value engagements. Conveys authority and professionalism.',
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
}