// lib/shared/models/client_profile_model.dart
//
// Client profile used by AI to generate proposal content.
// Stored at users/{uid}/clientProfiles/{clientId} in Firestore.
//
// Follows the same pattern as AiProfileModel:
//   - Sub-models with toJson/fromJson/copyWith
//   - Main model with full serialization
//   - All fields nullable/defaulted for backwards compatibility

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── SUB-MODELS ──────────────────────────────────────────────────────────

class DeliverableEntry {
  final String name;
  final String? description;

  const DeliverableEntry({this.name = '', this.description});

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
  };

  factory DeliverableEntry.fromJson(Map<String, dynamic> json) =>
      DeliverableEntry(
        name: json['name'] ?? '',
        description: json['description'],
      );

  DeliverableEntry copyWith({String? name, String? description}) =>
      DeliverableEntry(
        name: name ?? this.name,
        description: description ?? this.description,
      );
}

class MilestoneEntry {
  final String title;
  final String? date;
  final String? description;

  const MilestoneEntry({this.title = '', this.date, this.description});

  Map<String, dynamic> toJson() => {
    'title': title,
    'date': date,
    'description': description,
  };

  factory MilestoneEntry.fromJson(Map<String, dynamic> json) =>
      MilestoneEntry(
        title: json['title'] ?? '',
        date: json['date'],
        description: json['description'],
      );

  MilestoneEntry copyWith({String? title, String? date, String? description}) =>
      MilestoneEntry(
        title: title ?? this.title,
        date: date ?? this.date,
        description: description ?? this.description,
      );
}

class LineItemEntry {
  final String item;
  final String? description;
  final double? amount;

  const LineItemEntry({this.item = '', this.description, this.amount});

  Map<String, dynamic> toJson() => {
    'item': item,
    'description': description,
    'amount': amount,
  };

  factory LineItemEntry.fromJson(Map<String, dynamic> json) => LineItemEntry(
    item: json['item'] ?? '',
    description: json['description'],
    amount: (json['amount'] as num?)?.toDouble(),
  );

  LineItemEntry copyWith({String? item, String? description, double? amount}) =>
      LineItemEntry(
        item: item ?? this.item,
        description: description ?? this.description,
        amount: amount ?? this.amount,
      );
}

/// Dedicated line item for physical-product quotes: model/name, quantity,
/// and unit price. Line total is computed (qty × unitPrice), never stored.
class ProductLineItem {
  final String name;        // product / model name
  final String? sku;        // optional model number / SKU
  final int quantity;
  final double unitPrice;
  const ProductLineItem({
    this.name = '',
    this.sku,
    this.quantity = 1,
    this.unitPrice = 0,
  });

  /// Computed — qty × unit price. Not serialized (derived).
  double get lineTotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
    'name': name,
    'sku': sku,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };

  factory ProductLineItem.fromJson(Map<String, dynamic> json) => ProductLineItem(
    name: json['name'] ?? '',
    sku: json['sku'],
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
  );

  ProductLineItem copyWith({String? name, String? sku, int? quantity, double? unitPrice}) =>
      ProductLineItem(
        name: name ?? this.name,
        sku: sku ?? this.sku,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
      );
}

class TypeSpecificFields {
  // Development
  final List<String> techStack;
  final String? platformTargets;
  final String? integrationNeeds;
  final int? sprintCount;

  // Design
  final bool? brandGuidelines;
  final int? designRevisions;
  final String? creativeBrief;

  // Marketing
  final List<String> channels;
  final String? targetAudience;
  final String? campaignGoals;
  final List<String> kpiMetrics;

  // Product
  final String? warrantyTerms;
  final String? shippingTerms;
  final String? paymentTerms;
  final List<ProductLineItem> productItems;
  final double? taxPercent;
  final double? shippingCost;

  const TypeSpecificFields({
    this.techStack = const [],
    this.platformTargets,
    this.integrationNeeds,
    this.sprintCount,
    this.brandGuidelines,
    this.designRevisions,
    this.creativeBrief,
    this.channels = const [],
    this.targetAudience,
    this.campaignGoals,
    this.kpiMetrics = const [],
    this.warrantyTerms,
    this.shippingTerms,
    this.paymentTerms,
    this.productItems = const [],
    this.taxPercent,
    this.shippingCost,
  });

  Map<String, dynamic> toJson() => {
    'techStack': techStack,
    'platformTargets': platformTargets,
    'integrationNeeds': integrationNeeds,
    'sprintCount': sprintCount,
    'brandGuidelines': brandGuidelines,
    'designRevisions': designRevisions,
    'creativeBrief': creativeBrief,
    'channels': channels,
    'targetAudience': targetAudience,
    'campaignGoals': campaignGoals,
    'kpiMetrics': kpiMetrics,
    'warrantyTerms': warrantyTerms,
    'shippingTerms': shippingTerms,
    'paymentTerms': paymentTerms,
    'productItems': productItems.map((e) => e.toJson()).toList(),
    'taxPercent': taxPercent,
    'shippingCost': shippingCost,
  };

  factory TypeSpecificFields.fromJson(Map<String, dynamic> json) =>
      TypeSpecificFields(
        techStack: List<String>.from(json['techStack'] ?? []),
        platformTargets: json['platformTargets'],
        integrationNeeds: json['integrationNeeds'],
        sprintCount: json['sprintCount'] as int?,
        brandGuidelines: json['brandGuidelines'] as bool?,
        designRevisions: json['designRevisions'] as int?,
        creativeBrief: json['creativeBrief'],
        channels: List<String>.from(json['channels'] ?? []),
        targetAudience: json['targetAudience'],
        campaignGoals: json['campaignGoals'],
        kpiMetrics: List<String>.from(json['kpiMetrics'] ?? []),
        warrantyTerms: json['warrantyTerms'],
        shippingTerms: json['shippingTerms'],
        paymentTerms: json['paymentTerms'],
        productItems: (json['productItems'] as List<dynamic>?)
            ?.map((e) => ProductLineItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
            [],
        taxPercent: (json['taxPercent'] as num?)?.toDouble(),
        shippingCost: (json['shippingCost'] as num?)?.toDouble(),
      );

  TypeSpecificFields copyWith({
    List<String>? techStack,
    String? platformTargets,
    String? integrationNeeds,
    int? sprintCount,
    bool? brandGuidelines,
    int? designRevisions,
    String? creativeBrief,
    List<String>? channels,
    String? targetAudience,
    String? campaignGoals,
    List<String>? kpiMetrics,
    String? warrantyTerms,
    String? shippingTerms,
    String? paymentTerms,
    List<ProductLineItem>? productItems,
    double? taxPercent,
    double? shippingCost,
  }) =>
      TypeSpecificFields(
        techStack: techStack ?? this.techStack,
        platformTargets: platformTargets ?? this.platformTargets,
        integrationNeeds: integrationNeeds ?? this.integrationNeeds,
        sprintCount: sprintCount ?? this.sprintCount,
        brandGuidelines: brandGuidelines ?? this.brandGuidelines,
        designRevisions: designRevisions ?? this.designRevisions,
        creativeBrief: creativeBrief ?? this.creativeBrief,
        channels: channels ?? this.channels,
        targetAudience: targetAudience ?? this.targetAudience,
        campaignGoals: campaignGoals ?? this.campaignGoals,
        kpiMetrics: kpiMetrics ?? this.kpiMetrics,
        warrantyTerms: warrantyTerms ?? this.warrantyTerms,
        shippingTerms: shippingTerms ?? this.shippingTerms,
        paymentTerms: paymentTerms ?? this.paymentTerms,
        productItems: productItems ?? this.productItems,
        taxPercent: taxPercent ?? this.taxPercent,
        shippingCost: shippingCost ?? this.shippingCost,
      );

  bool get isEmpty =>
      techStack.isEmpty &&
          platformTargets == null &&
          integrationNeeds == null &&
          sprintCount == null &&
          brandGuidelines == null &&
          designRevisions == null &&
          creativeBrief == null &&
          channels.isEmpty &&
          targetAudience == null &&
          campaignGoals == null &&
          kpiMetrics.isEmpty &&
          warrantyTerms == null &&
          shippingTerms == null &&
          paymentTerms == null &&
          productItems.isEmpty &&
          taxPercent == null &&
          shippingCost == null;
}

// ─── MAIN CLIENT PROFILE MODEL ──────────────────────────────────────────

class ClientProfileModel {
  final String? id;

  // Step 1: Client Info
  final String clientName;
  final String? clientCompany;
  final String? clientEmail;
  final String? clientPhone;
  final String? clientWebsite;
  final String? industry;

  // Sender (your) info — pre-filled from chosen Career Profile (snapshot)
  final String? senderCompany;
  final String? senderName;
  final String? senderEmail;
  final String? senderPhone;

  // Step 2: Project Overview
  final String projectTitle;
  final String projectType; // consulting | development | design | marketing | product | service | general
  final String? projectDescription;
  final String? problemStatement;
  final List<String> projectGoals;

  // Step 3: Scope & Deliverables
  final List<DeliverableEntry> deliverables;
  final String? scopeNotes;

  // Step 4: Timeline
  final String? startDate;
  final String? endDate;
  final List<MilestoneEntry> milestones;

  // Step 5: Budget
  final String? budgetRange; // <1K | 1-5K | 5-25K | 25-100K | 100K+
  final String? pricingModel; // fixed | hourly | retainer | milestone | per-unit
  final List<LineItemEntry> lineItems;

  // Step 6: Additional Context
  final String? competitorInfo;
  final String? specialRequirements;
  final String? customNotes;

  // Type-specific fields
  final TypeSpecificFields typeSpecific;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Tax / registration (shown for product & service sales)
  final String? senderTaxId;      // your NTN / tax number
  final String? senderRegNumber;  // your company registration number
  final String? clientTaxId;      // client NTN / tax number

  const ClientProfileModel({
    this.id,
    this.clientName = '',
    this.clientCompany,
    this.clientEmail,
    this.clientPhone,
    this.clientWebsite,
    this.industry,
    this.senderCompany,
    this.senderName,
    this.senderEmail,
    this.senderPhone,
    this.projectTitle = '',
    this.projectType = 'general',
    this.projectDescription,
    this.problemStatement,
    this.projectGoals = const [],
    this.deliverables = const [],
    this.scopeNotes,
    this.startDate,
    this.endDate,
    this.milestones = const [],
    this.budgetRange,
    this.pricingModel,
    this.lineItems = const [],
    this.competitorInfo,
    this.specialRequirements,
    this.customNotes,
    this.typeSpecific = const TypeSpecificFields(),
    this.createdAt,
    this.updatedAt,
    this.senderTaxId,
    this.senderRegNumber,
    this.clientTaxId,
  });

  /// Display name for dropdown lists
  String get displayName {
    if (clientCompany != null && clientCompany!.isNotEmpty) {
      return '$clientName — $clientCompany';
    }
    return clientName.isNotEmpty ? clientName : 'Unnamed Client';
  }

  /// Short summary for cards/lists
  String get subtitle {
    final parts = <String>[];
    if (projectTitle.isNotEmpty) parts.add(projectTitle);
    if (industry != null && industry!.isNotEmpty) parts.add(industry!);
    return parts.isNotEmpty ? parts.join(' • ') : projectType;
  }

  /// Grand total for product quotes: sum of line totals + shipping + tax.
  double get productGrandTotal {
    final sub = typeSpecific.productItems.fold<double>(0, (s, e) => s + e.lineTotal);
    final ship = typeSpecific.shippingCost ?? 0;
    final taxable = sub + ship;
    final tax = (typeSpecific.taxPercent ?? 0) / 100 * taxable;
    return taxable + tax;
  }

  // ─── PROPOSAL TYPE HELPERS ───────────────────────────────────────

  static const List<String> projectTypes = [
    'consulting',
    'development',
    'design',
    'marketing',
    'product',
    'service',
    'general',
  ];

  static const Map<String, String> projectTypeLabels = {
    'consulting': 'Consulting & Advisory',
    'development': 'Software Development',
    'design': 'Design & Creative',
    'marketing': 'Marketing & Campaigns',
    'product': 'Product Supply',
    'service': 'Service Agreement',
    'general': 'General Proposal',
  };

  static const List<String> budgetRanges = [
    'Under \$1,000',
    '\$1,000 – \$5,000',
    '\$5,000 – \$25,000',
    '\$25,000 – \$100,000',
    'Over \$100,000',
    'To be discussed',
  ];

  static const List<String> pricingModels = [
    'fixed',
    'hourly',
    'retainer',
    'milestone',
    'per-unit',
  ];

  static const Map<String, String> pricingModelLabels = {
    'fixed': 'Fixed Price',
    'hourly': 'Hourly Rate',
    'retainer': 'Monthly Retainer',
    'milestone': 'Milestone-Based',
    'per-unit': 'Per Unit / Per Item',
  };

  // ─── JSON ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'clientName': clientName,
    'clientCompany': clientCompany,
    'clientEmail': clientEmail,
    'clientPhone': clientPhone,
    'clientWebsite': clientWebsite,
    'industry': industry,
    'senderCompany': senderCompany,
    'senderName': senderName,
    'senderEmail': senderEmail,
    'senderPhone': senderPhone,
    'projectTitle': projectTitle,
    'projectType': projectType,
    'projectDescription': projectDescription,
    'problemStatement': problemStatement,
    'projectGoals': projectGoals,
    'deliverables': deliverables.map((e) => e.toJson()).toList(),
    'scopeNotes': scopeNotes,
    'startDate': startDate,
    'endDate': endDate,
    'milestones': milestones.map((e) => e.toJson()).toList(),
    'budgetRange': budgetRange,
    'pricingModel': pricingModel,
    'lineItems': lineItems.map((e) => e.toJson()).toList(),
    'competitorInfo': competitorInfo,
    'specialRequirements': specialRequirements,
    'customNotes': customNotes,
    'typeSpecific': typeSpecific.toJson(),
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
    'senderTaxId': senderTaxId,
    'senderRegNumber': senderRegNumber,
    'clientTaxId': clientTaxId,
  };

  factory ClientProfileModel.fromJson(String id, Map<String, dynamic> json) {
    return ClientProfileModel(
      id: id,
      clientName: json['clientName'] ?? '',
      clientCompany: json['clientCompany'],
      clientEmail: json['clientEmail'],
      clientPhone: json['clientPhone'],
      clientWebsite: json['clientWebsite'],
      industry: json['industry'],
      senderCompany: json['senderCompany'],
      senderName: json['senderName'],
      senderEmail: json['senderEmail'],
      senderPhone: json['senderPhone'],
      projectTitle: json['projectTitle'] ?? '',
      projectType: json['projectType'] ?? 'general',
      projectDescription: json['projectDescription'],
      problemStatement: json['problemStatement'],
      projectGoals: List<String>.from(json['projectGoals'] ?? []),
      deliverables: (json['deliverables'] as List<dynamic>?)
          ?.map((e) => DeliverableEntry.fromJson(
          Map<String, dynamic>.from(e as Map)))
          .toList() ??
          [],
      scopeNotes: json['scopeNotes'],
      startDate: json['startDate'],
      endDate: json['endDate'],
      milestones: (json['milestones'] as List<dynamic>?)
          ?.map((e) => MilestoneEntry.fromJson(
          Map<String, dynamic>.from(e as Map)))
          .toList() ??
          [],
      budgetRange: json['budgetRange'],
      pricingModel: json['pricingModel'],
      lineItems: (json['lineItems'] as List<dynamic>?)
          ?.map((e) => LineItemEntry.fromJson(
          Map<String, dynamic>.from(e as Map)))
          .toList() ??
          [],
      competitorInfo: json['competitorInfo'],
      specialRequirements: json['specialRequirements'],
      customNotes: json['customNotes'],
      typeSpecific: json['typeSpecific'] != null
          ? TypeSpecificFields.fromJson(
          Map<String, dynamic>.from(json['typeSpecific'] as Map))
          : const TypeSpecificFields(),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      senderTaxId: json['senderTaxId'],
      senderRegNumber: json['senderRegNumber'],
      clientTaxId: json['clientTaxId'],
    );
  }

  ClientProfileModel copyWith({
    String? id,
    String? clientName,
    String? clientCompany,
    String? clientEmail,
    String? clientPhone,
    String? clientWebsite,
    String? industry,
    String? senderCompany,
    String? senderName,
    String? senderEmail,
    String? senderPhone,
    String? projectTitle,
    String? projectType,
    String? projectDescription,
    String? problemStatement,
    List<String>? projectGoals,
    List<DeliverableEntry>? deliverables,
    String? scopeNotes,
    String? startDate,
    String? endDate,
    List<MilestoneEntry>? milestones,
    String? budgetRange,
    String? pricingModel,
    List<LineItemEntry>? lineItems,
    String? competitorInfo,
    String? specialRequirements,
    String? customNotes,
    TypeSpecificFields? typeSpecific,
    String? senderTaxId,
    String? senderRegNumber,
    String? clientTaxId,
  }) {
    return ClientProfileModel(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      clientCompany: clientCompany ?? this.clientCompany,
      clientEmail: clientEmail ?? this.clientEmail,
      clientPhone: clientPhone ?? this.clientPhone,
      clientWebsite: clientWebsite ?? this.clientWebsite,
      industry: industry ?? this.industry,
      senderCompany: senderCompany ?? this.senderCompany,
      senderName: senderName ?? this.senderName,
      senderEmail: senderEmail ?? this.senderEmail,
      senderPhone: senderPhone ?? this.senderPhone,
      projectTitle: projectTitle ?? this.projectTitle,
      projectType: projectType ?? this.projectType,
      projectDescription: projectDescription ?? this.projectDescription,
      problemStatement: problemStatement ?? this.problemStatement,
      projectGoals: projectGoals ?? this.projectGoals,
      deliverables: deliverables ?? this.deliverables,
      scopeNotes: scopeNotes ?? this.scopeNotes,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      milestones: milestones ?? this.milestones,
      budgetRange: budgetRange ?? this.budgetRange,
      pricingModel: pricingModel ?? this.pricingModel,
      lineItems: lineItems ?? this.lineItems,
      competitorInfo: competitorInfo ?? this.competitorInfo,
      specialRequirements: specialRequirements ?? this.specialRequirements,
      customNotes: customNotes ?? this.customNotes,
      typeSpecific: typeSpecific ?? this.typeSpecific,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      senderTaxId: senderTaxId ?? this.senderTaxId,
      senderRegNumber: senderRegNumber ?? this.senderRegNumber,
      clientTaxId: clientTaxId ?? this.clientTaxId,
    );
  }
}