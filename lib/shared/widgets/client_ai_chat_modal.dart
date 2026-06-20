// lib/shared/widgets/client_ai_chat_modal.dart
//
// AI-driven client builder. The user types a brief and the AI either:
//   - returns mode:"complete" immediately (the wizard fills, no chat needed),
//   - or returns mode:"question" with form fields (text blanks + choice chips
//     + write-in) and the chat continues until it has enough.
//
// Transcript lives in memory only — never written to Firestore. Closing or
// reloading discards it. Token cost is tracked server-side by the aiFill
// function under tool:"clientChat" (the user sees totals in analytics).
//
// Returns a ClientProfileModel? — null if the user cancelled.
//
// Used from: client_wizard_modal.dart "Auto-fill with AI" button.
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../ai/claude_service.dart';
import '../models/client_profile_model.dart';

// ─── Transcript types ─────────────────────────────────────────────────
enum _Sender { user, ai }

class _ChatMessage {
  final _Sender sender;
  final String? text; // plain message text
  final _QuestionCard? card; // AI question with fields (if any)
  const _ChatMessage({required this.sender, this.text, this.card});
}

class _QuestionCard {
  final String? intro;
  final List<_AiField> fields;
  const _QuestionCard({this.intro, required this.fields});
}

class _AiField {
  final String key;
  final String label;
  final String type; // text | choice
  final String? hint;
  final List<String> options;
  final bool allowCustom;
  const _AiField({
    required this.key,
    required this.label,
    required this.type,
    this.hint,
    this.options = const [],
    this.allowCustom = true,
  });
}

// ─── Modal ────────────────────────────────────────────────────────────
class ClientAiChatModal extends StatefulWidget {
  /// The user's initial brief — sent as the first user turn.
  final String initialBrief;
  const ClientAiChatModal({super.key, required this.initialBrief});

  /// Open the chat modal. Returns a populated ClientProfileModel on success,
  /// or null if the user closed it without completing.
  static Future<ClientProfileModel?> show(
      BuildContext context, {
        required String initialBrief,
      }) {
    return showDialog<ClientProfileModel>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => ClientAiChatModal(initialBrief: initialBrief),
    );
  }

  @override
  State<ClientAiChatModal> createState() => _ClientAiChatModalState();
}

class _ClientAiChatModalState extends State<ClientAiChatModal> {
  // In-memory chat history (UI side).
  final List<_ChatMessage> _messages = [];

  // What we send back to Claude each turn (role+content), capped server-side too.
  final List<Map<String, String>> _transcript = [];

  // Per-question card state: fieldKey -> user input. Reset when a new card arrives.
  final Map<String, String> _answers = {};

  // Per-field controllers for the current card (disposed/cleared between cards).
  final Map<String, TextEditingController> _fieldCtrls = {};

  bool _busy = false;
  bool _closing = false;
  String? _error;

  final _scrollCtrl = ScrollController();

  // Cap: if the AI keeps asking, eventually we stop. 12 cards is plenty.
  static const _maxAiQuestions = 12;
  int _aiQuestionCount = 0;

  @override
  void initState() {
    super.initState();
    // Seed turn 1 with the user's brief and immediately call the AI.
    final brief = widget.initialBrief.trim();
    if (brief.isNotEmpty) {
      _messages.add(_ChatMessage(sender: _Sender.user, text: brief));
      _transcript.add({'role': 'user', 'content': brief});
    } else {
      _messages.add(const _ChatMessage(
        sender: _Sender.user,
        text: 'Help me build a client profile.',
      ));
      _transcript.add({'role': 'user', 'content': 'Help me build a client profile.'});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTurn());
  }

  @override
  void dispose() {
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Drive one AI turn ──────────────────────────────────────────────
  Future<void> _runTurn() async {
    if (_closing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final envelope = await ClaudeService.clientChat(_transcript);
      if (envelope == null) throw 'No response from AI';
      _handleEnvelope(envelope);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  /// Routes the AI envelope by mode. Three shapes:
  ///   { mode:"question", intro, fields:[...] }
  ///   { mode:"complete", profile:{...} }
  ///   { mode:"message",  text:"..." }   (rare; we just display)
  void _handleEnvelope(Map<String, dynamic> env) {
    final mode = (env['mode'] ?? '').toString();

    if (mode == 'complete') {
      final profileJson = env['profile'];
      if (profileJson is! Map) {
        setState(() => _error = 'AI returned an incomplete profile. Try again.');
        return;
      }
      final model = ClientProfileModel.fromJson(
          '', Map<String, dynamic>.from(profileJson as Map));
      // Add the assistant turn to transcript for completeness.
      _transcript.add({'role': 'assistant', 'content': '[profile complete]'});
      // Close and return the model.
      _closing = true;
      Navigator.of(context).pop(model);
      return;
    }

    if (mode == 'question') {
      _aiQuestionCount++;
      final fields = (env['fields'] as List? ?? [])
          .map((e) => _parseField(Map<String, dynamic>.from(e as Map)))
          .toList();
      final intro = env['intro']?.toString();
      final card = _QuestionCard(intro: intro, fields: fields);

      // Reset answers + controllers for the new card.
      for (final c in _fieldCtrls.values) {
        c.dispose();
      }
      _fieldCtrls.clear();
      _answers.clear();
      for (final f in fields) {
        _fieldCtrls[f.key] = TextEditingController();
        _answers[f.key] = '';
      }

      setState(() {
        _messages.add(_ChatMessage(sender: _Sender.ai, card: card));
      });
      // Add the raw AI JSON to the transcript so the model sees its own question.
      _transcript.add({'role': 'assistant', 'content': _stringifyCard(card)});

      if (_aiQuestionCount >= _maxAiQuestions) {
        setState(() => _error =
        'Reached question limit. Send what you have, or close and edit manually.');
      }
      return;
    }

    if (mode == 'message') {
      final txt = env['text']?.toString() ?? '';
      setState(() => _messages.add(_ChatMessage(sender: _Sender.ai, text: txt)));
      _transcript.add({'role': 'assistant', 'content': txt});
      return;
    }

    setState(() => _error = 'AI returned an unexpected response.');
  }

  _AiField _parseField(Map<String, dynamic> m) {
    final opts = (m['options'] as List? ?? []).map((e) => e.toString()).toList();
    return _AiField(
      key: (m['key'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      type: (m['type'] ?? 'text').toString(),
      hint: m['hint']?.toString(),
      options: opts,
      allowCustom: m['allowCustom'] == false ? false : true,
    );
  }

  String _stringifyCard(_QuestionCard c) {
    // Lightweight readable form for the transcript (Claude reads this).
    final buf = StringBuffer();
    if (c.intro != null && c.intro!.isNotEmpty) buf.writeln(c.intro);
    for (final f in c.fields) {
      buf.write('- ${f.label} (key=${f.key}, type=${f.type})');
      if (f.options.isNotEmpty) buf.write(' options=${f.options}');
      buf.writeln();
    }
    return buf.toString();
  }

  // ── Submit the current card's answers ──────────────────────────────
  void _submitAnswers() {
    final last = _messages.lastWhere(
          (m) => m.sender == _Sender.ai && m.card != null,
      orElse: () => const _ChatMessage(sender: _Sender.ai),
    );
    final card = last.card;
    if (card == null) return;

    // Build the user reply: a readable "key: value" block. Claude maps it
    // back via the field keys we provided in the question.
    final lines = <String>[];
    for (final f in card.fields) {
      final v = (_answers[f.key] ?? '').trim();
      if (v.isNotEmpty) lines.add('${f.key}: $v');
    }
    if (lines.isEmpty) {
      setState(() => _error = 'Please answer at least one field, or close to skip.');
      return;
    }
    final reply = lines.join('\n');

    setState(() {
      _messages.add(_ChatMessage(sender: _Sender.user, text: reply));
      _error = null;
    });
    _transcript.add({'role': 'user', 'content': reply});
    _runTurn();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── BUILD ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final w = screen.width < 700 ? screen.width - 32 : 640.0;
    final h = screen.height * 0.85;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: w,
        height: h,
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
          children: [
            _buildHeader(),
            _buildPrivacyBanner(),
            Expanded(child: _buildMessages()),
            if (_error != null) _buildErrorBar(),
            _buildBusyOrInputArea(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.sparkles, size: 16, color: AppColors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Client Assistant',
                    style: TextStyle(
                        fontSize: 15,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white)),
                Text('Answers follow-ups, then fills the form for you',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.white)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _confirmClose(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.x, size: 14, color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose() async {
    final close = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Discard progress?',
            style: TextStyle(
                fontSize: 16,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
                color: AppColors.prussianBlue)),
        content: const Text(
            'This chat isn\'t saved. Closing now discards your answers.',
            style: TextStyle(
                fontSize: 13,
                fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going',
                style: TextStyle(color: AppColors.slateGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard',
                style: TextStyle(color: AppColors.darkRaspberry)),
          ),
        ],
      ),
    );
    if (close == true && mounted) {
      _closing = true;
      Navigator.of(context).pop(); // returns null
    }
  }

  Widget _buildPrivacyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.petalFrost,
      child: const Row(
        children: [
          Icon(LucideIcons.shieldCheck, size: 12, color: AppColors.darkRaspberry),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This conversation isn\'t saved. Closing or reloading clears it.',
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppFonts.openSans,
                color: AppColors.prussianBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages list ────────────────────────────────────────────────
  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: _messages.length + (_busy ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length && _busy) return _buildThinkingBubble();
        return _buildBubble(_messages[i]);
      },
    );
  }

  Widget _buildBubble(_ChatMessage m) {
    final isUser = m.sender == _Sender.user;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (m.text != null) _textBubble(m.text!, isUser),
          if (m.card != null) _questionBubble(m.card!),
        ],
      ),
    );
  }

  Widget _textBubble(String text, bool isUser) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.darkRaspberry : AppColors.lavenderBlush,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 13,
            fontFamily: AppFonts.openSans,
            color: isUser ? AppColors.white : AppColors.prussianBlue,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _questionBubble(_QuestionCard card) {
    // Check whether this is the LAST AI card — only the last one is interactive.
    final last = _messages.lastWhere(
          (m) => m.sender == _Sender.ai && m.card != null,
      orElse: () => const _ChatMessage(sender: _Sender.ai),
    );
    final isActive = last.card == card && !_busy;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderBlush,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(14),
        ),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.intro != null && card.intro!.isNotEmpty) ...[
            Text(card.intro!,
                style: const TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: AppColors.prussianBlue)),
            const SizedBox(height: 12),
          ],
          ...card.fields.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildField(e.key + 1, e.value, isActive),
          )),
          if (isActive) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _busy ? null : _submitAnswers,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.darkRaspberry,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.send, size: 13, color: AppColors.white),
                        SizedBox(width: 6),
                        Text('Send answers',
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w600,
                                color: AppColors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(int num, _AiField f, bool active) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: AppColors.darkRaspberry,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$num',
                  style: const TextStyle(
                      fontSize: 10,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(f.label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      color: AppColors.prussianBlue)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: f.type == 'choice' ? _choiceField(f, active) : _textInput(f, active),
        ),
      ],
    );
  }

  Widget _textInput(_AiField f, bool active) {
    return TextField(
      controller: _fieldCtrls[f.key],
      enabled: active,
      onChanged: (v) => _answers[f.key] = v,
      style: const TextStyle(
          fontSize: 13, fontFamily: AppFonts.openSans, color: AppColors.prussianBlue),
      maxLines: _isMultiline(f.key) ? 2 : 1,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintText: f.hint ?? 'Type your answer...',
        hintStyle: const TextStyle(
            fontSize: 12,
            fontFamily: AppFonts.openSans,
            color: AppColors.slateGrey),
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.almondSilk),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.almondSilk),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.darkRaspberry, width: 1.5),
        ),
      ),
    );
  }

  /// List-y keys deserve more room to write (comma-separated values).
  bool _isMultiline(String key) {
    const multi = {
      'productItems', 'deliverables', 'milestones', 'lineItems', 'projectGoals',
      'techStack', 'channels', 'kpiMetrics', 'projectDescription',
      'problemStatement', 'creativeBrief', 'campaignGoals', 'scopeNotes',
      'specialRequirements', 'customNotes', 'competitorInfo',
    };
    return multi.contains(key);
  }

  Widget _choiceField(_AiField f, bool active) {
    final current = _answers[f.key] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final opt in f.options) _choiceChip(opt, current == opt, () {
              if (!active) return;
              setState(() {
                _answers[f.key] = opt;
                _fieldCtrls[f.key]?.text = '';
              });
            }),
          ],
        ),
        if (f.allowCustom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _fieldCtrls[f.key],
            enabled: active,
            onChanged: (v) {
              _answers[f.key] = v;
              setState(() {});
            },
            style: const TextStyle(
                fontSize: 12,
                fontFamily: AppFonts.openSans,
                color: AppColors.prussianBlue),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              hintText: 'Or write your own...',
              hintStyle: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppColors.darkRaspberry, width: 1.5),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.darkRaspberry : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.darkRaspberry : AppColors.almondSilk,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: AppFonts.poppins,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.white : AppColors.prussianBlue,
            ),
          ),
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────
  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.lavenderBlush,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.darkRaspberry)),
            SizedBox(width: 10),
            Text('Thinking...',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.slateGrey)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.error.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle,
              size: 13, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error ?? '',
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.error)),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(LucideIcons.x, size: 13, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildBusyOrInputArea() {
    // Retry is available whenever:
    //   - the chat isn't currently waiting on the AI, AND
    //   - the last message is from the user (so an AI response is owed).
    // This means the user can dismiss the error bar and still retry.
    final lastIsUser = _messages.isNotEmpty &&
        _messages.last.sender == _Sender.user;
    final canRetry = !_busy && lastIsUser;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0EBE6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _busy
                  ? 'AI is working on a response...'
                  : canRetry
                  ? 'Tap Retry to get the AI\'s response again.'
                  : 'Fill the fields above and tap Send. The AI will continue or finish on its own.',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey,
              ),
            ),
          ),
          if (canRetry)
            GestureDetector(
              onTap: _runTurn,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.darkRaspberry,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.refreshCw,
                          size: 12, color: AppColors.white),
                      SizedBox(width: 6),
                      Text('Retry',
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: AppFonts.poppins,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}