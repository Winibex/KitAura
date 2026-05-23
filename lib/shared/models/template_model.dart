class TemplateModel {
  final String id;
  final String label;
  final String category;
  final String? assetPath;
  final String? previewUrl;
  final bool isPremium;
  final int sortOrder;

  TemplateModel({
    required this.id,
    required this.label,
    required this.category,
    this.assetPath,
    this.previewUrl,
    this.isPremium = false,
    this.sortOrder = 0,
  });

  factory TemplateModel.fromJson(String id, Map<String, dynamic> json) {
    return TemplateModel(
      id: id,
      label: json['label'] ?? '',
      category: json['category'] ?? 'professional',
      assetPath: json['assetPath'],
      previewUrl: json['previewUrl'],
      isPremium: json['isPremium'] ?? false,
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
}