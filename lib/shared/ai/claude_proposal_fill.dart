// lib/shared/ai/claude_proposal_fill.dart
//
// Proposal-specific filling logic, extracted from claude_controller.dart during
// E1 file structure cleanup.
//
// This is a `part of` claude_controller.dart — it gets compiled into the
// same library, so it has full access to private members. The one exception
// is `state =` on StateNotifier, which Riverpod restricts to direct subclass
// methods only; the extension uses setStateFromExtension() as a bridge.

part of 'claude_controller.dart';

extension ClaudeProposalFillExtension on ClaudeController {

  // ═══════════════════════════════════════════════════════════════════════
  // AI GENERATE PROPOSAL (one-shot, whole proposal: text + tables)
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> fillAllProposalSections({
    required List<CanvasItem> items,
    required PropEditorController editor,
  }) async
  {
    if (stateForExtension.isActive) return;
    debugPrint('🤖 [ClaudeController] fillAllProposalSections');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setStateFromExtension(const ClaudeState(status: AiFillStatus.error, error: 'Please sign in.'));
      return;
    }

    setStateFromExtension(const ClaudeState(status: AiFillStatus.loading, activeOperation: 'fill'));

    AiProfileModel? profile;
    try {
      cachedProfile ??= await _loadAiProfile(uid);
      profile = cachedProfile;
    } catch (_) {}
    profile ??= const AiProfileModel();
    final templateId = editor.state.templateId ?? '';

    final client = await editor.getLinkedClient();
    if (client == null) {
      setStateFromExtension(const ClaudeState(
        status: AiFillStatus.error,
        error: 'No client linked. Select a client first.',
      ));
      return;
    }

    String? cvContent;
    if (editor.state.linkedCvId != null) {
      cvContent = await editor.getLinkedCvContent();
    }

    final manifest = <Map<String, dynamic>>[];
    final keyToItem = <String, CanvasItem>{};
    int slot = 0;
    for (final item in items) {
      if (item.role == 'hero' ||
          item.role == 'top_band' ||
          item.role == 'signature' ||
          item.role == 'heading' ||
          item.role == 'underline') {
        continue;
      }
      final lt = item.title.trim().toLowerCase();
      if (lt == 'signature' || lt == 'signature author') continue;
      if (item.isText && item.controller != null) {
        final key = 's$slot';
        keyToItem[key] = item;
        final shape = PropTemplateData.getContentShape(templateId, item.title);
        manifest.add({
          'id': key,
          'sectionType': item.sectionType.key,
          'title': item.title,
          'kind': 'text',
          'shape': ?shape,
        });
        slot++;
      } else if (item.isTable && item.tableData != null) {
        final key = 's$slot';
        keyToItem[key] = item;
        manifest.add({
          'id': key,
          'sectionType': item.sectionType.key,
          'title': item.title,
          'kind': 'table',
          'headers': item.tableData!.headers,
          'columnCount': item.tableData!.columnCount,
          'maxRows': item.tableData!.rowCount,
        });
        slot++;
      }
    }

    if (manifest.isEmpty) {
      setStateFromExtension(const ClaudeState(
        status: AiFillStatus.error,
        error: 'No fillable sections on this proposal.',
      ));
      return;
    }

    final clientBrief = _buildClientBrief(client);

    try {
      final content = await ClaudeService.aiFillSection(
        sectionType: 'all',
        tone: profile.tone,
        experienceLevel: profile.experienceLevel,
        profile: _sanitizeProfile(profile.toJson()),
        tool: 'proposal',
        documentId: editor.state.firestoreDocId,
        documentTitle: editor.state.title,
        jobDetails: clientBrief,
        cvContent: cvContent,
        sectionManifest: manifest,
      );

      if (!mounted) return;
      if (content == null) {
        setStateFromExtension(const ClaudeState(
          status: AiFillStatus.error,
          error: 'AI returned no content. Add more client detail.',
        ));
        return;
      }

      debugPrint('🤖 [Proposal] returned keys: ${content.keys.toList()}');
      debugPrint('🤖 [Proposal] expected keys: ${keyToItem.keys.toList()}');

      int filled = 0;
      content.forEach((key, sec) {
        final item = keyToItem[key];
        if (item == null || sec is! Map) return;
        final map = Map<String, dynamic>.from(sec);
        final kind = map['kind'] as String?;

        try {
          if (item.isText && item.controller != null && kind != 'table') {
            final styles = _extractStyles(item.controller!.document);
            item.controller!.updateSelection(
                const TextSelection.collapsed(offset: 0), ChangeSource.local);
            item.controller!.document =
                Document.fromJson(_buildStyledDelta(map, styles));
            filled++;
          } else if (item.isTable && item.tableData != null && kind == 'table') {
            final newRows = _coerceRows(map['rows'], item.tableData!.columnCount);
            if (newRows.isNotEmpty) {
              item.tableData!.rows = newRows;
              filled++;
            }
          }
        } catch (e) {
          debugPrint('🤖 [ClaudeController] Apply failed for $key: $e');
        }
      });

      _fillCoverSlots(items, client: client, profile: profile);
      _fillSignatureSlots(items, client: client, profile: profile);
      editor.canvas.autoArrange();
      editor.markDirty();

      setStateFromExtension(ClaudeState(status: AiFillStatus.done, streamedChars: filled));
      _bumpDashboardCounter(tool: 'proposal', isRewrite: false);
      debugPrint('🤖 [ClaudeController] fillAllProposalSections OK — $filled filled');
    } catch (e) {
      if (!mounted) return;
      final isPaywall = e.toString().contains('limit') || e.toString().contains('Upgrade');
      setStateFromExtension(ClaudeState(
        status: isPaywall ? AiFillStatus.paywalled : AiFillStatus.error,
        error: e.toString(),
      ));
    }
  }

  List<List<String>> _coerceRows(dynamic raw, int cols) {
    if (raw is! List) return [];
    final out = <List<String>>[];
    for (final r in raw) {
      if (r is! List) continue;
      final cells = r.map((c) => c?.toString() ?? '').toList();
      while (cells.length < cols) {
        cells.add('');
      }
      out.add(cells.length > cols ? cells.sublist(0, cols) : cells);
    }
    return out;
  }

  Map<String, dynamic> _buildClientBrief(ClientProfileModel c) {
    return {
      'clientName': c.clientName,
      'clientCompany': c.clientCompany,
      'industry': c.industry,
      'projectTitle': c.projectTitle,
      'projectType': c.projectType,
      'projectDescription': c.projectDescription,
      'problemStatement': c.problemStatement,
      'projectGoals': c.projectGoals,
      'deliverables': c.deliverables.map((d) => {
        'name': d.name, 'description': d.description,
      }).toList(),
      'scopeNotes': c.scopeNotes,
      'startDate': c.startDate,
      'endDate': c.endDate,
      'milestones': c.milestones.map((m) => {
        'title': m.title, 'date': m.date, 'description': m.description,
      }).toList(),
      'budgetRange': c.budgetRange,
      'pricingModel': c.pricingModel,
      'lineItems': c.lineItems.map((l) => {
        'item': l.item, 'description': l.description, 'amount': l.amount,
      }).toList(),
      'competitorInfo': c.competitorInfo,
      'specialRequirements': c.specialRequirements,
      'customNotes': c.customNotes,
      'typeSpecific': {
        'techStack': c.typeSpecific.techStack,
        'platformTargets': c.typeSpecific.platformTargets,
        'creativeBrief': c.typeSpecific.creativeBrief,
        'channels': c.typeSpecific.channels,
        'targetAudience': c.typeSpecific.targetAudience,
      },
    };
  }

  void _fillCoverSlots(
      List<CanvasItem> items, {
        required ClientProfileModel client,
        required AiProfileModel profile,
      })
  {
    final senderCompany = (client.senderCompany ?? '').isNotEmpty
        ? client.senderCompany!
        : (profile.companyName.isNotEmpty ? profile.companyName : 'Your Company');
    final senderEmail = (client.senderEmail ?? '').isNotEmpty
        ? client.senderEmail! : profile.email;

    for (final item in items) {
      final isCover = item.role == 'hero' || item.role == 'top_band' || item.role == 'pinned';
      if (!isCover || !item.isText || item.controller == null) {
        continue;
      }
      final title = item.title.trim().toLowerCase();

      List<String>? values;
      switch (title) {
        case 'proposal title':
          values = [
            keepLine0Sentinel,
            (client.projectTitle.isNotEmpty
                ? client.projectTitle
                : 'Project Proposal'),
          ];
          break;
        case 'client info':
          values = [
            keepLine0Sentinel,
            client.clientName.isNotEmpty ? client.clientName : 'Client Name',
            _joinPipe([client.clientCompany, client.clientEmail]),
          ];
          break;
        case 'author info':
          values = [
            profile.fullName.isNotEmpty ? profile.fullName : 'Your Name',
            (profile.jobTitle ?? '').isNotEmpty
                ? profile.jobTitle!
                : (profile.industry),
            _joinPipe([profile.email, profile.phone]),
          ];
          break;
        case 'date':
          values = [_todayLong()];
          break;
        case 'header':
          values = [
            profile.fullName.isNotEmpty ? profile.fullName : 'Your Name',
            _joinPipe([
              (profile.jobTitle ?? '').isNotEmpty
                  ? profile.jobTitle!
                  : profile.industry,
              'Freelance Professional',
            ]),
          ];
          break;
        case 'contact':
          values = [
            profile.email.isNotEmpty ? profile.email : 'email@example.com',
            profile.phone.isNotEmpty ? profile.phone : '+1 234 567 890',
            (profile.website ?? '').isNotEmpty
                ? profile.website!
                : 'www.yourwebsite.com',
          ];
          break;
        case 'proposal for':
          final clientName = client.clientName.isNotEmpty
              ? client.clientName
              : 'Client Name';
          values = ['Proposal for $clientName  |  ${_todayLong()}'];
          break;
        case 'title':
          final lineCountCheck = item.controller!.document
              .toDelta()
              .toList()
              .map((op) => (op.data is String ? op.data as String : '').split('\n').length - 1)
              .fold<int>(0, (a, b) => a + b);
          if (lineCountCheck >= 4) {
            final projectName = client.projectTitle.isNotEmpty
                ? client.projectTitle
                : 'Project Name';
            values = [
              keepLine0Sentinel,
              keepLine0Sentinel,
              keepLine0Sentinel,
              'Strategic Partnership for $projectName',
            ];
          } else {
            continue;
          }
          break;
        case 'client':
          final clientName = client.clientName.isNotEmpty
              ? client.clientName
              : 'Client Name';
          values = [
            keepLine0Sentinel,
            clientName,
            _joinPipe([client.clientCompany, _todayLong()]),
          ];
          break;
        case 'agency name':
          values = [
            (profile.industry).isNotEmpty
                ? profile.industry.toUpperCase()
                : 'YOUR AGENCY',
          ];
          break;
        case 'subtitle':
          final projectName = client.projectTitle.isNotEmpty
              ? client.projectTitle
              : 'Project Name';
          final clientName = client.clientName.isNotEmpty
              ? client.clientName
              : 'Client Name';
          values = [
            'A bold approach to $projectName',
            'Prepared for $clientName  |  ${_todayLong()}',
          ];
          break;
        case 'contact cover':
          values = [
            profile.fullName.isNotEmpty ? profile.fullName : 'Your Name',
            _joinPipe([
              (profile.jobTitle ?? '').isNotEmpty
                  ? profile.jobTitle!
                  : profile.industry,
              profile.email,
              profile.phone,
            ]),
          ];
          break;
        case 'main title':
          values = [
            keepLine0Sentinel,
            'Prepared for ${(client.clientCompany ?? '').isNotEmpty ? client.clientCompany! : 'Client Company'}',
            _todayLong(),
          ];
          break;
        case 'sidebar company':
          continue;
        case 'sidebar contact':
          values = [
            keepLine0Sentinel,
            profile.fullName.isNotEmpty ? profile.fullName : 'Your Name',
            (profile.jobTitle ?? '').isNotEmpty ? profile.jobTitle! : 'Sales Director',
            profile.email.isNotEmpty ? profile.email : 'your@email.com',
            profile.phone.isNotEmpty ? profile.phone : '+1 234 567 890',
          ];
          break;
        case 'company name':
        case 'provider company':
          values = [senderCompany];
          break;
        case 'project title':
          values = [
            keepLine0Sentinel,
            client.projectTitle.isNotEmpty
                ? client.projectTitle
                : 'Project Name',
          ];
          break;
        case 'meta info':
          values = [
            keepLine0Sentinel,
            client.clientName.isNotEmpty ? client.clientName : 'Client Name',
            (client.clientCompany ?? '').isNotEmpty
                ? client.clientCompany!
                : 'Client Company',
          ];
          break;
        case 'meta date':
          values = [
            keepLine0Sentinel,
            _todayLong(),
            keepLine0Sentinel,
          ];
          break;
        case 'parties':
          values = [
            keepLine0Sentinel,
            senderCompany,
            (profile.location.isNotEmpty ? profile.location : 'Address Line 1'),
            senderEmail.isNotEmpty ? senderEmail : 'contact@company.com',
          ];
          break;
        case 'service client':
          values = [
            keepLine0Sentinel,
            (client.clientCompany ?? '').isNotEmpty ? client.clientCompany! : 'Client Company',
            client.clientName.isNotEmpty ? client.clientName : 'Client Name',
            (client.clientEmail ?? '').isNotEmpty ? client.clientEmail! : 'client@company.com',
          ];
          break;
        case 'agreement date':
          values = ['Effective Date: ${_todayLong()}  |  Contract Period: 12 months  |  Auto-renewal: Yes'];
          break;
        case 'company header':
          values = [
            senderCompany,
            _joinPipe([
              'Product Supplier',
              (profile.website ?? '').isNotEmpty ? profile.website! : 'www.yourcompany.com',
            ]),
          ];
          break;
        case 'client details':
          values = [
            keepLine0Sentinel,
            client.clientName.isNotEmpty ? client.clientName : 'Client Name',
            (client.clientCompany ?? '').isNotEmpty ? client.clientCompany! : 'Client Company',
            keepLine0Sentinel,
            (client.clientEmail ?? '').isNotEmpty ? client.clientEmail! : 'client@company.com',
          ];
          break;
        case 'quote details':
          values = [
            keepLine0Sentinel,
            'Date: ${_todayLong()}',
            keepLine0Sentinel,
            keepLine0Sentinel,
            keepLine0Sentinel,
          ];
          break;
        default:
          continue;
      }
      _applyCoverValues(item.controller!, values);
    }
  }

  static const String keepLine0Sentinel = '\u0000KEEP\u0000';

  void _applyCoverValues(QuillController controller, List<String> values) {
    final oldOps = controller.document.toDelta().toJson();

    final lineTexts = <String>[];
    final lineAttrs = <Map<String, dynamic>>[];
    String curText = '';
    Map<String, dynamic> curAttrs = {};
    for (final op in oldOps) {
      final ins = op['insert'];
      if (ins is! String) continue;
      final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
      final parts = ins.split('\n');
      for (int i = 0; i < parts.length; i++) {
        curText += parts[i];
        if (parts[i].isNotEmpty) curAttrs = attrs;
        if (i < parts.length - 1) {
          lineTexts.add(curText);
          lineAttrs.add(curAttrs);
          curText = '';
          curAttrs = {};
        }
      }
    }
    if (curText.isNotEmpty) { lineTexts.add(curText); lineAttrs.add(curAttrs); }

    Map<String, dynamic> attrsFor(int i) =>
        i < lineAttrs.length ? lineAttrs[i] : (lineAttrs.isNotEmpty ? lineAttrs.last : {});

    final ops = <Map<String, dynamic>>[];
    for (int i = 0; i < values.length; i++) {
      var text = values[i];
      if (text == keepLine0Sentinel) text = i < lineTexts.length ? lineTexts[i] : '';
      final a = attrsFor(i);
      ops.add(a.isEmpty
          ? {'insert': text}
          : {'insert': text, 'attributes': Map<String, dynamic>.from(a)});
      ops.add({'insert': '\n'});
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});

    controller.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);
    controller.document = Document.fromJson(ops);
  }

  String _joinPipe(List<String?> parts) =>
      parts.where((p) => p != null && p.trim().isNotEmpty)
          .map((p) => p!.trim())
          .join('  |  ');

  String _todayLong() {
    const months = [
      'January','February','March','April','May','June','July',
      'August','September','October','November','December'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  void _fillSignatureSlots(
      List<CanvasItem> items, {
        required ClientProfileModel client,
        required AiProfileModel profile,
      })
  {
    for (final item in items) {
      if (item.role != 'signature' || !item.isText || item.controller == null) {
        continue;
      }
      final plain = item.controller!.document.toPlainText().toLowerCase();
      String name;
      if (plain.contains('accepted')) {
        name = client.clientName.isNotEmpty ? client.clientName : 'Client Name';
      } else if (plain.contains('submitted')) {
        name = profile.fullName.isNotEmpty ? profile.fullName : 'Your Name';
      } else if (plain.contains('@') || plain.contains('.com')) {
        final contact = _joinPipe([
          profile.email,
          profile.phone,
          (profile.website ?? '').isNotEmpty ? profile.website : null,
        ]);
        if (contact.isNotEmpty) {
          final oldOps = item.controller!.document.toDelta().toJson();
          Map<String, dynamic> firstAttrs = {};
          for (final op in oldOps) {
            final attrs = (op['attributes'] as Map?);
            if (attrs != null && attrs.isNotEmpty) {
              firstAttrs = Map<String, dynamic>.from(attrs);
              break;
            }
          }
          final newOps = <Map<String, dynamic>>[];
          newOps.add(firstAttrs.isEmpty
              ? {'insert': contact}
              : {'insert': contact, 'attributes': firstAttrs});
          newOps.add({'insert': '\n'});
          item.controller!.updateSelection(
              const TextSelection.collapsed(offset: 0), ChangeSource.local);
          item.controller!.document = Document.fromJson(newOps);
        }
        continue;
      } else {
        continue;
      }

      final oldOps = item.controller!.document.toDelta().toJson();
      final lineTexts = <String>[];
      final lineAttrs = <Map<String, dynamic>>[];
      String curText = '';
      Map<String, dynamic> curAttrs = {};
      for (final op in oldOps) {
        final ins = op['insert'];
        if (ins is! String) continue;
        final attrs = Map<String, dynamic>.from((op['attributes'] as Map?) ?? {});
        final parts = ins.split('\n');
        for (int i = 0; i < parts.length; i++) {
          curText += parts[i];
          if (parts[i].isNotEmpty) curAttrs = attrs;
          if (i < parts.length - 1) {
            lineTexts.add(curText);
            lineAttrs.add(curAttrs);
            curText = '';
            curAttrs = {};
          }
        }
      }
      if (curText.isNotEmpty) { lineTexts.add(curText); lineAttrs.add(curAttrs); }

      final isAccepted = plain.contains('accepted');
      final titleVal = isAccepted ? '' : (profile.jobTitle ?? '');
      final dateVal = _todayLong();
      for (int i = 0; i < lineTexts.length; i++) {
        if (!lineTexts[i].contains('|')) continue;
        final segs = lineTexts[i].split('|').map((s) => s.trim()).toList();
        final out = <String>[name];
        for (int j = 1; j < segs.length; j++) {
          final low = segs[j].toLowerCase();
          if (low == 'title') {
            if (titleVal.trim().isNotEmpty) out.add(titleVal.trim());
          } else if (low == 'date') {
            if (dateVal.trim().isNotEmpty) out.add(dateVal.trim());
          } else {
            out.add(segs[j]);
          }
        }
        lineTexts[i] = out.join('  |  ');
        break;
      }

      final ops = <Map<String, dynamic>>[];
      for (int i = 0; i < lineTexts.length; i++) {
        final a = i < lineAttrs.length ? lineAttrs[i] : {};
        if (lineTexts[i].isNotEmpty) {
          ops.add(a.isEmpty
              ? {'insert': lineTexts[i]}
              : {'insert': lineTexts[i], 'attributes': Map<String, dynamic>.from(a)});
        }
        ops.add({'insert': '\n'});
      }
      if (ops.isEmpty) ops.add({'insert': '\n'});

      item.controller!.updateSelection(
          const TextSelection.collapsed(offset: 0), ChangeSource.local);
      item.controller!.document = Document.fromJson(ops);
    }
  }
}