// lib/shared/widgets/client_wizard_modal.dart
//
// 6-step modal wizard for creating/editing client profiles.
// Adaptive fields based on projectType.
// Used from: proposal editor panel, settings > client profiles.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../models/client_profile_model.dart';

class ClientWizardModal extends StatefulWidget {
  final ClientProfileModel? existing;
  final String title;

  const ClientWizardModal({super.key, this.existing, this.title = 'New Client'});

  /// Shows the wizard and returns the filled model, or null if cancelled.
  static Future<ClientProfileModel?> show(BuildContext context,
      {ClientProfileModel? existing})
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
  State<ClientWizardModal> createState() => _ClientWizardModalState();
}

class _ClientWizardModalState extends State<ClientWizardModal> {
  int _step = 0;
  static const _totalSteps = 6;

  // Step 1: Client Info
  final _clientName = TextEditingController();
  final _clientCompany = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientWebsite = TextEditingController();
  final _industry = TextEditingController();

  // Step 2: Project Overview
  final _projectTitle = TextEditingController();
  String _projectType = 'general';
  final _projectDescription = TextEditingController();
  final _problemStatement = TextEditingController();
  List<String> _projectGoals = [];
  final _goalInput = TextEditingController();

  // Step 3: Deliverables
  List<DeliverableEntry> _deliverables = [];
  final _scopeNotes = TextEditingController();

  // Step 4: Timeline
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  List<MilestoneEntry> _milestones = [];

  // Step 5: Budget
  String? _budgetRange;
  String? _pricingModel;
  List<LineItemEntry> _lineItems = [];

  // Step 6: Additional
  final _competitorInfo = TextEditingController();
  final _specialRequirements = TextEditingController();
  final _customNotes = TextEditingController();

  // Type-specific
  List<String> _techStack = [];
  final _platformTargets = TextEditingController();
  final _creativeBrief = TextEditingController();
  List<String> _channels = [];
  final _targetAudience = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _loadExisting(widget.existing!);
  }

  void _loadExisting(ClientProfileModel p) {
    _clientName.text = p.clientName;
    _clientCompany.text = p.clientCompany ?? '';
    _clientEmail.text = p.clientEmail ?? '';
    _clientPhone.text = p.clientPhone ?? '';
    _clientWebsite.text = p.clientWebsite ?? '';
    _industry.text = p.industry ?? '';
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
    _techStack = List.from(p.typeSpecific.techStack);
    _platformTargets.text = p.typeSpecific.platformTargets ?? '';
    _creativeBrief.text = p.typeSpecific.creativeBrief ?? '';
    _channels = List.from(p.typeSpecific.channels);
    _targetAudience.text = p.typeSpecific.targetAudience ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _clientName, _clientCompany, _clientEmail, _clientPhone, _clientWebsite,
      _industry, _projectTitle, _projectDescription, _problemStatement,
      _goalInput, _scopeNotes, _startDate, _endDate, _competitorInfo,
      _specialRequirements, _customNotes, _platformTargets, _creativeBrief,
      _targetAudience,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ClientProfileModel _buildModel() {
    return ClientProfileModel(
      id: widget.existing?.id,
      clientName: _clientName.text.trim(),
      clientCompany: _clientCompany.text.trim().isEmpty ? null : _clientCompany.text.trim(),
      clientEmail: _clientEmail.text.trim().isEmpty ? null : _clientEmail.text.trim(),
      clientPhone: _clientPhone.text.trim().isEmpty ? null : _clientPhone.text.trim(),
      clientWebsite: _clientWebsite.text.trim().isEmpty ? null : _clientWebsite.text.trim(),
      industry: _industry.text.trim().isEmpty ? null : _industry.text.trim(),
      projectTitle: _projectTitle.text.trim(),
      projectType: _projectType,
      projectDescription: _projectDescription.text.trim().isEmpty ? null : _projectDescription.text.trim(),
      problemStatement: _problemStatement.text.trim().isEmpty ? null : _problemStatement.text.trim(),
      projectGoals: _projectGoals,
      deliverables: _deliverables,
      scopeNotes: _scopeNotes.text.trim().isEmpty ? null : _scopeNotes.text.trim(),
      startDate: _startDate.text.trim().isEmpty ? null : _startDate.text.trim(),
      endDate: _endDate.text.trim().isEmpty ? null : _endDate.text.trim(),
      milestones: _milestones,
      budgetRange: _budgetRange,
      pricingModel: _pricingModel,
      lineItems: _lineItems,
      competitorInfo: _competitorInfo.text.trim().isEmpty ? null : _competitorInfo.text.trim(),
      specialRequirements: _specialRequirements.text.trim().isEmpty ? null : _specialRequirements.text.trim(),
      customNotes: _customNotes.text.trim().isEmpty ? null : _customNotes.text.trim(),
      typeSpecific: TypeSpecificFields(
        techStack: _techStack,
        platformTargets: _platformTargets.text.trim().isEmpty ? null : _platformTargets.text.trim(),
        creativeBrief: _creativeBrief.text.trim().isEmpty ? null : _creativeBrief.text.trim(),
        channels: _channels,
        targetAudience: _targetAudience.text.trim().isEmpty ? null : _targetAudience.text.trim(),
      ),
      createdAt: widget.existing?.createdAt,
    );
  }

  void _save() {
    if (_clientName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client name is required')),
      );
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
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.userPlus, size: 16, color: AppColors.darkRaspberry),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: const TextStyle(fontSize: 16, fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
                Text(_stepLabels[_step],
                    style: const TextStyle(fontSize: 11, fontFamily: AppFonts.openSans,
                        color: AppColors.slateGrey)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F0EC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.x, size: 14, color: AppColors.slateGrey),
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
          key: ValueKey(_step),
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
        _field('Client Name *', _clientName, hint: 'John Smith'),
        _field('Company', _clientCompany, hint: 'Acme Corporation'),
        Row(children: [
          Expanded(child: _field('Email', _clientEmail, hint: 'john@acme.com')),
          const SizedBox(width: 12),
          Expanded(child: _field('Phone', _clientPhone, hint: '+1 234 567 890')),
        ]),
        _field('Website', _clientWebsite, hint: 'www.acme.com'),
        _field('Industry', _industry, hint: 'Manufacturing, Technology, Healthcare...'),
      ],
    );
  }

  // ── STEP 2: Project Overview ────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Project Title', _projectTitle, hint: 'Website Redesign, Pump Supply, etc.'),
        _dropdownField('Project Type', _projectType,
            ClientProfileModel.projectTypeLabels, (v) => setState(() => _projectType = v)),
        _textArea('Project Description', _projectDescription,
            hint: 'Describe the project scope and objectives...', maxLines: 4),
        _textArea('Problem Statement', _problemStatement,
            hint: 'What problem does the client need solved?', maxLines: 3),
        _chipListEditor(
          label: 'Project Goals',
          items: _projectGoals,
          controller: _goalInput,
          hint: 'Add a goal and press Enter',
          onAdd: (v) => setState(() => _projectGoals.add(v)),
          onRemove: (i) => setState(() => _projectGoals.removeAt(i)),
        ),
        // Type-specific fields
        if (_projectType == 'development') ...[
          const SizedBox(height: 8),
          _chipListEditor(
            label: 'Tech Stack',
            items: _techStack,
            hint: 'Flutter, Firebase, Node.js...',
            onAdd: (v) => setState(() => _techStack.add(v)),
            onRemove: (i) => setState(() => _techStack.removeAt(i)),
          ),
          _field('Platform Targets', _platformTargets, hint: 'Web, iOS, Android...'),
        ],
        if (_projectType == 'design')
          _textArea('Creative Brief', _creativeBrief,
              hint: 'Brand direction, style preferences, target audience...', maxLines: 3),
        if (_projectType == 'marketing') ...[
          _chipListEditor(
            label: 'Channels',
            items: _channels,
            hint: 'Social media, Email, SEO...',
            onAdd: (v) => setState(() => _channels.add(v)),
            onRemove: (i) => setState(() => _channels.removeAt(i)),
          ),
          _field('Target Audience', _targetAudience, hint: 'B2B enterprise, Gen Z consumers...'),
        ],
      ],
    );
  }

  // ── STEP 3: Deliverables ────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Deliverables'),
        ..._deliverables.asMap().entries.map((e) => _deliverableCard(e.key, e.value)),
        const SizedBox(height: 8),
        _addButton('Add Deliverable', () {
          setState(() => _deliverables.add(const DeliverableEntry()));
        }),
        const SizedBox(height: 16),
        _textArea('Scope Notes', _scopeNotes,
            hint: 'Any additional notes about what is/isn\'t included...', maxLines: 3),
      ],
    );
  }

  Widget _deliverableCard(int index, DeliverableEntry entry) {
    final nameCtrl = TextEditingController(text: entry.name);
    final descCtrl = TextEditingController(text: entry.description ?? '');
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
          Row(children: [
            Expanded(
              child: TextField(
                controller: nameCtrl,
                onChanged: (v) => _deliverables[index] = entry.copyWith(name: v),
                style: _inputStyle(),
                decoration: _inputDeco('Deliverable name'),
              ),
            ),
            const SizedBox(width: 8),
            _removeIconButton(() => setState(() => _deliverables.removeAt(index))),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: descCtrl,
            onChanged: (v) => _deliverables[index] = entry.copyWith(description: v),
            style: _inputStyle(),
            decoration: _inputDeco('Description (optional)'),
          ),
        ],
      ),
    );
  }

  // ── STEP 4: Timeline ────────────────────────────────────────────

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _field('Start Date', _startDate, hint: 'Jan 2026')),
          const SizedBox(width: 12),
          Expanded(child: _field('End Date', _endDate, hint: 'Mar 2026')),
        ]),
        const SizedBox(height: 16),
        _sectionLabel('Milestones'),
        ..._milestones.asMap().entries.map((e) => _milestoneCard(e.key, e.value)),
        const SizedBox(height: 8),
        _addButton('Add Milestone', () {
          setState(() => _milestones.add(const MilestoneEntry()));
        }),
      ],
    );
  }

  Widget _milestoneCard(int index, MilestoneEntry entry) {
    final titleCtrl = TextEditingController(text: entry.title);
    final dateCtrl = TextEditingController(text: entry.date ?? '');
    final descCtrl = TextEditingController(text: entry.description ?? '');
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
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: titleCtrl,
                onChanged: (v) => _milestones[index] = entry.copyWith(title: v),
                style: _inputStyle(),
                decoration: _inputDeco('Milestone title'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: dateCtrl,
                onChanged: (v) => _milestones[index] = entry.copyWith(date: v),
                style: _inputStyle(),
                decoration: _inputDeco('Date'),
              ),
            ),
            const SizedBox(width: 8),
            _removeIconButton(() => setState(() => _milestones.removeAt(index))),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: descCtrl,
            onChanged: (v) => _milestones[index] = entry.copyWith(description: v),
            style: _inputStyle(),
            decoration: _inputDeco('Description (optional)'),
          ),
        ],
      ),
    );
  }

  // ── STEP 5: Budget ──────────────────────────────────────────────

  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdownField('Budget Range', _budgetRange ?? '',
            {for (final b in ClientProfileModel.budgetRanges) b: b},
                (v) => setState(() => _budgetRange = v)),
        _dropdownField('Pricing Model', _pricingModel ?? '',
            ClientProfileModel.pricingModelLabels,
                (v) => setState(() => _pricingModel = v)),
        const SizedBox(height: 16),
        _sectionLabel('Line Items'),
        ..._lineItems.asMap().entries.map((e) => _lineItemCard(e.key, e.value)),
        const SizedBox(height: 8),
        _addButton('Add Line Item', () {
          setState(() => _lineItems.add(const LineItemEntry()));
        }),
      ],
    );
  }

  Widget _lineItemCard(int index, LineItemEntry entry) {
    final itemCtrl = TextEditingController(text: entry.item);
    final descCtrl = TextEditingController(text: entry.description ?? '');
    final amtCtrl = TextEditingController(
        text: entry.amount != null ? entry.amount!.toStringAsFixed(2) : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: itemCtrl,
            onChanged: (v) => _lineItems[index] = entry.copyWith(item: v),
            style: _inputStyle(),
            decoration: _inputDeco('Item name'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: descCtrl,
            onChanged: (v) => _lineItems[index] = entry.copyWith(description: v),
            style: _inputStyle(),
            decoration: _inputDeco('Description'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: amtCtrl,
            onChanged: (v) => _lineItems[index] =
                entry.copyWith(amount: double.tryParse(v)),
            style: _inputStyle(),
            keyboardType: TextInputType.number,
            decoration: _inputDeco('Amount'),
          ),
        ),
        const SizedBox(width: 8),
        _removeIconButton(() => setState(() => _lineItems.removeAt(index))),
      ]),
    );
  }

  // ── STEP 6: Additional Context ──────────────────────────────────

  Widget _buildStep6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textArea('Competitor Info', _competitorInfo,
            hint: 'Who are the client\'s competitors? Any reference projects?', maxLines: 3),
        _textArea('Special Requirements', _specialRequirements,
            hint: 'Compliance, accessibility, integration constraints...', maxLines: 3),
        _textArea('Custom Notes', _customNotes,
            hint: 'Anything else the AI should know when generating the proposal...', maxLines: 3),
      ],
    );
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.almondSilk),
                  ),
                  child: const Text('Back',
                      style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w500, color: AppColors.slateGrey)),
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500, color: AppColors.slateGrey)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _step < _totalSteps - 1 ? () => setState(() => _step++) : _save,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.darkRaspberry,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _step < _totalSteps - 1 ? 'Next' : 'Save Client',
                  style: const TextStyle(fontSize: 13, fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600, color: AppColors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SHARED WIDGETS ─────────────────────────────────────────────

  Widget _field(String label, TextEditingController controller, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
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

  Widget _textArea(String label, TextEditingController controller,
      {String? hint, int maxLines = 3}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
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

  Widget _dropdownField(String label, String value, Map<String, String> options,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Container(
            width: double.infinity,
            height: 52, // matches text field height (vertical:16 padding)
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
                hint: const Text('Select...', style: TextStyle(fontSize: 13,
                    fontFamily: AppFonts.openSans, color: AppColors.slateGrey)),
                style: _inputStyle(),
                icon: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.slateGrey),
                items: options.entries.map((e) => DropdownMenuItem(
                    value: e.key, child: Text(e.value, style: _inputStyle()))).toList(),
                onChanged: (v) { if (v != null) onChanged(v); },
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
          Text(label, style: const TextStyle(fontSize: 11, fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.value, style: const TextStyle(fontSize: 11,
                          fontFamily: AppFonts.poppins, color: AppColors.darkRaspberry)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => onRemove(e.key),
                        child: const Icon(LucideIcons.x, size: 12, color: AppColors.darkRaspberry),
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
      child: Text(text, style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
          fontWeight: FontWeight.w600, color: AppColors.prussianBlue)),
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
              const Icon(LucideIcons.plus, size: 14, color: AppColors.darkRaspberry),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600, color: AppColors.darkRaspberry)),
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
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(LucideIcons.trash2, size: 12, color: Color(0xFFDC2626)),
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
          style: const TextStyle(fontSize: 11, fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500, color: AppColors.slateGrey, letterSpacing: 0.2),
          children: required
              ? const [TextSpan(text: ' *',
              style: TextStyle(color: AppColors.darkRaspberry, fontWeight: FontWeight.w700))]
              : null,
        ),
      ),
    );
  }

  TextStyle _inputStyle() => const TextStyle(
      fontSize: 13, fontFamily: AppFonts.openSans, color: AppColors.prussianBlue);

  InputDecoration _inputDeco(String hint) => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, fontFamily: AppFonts.openSans,
        color: AppColors.slateGrey), // full opacity → readable
    filled: true,
    fillColor: AppColors.lavenderBlush,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkRaspberry, width: 1.5)),
  );
}