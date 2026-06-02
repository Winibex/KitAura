// lib/features/cover_letter/controller/cl_template_controller.dart

import 'package:flutter_riverpod/legacy.dart';
import '../data/cl_template_data.dart';

class ClTemplateState {
  final List<ClTemplateInfo> templates;
  final String activeFilter;
  final String searchQuery;
  final bool isLoading;

  ClTemplateState({
    this.templates = const [],
    this.activeFilter = 'All',
    this.searchQuery = '',
    this.isLoading = false,
  });

  List<ClTemplateInfo> get filteredTemplates {
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
          t.description.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    return list;
  }

  ClTemplateState copyWith({
    List<ClTemplateInfo>? templates,
    String? activeFilter,
    String? searchQuery,
    bool? isLoading,
  }) {
    return ClTemplateState(
      templates: templates ?? this.templates,
      activeFilter: activeFilter ?? this.activeFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ClTemplateController extends StateNotifier<ClTemplateState> {
  ClTemplateController() : super(ClTemplateState()) {
    loadTemplates();
  }

  static const List<String> categories = [
    'All',
    'Professional',
    'Modern',
    'Creative',
    'Executive',
    'Tech',
  ];

  void loadTemplates() {
    state = state.copyWith(isLoading: true);
    state = state.copyWith(
      templates: ClTemplateData.templates,
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

final clTemplateControllerProvider =
StateNotifierProvider<ClTemplateController, ClTemplateState>(
      (ref) => ClTemplateController(),
);