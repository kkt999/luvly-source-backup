import 'package:flutter/material.dart';
import '../packages/package_api.dart' show packageRequestId;
import '../src/design.dart' show CustomerUi;
import 'assistant_api.dart';
import 'support_repository.dart' show supportTextError;

class SupportAssistantScreen extends StatefulWidget {
  const SupportAssistantScreen({
    super.key,
    this.api,
    this.onContact,
    this.onClose,
  });
  final AssistantApi? api;
  final Future<void> Function(String draft)? onContact;
  final VoidCallback? onClose;
  @override
  State<SupportAssistantScreen> createState() => _AssistantState();
}

class _Turn {
  _Turn(this.question, this.requestId);
  final String question, requestId;
  AssistantReply? reply;
}

class _AssistantState extends State<SupportAssistantScreen> {
  late final AssistantApi api = widget.api ?? LuvlyAssistantApi();
  final input = TextEditingController(), scroll = ScrollController();
  final composerFocus = FocusNode();
  final turns = <_Turn>[];
  bool ready = false,
      aiConfigured = false,
      ai = false,
      consentDecided = false,
      deciding = false,
      busy = false,
      contacting = false;
  String language = 'auto';
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    bool configured = false;
    try {
      configured = await api.configured();
    } catch (_) {
      /* Guide remains available. */
    }
    if (mounted) {
      setState(() {
        ready = true;
        aiConfigured = configured;
      });
    }
  }

  @override
  void dispose() {
    input.dispose();
    composerFocus.dispose();
    scroll.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<bool> changeAI() async {
    if (busy || deciding || !aiConfigured) return false;
    if (ai) {
      setState(() {
        ai = false;
        consentDecided = true;
      });
      return true;
    }
    setState(() => deciding = true);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Use AI-assisted answers?'),
        content: const SingleChildScrollView(
          child: Text(
            'Google Gemini receives your question, up to four recent questions from this conversation, and Luvly’s help guide. Your account records are not included.\n\nGoogle may use submitted content and responses to improve its products, and human reviewers may review them. Do not share names, contact details, order references, passwords, banking information or other personal details. Messages are not guaranteed to be fully anonymised.\n\nAI can make mistakes and cannot check or change your orders, payments, stock or refunds. You can contact our team or switch AI off at any time.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Use help guide'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Enable AI'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    setState(() {
      deciding = false;
      if (accepted != null) {
        ai = accepted;
        consentDecided = true;
      }
    });
    return accepted != null;
  }

  void bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });
  Future<void> send([String? suggestion]) async {
    if (busy || deciding || !ready) return;
    final question = (suggestion ?? input.text).trim(),
        validation = supportTextError(question, 1, 256);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    if (turns.length >= 20) {
      setState(() => error = 'Start a new conversation to continue.');
      return;
    }
    // Opening the chat never sends a question to Google. Ask once, at the
    // first general message, and keep the draft if the dialog is dismissed.
    if (!assistantPrivacyBlocked(question) && aiConfigured && !consentDecided) {
      FocusScope.of(context).unfocus();
      final proceed = await changeAI();
      if (!mounted || !proceed) return;
    }
    final history = turns
        .where((t) => t.reply?.notice != 'Privacy')
        .map((t) => t.question)
        .toList();
    final turn = _Turn(question, packageRequestId());
    setState(() {
      turns.add(turn);
      busy = true;
      error = null;
      input.clear();
    });
    bottom();
    try {
      final reply = assistantPrivacyBlocked(question)
          ? await localHelp(question, const [], language)
          : await api.ask(
              message: question,
              history: history
                  .skip(history.length > 4 ? history.length - 4 : 0)
                  .toList(),
              language: language,
              ai: ai,
              requestId: turn.requestId,
            );
      if (mounted) setState(() => turn.reply = reply);
    } catch (_) {
      if (mounted) {
        setState(() {
          turns.remove(turn);
          input.text = question;
          error =
              'We couldn’t answer your question. Try sending it again or contact our team.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        bottom();
      }
    }
  }

  Future<void> contact() async {
    if (widget.onContact == null || contacting) return;
    final safeTurns = turns
        .where(
          (t) =>
              t.reply?.notice != 'Privacy' &&
              !assistantPrivacyBlocked(t.question),
        )
        .toList();
    final recent = safeTurns.skip(
      safeTurns.length > 3 ? safeTurns.length - 3 : 0,
    );
    var draft = recent
        .map(
          (t) =>
              'Customer: ${t.question}\n${t.reply?.mode == 'AI' ? 'Gemini AI' : 'Help guide'}: ${t.reply?.answer ?? '(No answer)'}',
        )
        .join('\n\n');
    if (draft.length > 1700) draft = draft.substring(0, 1700);
    setState(() => contacting = true);
    try {
      await widget.onContact!(
        'Assistant follow-up — please review before sending.\n\n$draft',
      );
    } finally {
      if (mounted) setState(() => contacting = false);
    }
  }

  Future<void> clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start a new conversation?'),
        content: const Text(
          'This chat stays on this screen only. Clear it when you no longer need it. Team tickets already sent are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep chat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        turns.clear();
        error = null;
        input.clear();
      });
    }
  }

  void explainModes() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Two ways to find an answer',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 18),
            Text(
              'AI chat · conversational answers',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Gemini generates a natural answer using Luvly’s policy guide and up to four recent general questions on this screen. You can ask follow-up questions. It cannot read your account or perform actions, and it can make mistakes.',
            ),
            SizedBox(height: 18),
            Text(
              'Help guide · finds matching keywords',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Browse common questions or search using clear keywords such as fitting, deposit or cancellation. No question is sent to Gemini.',
            ),
            SizedBox(height: 18),
            Text(
              'Both use the same approved Luvly policies, so prices and rules should agree. Check policy details for important decisions. Only our team can help with a personal order, payment or refund.',
            ),
          ],
        ),
      ),
    ),
  );

  Widget avatar({double size = 40}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFF3E6E8),
      borderRadius: BorderRadius.circular(size * .35),
    ),
    child: Icon(
      Icons.smart_toy_outlined,
      color: const Color(0xFF924653),
      size: size * .56,
    ),
  );

  String noticeLabel(String notice) => switch (notice) {
    'Offline' => 'Connection unavailable · showing the saved guide',
    'SetupRequired' => 'AI not connected · using the help guide',
    'ShortenQuestion' => 'Please shorten your question · showing the guide',
    'Quota' => 'Daily AI limit reached · the help guide is still available',
    'Busy' => 'AI is busy · showing the guide instead',
    'PersonalSupport' => 'For a personal action, please contact our team',
    'OutsideScope' => 'Please ask our team for help beyond the policy guide',
    'AlreadyAnswered' =>
      'Previous request completed · showing its guide without another AI call',
    _ => 'AI unavailable · using the help guide',
  };

  Widget answerCard(AssistantReply reply) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            avatar(size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reply.mode == 'AI' ? 'Gemini · AI answer' : 'Help guide answer',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF827579),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFECE4E1)),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reply.notice != null && reply.notice != 'Privacy')
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    noticeLabel(reply.notice!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B6548),
                    ),
                  ),
                ),
              SelectableText(
                reply.answer,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              if (reply.sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        reply.mode == 'AI'
                            ? Icons.auto_awesome_outlined
                            : Icons.menu_book_outlined,
                        size: 14,
                        color: const Color(0xFFA65360),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${reply.mode == 'AI' ? 'Based on' : 'Guide topic'}: ${reply.sources.map((s) => s['title']).join(' · ')}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF827579),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (reply.mode == 'AI' &&
                  reply.sources.any((s) => s['excerpt'] != null))
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text(
                    'Check Luvly policy details',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    for (final source in reply.sources.where(
                      (s) => s['excerpt'] != null,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source['title']!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              source['excerpt']!,
                              style: const TextStyle(fontSize: 12, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Policy version ${reply.version}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF827579),
                      ),
                    ),
                  ],
                ),
              if (reply.handoff && widget.onContact != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton.icon(
                    onPressed: contacting ? null : contact,
                    icon: const Icon(Icons.support_agent, size: 17),
                    label: const Text('Ask the Luvly team'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFCF9F7),
    appBar: AppBar(
      backgroundColor: Colors.white,
      centerTitle: false,
      automaticallyImplyLeading: widget.onClose == null,
      titleSpacing: widget.onClose == null ? 0 : 18,
      title: Row(
        children: [
          avatar(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Luvly Assistant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  ai
                      ? 'AI chat · powered by Gemini'
                      : !ready
                      ? 'Connecting…'
                      : aiConfigured && !consentDecided
                      ? 'Here to help'
                      : 'Help guide · AI is off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF827579),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Chat options',
          popUpAnimationStyle: CustomerUi.popupMotion(context),
          onSelected: (v) {
            if (v == 'new') {
              clear();
            } else if (v == 'ai') {
              changeAI();
            } else if (v == 'contact') {
              contact();
            } else if (v == 'modes') {
              explainModes();
            } else {
              setState(() => language = v);
            }
          },
          itemBuilder: (_) => [
            if (aiConfigured)
              PopupMenuItem(
                value: 'ai',
                enabled: !busy && !deciding,
                child: Text(ai ? 'Turn AI off' : 'Enable AI'),
              ),
            if (widget.onContact != null)
              PopupMenuItem(
                value: 'contact',
                enabled: !busy && !deciding && !contacting,
                child: const Text('Contact the team'),
              ),
            const PopupMenuItem(
              value: 'modes',
              child: Text('How AI differs from the guide'),
            ),
            PopupMenuItem(
              value: 'new',
              enabled: !busy && !deciding && turns.isNotEmpty,
              child: const Text('New conversation'),
            ),
            const PopupMenuDivider(),
            for (final l in {
              'auto': 'Auto language',
              'en': 'English',
              'zh': '中文',
              'ms': 'Bahasa Melayu',
            }.entries)
              PopupMenuItem(
                value: l.key,
                child: Text('${language == l.key ? '✓ ' : ''}${l.value}'),
              ),
          ],
          icon: const Icon(Icons.more_horiz),
        ),
        if (widget.onClose != null)
          IconButton(
            onPressed: widget.onClose,
            tooltip: 'Close assistant',
            icon: const Icon(Icons.close, size: 21),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            if (!ready) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 24, bottom: 24),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFECE4E1)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'Hi, I’m your Luvly Assistant. How can I help with your fitting or bridal rental today?',
                        style: TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                  ),
                  if (turns.isEmpty)
                    Padding(
                      key: const Key('assistant-question-starters'),
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'You can ask…',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF827579),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final question in const [
                                'How much is a fitting?',
                                'How does the deposit work?',
                                'When should I book my fitting?',
                              ])
                                OutlinedButton(
                                  onPressed: !ready || busy || deciding
                                      ? null
                                      : () {
                                          input.value = TextEditingValue(
                                            text: question,
                                            selection: TextSelection.collapsed(
                                              offset: question.length,
                                            ),
                                          );
                                          setState(() => error = null);
                                          composerFocus.requestFocus();
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF924653),
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Color(0xFFE7D8DB),
                                    ),
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: Text(
                                    question,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  for (final turn in turns) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(left: 38, bottom: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF924653),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                          ),
                        ),
                        child: Text(
                          turn.question,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (turn.reply != null) answerCard(turn.reply!),
                  ],
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          avatar(size: 28),
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              ai
                                  ? 'Understanding your question…'
                                  : 'Finding a guide topic…',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF827579),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Text(
                  error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFECE4E1))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: input,
                              focusNode: composerFocus,
                              enabled: ready && !busy && !deciding,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 256,
                              style: const TextStyle(fontSize: 13),
                              textInputAction: TextInputAction.send,
                              decoration: InputDecoration(
                                hintText: 'Message Luvly…',
                                counterText: '',
                                fillColor: const Color(0xFFFCF9F7),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                              ),
                              onSubmitted: (_) => send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: !ready || busy || deciding ? null : send,
                            tooltip: 'Send question',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF924653),
                              minimumSize: const Size(46, 46),
                            ),
                            icon: const Icon(Icons.arrow_upward, size: 21),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ai
                            ? 'AI can make mistakes. Check policies. Don’t share personal details.'
                            : !ready
                            ? 'Connecting to Luvly…'
                            : !aiConfigured
                            ? 'AI is not connected · help guide answers only.'
                            : !consentDecided
                            ? 'General questions only · please don’t share personal details.'
                            : 'Help guide · no question is sent to AI.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF827579),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
