import 'package:flutter_riverpod/legacy.dart';
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
        assetPath: 'assets/cv_templates/template_classic_navy.json',
        isPremium: false,
        sortOrder: 1,
      ),
      TemplateModel(
        id: 'two_column',
        label: 'Two Column',
        category: 'creative',
        assetPath: 'assets/cv_templates/template_two_column.json',
        isPremium: false,
        sortOrder: 2,
      ),
      TemplateModel(
        id: 'minimal_clean',
        label: 'Minimal Clean',
        category: 'minimal',
        assetPath: 'assets/cv_templates/template_minimal.json',
        isPremium: false,
        sortOrder: 3,
      ),
      TemplateModel(
        id: 'executive_dark',
        label: 'Executive Dark',
        category: 'professional',
        assetPath: null,
        isPremium: true,
        sortOrder: 4,
      ),
      TemplateModel(
        id: 'modern_gradient',
        label: 'Modern Gradient',
        category: 'modern',
        assetPath: null,
        isPremium: true,
        sortOrder: 5,
      ),
      TemplateModel(
        id: 'corporate_blue',
        label: 'Corporate Blue',
        category: 'professional',
        assetPath: null,
        isPremium: true,
        sortOrder: 6,
      ),
      TemplateModel(
        id: 'creative_bold',
        label: 'Creative Bold',
        category: 'creative',
        assetPath: null,
        isPremium: true,
        sortOrder: 7,
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