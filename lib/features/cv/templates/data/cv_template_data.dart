// lib/features/cv_templates/data/cv_template_data.dart
//
// Thin registry for CV templates. All layout data lives in JSON files
// under assets/cv_templates/. This file only stores metadata (labels,
// categories, descriptions, asset paths) and provides load helpers.
//
// ASSET REGISTRATION — add to pubspec.yaml:
//   flutter:
//     assets:
//       - assets/cv_templates/

import 'dart:convert';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_assets.dart';

class CvTemplateData {
  CvTemplateData._();

  // ─── REGISTRY ─────────────────────────────────────────────────────────

  static const List<CvTemplateInfo> all = [
    CvTemplateInfo(
      id: 'classic_navy',
      label: 'Classic Navy',
      category: 'professional',
      assetPath: AppAssets.templateClassicNavy,
      isPremium: false,
      sortOrder: 1,
      description: 'A polished dark navy header with gold accents. '
          'Single-column layout with clear section hierarchy. '
          'Perfect for corporate and traditional industries.',
    ),
    CvTemplateInfo(
      id: 'two_column',
      label: 'Two Column',
      category: 'creative',
      assetPath: AppAssets.templateTwoColumn,
      isPremium: false,
      sortOrder: 2,
      description: 'Dark sidebar with contact and skills, white main area '
          'for experience and education. Red accent dividers. '
          'Great for designers and tech professionals.',
    ),
    CvTemplateInfo(
      id: 'minimal_clean',
      label: 'Minimal Clean',
      category: 'minimal',
      assetPath: AppAssets.templateMinimal,
      isPremium: false,
      sortOrder: 3,
      description: 'Clean white layout with green accent lines. '
          'Generous whitespace and elegant typography. '
          'Ideal for modern tech roles and startups.',
    ),
    CvTemplateInfo(
      id: 'executive_dark',
      label: 'Executive Dark',
      category: 'professional',
      assetPath: AppAssets.templateExecutiveDark,
      isPremium: true,
      sortOrder: 4,
      description: 'Premium dark background with gold typography. '
          'Designed for C-suite and senior leadership roles. '
          'Makes a powerful first impression.',
    ),
    CvTemplateInfo(
      id: 'modern_gradient',
      label: 'Modern Gradient',
      category: 'modern',
      assetPath: AppAssets.templateModernGradient,
      isPremium: true,
      sortOrder: 5,
      description: 'Eye-catching purple-to-blue gradient header. '
          'Contemporary layout for creative and design roles. '
          'Stands out from traditional CVs.',
    ),
    CvTemplateInfo(
      id: 'corporate_blue',
      label: 'Corporate Blue',
      category: 'professional',
      assetPath: AppAssets.templateCorporateBlue,
      isPremium: true,
      sortOrder: 6,
      description: 'Professional blue header with green accent. '
          'Clean corporate layout for project managers, '
          'consultants, and business professionals.',
    ),
    CvTemplateInfo(
      id: 'creative_bold',
      label: 'Creative Bold',
      category: 'creative',
      assetPath: AppAssets.templateCreativeBold,
      isPremium: true,
      sortOrder: 7,
      description: 'Bold pink sidebar with striking typography. '
          'For creative directors, designers, and artists. '
          'Showcases personality and creative flair.',
    ),
    CvTemplateInfo(
      id: 'ats_classic',
      label: 'ATS Classic',
      category: 'ats',
      assetPath: AppAssets.templateAtsClassic,
      isPremium: false,
      sortOrder: 8,
      description: 'Single-column, black-on-white layout with Arial font. '
          'Optimized for Applicant Tracking Systems used by Microsoft, Google, '
          'and most Fortune 500 companies. Maximum ATS pass-through rate.',
    ),
    CvTemplateInfo(
      id: 'ats_modern',
      label: 'ATS Modern',
      category: 'ats',
      assetPath: AppAssets.templateAtsModern,
      isPremium: false,
      sortOrder: 9,
      description: 'Clean ATS-friendly design with subtle blue accents and OpenSans font. '
          'Best for product managers, business roles, and consultants. '
          'LinkedIn-inspired layout that passes ATS while looking modern.',
    ),
    CvTemplateInfo(
      id: 'ats_tech',
      label: 'ATS Tech',
      category: 'ats',
      assetPath: AppAssets.templateAtsTech,
      isPremium: true,
      sortOrder: 10,
      description: 'FAANG-style template optimized for software engineers. '
          'Skills section positioned for keyword matching, compact header, '
          'and project showcase with GitHub stars and tech stack.',
    ),
    CvTemplateInfo(
      id: 'ats_executive',
      label: 'ATS Executive',
      category: 'ats',
      assetPath: AppAssets.templateAtsExecutive,
      isPremium: true,
      sortOrder: 11,
      description: 'Conservative ATS-perfect formatting for senior leadership roles. '
          'Includes board positions and speaking engagements sections. '
          'Best for C-suite, VP, and director-level executives.',
    ),
  ];

  // ─── LOOKUPS ──────────────────────────────────────────────────────────

  /// Get template info by ID. Returns null if not found.
  static CvTemplateInfo? getInfo(String id) {
    try {
      return all.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Check if a given ID is a registered template (not a Firestore doc ID).
  static bool isTemplateId(String id) => getInfo(id) != null || id == 'blank';

  /// Get the asset path for a template ID.
  static String? getAssetPath(String id) => getInfo(id)?.assetPath;

  /// Get description for a template ID.
  static String getDescription(String id) =>
      getInfo(id)?.description ?? 'A professional CV template.';

  /// Load full template JSON from the asset file. This is the primary way
  /// to get template data for the canvas editor and preview modal.
  static Future<Map<String, dynamic>> loadTemplateJson(String id) async {
    final info = getInfo(id);
    if (info == null) return _fallbackJson;

    try {
      final jsonStr = await rootBundle.loadString(info.assetPath);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return _fallbackJson;
    }
  }

  /// Load template JSON directly from an asset path.
  static Future<Map<String, dynamic>> loadFromAsset(String assetPath) async {
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return _fallbackJson;
    }
  }

  // ─── FALLBACK ─────────────────────────────────────────────────────────

  static const Map<String, dynamic> _fallbackJson = {
    'canvasBackground': '#FFFFFF',
    'items': [],
  };
}

// ─── TEMPLATE INFO MODEL ──────────────────────────────────────────────────

class CvTemplateInfo {
  final String id;
  final String label;
  final String category;
  final String assetPath;
  final bool isPremium;
  final int sortOrder;
  final String description;

  const CvTemplateInfo({
    required this.id,
    required this.label,
    required this.category,
    required this.assetPath,
    required this.isPremium,
    required this.sortOrder,
    required this.description,
  });
}