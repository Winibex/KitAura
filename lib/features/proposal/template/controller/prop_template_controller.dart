// lib/features/proposal/template/controller/prop_template_controller.dart

import 'package:flutter_riverpod/legacy.dart';
import '../data/prop_template_data.dart';

class PropTemplateState {
  final List<PropTemplateInfo> templates;
  final String activeFilter;
  final String searchQuery;
  final bool isLoading;

  PropTemplateState({
    this.templates = const [],
    this.activeFilter = 'All',
    this.searchQuery = '',
    this.isLoading = false,
  });

  List<PropTemplateInfo> get filteredTemplates {
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
      t.label.toLowerCase().contains(searchQuery.toLowerCase()) ||
          t.description
              .toLowerCase()
              .contains(searchQuery.toLowerCase()))
          .toList();
    }

    return list;
  }

  PropTemplateState copyWith({
    List<PropTemplateInfo>? templates,
    String? activeFilter,
    String? searchQuery,
    bool? isLoading,
  }) {
    return PropTemplateState(
      templates: templates ?? this.templates,
      activeFilter: activeFilter ?? this.activeFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PropTemplateController extends StateNotifier<PropTemplateState> {
  PropTemplateController() : super(PropTemplateState()) {
    loadTemplates();
  }

  static const List<String> categories = [
    'All',
    'Business',
    'Project',
    'Freelance',
    'Product',
    'Service',
    'Creative',
    'Executive',
    'Sales',
  ];

  void loadTemplates() {
    state = state.copyWith(isLoading: true);
    state = state.copyWith(
      templates: PropTemplateData.templates,
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

final propTemplateControllerProvider =
StateNotifierProvider<PropTemplateController, PropTemplateState>(
      (ref) => PropTemplateController(),
);