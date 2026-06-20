// lib/shared/widgets/client_type_config.dart
//
// Drives the ADAPTIVE client wizard. For each projectType, declares which
// fields appear in each step + the right labels. The wizard reads this config
// and renders only the relevant fields — so a Product quote never shows
// "problem statement", and a Development project never shows marketing channels.
//
// To change what a type shows, edit its entry here. The wizard needs no changes.
library;

class ClientTypeConfig {
  // ─── STEP 1: Client Info ──────────────────────────────────────────
  /// Show tax/registration fields (NTN, company reg, client tax id).
  /// True for sales of goods/services where invoices need them.
  final bool showTaxFields;

  // ─── STEP 2: Overview ─────────────────────────────────────────────
  final String titleLabel; // e.g. "Project Title" / "Catalog Title"
  final String titleHint;
  final bool showDescription;
  final bool showProblem;
  final bool showGoals;
  // Development
  final bool showTechStack;
  final bool showPlatformTargets;
  final bool showIntegrationNeeds;
  // Design
  final bool showCreativeBrief;
  final bool showBrandGuidelines;
  final bool showRevisions;
  // Marketing
  final bool showChannels;
  final bool showTargetAudience;
  final bool showCampaignGoals;
  final bool showKpiMetrics;

  // ─── STEP 3: Scope ────────────────────────────────────────────────
  final bool showDeliverables;
  final bool showScopeNotes;
  final bool showSprintCount;
  final bool showProductTable; // physical-product line items (qty × unit price)
  final bool showWarrantyShipping;

  // ─── STEP 4: Timeline ─────────────────────────────────────────────
  final bool showStartEnd;
  final bool showMilestones;
  final bool
  showDeliveryLeadTime; // product: simple lead-time instead of milestones

  // ─── STEP 5: Budget ───────────────────────────────────────────────
  final bool showBudgetRange;
  final bool showPricingModel;
  final bool showLineItems;
  final bool showProductBudget; // tax %, shipping cost, auto grand total
  final bool showPaymentTerms;

  const ClientTypeConfig({
    this.showTaxFields = false,
    this.titleLabel = 'Project Title',
    this.titleHint = 'Give this project a title',
    this.showDescription = true,
    this.showProblem = false,
    this.showGoals = false,
    this.showTechStack = false,
    this.showPlatformTargets = false,
    this.showIntegrationNeeds = false,
    this.showCreativeBrief = false,
    this.showBrandGuidelines = false,
    this.showRevisions = false,
    this.showChannels = false,
    this.showTargetAudience = false,
    this.showCampaignGoals = false,
    this.showKpiMetrics = false,
    this.showDeliverables = true,
    this.showScopeNotes = true,
    this.showSprintCount = false,
    this.showProductTable = false,
    this.showWarrantyShipping = false,
    this.showStartEnd = true,
    this.showMilestones = true,
    this.showDeliveryLeadTime = false,
    this.showBudgetRange = true,
    this.showPricingModel = true,
    this.showLineItems = true,
    this.showProductBudget = false,
    this.showPaymentTerms = false,
  });

  /// Look up the config for a projectType. Falls back to `general`.
  static ClientTypeConfig forType(String type) =>
      _configs[type] ?? _configs['general']!;

  static const Map<String, ClientTypeConfig> _configs = {
    // ── DEVELOPMENT ───────────────────────────────────────────────
    'development': ClientTypeConfig(
      titleLabel: 'Project Title',
      titleHint: 'Mobile App, Web Platform, API Service...',
      showProblem: true, // a dev project usually solves a problem
      showGoals: true,
      showTechStack: true,
      showPlatformTargets: true,
      showIntegrationNeeds: true,
      showDeliverables: true,
      showScopeNotes: true,
      showSprintCount: true,
      showMilestones: true,
      showPricingModel: true,
      showLineItems: true,
    ),

    // ── DESIGN ────────────────────────────────────────────────────
    'design': ClientTypeConfig(
      titleLabel: 'Project Title',
      titleHint: 'Brand Identity, UI Redesign, Marketing Kit...',
      showCreativeBrief: true,
      showBrandGuidelines: true,
      showRevisions: true,
      showDeliverables: true,
      showScopeNotes: true,
      showMilestones: true,
      showPricingModel: true,
      showLineItems: true,
    ),

    // ── MARKETING ─────────────────────────────────────────────────
    'marketing': ClientTypeConfig(
      titleLabel: 'Campaign Title',
      titleHint: 'Q3 Growth Campaign, SEO Overhaul...',
      showChannels: true,
      showTargetAudience: true,
      showCampaignGoals: true,
      showKpiMetrics: true,
      showDeliverables: true,
      showScopeNotes: true,
      showMilestones: true,
      showPricingModel: true,
      showLineItems: true,
    ),

    // ── CONSULTING ────────────────────────────────────────────────
    'consulting': ClientTypeConfig(
      titleLabel: 'Engagement Title',
      titleHint: 'Strategy Review, Process Audit...',
      showProblem: true, // consulting is problem-driven
      showGoals: true,
      showDeliverables: true,
      showScopeNotes: true,
      showMilestones: true,
      showPricingModel: true,
      showLineItems: true,
    ),

    // ── PRODUCT (physical goods sale) ─────────────────────────────
    'product': ClientTypeConfig(
      showTaxFields: true, // invoices/quotes for goods need tax/reg numbers
      titleLabel: 'Quote / Catalog Title',
      titleHint: "Men's Footwear Order, Equipment Supply...",
      showDescription: true,
      showProblem: false, // a sale, not a project — no problem/goals
      showGoals: false,
      showDeliverables: false, // replaced by the product table
      showScopeNotes: false,
      showProductTable: true, // model / qty / unit price
      showWarrantyShipping: true,
      showStartEnd: false, // no project window
      showMilestones: false, // no milestones for an order
      showDeliveryLeadTime: true, // just a delivery/lead time
      showBudgetRange: false, // total comes from the table
      showPricingModel: false,
      showLineItems: false,
      showProductBudget: true, // tax %, shipping, grand total
      showPaymentTerms: true,
    ),

    // ── SERVICE (ongoing service agreement) ───────────────────────
    'service': ClientTypeConfig(
      showTaxFields: true, // service invoices often need tax/reg numbers
      titleLabel: 'Service Title',
      titleHint: 'Managed IT Support, Maintenance Plan...',
      showDescription: true,
      showDeliverables: true, // service inclusions
      showScopeNotes: true,
      showMilestones: true,
      showPricingModel: true,
      showLineItems: true,
      showPaymentTerms: true,
    ),

    // ── GENERAL (catch-all) ───────────────────────────────────────
    'general': ClientTypeConfig(
      titleLabel: 'Project Title',
      titleHint: 'Give this project a title',
      showProblem: true,
      showGoals: true,
      showDeliverables: true,
      showScopeNotes: true,
      showMilestones: true,
      showPricingModel: true,
      showLineItems: true,
    ),
  };
}
