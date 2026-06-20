// lib/shared/widgets/client_wizard_modal.dart
//
// 6-step ADAPTIVE modal wizard for creating/editing client profiles.
// Fields shown per step are driven by ClientTypeConfig.forType(projectType):
//   - Product quotes show a product line-item table + tax/shipping totals,
//     and hide problem/goals/milestones.
//   - Development shows tech stack / platform / integrations.
//   - Marketing shows channels / audience / KPIs. etc.
//
// Depends on: ClientProfileModel (with ProductLineItem + tax fields),
//             ClientTypeConfig, aiProfilesProvider (cached profiles).
//
// Used from: proposal editor panel, settings > client profiles.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';
import '../../features/settings/view/upgrade_modal.dart';
import '../ai/claude_service.dart';
import '../models/ai_profile_model.dart';
import '../models/client_profile_model.dart';
import '../providers/ai_profiles_provider.dart';
import 'client_type_config.dart';

class ClientWizardModal extends ConsumerStatefulWidget {
  final ClientProfileModel? existing;
  final String title;
  const ClientWizardModal({
    super.key,
    this.existing,
    this.title = 'New Client',
  });

  /// Shows the wizard and returns the filled model, or null if cancelled.
  static Future<ClientProfileModel?> show(
    BuildContext context, {
    ClientProfileModel? existing,
  })
  {
    return showDialog<ClientProfileModel>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => ClientWizardModal(
        existing: existing,
        title: existing != null ? 'Edit Client' : 'New Client',
      ),
    );
  }

  @override
  ConsumerState<ClientWizardModal> createState() => _ClientWizardModalState();
}

class _ClientWizardModalState extends ConsumerState<ClientWizardModal> {
  int _step = 0;
  static const _totalSteps = 6;

  // Step 1: Client Info
  final _clientName = TextEditingController();
  final _clientCompany = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientWebsite = TextEditingController();
  final _industry = TextEditingController();

  // Sender (your) info
  final _senderCompany = TextEditingController();
  final _senderName = TextEditingController();
  final _senderEmail = TextEditingController();
  final _senderPhone = TextEditingController();

  // Tax / registration (shown for product & service)
  final _senderTaxId = TextEditingController();
  final _senderRegNumber = TextEditingController();
  final _clientTaxId = TextEditingController();

  // Step 2: Project Overview
  final _projectTitle = TextEditingController();
  String _projectType = 'general';
  final _projectDescription = TextEditingController();
  final _problemStatement = TextEditingController();
  List<String> _projectGoals = [];
  final _goalInput = TextEditingController();

  // Type-specific (text)
  final _platformTargets = TextEditingController();
  final _integrationNeeds = TextEditingController();
  final _creativeBrief = TextEditingController();
  final _campaignGoals = TextEditingController();
  final _targetAudience = TextEditingController();
  // Type-specific (numbers)
  final _sprintCount = TextEditingController();
  final _designRevisions = TextEditingController();
  // Type-specific (bool)
  bool? _brandGuidelines;
  // Type-specific (lists)
  List<String> _techStack = [];
  List<String> _channels = [];
  List<String> _kpiMetrics = [];

  // Step 3: Deliverables / Product table
  List<DeliverableEntry> _deliverables = [];
  final _scopeNotes = TextEditingController();
  final _warrantyTerms = TextEditingController();
  final _shippingTerms = TextEditingController();
  List<ProductLineItem> _productItems = [];

  // Step 4: Timeline
  final _startDate = TextEditingController();
  final _endDate =
      TextEditingController(); // product: reused as "Delivery / Lead Time"
  List<MilestoneEntry> _milestones = [];

  // Step 5: Budget
  String? _budgetRange;
  String? _pricingModel;
  List<LineItemEntry> _lineItems = [];
  final _taxPercent = TextEditingController();
  final _shippingCost = TextEditingController();
  final _paymentTerms = TextEditingController();

  // Step 6: Additional
  final _competitorInfo = TextEditingController();
  final _specialRequirements = TextEditingController();
  final _customNotes = TextEditingController();

  // AI profile dropdown
  String? _selectedProfileId;

  final _briefCtrl = TextEditingController();
  bool _aiBusy = false;
  bool _briefOpen = false;

  // Controller maps for list editors (rebuilt lazily via putIfAbsent)
  final Map<int, Map<String, TextEditingController>> _milestoneCtrls = {};
  final Map<int, Map<String, TextEditingController>> _deliverableCtrls = {};
  final Map<int, Map<String, TextEditingController>> _lineItemCtrls = {};
  final Map<int, Map<String, TextEditingController>> _productCtrls = {};

  ClientTypeConfig get _cfg => ClientTypeConfig.forType(_projectType);

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _loadExisting(widget.existing!);
  }

  // Snapshot copy: pull sender fields from the chosen profile.
  void _applyProfile(String? profileId, List<AiProfileModel> profiles) {
    setState(() => _selectedProfileId = profileId);
    if (profileId == null) return;
    final p = profiles.firstWhere(
      (e) => e.id == profileId,
      orElse: () => const AiProfileModel(),
    );
    _senderCompany.text = p.companyName;
    _senderName.text = p.fullName;
    _senderEmail.text = p.email;
    _senderPhone.text = p.phone;
  }

  void _loadExisting(ClientProfileModel p) {
    _clientName.text = p.clientName;
    _clientCompany.text = p.clientCompany ?? '';
    _clientEmail.text = p.clientEmail ?? '';
    _clientPhone.text = p.clientPhone ?? '';
    _clientWebsite.text = p.clientWebsite ?? '';
    _industry.text = p.industry ?? '';
    _senderCompany.text = p.senderCompany ?? '';
    _senderName.text = p.senderName ?? '';
    _senderEmail.text = p.senderEmail ?? '';
    _senderPhone.text = p.senderPhone ?? '';
    _senderTaxId.text = p.senderTaxId ?? '';
    _senderRegNumber.text = p.senderRegNumber ?? '';
    _clientTaxId.text = p.clientTaxId ?? '';

    _projectTitle.text = p.projectTitle;
    _projectType = p.projectType;
    _projectDescription.text = p.projectDescription ?? '';
    _problemStatement.text = p.problemStatement ?? '';
    _projectGoals = List.from(p.projectGoals);

    _deliverables = p.deliverables.map((e) => e.copyWith()).toList();
    _scopeNotes.text = p.scopeNotes ?? '';
    _startDate.text = p.startDate ?? '';
    _endDate.text = p.endDate ?? '';
    _milestones = p.milestones.map((e) => e.copyWith()).toList();
    _budgetRange = p.budgetRange;
    _pricingModel = p.pricingModel;
    _lineItems = p.lineItems.map((e) => e.copyWith()).toList();
    _competitorInfo.text = p.competitorInfo ?? '';
    _specialRequirements.text = p.specialRequirements ?? '';
    _customNotes.text = p.customNotes ?? '';

    final ts = p.typeSpecific;
    _techStack = List.from(ts.techStack);
    _platformTargets.text = ts.platformTargets ?? '';
    _integrationNeeds.text = ts.integrationNeeds ?? '';
    _sprintCount.text = ts.sprintCount?.toString() ?? '';
    _brandGuidelines = ts.brandGuidelines;
    _designRevisions.text = ts.designRevisions?.toString() ?? '';
    _creativeBrief.text = ts.creativeBrief ?? '';
    _channels = List.from(ts.channels);
    _targetAudience.text = ts.targetAudience ?? '';
    _campaignGoals.text = ts.campaignGoals ?? '';
    _kpiMetrics = List.from(ts.kpiMetrics);
    _warrantyTerms.text = ts.warrantyTerms ?? '';
    _shippingTerms.text = ts.shippingTerms ?? '';
    _paymentTerms.text = ts.paymentTerms ?? '';
    _productItems = ts.productItems.map((e) => e.copyWith()).toList();
    _taxPercent.text = ts.taxPercent?.toString() ?? '';
    _shippingCost.text = ts.shippingCost?.toString() ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _clientName,
      _clientCompany,
      _clientEmail,
      _clientPhone,
      _clientWebsite,
      _industry,
      _projectTitle,
      _projectDescription,
      _problemStatement,
      _goalInput,
      _scopeNotes,
      _startDate,
      _endDate,
      _competitorInfo,
      _specialRequirements,
      _customNotes,
      _platformTargets,
      _integrationNeeds,
      _creativeBrief,
      _campaignGoals,
      _targetAudience,
      _sprintCount,
      _designRevisions,
      _warrantyTerms,
      _shippingTerms,
      _paymentTerms,
      _taxPercent,
      _shippingCost,
      _senderCompany,
      _senderName,
      _senderEmail,
      _senderPhone,
      _senderTaxId,
      _senderRegNumber,
      _clientTaxId,
      _briefCtrl,
    ]) {
      c.dispose();
    }
    for (final m in [
      ..._milestoneCtrls.values,
      ..._deliverableCtrls.values,
      ..._lineItemCtrls.values,
      ..._productCtrls.values,
    ]) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  ClientProfileModel _buildModel() {
    return ClientProfileModel(
      id: widget.existing?.id,
      clientName: _clientName.text.trim(),
      clientCompany: _nz(_clientCompany),
      clientEmail: _nz(_clientEmail),
      clientPhone: _nz(_clientPhone),
      clientWebsite: _nz(_clientWebsite),
      industry: _nz(_industry),
      senderCompany: _nz(_senderCompany),
      senderName: _nz(_senderName),
      senderEmail: _nz(_senderEmail),
      senderPhone: _nz(_senderPhone),
      senderTaxId: _nz(_senderTaxId),
      senderRegNumber: _nz(_senderRegNumber),
      clientTaxId: _nz(_clientTaxId),
      projectTitle: _projectTitle.text.trim(),
      projectType: _projectType,
      projectDescription: _nz(_projectDescription),
      problemStatement: _nz(_problemStatement),
      projectGoals: _projectGoals,
      deliverables: _deliverables,
      scopeNotes: _nz(_scopeNotes),
      startDate: _nz(_startDate),
      endDate: _nz(_endDate),
      milestones: _milestones,
      budgetRange: _budgetRange,
      pricingModel: _pricingModel,
      lineItems: _lineItems,
      competitorInfo: _nz(_competitorInfo),
      specialRequirements: _nz(_specialRequirements),
      customNotes: _nz(_customNotes),
      typeSpecific: TypeSpecificFields(
        techStack: _techStack,
        platformTargets: _nz(_platformTargets),
        integrationNeeds: _nz(_integrationNeeds),
        sprintCount: int.tryParse(_sprintCount.text.trim()),
        brandGuidelines: _brandGuidelines,
        designRevisions: int.tryParse(_designRevisions.text.trim()),
        creativeBrief: _nz(_creativeBrief),
        channels: _channels,
        targetAudience: _nz(_targetAudience),
        campaignGoals: _nz(_campaignGoals),
        kpiMetrics: _kpiMetrics,
        warrantyTerms: _nz(_warrantyTerms),
        shippingTerms: _nz(_shippingTerms),
        paymentTerms: _nz(_paymentTerms),
        productItems: _productItems,
        taxPercent: double.tryParse(_taxPercent.text.trim()),
        shippingCost: double.tryParse(_shippingCost.text.trim()),
      ),
      createdAt: widget.existing?.createdAt,
    );
  }

  /// null if empty, trimmed otherwise.
  String? _nz(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (_clientName.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Client name is required')));
      setState(() => _step = 0);
      return;
    }
    Navigator.of(context).pop(_buildModel());
  }

  // ─── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final dialogW = screenW < 650 ? screenW - 32 : 600.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: dialogW,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Flexible(child: _buildStepContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              LucideIcons.userPlus,
              size: 16,
              color: AppColors.darkRaspberry,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold,
                    color: AppColors.prussianBlue,
                  ),
                ),
                Text(
                  _stepLabels[_step],
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.slateGrey,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F0EC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.x,
                size: 14,
                color: AppColors.slateGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _stepLabels = [
    'Step 1 of 6 — Client Info',
    'Step 2 of 6 — Project Overview',
    'Step 3 of 6 — Scope & Deliverables',
    'Step 4 of 6 — Timeline',
    'Step 5 of 6 — Budget',
    'Step 6 of 6 — Additional Context',
  ];

  // ─── STEP INDICATOR ─────────────────────────────────────────────
  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final isActive = i == _step;
          final isDone = i < _step;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _step = i),
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.darkRaspberry
                      : isActive
                      ? AppColors.magentaBloom
                      : AppColors.almondSilk.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── STEP CONTENT ───────────────────────────────────────────────
  Widget _buildStepContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey('$_step-$_projectType'),
          child: switch (_step) {
            0 => _buildStep1(),
            1 => _buildStep2(),
            2 => _buildStep3(),
            3 => _buildStep4(),
            4 => _buildStep5(),
            5 => _buildStep6(),
            _ => const SizedBox(),
          },
        ),
      ),
    );
  }

  // ── STEP 1: Client Info ─────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiAutoFill(),
        _buildProfileDropdown(),
        const SizedBox(height: 6),
        _sectionLabel('Your Details'),
        _field('Your Company', _senderCompany, hint: 'Your Company Ltd.'),
        _field('Your Name', _senderName, hint: 'Ahmad Ali Khan'),
        Row(
          children: [
            Expanded(
              child: _field(
                'Your Email',
                _senderEmail,
                hint: 'you@company.com',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field('Your Phone', _senderPhone, hint: '+1 234 567 890'),
            ),
          ],
        ),
        if (_cfg.showTaxFields) ...[
          Row(
            children: [
              Expanded(
                child: _field(
                  'Your Tax ID (NTN/VAT)',
                  _senderTaxId,
                  hint: '1234567-8',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  'Company Reg. No.',
                  _senderRegNumber,
                  hint: 'Optional',
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _sectionLabel('Client Details'),
        _field('Client Name *', _clientName, hint: 'John Smith'),
        _field('Company', _clientCompany, hint: 'Acme Corporation'),
        Row(
          children: [
            Expanded(
              child: _field('Email', _clientEmail, hint: 'john@acme.com'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field('Phone', _clientPhone, hint: '+1 234 567 890'),
            ),
          ],
        ),
        if (_cfg.showTaxFields)
          _field('Client Tax ID (NTN/VAT)', _clientTaxId, hint: 'Optional'),
        _field('Website', _clientWebsite, hint: 'www.acme.com'),
        _field(
          'Industry',
          _industry,
          hint: 'Manufacturing, Technology, Healthcare...',
        ),
      ],
    );
  }

  Widget _buildProfileDropdown() {
    final profilesAsync = ref.watch(aiProfilesProvider);
    return profilesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.darkRaspberry,
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (profiles) {
        if (profiles.isEmpty) return const SizedBox.shrink();
        final options = <String, String>{
          for (final p in profiles) (p.id ?? ''): p.name,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Use AI Profile (autofills your details)'),
            Container(
              width: double.infinity,
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.lavenderBlush,
              ),
              alignment: Alignment.center,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value:
                      (_selectedProfileId != null &&
                          options.containsKey(_selectedProfileId))
                      ? _selectedProfileId
                      : null,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(12),
                  hint: const Text(
                    'None — I\'ll fill it myself',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.openSans,
                      color: AppColors.slateGrey,
                    ),
                  ),
                  style: _inputStyle(),
                  icon: const Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.slateGrey,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'None — I\'ll fill it myself',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    ...options.entries.map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, style: _inputStyle()),
                      ),
                    ),
                  ],
                  onChanged: (id) => _applyProfile(id, profiles),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }

  Widget _buildAiAutoFill() {
    final isPro = ref.watch(dashboardControllerProvider).isPro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible header
        GestureDetector(
          onTap: () {
            if (!isPro) {
              showDialog(context: context, builder: (_) => const UpgradeModal());
              return;
            }
            setState(() => _briefOpen = !_briefOpen);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles, size: 16, color: AppColors.white),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Auto-fill with AI',
                      style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w600, color: AppColors.white)),
                ),
                if (!isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('PRO',
                        style: TextStyle(fontSize: 9, fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.white)),
                  )
                else
                  Icon(_briefOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 16, color: AppColors.white),
              ],
            ),
          ),
        ),
        if (_briefOpen && isPro) ...[
          const SizedBox(height: 10),
          // Privacy notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.shieldCheck, size: 13, color: AppColors.darkRaspberry),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This text isn\'t saved for your privacy. Closing or reloading clears it.',
                    style: TextStyle(fontSize: 11, fontFamily: AppFonts.openSans,
                        color: AppColors.prussianBlue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _briefCtrl,
            maxLines: 4,
            style: _inputStyle(),
            decoration: _inputDeco(
                'Paste your project brief — e.g. "Mobile app for a gym, 4 weeks, '
                    'auth + dashboard + payments modules, fixed price \$8k for Acme Corp."'),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _aiBusy ? null : _runAutoFill,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: _aiBusy ? AppColors.slateGrey : AppColors.darkRaspberry,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_aiBusy)
                      const SizedBox(width: 15, height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                    else
                      Icon(LucideIcons.sparkles, size: 15, color: AppColors.white),
                    const SizedBox(width: 8),
                    Text(_aiBusy ? 'Reading your brief...' : 'Fill the form',
                        style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w600, color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _runAutoFill() async {
    final brief = _briefCtrl.text.trim();
    if (brief.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final json = await ClaudeService.extractClient(brief);
      if (json == null) throw 'No data returned';
      // Build a model from the AI JSON and populate every field.
      final model = ClientProfileModel.fromJson('', Map<String, dynamic>.from(json));
      _clearControllerMaps();
      _loadExisting(model);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Form filled — review and edit before saving'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// Clear list-editor controller maps so reloaded data rebuilds fresh.
  void _clearControllerMaps() {
    for (final m in [
      ..._milestoneCtrls.values, ..._deliverableCtrls.values,
      ..._lineItemCtrls.values, ..._productCtrls.values,
    ]) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _milestoneCtrls.clear();
    _deliverableCtrls.clear();
    _lineItemCtrls.clear();
    _productCtrls.clear();
  }

  // ── STEP 2: Project Overview (adaptive) ─────────────────────────
  Widget _buildStep2() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(cfg.titleLabel, _projectTitle, hint: cfg.titleHint),
        _dropdownField(
          'Project Type',
          _projectType,
          ClientProfileModel.projectTypeLabels,
          (v) => setState(() => _projectType = v),
        ),
        if (cfg.showDescription)
          _textArea(
            'Description',
            _projectDescription,
            hint: 'Describe the scope and objectives...',
            maxLines: 4,
          ),
        if (cfg.showProblem)
          _textArea(
            'Problem Statement',
            _problemStatement,
            hint: 'What problem does the client need solved?',
            maxLines: 3,
          ),
        if (cfg.showGoals)
          _chipListEditor(
            label: 'Goals',
            items: _projectGoals,
            controller: _goalInput,
            hint: 'Add a goal and press Enter',
            onAdd: (v) => setState(() => _projectGoals.add(v)),
            onRemove: (i) => setState(() => _projectGoals.removeAt(i)),
          ),
        // Development
        if (cfg.showTechStack)
          _chipListEditor(
            label: 'Tech Stack',
            items: _techStack,
            hint: 'Flutter, Firebase, Node.js...',
            onAdd: (v) => setState(() => _techStack.add(v)),
            onRemove: (i) => setState(() => _techStack.removeAt(i)),
          ),
        if (cfg.showPlatformTargets)
          _field(
            'Platform Targets',
            _platformTargets,
            hint: 'Web, iOS, Android...',
          ),
        if (cfg.showIntegrationNeeds)
          _field(
            'Integration Needs',
            _integrationNeeds,
            hint: 'Stripe, Google Maps, CRM...',
          ),
        // Design
        if (cfg.showCreativeBrief)
          _textArea(
            'Creative Brief',
            _creativeBrief,
            hint: 'Brand direction, style preferences...',
            maxLines: 3,
          ),
        if (cfg.showBrandGuidelines)
          _toggleField(
            'Brand Guidelines Provided?',
            _brandGuidelines,
            (v) => setState(() => _brandGuidelines = v),
          ),
        if (cfg.showRevisions)
          _numberField(
            'Design Revisions Included',
            _designRevisions,
            hint: 'e.g. 3',
          ),
        // Marketing
        if (cfg.showChannels)
          _chipListEditor(
            label: 'Channels',
            items: _channels,
            hint: 'Social media, Email, SEO...',
            onAdd: (v) => setState(() => _channels.add(v)),
            onRemove: (i) => setState(() => _channels.removeAt(i)),
          ),
        if (cfg.showTargetAudience)
          _field(
            'Target Audience',
            _targetAudience,
            hint: 'B2B enterprise, Gen Z...',
          ),
        if (cfg.showCampaignGoals)
          _textArea(
            'Campaign Goals',
            _campaignGoals,
            hint: 'Awareness, lead-gen, conversions...',
            maxLines: 2,
          ),
        if (cfg.showKpiMetrics)
          _chipListEditor(
            label: 'KPI Metrics',
            items: _kpiMetrics,
            hint: 'CTR, CAC, ROAS...',
            onAdd: (v) => setState(() => _kpiMetrics.add(v)),
            onRemove: (i) => setState(() => _kpiMetrics.removeAt(i)),
          ),
      ],
    );
  }

  // ── STEP 3: Scope (adaptive) ────────────────────────────────────
  Widget _buildStep3() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product line-item table
        if (cfg.showProductTable) ...[
          _sectionLabel('Products'),
          ..._productItems.asMap().entries.map(
            (e) => _productItemCard(e.key, e.value),
          ),
          const SizedBox(height: 8),
          _addButton('Add Product', () {
            setState(() => _productItems.add(const ProductLineItem()));
          }),
          if (_productItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            _productSubtotalRow(),
          ],
        ],
        if (cfg.showWarrantyShipping) ...[
          const SizedBox(height: 16),
          _textArea(
            'Warranty Terms',
            _warrantyTerms,
            hint: '1 year manufacturer warranty...',
            maxLines: 2,
          ),
          _textArea(
            'Shipping Terms',
            _shippingTerms,
            hint: 'Delivery within city, freight charges...',
            maxLines: 2,
          ),
        ],
        // Standard deliverables
        if (cfg.showDeliverables) ...[
          _sectionLabel('Deliverables'),
          ..._deliverables.asMap().entries.map(
            (e) => _deliverableCard(e.key, e.value),
          ),
          const SizedBox(height: 8),
          _addButton('Add Deliverable', () {
            setState(() => _deliverables.add(const DeliverableEntry()));
          }),
        ],
        if (cfg.showSprintCount) ...[
          const SizedBox(height: 16),
          _numberField('Number of Sprints', _sprintCount, hint: 'e.g. 6'),
        ],
        if (cfg.showScopeNotes) ...[
          const SizedBox(height: 16),
          _textArea(
            'Scope Notes',
            _scopeNotes,
            hint: 'What is / isn\'t included...',
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  // ── STEP 4: Timeline (adaptive) ─────────────────────────────────
  Widget _buildStep4() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cfg.showStartEnd)
          Row(
            children: [
              Expanded(
                child: _field('Start Date', _startDate, hint: 'Jan 2026'),
              ),
              const SizedBox(width: 12),
              Expanded(child: _field('End Date', _endDate, hint: 'Mar 2026')),
            ],
          ),
        if (cfg.showDeliveryLeadTime)
          _field(
            'Delivery / Lead Time',
            _endDate,
            hint: 'e.g. 2–3 weeks from order',
          ),
        if (cfg.showMilestones) ...[
          const SizedBox(height: 16),
          _sectionLabel('Milestones'),
          ..._milestones.asMap().entries.map(
            (e) => _milestoneCard(e.key, e.value),
          ),
          const SizedBox(height: 8),
          _addButton('Add Milestone', () {
            setState(() => _milestones.add(const MilestoneEntry()));
          }),
        ],
      ],
    );
  }

  // ── STEP 5: Budget (adaptive) ───────────────────────────────────
  Widget _buildStep5() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product budget: tax %, shipping, auto grand total
        if (cfg.showProductBudget) ...[
          _sectionLabel('Order Totals'),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  'Tax %',
                  _taxPercent,
                  hint: 'e.g. 17',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(
                  'Shipping Cost',
                  _shippingCost,
                  hint: 'e.g. 500',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _grandTotalBox(),
        ],
        if (cfg.showBudgetRange)
          _dropdownField('Budget Range', _budgetRange ?? '', {
            for (final b in ClientProfileModel.budgetRanges) b: b,
          }, (v) => setState(() => _budgetRange = v)),
        if (cfg.showPricingModel)
          _dropdownField(
            'Pricing Model',
            _pricingModel ?? '',
            ClientProfileModel.pricingModelLabels,
            (v) => setState(() => _pricingModel = v),
          ),
        if (cfg.showLineItems) ...[
          const SizedBox(height: 16),
          _sectionLabel('Line Items'),
          ..._lineItems.asMap().entries.map(
            (e) => _lineItemCard(e.key, e.value),
          ),
          const SizedBox(height: 8),
          _addButton('Add Line Item', () {
            setState(() => _lineItems.add(const LineItemEntry()));
          }),
        ],
        if (cfg.showPaymentTerms) ...[
          const SizedBox(height: 16),
          _textArea(
            'Payment Terms',
            _paymentTerms,
            hint: '50% advance, balance on delivery...',
            maxLines: 2,
          ),
        ],
      ],
    );
  }

  // ── STEP 6: Additional Context ──────────────────────────────────
  Widget _buildStep6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textArea(
          'Competitor Info',
          _competitorInfo,
          hint: 'Who are the client\'s competitors?',
          maxLines: 3,
        ),
        _textArea(
          'Special Requirements',
          _specialRequirements,
          hint: 'Compliance, accessibility, constraints...',
          maxLines: 3,
        ),
        _textArea(
          'Custom Notes',
          _customNotes,
          hint: 'Anything else the AI should know...',
          maxLines: 3,
        ),
      ],
    );
  }

  // ─── PRODUCT TABLE ──────────────────────────────────────────────
  Widget _productItemCard(int index, ProductLineItem item) {
    final ctrls = _productCtrls.putIfAbsent(
      index,
      () => {
        'name': TextEditingController(text: item.name),
        'sku': TextEditingController(text: item.sku ?? ''),
        'qty': TextEditingController(text: item.quantity.toString()),
        'price': TextEditingController(
          text: item.unitPrice == 0 ? '' : item.unitPrice.toString(),
        ),
      },
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: ctrls['name'],
                  onChanged: (v) => _productItems[index] = _productItems[index]
                      .copyWith(name: v),
                  style: _inputStyle(),
                  decoration: _inputDeco('Product / model name'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: ctrls['sku'],
                  onChanged: (v) => _productItems[index] = _productItems[index]
                      .copyWith(sku: v),
                  style: _inputStyle(),
                  decoration: _inputDeco('SKU'),
                ),
              ),
              const SizedBox(width: 8),
              _removeIconButton(() => _removeProductItem(index)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrls['qty'],
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(
                    () => _productItems[index] = _productItems[index].copyWith(
                      quantity: int.tryParse(v) ?? 1,
                    ),
                  ),
                  style: _inputStyle(),
                  decoration: _inputDeco('Qty'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrls['price'],
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(
                    () => _productItems[index] = _productItems[index].copyWith(
                      unitPrice: double.tryParse(v) ?? 0,
                    ),
                  ),
                  style: _inputStyle(),
                  decoration: _inputDeco('Unit price'),
                ),
              ),
              const SizedBox(width: 8),
              // Line total (computed)
              Expanded(
                child: Container(
                  height: 48,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderBlush,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _money(_productItems[index].lineTotal),
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      color: AppColors.prussianBlue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _removeProductItem(int index) {
    setState(() {
      _productItems.removeAt(index);
      _productCtrls.clear();
    });
  }

  double get _productSubtotal =>
      _productItems.fold<double>(0, (s, e) => s + e.lineTotal);

  Widget _productSubtotalRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.petalFrost,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Text(
            'Subtotal',
            style: TextStyle(
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.prussianBlue,
            ),
          ),
          const Spacer(),
          Text(
            _money(_productSubtotal),
            style: const TextStyle(
              fontSize: 14,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
              color: AppColors.darkRaspberry,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grandTotalBox() {
    final subtotal = _productSubtotal;
    final ship = double.tryParse(_shippingCost.text.trim()) ?? 0;
    final taxPct = double.tryParse(_taxPercent.text.trim()) ?? 0;
    final taxable = subtotal + ship;
    final tax = taxPct / 100 * taxable;
    final grand = taxable + tax;
    Widget row(String label, double val, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 12,
              fontFamily: AppFonts.openSans,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: bold ? AppColors.prussianBlue : AppColors.slateGrey,
            ),
          ),
          const Spacer(),
          Text(
            _money(val),
            style: TextStyle(
              fontSize: bold ? 15 : 12,
              fontFamily: AppFonts.poppins,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? AppColors.darkRaspberry : AppColors.prussianBlue,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderBlush,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          row('Subtotal', subtotal),
          if (ship > 0) row('Shipping', ship),
          if (taxPct > 0) row('Tax ($taxPct%)', tax),
          const Divider(height: 14, color: AppColors.almondSilk),
          row('Grand Total', grand, bold: true),
        ],
      ),
    );
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  // ─── DELIVERABLE / MILESTONE / LINE ITEM CARDS ──────────────────
  Widget _deliverableCard(int index, DeliverableEntry entry) {
    final ctrls = _deliverableCtrls.putIfAbsent(
      index,
      () => {
        'name': TextEditingController(text: entry.name),
        'desc': TextEditingController(text: entry.description ?? ''),
      },
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrls['name'],
                  onChanged: (v) => _deliverables[index] = _deliverables[index]
                      .copyWith(name: v),
                  style: _inputStyle(),
                  decoration: _inputDeco('Deliverable name'),
                ),
              ),
              const SizedBox(width: 8),
              _removeIconButton(() => _removeDeliverable(index)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrls['desc'],
            onChanged: (v) => _deliverables[index] = _deliverables[index]
                .copyWith(description: v),
            style: _inputStyle(),
            decoration: _inputDeco('Description (optional)'),
          ),
        ],
      ),
    );
  }

  void _removeDeliverable(int index) {
    setState(() {
      _deliverables.removeAt(index);
      _deliverableCtrls.clear();
    });
  }

  Widget _milestoneCard(int index, MilestoneEntry entry) {
    final ctrls = _milestoneCtrls.putIfAbsent(
      index,
      () => {
        'title': TextEditingController(text: entry.title),
        'date': TextEditingController(text: entry.date ?? ''),
        'desc': TextEditingController(text: entry.description ?? ''),
      },
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: ctrls['title'],
                  onChanged: (v) => _milestones[index] = _milestones[index]
                      .copyWith(title: v),
                  style: _inputStyle(),
                  decoration: _inputDeco('Milestone title'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: ctrls['date'],
                  onChanged: (v) =>
                      _milestones[index] = _milestones[index].copyWith(date: v),
                  style: _inputStyle(),
                  decoration: _inputDeco('Date'),
                ),
              ),
              const SizedBox(width: 8),
              _removeIconButton(() => _removeMilestone(index)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrls['desc'],
            onChanged: (v) => _milestones[index] = _milestones[index].copyWith(
              description: v,
            ),
            style: _inputStyle(),
            decoration: _inputDeco('Description (optional)'),
          ),
        ],
      ),
    );
  }

  void _removeMilestone(int index) {
    setState(() {
      _milestones.removeAt(index);
      _milestoneCtrls.clear();
    });
  }

  Widget _lineItemCard(int index, LineItemEntry entry) {
    final ctrls = _lineItemCtrls.putIfAbsent(
      index,
      () => {
        'item': TextEditingController(text: entry.item),
        'desc': TextEditingController(text: entry.description ?? ''),
        'amount': TextEditingController(
          text: entry.amount != null ? entry.amount!.toStringAsFixed(2) : '',
        ),
      },
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: ctrls['item'],
              onChanged: (v) =>
                  _lineItems[index] = _lineItems[index].copyWith(item: v),
              style: _inputStyle(),
              decoration: _inputDeco('Item name'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: ctrls['desc'],
              onChanged: (v) => _lineItems[index] = _lineItems[index].copyWith(
                description: v,
              ),
              style: _inputStyle(),
              decoration: _inputDeco('Description'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: ctrls['amount'],
              onChanged: (v) => _lineItems[index] = _lineItems[index].copyWith(
                amount: double.tryParse(v),
              ),
              style: _inputStyle(),
              keyboardType: TextInputType.number,
              decoration: _inputDeco('Amount'),
            ),
          ),
          const SizedBox(width: 8),
          _removeIconButton(() => _removeLineItem(index)),
        ],
      ),
    );
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems.removeAt(index);
      _lineItemCtrls.clear();
    });
  }

  // ─── FOOTER ─────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0EBE6))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            GestureDetector(
              onTap: () => setState(() => _step--),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.almondSilk),
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                      color: AppColors.slateGrey,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500,
                  color: AppColors.slateGrey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _step < _totalSteps - 1
                ? () => setState(() => _step++)
                : _save,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.darkRaspberry,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _step < _totalSteps - 1 ? 'Next' : 'Save Client',
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SHARED WIDGETS ─────────────────────────────────────────────
  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: _inputStyle(),
            decoration: _inputDeco(hint ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller, {
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            onChanged: onChanged,
            style: _inputStyle(),
            decoration: _inputDeco(hint ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _toggleField(String label, bool? value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
                color: AppColors.prussianBlue,
              ),
            ),
          ),
          _toggleChip('Yes', value == true, () => onChanged(true)),
          const SizedBox(width: 8),
          _toggleChip('No', value == false, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.darkRaspberry : AppColors.lavenderBlush,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.white : AppColors.slateGrey,
          ),
        ),
      ),
    );
  }

  Widget _textArea(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: _inputStyle(),
            maxLines: maxLines,
            decoration: _inputDeco(hint ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Container(
            width: double.infinity,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.lavenderBlush,
            ),
            alignment: Alignment.center,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.containsKey(value) ? value : null,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                hint: const Text(
                  'Select...',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.slateGrey,
                  ),
                ),
                style: _inputStyle(),
                icon: const Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: AppColors.slateGrey,
                ),
                items: options.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, style: _inputStyle()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipListEditor({
    required String label,
    required List<String> items,
    TextEditingController? controller,
    String hint = 'Type and press Enter',
    required ValueChanged<String> onAdd,
    required ValueChanged<int> onRemove,
  }) {
    final ctrl = controller ?? TextEditingController();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            style: _inputStyle(),
            decoration: _inputDeco(hint),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                onAdd(v.trim());
                ctrl.clear();
              }
            },
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.asMap().entries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.value,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: AppFonts.poppins,
                          color: AppColors.darkRaspberry,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => onRemove(e.key),
                        child: const Icon(
                          LucideIcons.x,
                          size: 12,
                          color: AppColors.darkRaspberry,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: AppFonts.poppins,
          fontWeight: FontWeight.w600,
          color: AppColors.prussianBlue,
        ),
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.petalFrost,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.plus,
                size: 14,
                color: AppColors.darkRaspberry,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkRaspberry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _removeIconButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          LucideIcons.trash2,
          size: 12,
          color: Color(0xFFDC2626),
        ),
      ),
    );
  }

  Widget _label(String text) {
    final required = text.trimRight().endsWith('*');
    final base = required ? text.replaceAll('*', '').trim() : text;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: RichText(
        text: TextSpan(
          text: base,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w500,
            color: AppColors.slateGrey,
            letterSpacing: 0.2,
          ),
          children: required
              ? const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: AppColors.darkRaspberry,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  TextStyle _inputStyle() => const TextStyle(
    fontSize: 13,
    fontFamily: AppFonts.openSans,
    color: AppColors.prussianBlue,
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 13,
      fontFamily: AppFonts.openSans,
      color: AppColors.slateGrey,
    ),
    filled: true,
    fillColor: AppColors.lavenderBlush,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.darkRaspberry, width: 1.5),
    ),
  );
}
