import 'dart:async';
import 'package:flutter/material.dart';
import '../packages/package_api.dart' show packageRequestId;
import '../payments/payment_api.dart' show PaymentFailure;
import '../src/design.dart' show CustomerUi;
import 'assistant_api.dart';
import 'assistant_history_api.dart';
import 'assistant_strings.dart';
import 'assistant_history_screen.dart';
import 'support_repository.dart' show supportTextError;

class SupportAssistantScreen extends StatefulWidget {
  const SupportAssistantScreen({
    super.key,
    this.api,
    this.onContact,
    this.onClose,
    this.session,
    this.offlineGuide = false,
    this.initialLanguage = 'auto',
  });
  final AssistantApi? api;
  final Future<void> Function(String draft)? onContact;
  final VoidCallback? onClose;
  final AssistantSession? session;
  final bool offlineGuide;
  final String initialLanguage;
  @override
  State<SupportAssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends State<SupportAssistantScreen>
    with WidgetsBindingObserver {
  late final AssistantApi api =
      widget.api ??
      (widget.offlineGuide ? _OfflineGuide() : LuvlyAssistantApi());
  final input = TextEditingController(), scroll = ScrollController();
  final composerFocus = FocusNode();
  final turns = <AssistantTurn>[];
  bool ready = false,
      aiConfigured = false,
      ai = false,
      consentDecided = false,
      deciding = false,
      busy = false,
      contacting = false;
  late String language = widget.initialLanguage;
  AssistantText? error;

  late AssistantStrings autoStrings;
  AssistantStrings get strings =>
      language == 'auto' ? autoStrings : AssistantStrings(language);
  int viewRevision = 0;
  AssistantConversation? conversation;
  int? before;
  bool restoring = false,
      restoreFailed = false,
      loadingOlder = false,
      changingLanguage = false,
      checkingPending = false;
  Timer? poll;
  AssistantReply? privacyNotice;

  AssistantSession? get session => widget.session;
  AssistantHistoryApi? get historyApi => session?.history;
  String? get chatId => conversation?.id;
  bool get archived => conversation?.archived ?? false;
  bool get reverseChat =>
      session != null && (turns.isNotEmpty || privacyNotice != null);
  AssistantTurn? get pending =>
      turns.lastOrNull?.reply == null ? turns.lastOrNull : null;
  bool get canCompose =>
      ready &&
      !restoring &&
      !restoreFailed &&
      !archived &&
      !busy &&
      !deciding &&
      !changingLanguage &&
      (session == null || pending == null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    input.addListener(onInput);
    if (session != null) restore();
    load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    autoStrings = AssistantStrings.of(context, 'auto');
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    setState(() => autoStrings = AssistantStrings.of(context, 'auto'));
  }

  void onInput() {
    session?.rememberDraft(chatId, input.text);
    if (mounted) setState(() {});
  }

  Future<void> restore() async {
    setState(() {
      restoring = true;
      restoreFailed = false;
      error = null;
    });
    try {
      final page = await session!.resume();
      if (mounted) showPage(page);
    } catch (_) {
      if (mounted) setState(() => restoreFailed = true);
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  void showPage(AssistantChatPage page) {
    poll?.cancel();
    viewRevision++;
    final prior = session!;
    final id = page.conversation?.id;
    final unsyncedId = id ?? prior.newConversationId;
    final unsynced = prior.submissions[unsyncedId];
    final draft = prior.drafts[prior.draftKey(id)] ?? '';
    setState(() {
      conversation = page.conversation;
      before = page.before;
      language = page.language;
      restoreFailed = false;
      checkingPending = false;
      loadingOlder = false;
      error = null;
      privacyNotice = null;
      turns
        ..clear()
        ..addAll(page.turns);
      if (unsynced != null && !turns.any((turn) => turn.id == unsynced.id)) {
        turns.add(unsynced);
      } else if (unsyncedId != null) {
        prior.submissions.remove(unsyncedId);
        if (unsyncedId == prior.newConversationId) {
          prior.newConversationId = null;
        }
      }
    });
    input.text = draft;
    bottom();
    schedulePendingCheck();
  }

  Future<void> older() async {
    final cursor = before;
    final id = chatId;
    final revision = viewRevision;
    if (cursor == null || id == null || loadingOlder) return;
    setState(() => loadingOlder = true);
    try {
      final page = await historyApi!.read(id, before: cursor);
      if (mounted && revision == viewRevision) {
        setState(() {
          final seen = turns.map((turn) => turn.id).toSet();
          turns.insertAll(0, page.turns.where((turn) => seen.add(turn.id)));
          before = page.before;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted && revision == viewRevision && !handleMissing(failure)) {
        setState(() => error = AssistantText.olderFailed);
      }
    } finally {
      if (mounted && revision == viewRevision) {
        setState(() => loadingOlder = false);
      }
    }
  }

  bool handleMissing(Object failure) {
    if (failure is! PaymentFailure ||
        failure.code != 'ASSISTANT_CONVERSATION_MISSING') {
      return false;
    }
    final id = chatId ?? session?.newConversationId;
    if (id != null) session?.forget(id);
    showPage(AssistantChatPage(language: language));
    setState(() => error = AssistantText.missing);
    return true;
  }

  void schedulePendingCheck() {
    poll?.cancel();
    if (pending?.status == 'generating' && chatId != null && !archived) {
      poll = Timer(const Duration(seconds: 3), checkPending);
    }
  }

  Future<void> checkPending() async {
    final id = chatId;
    final revision = viewRevision;
    if (id == null || archived || busy || restoring || checkingPending) return;
    poll?.cancel();
    setState(() => checkingPending = true);
    try {
      final page = await historyApi!.read(id);
      if (!mounted || revision != viewRevision) return;
      setState(() {
        conversation = page.conversation;
        for (final turn in page.turns) {
          updateTurn(turn);
        }
        final local = session?.submissions[id];
        if (local != null &&
            local.status == 'failed' &&
            !page.turns.any((turn) => turn.id == local.id)) {
          updateTurn(local);
        }
        error = null;
      });
      if (pending == null) bottom();
      schedulePendingCheck();
    } catch (failure) {
      if (mounted && revision == viewRevision && !handleMissing(failure)) {
        setState(() => error = AssistantText.checkFailed);
      }
    } finally {
      if (mounted && revision == viewRevision) {
        setState(() => checkingPending = false);
      }
    }
  }

  void updateTurn(AssistantTurn turn) {
    final index = turns.indexWhere((entry) => entry.id == turn.id);
    if (index < 0) {
      turns.add(turn);
      turns.sort((a, b) => a.sequence.compareTo(b.sequence));
    } else {
      turns[index] = turn;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    input.removeListener(onInput);
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
      barrierLabel: strings[AssistantText.dismiss],
      builder: (c) => AlertDialog(
        title: Text(strings[AssistantText.consentTitle]),
        content: SingleChildScrollView(
          child: Text(strings[AssistantText.consentBody]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(strings[AssistantText.useGuide]),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(strings[AssistantText.enableAi]),
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
    if (mounted && scroll.hasClients) {
      final position = scroll.position;
      final latest = reverseChat
          ? position.minScrollExtent
          : position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(latest);
      } else {
        scroll.animateTo(
          latest,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  });
  Future<void> send([String? suggestion]) async {
    if (!canCompose) return;
    final question = (suggestion ?? input.text).trim(),
        validation = supportTextError(question, 1, 256);
    if (validation != null) {
      setState(
        () => error = question.isEmpty || question.length > 256
            ? AssistantText.length
            : AssistantText.invalidChars,
      );
      return;
    }
    if (session == null && turns.length >= 20) {
      setState(() => error = AssistantText.limitNew);
      return;
    }
    // Opening the chat never sends a question to Google. Ask once, at the
    // first general message, and keep the draft if the dialog is dismissed.
    if (!assistantPrivacyBlocked(question) && aiConfigured && !consentDecided) {
      FocusScope.of(context).unfocus();
      final proceed = await changeAI();
      if (!mounted || !proceed) return;
    }
    final turn = AssistantTurn(question: question, id: packageRequestId());
    if (session != null) {
      await sendPersisted(turn, newQuestion: true);
      return;
    }
    final history = turns
        .where((t) => t.reply?.notice != 'Privacy')
        .map((t) => t.question)
        .toList();
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
              requestId: turn.id,
            );
      if (mounted) {
        setState(
          () => updateTurn(
            AssistantTurn(
              question: question,
              id: turn.id,
              status: 'complete',
              reply: reply,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          turns.remove(turn);
          input.text = question;
          error = AssistantText.answerFailed;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        bottom();
      }
    }
  }

  Future<void> sendPersisted(
    AssistantTurn turn, {
    bool newQuestion = false,
  }) async {
    final owner = session!;
    if (newQuestion && assistantPrivacyBlocked(turn.question)) {
      final notice = await localHelp(turn.question, const [], language);
      if (mounted) {
        setState(() {
          input.clear();
          privacyNotice = notice;
        });
        bottom();
      }
      return;
    }
    final id = chatId ?? (owner.newConversationId ??= packageRequestId());
    if (newQuestion) owner.submissions[id] = turn;
    final original = owner.submissions[id];
    setState(() {
      if (newQuestion) {
        turns.add(turn);
        input.clear();
      }
      privacyNotice = null;
      busy = true;
      error = null;
    });
    bottom();
    try {
      final saved = await owner.history.send(
        id,
        requestId: turn.id,
        question: original?.question,
        language: language,
        ai: ai,
        create: chatId == null,
      );
      if (owner.disposed) return;
      if (identical(owner.submissions[id], original)) {
        owner.submissions.remove(id);
      }
      if (owner.newConversationId == id) owner.newConversationId = null;
      if (!mounted) return;
      setState(() {
        if (saved.privacy != null) {
          turns.removeWhere((entry) => entry.id == turn.id);
          privacyNotice = saved.privacy;
        } else {
          conversation = saved.conversation!;
          updateTurn(saved.turn!);
        }
      });
      schedulePendingCheck();
    } catch (failure) {
      if (owner.disposed) return;
      final failed = AssistantTurn(
        question: turn.question,
        id: turn.id,
        sequence: turn.sequence,
        status: 'failed',
      );
      if (original != null && identical(owner.submissions[id], original)) {
        owner.submissions[id] = failed;
      }
      if (!mounted || handleMissing(failure)) return;
      if (failure is PaymentFailure &&
          [
            'ASSISTANT_TURN_PENDING',
            'ASSISTANT_CONVERSATION_ARCHIVED',
          ].contains(failure.code)) {
        owner.submissions.remove(id);
        try {
          final page = await owner.history.read(id);
          if (mounted) {
            showPage(page);
            input.text = turn.question;
            setState(() => error = AssistantText.changedDraft);
          }
          return;
        } catch (_) {
          if (!mounted) return;
          if (original != null) owner.submissions[id] = failed;
        }
      }
      setState(() => updateTurn(failed));
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
              (session == null || t.reply != null) &&
              !assistantPrivacyBlocked(t.question),
        )
        .toList();
    final recent = safeTurns.skip(
      safeTurns.length > 3 ? safeTurns.length - 3 : 0,
    );
    var draft = recent
        .map(
          (t) =>
              '${strings[AssistantText.customer]}: ${t.question}\n${t.reply?.mode == 'AI' ? 'Gemini AI' : strings[AssistantText.guide]}: ${t.reply?.answer ?? strings[AssistantText.noAnswer]}',
        )
        .join('\n\n');
    if (draft.length > 1700) draft = draft.substring(0, 1700);
    setState(() => contacting = true);
    try {
      await widget.onContact!(
        '${strings[AssistantText.reviewDraft]}\n\n$draft',
      );
    } finally {
      if (mounted) setState(() => contacting = false);
    }
  }

  Future<void> clear() async {
    if (session != null) {
      await newChat();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierLabel: strings[AssistantText.dismiss],
      builder: (c) => AlertDialog(
        title: Text(strings[AssistantText.startNew]),
        content: Text(strings[AssistantText.legacyClear]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(strings[AssistantText.keepChat]),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(strings[AssistantText.clearChat]),
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

  Future<void> newChat() async {
    final owner = session!;
    if (busy || deciding || restoring || changingLanguage) return;
    if (chatId == null && (input.text.trim().isNotEmpty || pending != null)) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierLabel: strings[AssistantText.dismiss],
        builder: (dialog) => AlertDialog(
          title: Text(strings[AssistantText.startNew]),
          content: Text(strings[AssistantText.unsentWarning]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(strings[AssistantText.keepDraft]),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(strings[AssistantText.newChat]),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() => restoring = true);
    try {
      await owner.history.newChat(language);
      if (!mounted) return;
      final unsynced = owner.newConversationId;
      if (unsynced != null) owner.forget(unsynced);
      owner.rememberDraft(null, '');
      // Begin with the language the customer was just using.
      showPage(AssistantChatPage(language: language));
    } catch (_) {
      if (mounted) {
        setState(() => error = AssistantText.newFailed);
      }
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  Future<void> showHistory() async {
    final owner = session!;
    poll?.cancel();
    final revision = owner.historyRevision;
    final choice = await Navigator.of(context).push<AssistantHistoryChoice>(
      MaterialPageRoute(
        builder: (_) => ScaffoldMessenger(
          child: AssistantHistoryScreen(session: owner, strings: strings),
        ),
      ),
    );
    if (!mounted) return;
    if (choice?.newChat == true) {
      await newChat();
      return;
    }
    final id = choice?.id ?? chatId;
    if (id == null || choice == null && revision == owner.historyRevision) {
      schedulePendingCheck();
      return;
    }
    setState(() => restoring = true);
    try {
      final page = choice?.id == null
          ? await owner.history.read(id)
          : await owner.history.open(id);
      if (mounted) showPage(page);
    } catch (failure) {
      if (!mounted || id == chatId && handleMissing(failure)) return;
      setState(() => error = AssistantText.openFailed);
    } finally {
      if (mounted) {
        setState(() => restoring = false);
        schedulePendingCheck();
      }
    }
  }

  Future<void> setLanguage(String value) async {
    if (value == language ||
        changingLanguage ||
        busy ||
        archived ||
        restoring) {
      return;
    }
    if (session == null) {
      setState(() => language = value);
      return;
    }
    final previous = language;
    setState(() {
      changingLanguage = true;
      language = value;
      error = null;
    });
    try {
      await session!.saveLanguage(chatId, value);
    } catch (failure) {
      if (mounted) {
        setState(() => language = previous);
        if (!handleMissing(failure)) {
          setState(() => error = AssistantText.languageFailed);
        }
      }
    } finally {
      if (mounted) setState(() => changingLanguage = false);
    }
  }

  Future<void> restoreArchive() async {
    final id = chatId;
    if (id == null || restoring) return;
    setState(() => restoring = true);
    try {
      await historyApi!.setArchived(id, false);
      final page = await historyApi!.open(id);
      if (mounted) showPage(page);
    } catch (failure) {
      if (mounted && !handleMissing(failure)) {
        setState(() => error = AssistantText.restoreFailed);
      }
    } finally {
      if (mounted) {
        setState(() => restoring = false);
        schedulePendingCheck();
      }
    }
  }

  void explainModes() => showModalBottomSheet<void>(
    context: context,
    barrierLabel: strings[AssistantText.dismiss],
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings[AssistantText.waysTitle],
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 18),
            Text(
              strings[AssistantText.aiMode],
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(strings[AssistantText.aiModeDetail]),
            SizedBox(height: 18),
            Text(
              strings[AssistantText.guideMode],
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(strings[AssistantText.guideModeDetail]),
            SizedBox(height: 18),
            Text(strings[AssistantText.compareDetail]),
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
    'Offline' => strings[AssistantText.noticeOffline],
    'SetupRequired' => strings[AssistantText.noticeSetup],
    'ShortenQuestion' => strings[AssistantText.noticeShorten],
    'Quota' => strings[AssistantText.noticeQuota],
    'Busy' => strings[AssistantText.noticeBusy],
    'PersonalSupport' => strings[AssistantText.noticePersonal],
    'OutsideScope' => strings[AssistantText.noticeScope],
    'AlreadyAnswered' => strings[AssistantText.noticeAnswered],
    _ => strings[AssistantText.noticeUnavailable],
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
                reply.mode == 'AI'
                    ? strings[AssistantText.aiAnswer]
                    : strings[AssistantText.guideAnswer],
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
                          strings.format(
                            reply.mode == 'AI'
                                ? AssistantText.basedOn
                                : AssistantText.guideTopic,
                            reply.sources
                                .map((source) => source['title'])
                                .join(' · '),
                          ),
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
                  title: Text(
                    strings[AssistantText.checkPolicy],
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
                      strings.format(
                        AssistantText.policyVersion,
                        reply.version,
                      ),
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
                    label: Text(strings[AssistantText.askTeam]),
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
      automaticallyImplyLeading: false,
      leading:
          widget.onClose == null && (ModalRoute.of(context)?.canPop ?? false)
          ? IconButton(
              tooltip: strings[AssistantText.back],
              icon: const BackButtonIcon(),
              onPressed: () => Navigator.maybePop(context),
            )
          : null,
      titleSpacing: widget.onClose == null ? 0 : 18,
      title: Row(
        children: [
          avatar(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings[AssistantText.appName],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  conversation?.title ??
                      (ai
                          ? strings[AssistantText.aiStatus]
                          : !ready
                          ? strings[AssistantText.connecting]
                          : aiConfigured && !consentDecided
                          ? strings[AssistantText.companion]
                          : strings[AssistantText.guideAiOff]),
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
        if (session != null)
          IconButton(
            tooltip: strings[AssistantText.history],
            icon: const Icon(Icons.history, size: 21),
            onPressed: busy || deciding || restoring || changingLanguage
                ? null
                : showHistory,
          ),
        PopupMenuButton<String>(
          tooltip: strings[AssistantText.chatOptions],
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
              setLanguage(v);
            }
          },
          itemBuilder: (_) => [
            if (aiConfigured)
              PopupMenuItem(
                value: 'ai',
                enabled: !busy && !deciding,
                child: Text(
                  ai
                      ? strings[AssistantText.disableAi]
                      : strings[AssistantText.enableAi],
                ),
              ),
            if (widget.onContact != null)
              PopupMenuItem(
                value: 'contact',
                enabled: !busy && !deciding && !contacting,
                child: Text(strings[AssistantText.contact]),
              ),
            PopupMenuItem(
              value: 'modes',
              child: Text(strings[AssistantText.compareModes]),
            ),
            PopupMenuItem(
              value: 'new',
              enabled:
                  !busy &&
                  !deciding &&
                  !restoring &&
                  !changingLanguage &&
                  (session != null || turns.isNotEmpty),
              child: Text(strings[AssistantText.newChat]),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              enabled: false,
              child: Semantics(
                header: true,
                child: Text(strings[AssistantText.languageSelection]),
              ),
            ),
            for (final l in assistantPreferences.entries)
              PopupMenuItem(
                value: l.key,
                enabled: !archived && !restoring && !busy && !changingLanguage,
                child: Semantics(
                  selected: language == l.key,
                  child: Text(
                    '${language == l.key ? '✓ ' : ''}${l.key == 'auto' ? strings[AssistantText.auto] : l.value}',
                  ),
                ),
              ),
          ],
          icon: const Icon(Icons.more_horiz),
        ),
        if (widget.onClose != null)
          IconButton(
            onPressed: widget.onClose,
            tooltip: strings[AssistantText.closeAssistant],
            icon: const Icon(Icons.close, size: 21),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            if (!ready || restoring || changingLanguage)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: restoreFailed
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              strings[AssistantText.loadChatFailed],
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: restore,
                              child: Text(strings[AssistantText.retry]),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SupportAssistantScreen(
                                    offlineGuide: true,
                                    initialLanguage: language,
                                    onContact: widget.onContact,
                                  ),
                                ),
                              ),
                              child: Text(strings[AssistantText.useOffline]),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      controller: scroll,
                      reverse: reverseChat,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                      children: <Widget>[
                        if (before != null)
                          TextButton(
                            onPressed: loadingOlder || restoring ? null : older,
                            child: Text(
                              loadingOlder
                                  ? strings[AssistantText.loadingOlder]
                                  : strings[AssistantText.older],
                            ),
                          ),
                        if (!restoring &&
                            !archived &&
                            (session == null || turns.isEmpty))
                          Padding(
                            padding: const EdgeInsets.only(
                              right: 24,
                              bottom: 24,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFECE4E1),
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                strings[AssistantText.welcome],
                                style: TextStyle(fontSize: 14, height: 1.6),
                              ),
                            ),
                          ),
                        if (!restoring && turns.isEmpty && !archived)
                          Padding(
                            key: const Key('assistant-question-starters'),
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings[AssistantText.suggestions],
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
                                    for (final question in [
                                      strings[AssistantText.fittingQuestion],
                                      strings[AssistantText.depositQuestion],
                                      strings[AssistantText.scheduleQuestion],
                                    ])
                                      OutlinedButton(
                                        onPressed: !canCompose
                                            ? null
                                            : () {
                                                input.value = TextEditingValue(
                                                  text: question,
                                                  selection:
                                                      TextSelection.collapsed(
                                                        offset: question.length,
                                                      ),
                                                );
                                                setState(() => error = null);
                                                composerFocus.requestFocus();
                                              },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF924653,
                                          ),
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
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
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
                              margin: const EdgeInsets.only(
                                left: 38,
                                bottom: 18,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: session == null
                                    ? const Color(0xFF924653)
                                    : const Color(0xFFF3E6E8),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  topRight: Radius.circular(18),
                                  bottomLeft: Radius.circular(18),
                                ),
                              ),
                              child: Text(
                                turn.question,
                                style: TextStyle(
                                  color: session == null
                                      ? Colors.white
                                      : const Color(0xFF382E31),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (turn.reply != null) answerCard(turn.reply!),
                        ],
                        if (privacyNotice != null) answerCard(privacyNotice!),
                        if (session != null &&
                            pending != null &&
                            !busy &&
                            !archived)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed:
                                  restoring || changingLanguage || deciding
                                  ? null
                                  : pending!.status == 'generating' &&
                                        chatId != null
                                  ? checkPending
                                  : () => sendPersisted(pending!),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(
                                pending!.status == 'generating' &&
                                        chatId != null
                                    ? strings[AssistantText.checkReply]
                                    : strings[AssistantText.retryMessage],
                              ),
                            ),
                          ),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    ai
                                        ? strings[AssistantText.generating]
                                        : strings[AssistantText.findingGuide],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF827579),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ].letInChatOrder(reverseChat),
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Text(
                  strings[error!],
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (archived)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: OutlinedButton.icon(
                    onPressed: restoring ? null : restoreArchive,
                    icon: const Icon(Icons.unarchive_outlined),
                    label: Text(strings[AssistantText.restoreToChat]),
                  ),
                ),
              )
            else if (!restoreFailed)
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
                                enabled: canCompose,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 256,
                                style: const TextStyle(fontSize: 13),
                                textInputAction: TextInputAction.send,
                                decoration: InputDecoration(
                                  hintText: strings[AssistantText.composer],
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
                            Semantics(
                              hint: session != null && input.text.trim().isEmpty
                                  ? strings[AssistantText.sendEmpty]
                                  : null,
                              child: IconButton.filled(
                                onPressed:
                                    !canCompose ||
                                        session != null &&
                                            input.text.trim().isEmpty
                                    ? null
                                    : send,
                                tooltip: strings[AssistantText.send],
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF924653),
                                  minimumSize: const Size(46, 46),
                                ),
                                icon: const Icon(Icons.arrow_upward, size: 21),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.offlineGuide
                              ? strings[AssistantText.offlineSaved]
                              : ai
                              ? strings[AssistantText.aiReminder]
                              : !ready
                              ? strings[AssistantText.connectingLuvly]
                              : session != null
                              ? strings[AssistantText.savedReminder]
                              : !aiConfigured
                              ? strings[AssistantText.guideOnly]
                              : !consentDecided
                              ? strings[AssistantText.generalReminder]
                              : strings[AssistantText.guideReminder],
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

extension on List<Widget> {
  List<Widget> letInChatOrder(bool reverse) =>
      reverse ? reversed.toList(growable: false) : this;
}

class _OfflineGuide implements AssistantApi {
  @override
  Future<bool> configured() async => false;

  @override
  Future<AssistantReply> ask({
    required String message,
    required List<String> history,
    required String language,
    required bool ai,
    required String requestId,
  }) => localHelp(message, history, language);

  @override
  void close() {}
}
