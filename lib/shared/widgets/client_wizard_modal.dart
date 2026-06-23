// lib/shared/widgets/client_wizard_modal.dart
//
// 6-step ADAPTIVE modal wizard for creating/editing client profiles.
// Fields shown per step are driven by ClientTypeConfig.forType(projectType).
// All inputs share a unified 48px height + InfoLabel for inline help.
// Layout adapts: phone <600px (stacked) / tablet 600–900 / desktop 900+.
//
// Used from: proposal editor panel, settings > client profiles.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../features/dashboard/controller/dashboard_controller.dart';
import '../../features/settings/view/upgrade_modal.dart';
import '../models/ai_profile_model.dart';
import '../models/client_profile_model.dart';
import '../providers/ai_profiles_provider.dart';
import 'client_ai_chat_modal.dart';
import 'client_type_config.dart';
import 'info_label.dart';

class ClientWizardModal extends ConsumerStatefulWidget {
  final ClientProfileModel? existing;
  final String title;
  const ClientWizardModal({
    super.key,
    this.existing,
    this.title = 'New Client',
  });

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

  bool get _isPhone => MediaQuery.of(context).size.width < 600;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 900;

  // Step 1
  final _clientName = TextEditingController();
  final _clientCompany = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientWebsite = TextEditingController();
  final _industry = TextEditingController();
  final _senderCompany = TextEditingController();
  final _senderName = TextEditingController();
  final _senderEmail = TextEditingController();
  final _senderPhone = TextEditingController();
  final _senderTaxId = TextEditingController();
  final _senderRegNumber = TextEditingController();
  final _clientTaxId = TextEditingController();

  // Step 2
  final _projectTitle = TextEditingController();
  String _projectType = 'general';
  final _projectDescription = TextEditingController();
  final _problemStatement = TextEditingController();
  List<String> _projectGoals = [];
  final _goalInput = TextEditingController();
  final _platformTargets = TextEditingController();
  final _integrationNeeds = TextEditingController();
  final _creativeBrief = TextEditingController();
  final _campaignGoals = TextEditingController();
  final _targetAudience = TextEditingController();
  final _sprintCount = TextEditingController();
  final _designRevisions = TextEditingController();
  bool? _brandGuidelines;
  List<String> _techStack = [];
  List<String> _channels = [];
  List<String> _kpiMetrics = [];

  // Step 3
  List<DeliverableEntry> _deliverables = [];
  final _scopeNotes = TextEditingController();
  final _warrantyTerms = TextEditingController();
  final _shippingTerms = TextEditingController();
  List<ProductLineItem> _productItems = [];

  // Step 4
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  List<MilestoneEntry> _milestones = [];

  // Step 5
  String? _budgetRange;
  String? _pricingModel;
  List<LineItemEntry> _lineItems = [];
  final _taxPercent = TextEditingController();
  final _shippingCost = TextEditingController();
  final _paymentTerms = TextEditingController();

  // Step 6
  final _competitorInfo = TextEditingController();
  final _specialRequirements = TextEditingController();
  final _customNotes = TextEditingController();

  // AI
  String? _selectedProfileId;
  final _briefCtrl = TextEditingController();
  bool _briefOpen = false;
  bool _aiBusy = false;

  // List editor controller caches
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

  ClientProfileModel _buildModel() => ClientProfileModel(
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
    final screen = MediaQuery.of(context).size;
    final dialogW = _isPhone
        ? screen.width - 16
        : _isTablet
        ? screen.width * 0.85
        : 620.0;
    final maxH = _isPhone ? screen.height * 0.94 : screen.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(_isPhone ? 8 : 16),
      child: Container(
        width: dialogW,
        constraints: BoxConstraints(maxHeight: maxH),
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

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(_isPhone ? 16 : 22, 16, 12, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              LucideIcons.userPlus,
              size: 18,
              color: AppColors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: _isPhone ? 15 : 16,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold,
                    color: AppColors.prussianBlue,
                  ),
                ),
                Text(
                  'Step ${_step + 1} of $_totalSteps',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.slateGrey,
                  ),
                ),
              ],
            ),
          ),
          _iconButton(
            LucideIcons.x,
            () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
    final btn = GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0EC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: AppColors.slateGrey),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  Widget _buildStepIndicator() {
    if (_isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_totalSteps, (i) {
            final isActive = i == _step;
            final isDone = i < _step;
            return GestureDetector(
              onTap: () => setState(() => _step = i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.darkRaspberry
                      : isDone
                      ? AppColors.magentaBloom
                      : AppColors.almondSilk.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
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

  Widget _buildStepContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        _isPhone ? 16 : 22,
        12,
        _isPhone ? 16 : 22,
        8,
      ),
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

  /// Two-up row that auto-stacks on phone.
  Widget _pair(Widget a, Widget b) {
    if (_isPhone) return Column(children: [a, b]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }

  // ── STEP 1 ─────────────────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiAutoFill(),
        _buildProfileDropdown(),
        const SizedBox(height: 8),
        _sectionLabel('Your Details'),
        _field(
          'Your Company',
          _senderCompany,
          hint: 'Your Company Ltd.',
          info: 'The name shown on the proposal as the sender.',
        ),
        _field(
          'Your Name',
          _senderName,
          hint: 'Ahmad Ali Khan',
          info: 'Who the client will see as the proposal\'s author.',
        ),
        _pair(
          _field(
            'Your Email',
            _senderEmail,
            hint: 'you@company.com',
            info: 'Used in the proposal contact block.',
          ),
          _field(
            'Your Phone',
            _senderPhone,
            hint: '+1 234 567 890',
            info: 'Optional. Shown in the contact block.',
          ),
        ),
        if (_cfg.showTaxFields)
          _pair(
            _field(
              'Your Tax ID (NTN/VAT)',
              _senderTaxId,
              hint: '1234567-8',
              info:
                  'Your tax identification number. Required on invoices for goods/services.',
            ),
            _field(
              'Company Reg. No.',
              _senderRegNumber,
              hint: 'Optional',
              info:
                  'Your business registration number, if it belongs on the invoice.',
            ),
          ),
        const SizedBox(height: 12),
        _sectionLabel('Client Details'),
        _field(
          'Client Name',
          _clientName,
          hint: 'John Smith',
          required: true,
          info: 'The primary contact at the client\'s end.',
        ),
        _field(
          'Company',
          _clientCompany,
          hint: 'Acme Corporation',
          info: 'The client\'s company or organization name.',
        ),
        _pair(
          _field(
            'Email',
            _clientEmail,
            hint: 'john@acme.com',
            info: 'Where the proposal will be sent.',
          ),
          _field(
            'Phone',
            _clientPhone,
            hint: '+1 234 567 890',
            info: 'Optional client phone.',
          ),
        ),
        if (_cfg.showTaxFields)
          _field(
            'Client Tax ID (NTN/VAT)',
            _clientTaxId,
            hint: 'Optional',
            info: 'Client\'s tax ID, if their invoice needs it.',
          ),
        _field(
          'Website',
          _clientWebsite,
          hint: 'www.acme.com',
          info: 'Helps the AI research the client\'s context.',
        ),
        _field(
          'Industry',
          _industry,
          hint: 'Manufacturing, Technology, Healthcare...',
          info: 'AI uses this to write industry-appropriate language.',
        ),
      ],
    );
  }

  Widget _buildProfileDropdown() {
    final profilesAsync = ref.watch(aiProfilesProvider);
    return profilesAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          InfoLabel(
            'Use Career Profile',
            info: 'Pre-fills your details from a saved Career Profile.',
          ),
          _SkeletonBox(height: 48),
          SizedBox(height: 14),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (profiles) {
        if (profiles.isEmpty) return const SizedBox.shrink();
        final options = <String, String>{
          for (final p in profiles) (p.id ?? ''): p.name,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InfoLabel(
              'Use Career Profile',
              info:
                  'Pre-fills your name, company, and email from a saved Career Profile.',
            ),
            _dropdownContainer(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value:
                      (_selectedProfileId != null &&
                          options.containsKey(_selectedProfileId))
                      ? _selectedProfileId
                      : null,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(10),
                  hint: const Text(
                    'None — fill it myself',
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
                        'None — fill it myself',
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
        // ── Tap-to-expand header (works for both free + pro) ─────
        GestureDetector(
          onTap: () => setState(() => _briefOpen = !_briefOpen),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkRaspberry.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.sparkles,
                    size: 16,
                    color: AppColors.white,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Build this with AI',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  if (!isPro)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _briefOpen
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.white,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Expanded section (different content for free vs pro) ─
        if (_briefOpen) ...[
          const SizedBox(height: 10),
          if (!isPro) _buildFreeUserPreview() else _buildProUserChat(),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  /// Free-user view: explains the feature, shows a disabled input field,
  /// and pops the upgrade modal when they try to send.
  Widget _buildFreeUserPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // What the feature does — bullet list
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.lavenderBlush,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'What this does',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w700,
                  color: AppColors.prussianBlue,
                ),
              ),
              SizedBox(height: 8),
              _FeatureBullet('Skip the 6-step wizard'),
              _FeatureBullet('Just describe your client and project in plain English'),
              _FeatureBullet('AI asks follow-up questions for missing details'),
              _FeatureBullet('Auto-fills sender, client, scope, timeline, and budget'),
              _FeatureBullet('You review and edit before saving'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Disabled textarea (so they can see the input UI)
        Opacity(
          opacity: 0.55,
          child: IgnorePointer(
            child: TextField(
              maxLines: 4,
              enabled: false,
              style: _inputStyle(),
              decoration: _inputDeco(
                'Describe your client and project here...',
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Send button that opens the upgrade modal
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => const UpgradeModal(),
            );
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkRaspberry,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    LucideIcons.sparkles,
                    size: 15,
                    color: AppColors.white,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Unlock with Pro',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pro/Trial user view: the actual chat brief composer.
  Widget _buildProUserChat() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.petalFrost,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(
                LucideIcons.shieldCheck,
                size: 13,
                color: AppColors.darkRaspberry,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your brief isn\'t saved. Closing or reloading clears it.',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.prussianBlue,
                  ),
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
            'Describe your client and project — paste a brief, email, or notes. AI will ask follow-ups if needed and fill the form.',
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _aiBusy ? null : _runAutoFill,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _aiBusy
                    ? AppColors.slateGrey
                    : AppColors.darkRaspberry,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_aiBusy)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  else
                    const Icon(
                      LucideIcons.sparkles,
                      size: 15,
                      color: AppColors.white,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _aiBusy ? 'Working...' : 'Start with AI',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runAutoFill() async {
    final brief = _briefCtrl.text.trim();
    if (brief.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final model = await ClientAiChatModal.show(context, initialBrief: brief);
      if (model == null) return;
      _clearControllerMaps();
      _loadExisting(model);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Form filled — review and edit before saving'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _clearControllerMaps() {
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
    _milestoneCtrls.clear();
    _deliverableCtrls.clear();
    _lineItemCtrls.clear();
    _productCtrls.clear();
  }

  // ── STEP 2 ─────────────────────────────────────────────────────
  Widget _buildStep2() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          cfg.titleLabel,
          _projectTitle,
          hint: cfg.titleHint,
          info: 'A short, memorable name that\'ll head the proposal.',
        ),
        _dropdownField(
          'Project Type',
          _projectType,
          ClientProfileModel.projectTypeLabels,
          (v) => setState(() => _projectType = v),
          info: 'Changes which fields appear in later steps.',
        ),
        if (cfg.showDescription)
          _textArea(
            'Description',
            _projectDescription,
            hint: 'Describe the scope and objectives...',
            maxLines: 4,
            info: 'A 2-3 sentence overview of what you\'re proposing.',
          ),
        if (cfg.showProblem)
          _textArea(
            'Problem Statement',
            _problemStatement,
            hint: 'What problem does the client need solved?',
            maxLines: 3,
            info: 'The pain point this work addresses. Frames the proposal.',
          ),
        if (cfg.showGoals)
          _chipListEditor(
            label: 'Goals',
            items: _projectGoals,
            controller: _goalInput,
            hint: 'Add a goal and press Enter',
            info: 'The outcomes the client wants. Add each one as a tag.',
            onAdd: (v) => setState(() => _projectGoals.add(v)),
            onRemove: (i) => setState(() => _projectGoals.removeAt(i)),
          ),
        if (cfg.showTechStack)
          _chipListEditor(
            label: 'Tech Stack',
            items: _techStack,
            hint: 'Flutter, Firebase, Node.js...',
            info: 'Technologies you\'ll use. Shapes the technical sections.',
            onAdd: (v) => setState(() => _techStack.add(v)),
            onRemove: (i) => setState(() => _techStack.removeAt(i)),
          ),
        if (cfg.showPlatformTargets)
          _field(
            'Platform Targets',
            _platformTargets,
            hint: 'Web, iOS, Android...',
            info: 'Which platforms the deliverable runs on.',
          ),
        if (cfg.showIntegrationNeeds)
          _field(
            'Integration Needs',
            _integrationNeeds,
            hint: 'Stripe, Google Maps, CRM...',
            info: 'Third-party services or systems to connect with.',
          ),
        if (cfg.showCreativeBrief)
          _textArea(
            'Creative Brief',
            _creativeBrief,
            hint: 'Brand direction, style preferences...',
            maxLines: 3,
            info: 'The look-and-feel direction for the design work.',
          ),
        if (cfg.showBrandGuidelines)
          _toggleField(
            'Brand Guidelines Provided?',
            _brandGuidelines,
            (v) => setState(() => _brandGuidelines = v),
            info: 'Yes if the client has a brand guide you must follow.',
          ),
        if (cfg.showRevisions)
          _numberField(
            'Design Revisions Included',
            _designRevisions,
            hint: 'e.g. 3',
            info: 'How many revision rounds are in the price.',
          ),
        if (cfg.showChannels)
          _chipListEditor(
            label: 'Channels',
            items: _channels,
            hint: 'Social media, Email, SEO...',
            info: 'Marketing channels in scope.',
            onAdd: (v) => setState(() => _channels.add(v)),
            onRemove: (i) => setState(() => _channels.removeAt(i)),
          ),
        if (cfg.showTargetAudience)
          _field(
            'Target Audience',
            _targetAudience,
            hint: 'B2B enterprise, Gen Z...',
            info: 'Who the campaign is aimed at.',
          ),
        if (cfg.showCampaignGoals)
          _textArea(
            'Campaign Goals',
            _campaignGoals,
            hint: 'Awareness, lead-gen, conversions...',
            maxLines: 2,
            info: 'What success looks like for the campaign.',
          ),
        if (cfg.showKpiMetrics)
          _chipListEditor(
            label: 'KPI Metrics',
            items: _kpiMetrics,
            hint: 'CTR, CAC, ROAS...',
            info: 'Metrics you\'ll report against.',
            onAdd: (v) => setState(() => _kpiMetrics.add(v)),
            onRemove: (i) => setState(() => _kpiMetrics.removeAt(i)),
          ),
      ],
    );
  }

  // ── STEP 3 ─────────────────────────────────────────────────────
  Widget _buildStep3() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cfg.showProductTable) ...[
          _sectionLabel(
            'Products',
            info: 'Items being sold. Line total is qty × unit price.',
          ),
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
            info: 'What the warranty covers and for how long.',
          ),
          _textArea(
            'Shipping Terms',
            _shippingTerms,
            hint: 'Delivery within city, freight charges...',
            maxLines: 2,
            info: 'How and where you deliver, plus any freight terms.',
          ),
        ],
        if (cfg.showDeliverables) ...[
          _sectionLabel(
            'Deliverables',
            info: 'Concrete outputs the client will receive.',
          ),
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
          _numberField(
            'Number of Sprints',
            _sprintCount,
            hint: 'e.g. 6',
            info: 'Total dev sprints planned. Shapes the timeline section.',
          ),
        ],
        if (cfg.showScopeNotes) ...[
          const SizedBox(height: 16),
          _textArea(
            'Scope Notes',
            _scopeNotes,
            hint: 'What\'s in scope, what\'s explicitly out...',
            maxLines: 3,
            info: 'Anything that needs calling out about scope boundaries.',
          ),
        ],
      ],
    );
  }

  // ── STEP 4 ─────────────────────────────────────────────────────
  Widget _buildStep4() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cfg.showStartEnd)
          _pair(
            _field(
              'Start Date',
              _startDate,
              hint: 'Jan 2026',
              info: 'When the work begins.',
            ),
            _field(
              'End Date',
              _endDate,
              hint: 'Mar 2026',
              info: 'Expected completion date.',
            ),
          ),
        if (cfg.showDeliveryLeadTime)
          _field(
            'Delivery / Lead Time',
            _endDate,
            hint: 'e.g. 2–3 weeks from order',
            info: 'How long after the order until the goods are delivered.',
          ),
        if (cfg.showMilestones) ...[
          const SizedBox(height: 16),
          _sectionLabel(
            'Milestones',
            info: 'Key checkpoints. Each one should have a deliverable.',
          ),
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

  // ── STEP 5 ─────────────────────────────────────────────────────
  Widget _buildStep5() {
    final cfg = _cfg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cfg.showProductBudget) ...[
          _sectionLabel(
            'Order Totals',
            info: 'Grand total = subtotal + shipping + tax %.',
          ),
          _pair(
            _numberField(
              'Tax %',
              _taxPercent,
              hint: 'e.g. 17',
              info: 'Applied to subtotal + shipping.',
              onChanged: (_) => setState(() {}),
            ),
            _numberField(
              'Shipping Cost',
              _shippingCost,
              hint: 'e.g. 500',
              info: 'Flat shipping fee. Leave blank for free shipping.',
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          _grandTotalBox(),
        ],
        if (cfg.showBudgetRange)
          _dropdownField(
            'Budget Range',
            _budgetRange ?? '',
            {for (final b in ClientProfileModel.budgetRanges) b: b},
            (v) => setState(() => _budgetRange = v),
            info: 'Rough ballpark. The AI uses this to anchor pricing.',
          ),
        if (cfg.showPricingModel)
          _dropdownField(
            'Pricing Model',
            _pricingModel ?? '',
            ClientProfileModel.pricingModelLabels,
            (v) => setState(() => _pricingModel = v),
            info: 'How you\'re charging — fixed, hourly, retainer, etc.',
          ),
        if (cfg.showLineItems) ...[
          const SizedBox(height: 16),
          _sectionLabel(
            'Line Items',
            info: 'Itemized pricing rows that\'ll appear in the proposal.',
          ),
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
            info: 'When and how the client pays.',
          ),
        ],
      ],
    );
  }

  // ── STEP 6 ─────────────────────────────────────────────────────
  Widget _buildStep6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textArea(
          'Competitor Info',
          _competitorInfo,
          hint: 'Who are the client\'s competitors?',
          maxLines: 3,
          info: 'AI can position your proposal against these competitors.',
        ),
        _textArea(
          'Special Requirements',
          _specialRequirements,
          hint: 'Compliance, accessibility, constraints...',
          maxLines: 3,
          info: 'Must-haves or constraints the proposal must respect.',
        ),
        _textArea(
          'Custom Notes',
          _customNotes,
          hint: 'Anything else the AI should know...',
          maxLines: 3,
          info: 'Catch-all for context not covered by other fields.',
        ),
      ],
    );
  }

  // ─── PRODUCT TABLE ─────────────────────────────────────────────
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
                child: _bareTextField(
                  ctrls['name']!,
                  'Product / model name',
                  (v) => _productItems[index] = _productItems[index].copyWith(
                    name: v,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _bareTextField(
                  ctrls['sku']!,
                  'SKU',
                  (v) => _productItems[index] = _productItems[index].copyWith(
                    sku: v,
                  ),
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
                child: _bareTextField(
                  ctrls['qty']!,
                  'Qty',
                  (v) => setState(
                    () => _productItems[index] = _productItems[index].copyWith(
                      quantity: int.tryParse(v) ?? 1,
                    ),
                  ),
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bareTextField(
                  ctrls['price']!,
                  'Unit price',
                  (v) => setState(
                    () => _productItems[index] = _productItems[index].copyWith(
                      unitPrice: double.tryParse(v) ?? 0,
                    ),
                  ),
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderBlush,
                    borderRadius: BorderRadius.circular(10),
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

  // ─── DELIVERABLE / MILESTONE / LINE ITEM CARDS ────────────────
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
                child: _bareTextField(
                  ctrls['name']!,
                  'Deliverable name',
                  (v) => _deliverables[index] = _deliverables[index].copyWith(
                    name: v,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _removeIconButton(() => _removeDeliverable(index)),
            ],
          ),
          const SizedBox(height: 8),
          _bareTextField(
            ctrls['desc']!,
            'Description (optional)',
            (v) => _deliverables[index] = _deliverables[index].copyWith(
              description: v,
            ),
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
          _pair(
            _bareTextField(
              ctrls['title']!,
              'Milestone title',
              (v) => _milestones[index] = _milestones[index].copyWith(title: v),
            ),
            _bareTextField(
              ctrls['date']!,
              'Date',
              (v) => _milestones[index] = _milestones[index].copyWith(date: v),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _bareTextField(
                  ctrls['desc']!,
                  'Description (optional)',
                  (v) => _milestones[index] = _milestones[index].copyWith(
                    description: v,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _removeIconButton(() => _removeMilestone(index)),
            ],
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
      child: Column(
        children: [
          _pair(
            _bareTextField(
              ctrls['item']!,
              'Item name',
              (v) => _lineItems[index] = _lineItems[index].copyWith(item: v),
            ),
            _bareTextField(
              ctrls['amount']!,
              'Amount',
              (v) => _lineItems[index] = _lineItems[index].copyWith(
                amount: double.tryParse(v),
              ),
              isNumber: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _bareTextField(
                  ctrls['desc']!,
                  'Description',
                  (v) => _lineItems[index] = _lineItems[index].copyWith(
                    description: v,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _removeIconButton(() => _removeLineItem(index)),
            ],
          ),
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

  // ─── FOOTER ────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        _isPhone ? 16 : 22,
        12,
        _isPhone ? 16 : 22,
        16,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0EBE6))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            _ghostButton(
              'Back',
              LucideIcons.arrowLeft,
              onTap: () => setState(() => _step--),
            ),
          const Spacer(),
          if (!_isPhone) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            const SizedBox(width: 4),
          ],
          _primaryButton(
            _step < _totalSteps - 1 ? 'Next' : 'Save Client',
            _step < _totalSteps - 1
                ? LucideIcons.arrowRight
                : LucideIcons.check,
            iconLeft: false,
            onTap: _step < _totalSteps - 1
                ? () => setState(() => _step++)
                : _save,
          ),
        ],
      ),
    );
  }

  Widget _ghostButton(
    String label,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.almondSilk),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.slateGrey),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500,
                  color: AppColors.slateGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(
    String label,
    IconData icon, {
    required VoidCallback onTap,
    bool iconLeft = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.darkRaspberry,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkRaspberry.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconLeft) ...[
                Icon(icon, size: 13, color: AppColors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.white,
                ),
              ),
              if (!iconLeft) ...[
                const SizedBox(width: 6),
                Icon(icon, size: 13, color: AppColors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── SHARED INPUTS (uniform 48px) ──────────────────────────────
  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    String? info,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(label, info: info, required: required),
          SizedBox(
            height: 48,
            child: TextField(
              controller: controller,
              style: _inputStyle(),
              decoration: _inputDeco(hint ?? ''),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller, {
    String? hint,
    String? info,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(label, info: info),
          SizedBox(
            height: 48,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              onChanged: onChanged,
              style: _inputStyle(),
              decoration: _inputDeco(hint ?? ''),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleField(
    String label,
    bool? value,
    ValueChanged<bool> onChanged, {
    String? info,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(child: InfoLabel(label, info: info)),
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
      ),
    );
  }

  Widget _textArea(
    String label,
    TextEditingController controller, {
    String? hint,
    String? info,
    int maxLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(label, info: info),
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
    ValueChanged<String> onChanged, {
    String? info,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(label, info: info),
          _dropdownContainer(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.containsKey(value) ? value : null,
                isExpanded: true,
                borderRadius: BorderRadius.circular(10),
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
    String? info,
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
          InfoLabel(label, info: info),
          SizedBox(
            height: 48,
            child: TextField(
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

  Widget _sectionLabel(String text, {String? info}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
              color: AppColors.prussianBlue,
              letterSpacing: 0.2,
            ),
          ),
          if (info != null) ...[
            const SizedBox(width: 6),
            _SectionInfoIcon(text: info),
          ],
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.petalFrost,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.darkRaspberry.withValues(alpha: 0.15),
            ),
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            LucideIcons.trash2,
            size: 13,
            color: Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }

  Widget _dropdownContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.lavenderBlush,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  /// Card-internal text field (no label, no info icon, uniform 48px).
  Widget _bareTextField(
    TextEditingController c,
    String hint,
    ValueChanged<String> onChanged, {
    bool isNumber = false,
  }) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: c,
        keyboardType: isNumber ? TextInputType.number : null,
        onChanged: onChanged,
        style: _inputStyle(),
        decoration: _inputDeco(hint),
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 13,
      fontFamily: AppFonts.openSans,
      color: AppColors.slateGrey,
    ),
    filled: true,
    fillColor: AppColors.lavenderBlush,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.darkRaspberry, width: 1.5),
    ),
  );
}

// ─── Tiny info icon used inline next to section labels ───────────────
class _SectionInfoIcon extends StatelessWidget {
  final String text;
  const _SectionInfoIcon({required this.text});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      textStyle: const TextStyle(
        fontSize: 11.5,
        fontFamily: AppFonts.openSans,
        color: AppColors.white,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: AppColors.prussianBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: const Icon(LucideIcons.info, size: 13, color: AppColors.slateGrey),
    );
  }
}

// ─── Skeleton box with a soft shimmer (no extra package) ─────────────
class _SkeletonBox extends StatefulWidget {
  final double height;
  const _SkeletonBox({required this.height});
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        return Container(
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Color.lerp(AppColors.lavenderBlush, AppColors.petalFrost, t),
          ),
        );
      },
    );
  }
}

// ─── Bullet row for the free-user feature preview ────────────────────
class _FeatureBullet extends StatelessWidget {
  final String text;
  const _FeatureBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.check,
            size: 13,
            color: AppColors.darkRaspberry,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: AppFonts.openSans,
                color: AppColors.prussianBlue,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}