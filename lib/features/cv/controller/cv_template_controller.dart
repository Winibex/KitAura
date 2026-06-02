import 'package:flutter_riverpod/legacy.dart';
import 'package:kitaura/core/constants/app_assets.dart';
import '../../../shared/models/template_model.dart';

class CVTemplateState {
  final List<TemplateModel> templates;
  final String activeFilter;
  final String searchQuery;
  final bool isLoading;

  CVTemplateState({
    this.templates = const [],
    this.activeFilter = 'All',
    this.searchQuery = '',
    this.isLoading = false,
  });

  List<TemplateModel> get filteredTemplates {
    var list = templates;

    if (activeFilter != 'All') {
      list = list
          .where((t) =>
      t.category.toLowerCase() == activeFilter.toLowerCase())
          .toList();
    }

    if (searchQuery.isNotEmpty) {
      list = list
          .where((t) =>
          t.label.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    return list;
  }

  CVTemplateState copyWith({
    List<TemplateModel>? templates,
    String? activeFilter,
    String? searchQuery,
    bool? isLoading,
  }) {
    return CVTemplateState(
      templates: templates ?? this.templates,
      activeFilter: activeFilter ?? this.activeFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CVTemplateController extends StateNotifier<CVTemplateState> {

  CVTemplateController() : super(CVTemplateState()) {
    loadTemplates();
  }

  static const List<String> categories = [
    'All',
    'Professional',
    'Creative',
    'Minimal',
    'Modern',
    'Ats'
  ];

  void loadTemplates() {
    state = state.copyWith(
      isLoading: true,
    );

    // Built-in cv_templates
    final templates = [
      TemplateModel(
        id: 'blank',
        label: 'Blank Canvas',
        category: 'all',
        assetPath: null,
        isPremium: false,
        sortOrder: 0,
      ),
      TemplateModel(
        id: 'classic_navy',
        label: 'Classic Navy',
        category: 'professional',
        assetPath: AppAssets.templateClassicNavy,
        isPremium: false,
        sortOrder: 1,
      ),
      TemplateModel(
        id: 'two_column',
        label: 'Two Column',
        category: 'creative',
        assetPath: AppAssets.templateTwoColumn,
        isPremium: false,
        sortOrder: 2,
      ),
      TemplateModel(
        id: 'minimal_clean',
        label: 'Minimal Clean',
        category: 'minimal',
        assetPath: AppAssets.templateMinimal,
        isPremium: false,
        sortOrder: 3,
      ),
      TemplateModel(
        id: 'executive_dark',
        label: 'Executive Dark',
        category: 'professional',
        assetPath: AppAssets.templateExecutiveDark,
        isPremium: true,
        sortOrder: 4,
      ),
      TemplateModel(
        id: 'modern_gradient',
        label: 'Modern Gradient',
        category: 'modern',
        assetPath: AppAssets.templateModernGradient,
        isPremium: true,
        sortOrder: 5,
      ),
      TemplateModel(
        id: 'corporate_blue',
        label: 'Corporate Blue',
        category: 'professional',
        assetPath: AppAssets.templateCorporateBlue,
        isPremium: true,
        sortOrder: 6,
      ),
      TemplateModel(
        id: 'creative_bold',
        label: 'Creative Bold',
        category: 'creative',
        assetPath: AppAssets.templateCreativeBold,
        isPremium: true,
        sortOrder: 7,
      ),
      TemplateModel(
        id: 'ats_classic',
        label: 'ATS Classic',
        category: 'ats',
        assetPath: AppAssets.templateAtsClassic,
        isPremium: false,
        sortOrder: 8,
      ),
      TemplateModel(
        id: 'ats_modern',
        label: 'ATS Modern',
        category: 'ats',
        assetPath: AppAssets.templateAtsModern,
        isPremium: false,
        sortOrder: 9,
      ),
      TemplateModel(
        id: 'ats_tech',
        label: 'ATS Tech',
        category: 'ats',
        assetPath: AppAssets.templateAtsTech,
        isPremium: true,
        sortOrder: 10,
      ),
      TemplateModel(
        id: 'ats_executive',
        label: 'ATS Executive',
        category: 'ats',
        assetPath: AppAssets.templateAtsExecutive,
        isPremium: true,
        sortOrder: 11,
      ),
    ];

    state = state.copyWith(
      templates: templates,
      isLoading: false,
    );
  }

  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  void setSearch(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

// Provider
final templateControllerProvider =
StateNotifierProvider<CVTemplateController, CVTemplateState>(
      (ref) => CVTemplateController(),
);