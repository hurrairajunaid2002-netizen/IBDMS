import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';

/// AI Health Chatbot
/// — 5-step guided eligibility assessment (state machine, runs offline)
/// — Free-text Q&A forwarded to the backend FAQ engine (25-topic coverage)
/// — Quick-reply suggestion chips for common topics
class ChatbotScreen extends StatefulWidget {
  final String token;
  final bool embedInShell;

  const ChatbotScreen({
    super.key,
    required this.token,
    this.embedInShell = false,
  });

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  final List<_ChatMessage> _messages = [];
  bool _botTyping = false;

  // ── Eligibility assessment state machine ──────────────────────────────────
  int _step = 0;
  bool _assessmentActive = false;
  final Map<String, dynamic> _answers = {};
  static const int _totalSteps = 5;

  // ── Quick-reply chips shown in idle mode ──────────────────────────────────
  static const _quickReplies = [
    ('How often can I donate?', Icons.schedule),
    ('Weight requirement', Icons.monitor_weight_outlined),
    ('Age requirement', Icons.cake_outlined),
    ('Blood type compatibility', Icons.bloodtype_outlined),
    ('What are the eligibility criteria?', Icons.checklist_outlined),
    ('Medication & drug deferral', Icons.medication_outlined),
    ('COVID-19 & vaccination', Icons.vaccines_outlined),
    ('Benefits of donating', Icons.favorite_border),
    ('Post-donation care', Icons.healing_outlined),
    ('Platelet & plasma donation', Icons.science_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _showWelcome();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _showWelcome() {
    _messages.clear();
    _addBot(
      'Hello! 👋 I am your **IBDMS AI Health Assistant**.\n\n'
      'I can help with blood donation eligibility, health conditions, '
      'medications, post-donation care, blood type compatibility, and much more.\n\n'
      'Tap a quick topic below or type your question freely. '
      'For a step-by-step personal eligibility check, tap '
      '**Start Eligibility Check**.',
      isIntro: true,
    );
  }

  // ── Message helpers ───────────────────────────────────────────────────────

  void _addBot(String text, {bool isIntro = false}) {
    setState(() => _messages.add(
        _ChatMessage(text: text, isUser: false, isIntro: isIntro)));
    _scrollToBottom();
  }

  void _addUser(String text) {
    setState(
        () => _messages.add(_ChatMessage(text: text, isUser: true)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  // ── Assessment state machine ──────────────────────────────────────────────

  void _startAssessment() {
    _inputFocus.unfocus();
    setState(() {
      _assessmentActive = true;
      _step = 1;
      _answers.clear();
    });
    _addBot(_questionForStep(1));
  }

  String _questionForStep(int s) => switch (s) {
        1 => 'Have you donated **whole blood in the last 56 days**?\n'
            '_(Reply: yes / no)_',
        2 => 'What is your current **weight in kg**?\n'
            '_(Type a number, e.g. 68)_',
        3 => 'How old are you? _(Enter your age in years)_',
        4 => 'In the past **7 days**, have you had any of the following?\n'
            '• Fever   • Cold / Flu   • Active infection\n'
            '_(Reply: yes / no)_',
        5 => 'Have you had **major surgery** or received a **blood transfusion** '
            'in the last 12 months?\n_(Reply: yes / no)_',
        _ => '',
      };

  Future<void> _handleUserInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    _addUser(text);

    if (_assessmentActive) {
      _processAnswer(text);
    } else {
      await _queryBackend(text);
    }
  }

  void _processAnswer(String answer) async {
    final lower = answer.toLowerCase();

    switch (_step) {
      case 1:
        _answers['donated_recently'] = lower.contains('yes');
        if (_answers['donated_recently'] as bool) {
          _finishWithResult(
            eligible: false,
            reason: '⛔  You need to wait at least **56 days** (8 weeks) '
                'between whole-blood donations.\n\n'
                'Your haemoglobin and iron stores need that time to fully '
                'replenish. Please check back once the cooling period has passed.',
          );
          return;
        }

      case 2:
        final w =
            double.tryParse(answer.replaceAll(RegExp(r'[^0-9.]'), ''));
        _answers['weight_kg'] = w;
        if (w == null || w < 50) {
          _finishWithResult(
            eligible: false,
            reason: '⛔  The minimum donor weight is **50 kg**.\n\n'
                'Your current weight (${w?.toStringAsFixed(1) ?? 'unknown'} kg) '
                'is below the threshold required to safely tolerate the blood '
                'drawn. Focus on a nutritious diet and try again when you reach 50 kg.',
          );
          return;
        }

      case 3:
        final age =
            int.tryParse(answer.replaceAll(RegExp(r'[^0-9]'), ''));
        _answers['age'] = age;
        if (age == null || age < 18 || age > 65) {
          _finishWithResult(
            eligible: false,
            reason: '⛔  The eligible donor age range is **18–65 years**.\n\n'
                'Your age (${age ?? '?'} years) is outside the accepted range. '
                'Some centres accept donors under 18 with parental consent or '
                'healthy adults over 65 on a case-by-case basis — '
                'contact your nearest blood bank for guidance.',
          );
          return;
        }

      case 4:
        _answers['illness_recent'] = lower.contains('yes');
        if (_answers['illness_recent'] as bool) {
          _finishWithResult(
            eligible: false,
            reason: '⛔  Active illness (fever, cold, infection) disqualifies '
                'donation.\n\n'
                'Donating while ill puts both you and the recipient at risk. '
                'Please recover fully and wait at least **7 days** after all '
                'symptoms have completely cleared before donating.',
          );
          return;
        }

      case 5:
        _answers['surgery_recent'] = lower.contains('yes');
        if (_answers['surgery_recent'] as bool) {
          _finishWithResult(
            eligible: false,
            reason: '⛔  Recent surgery or a blood transfusion within the '
                'last 12 months requires medical clearance before donation.\n\n'
                'This deferral protects against potential bloodborne infection '
                'transmission. Please consult your physician and revisit after '
                'the 12-month period.',
          );
          return;
        }
    }

    if (_step < _totalSteps) {
      setState(() => _step++);
      await Future.delayed(const Duration(milliseconds: 350));
      _addBot(_questionForStep(_step));
    } else {
      _finishWithResult(eligible: true);
    }
  }

  void _finishWithResult({required bool eligible, String? reason}) {
    setState(() {
      _assessmentActive = false;
      _step = 0;
    });
    if (eligible) {
      _addBot(
        '✅  **You appear eligible to donate blood!**\n\n'
        'Summary of your responses:\n'
        '• No donation in the past 56 days ✓\n'
        '• Weight ≥ 50 kg ✓\n'
        '• Age within 18–65 years ✓\n'
        '• No active illness in the past 7 days ✓\n'
        '• No major surgery or transfusion in the past 12 months ✓\n\n'
        '**Next step:** Visit a certified blood bank for official medical '
        'screening, haemoglobin test, and blood pressure check before donation.\n\n'
        '_Remember: Drink plenty of water and eat a healthy meal before you go!_ 🩸',
      );
    } else {
      _addBot('$reason\n\nFeel free to ask another question or tap '
          '**Start Eligibility Check** to reassess when you are ready.');
    }
  }

  // ── Backend FAQ query ─────────────────────────────────────────────────────

  Future<void> _queryBackend(String message) async {
    setState(() => _botTyping = true);
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/chatbot/query'
          '?user_message=${Uri.encodeComponent(message)}');
      final res = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _addBot(data['reply']?.toString() ?? 'No response from server.');
      } else {
        _addBot(
            'Server returned an error. Please check your connection and try again.');
      }
    } catch (_) {
      _addBot(
          'Could not reach the server. Check that the backend is running.\n\n'
          '_Tip: You can still use the guided Eligibility Check offline._');
    } finally {
      if (mounted) setState(() => _botTyping = false);
    }
  }

  double get _progress =>
      _assessmentActive ? (_step - 1) / _totalSteps : 0;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: widget.embedInShell
          ? null
          : AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.smart_toy_outlined,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Text('AI Health Assistant'),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Reset conversation',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() {
                    _assessmentActive = false;
                    _step = 0;
                    _answers.clear();
                    _showWelcome();
                  }),
                ),
              ],
            ),
      body: Column(
        children: [
          if (widget.embedInShell)
            Container(
              width: double.infinity,
              color: const Color(0xFFB71C1C),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_outlined,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI Health Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset conversation',
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () => setState(() {
                      _assessmentActive = false;
                      _step = 0;
                      _answers.clear();
                      _showWelcome();
                    }),
                  ),
                ],
              ),
            ),
          // Assessment progress bar
          if (_assessmentActive) _buildProgressBar(),

          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              itemCount: _messages.length + (_botTyping ? 1 : 0),
              itemBuilder: (_, i) {
                if (_botTyping && i == _messages.length) {
                  return _buildTypingIndicator();
                }
                return _buildBubble(_messages[i]);
              },
            ),
          ),

          // Quick-reply chips (idle mode only)
          if (!_assessmentActive && !_botTyping)
            _buildQuickReplies(),

          // Start eligibility button
          if (!_assessmentActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: OutlinedButton.icon(
                onPressed: _startAssessment,
                icon: const Icon(Icons.checklist_outlined,
                    color: Color(0xFFB71C1C), size: 18),
                label: const Text('Start Eligibility Check',
                    style: TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: Color(0xFFB71C1C)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Eligibility Check — Step $_step of $_totalSteps',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                '${(_progress * 100).toInt()}% complete',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFFB71C1C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplies() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Common topics — tap to ask:',
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
                letterSpacing: 0.3),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (label, icon) = _quickReplies[i];
                return ActionChip(
                  avatar: Icon(icon, size: 14, color: const Color(0xFFB71C1C)),
                  label: Text(label,
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    _addUser(label);
                    _queryBackend(label);
                  },
                  backgroundColor: Colors.red[50],
                  side: const BorderSide(color: Color(0xFFEF9A9A)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              decoration: InputDecoration(
                hintText: _assessmentActive
                    ? 'Type your answer (yes / no / number)…'
                    : 'Ask anything about blood donation…',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: Color(0xFFB71C1C)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: _handleUserInput,
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: const Color(0xFFB71C1C),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _handleUserInput(_input.text),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child:
                    Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bubble ────────────────────────────────────────────────────────────────

  Widget _buildBubble(_ChatMessage msg) {
    return Align(
      alignment:
          msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.80),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUser
              ? const Color(0xFFB71C1C)
              : (msg.isIntro
                  ? const Color(0xFFE3F2FD)
                  : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
          border: msg.isIntro
              ? Border.all(color: const Color(0xFF90CAF9))
              : (!msg.isUser
                  ? Border.all(color: Colors.grey[200]!)
                  : null),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _renderMarkdown(msg.text, msg.isUser),
      ),
    );
  }

  /// Renders a small subset of markdown: **bold**, _italic_, bullet lists.
  Widget _renderMarkdown(String text, bool isUser) {
    final Color baseColor = isUser ? Colors.white : Colors.grey[850]!;

    final lines = text.split('\n');
    final spans = <InlineSpan>[];

    for (int li = 0; li < lines.length; li++) {
      if (li > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[li];

      // Bullet line
      if (line.trimLeft().startsWith('•') ||
          line.trimLeft().startsWith('-')) {
        spans.addAll(_parseInline(line, isUser, baseColor));
        continue;
      }
      spans.addAll(_parseInline(line, isUser, baseColor));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
            color: baseColor, fontSize: 13.5, height: 1.5),
        children: spans,
      ),
    );
  }

  List<InlineSpan> _parseInline(
      String text, bool isUser, Color base) {
    final spans = <InlineSpan>[];
    // Patterns: **bold**, _italic_, `code`
    final regex =
        RegExp(r'\*\*(.*?)\*\*|_(.*?)_|`(.*?)`');
    int last = 0;

    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      if (m.group(1) != null) {
        // Bold
        spans.add(TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.bold)));
      } else if (m.group(2) != null) {
        // Italic
        spans.add(TextSpan(
            text: m.group(2),
            style: TextStyle(
                fontStyle: FontStyle.italic,
                color: isUser
                    ? Colors.white70
                    : Colors.grey[600])));
      } else if (m.group(3) != null) {
        // Code / inline highlight
        spans.add(TextSpan(
            text: m.group(3),
            style: TextStyle(
                fontFamily: 'monospace',
                color: isUser
                    ? Colors.white
                    : const Color(0xFFB71C1C))));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (i) => Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 3),
              child: _BouncingDot(delay: i * 180),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isIntro;
  _ChatMessage(
      {required this.text,
      required this.isUser,
      this.isIntro = false});
}

// ── Typing indicator dot ──────────────────────────────────────────────────────

class _BouncingDot extends StatefulWidget {
  final int delay;
  const _BouncingDot({required this.delay});
  @override
  State<_BouncingDot> createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay),
        () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[400]),
        ),
      ),
    );
  }
}
