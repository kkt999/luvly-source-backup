import 'package:flutter/material.dart';
import 'support_repository.dart';
import 'assistant_launcher.dart';
import '../shared/list_controls.dart';
import 'support_hub.dart';
import 'assistant_api.dart';

class LiveSupportScreen extends StatefulWidget {
  const LiveSupportScreen({
    super.key,
    required this.uid,
    required this.name,
    this.staff = false,
    this.active = true,
    this.assistantApi,
  });
  final String uid, name;
  final bool staff;
  final bool active;
  final AssistantApi? assistantApi;
  @override
  State<LiveSupportScreen> createState() => _LiveSupportScreenState();
}

class _LiveSupportScreenState extends State<LiveSupportScreen> {
  Stream<List<SupportCase>>? feed;
  SupportRepository? _repository;
  String filter = 'Active';
  String query = '';
  String category = 'All categories';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = SupportScope.maybeOf(context);
    if (!identical(_repository, repository)) {
      _repository = repository;
      reloadFeed();
    }
  }

  @override
  void didUpdateWidget(LiveSupportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.staff != widget.staff) {
      reloadFeed();
    }
  }

  void reloadFeed() {
    feed = _repository?.cases(uid: widget.staff ? null : widget.uid);
  }

  Future<String?> Function(SupportCase)? get loadPreview {
    final repository = _repository;
    return repository is SupportPreviewRepository
        ? (repository as SupportPreviewRepository).latestMessagePreview
        : null;
  }

  @override
  Widget build(BuildContext context) => widget.staff
      ? staffWorkspace(context)
      : AssistantExclusion(
          enabled: widget.active,
          child: CustomerSupportHub(
            key: ValueKey(widget.uid),
            feed: feed,
            loadPreview: loadPreview,
            active: widget.active,
            onRetry: () => setState(reloadFeed),
            onAssistant: () => openLuvlyAssistant(
              context,
              api: widget.assistantApi,
              onContact: (draft) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NewSupportTicket(
                      uid: widget.uid,
                      name: widget.name,
                      initialSubject: 'Assistant follow-up',
                      initialBody: draft,
                      initialCategory: 'Other',
                    ),
                  ),
                );
              },
            ),
            onMessage: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    NewSupportTicket(uid: widget.uid, name: widget.name),
              ),
            ),
            onOpen: (ticket) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SupportConversation(
                  id: ticket.id,
                  uid: widget.uid,
                  name: widget.name,
                ),
              ),
            ),
          ),
        );

  Widget staffWorkspace(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
    children: [
      Text(
        widget.staff ? 'Customer support' : 'Here for your\nbridal journey.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        widget.staff
            ? 'Manage customer conversations and follow-ups. Assistant guidance is separate from team replies.'
            : 'A quick answer, or a conversation with our team.',
        style: const TextStyle(fontSize: 13, color: Color(0xFF827579)),
      ),
      if (!widget.staff) ...[
        const SizedBox(height: 22),
        Material(
          color: const Color(0xFFF3E6E8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openLuvlyAssistant(
              context,
              onContact: (draft) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NewSupportTicket(
                      uid: widget.uid,
                      name: widget.name,
                      initialSubject: 'Assistant follow-up',
                      initialBody: draft,
                      initialCategory: 'Other',
                    ),
                  ),
                );
              },
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.smart_toy_outlined,
                      color: Color(0xFF924653),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Luvly Assistant',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Fittings, rentals & the little details',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF827579),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.north_east,
                    color: Color(0xFF924653),
                    size: 19,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 28),
      Row(
        children: [
          Expanded(
            child: Text(
              widget.staff ? 'Customer conversations' : 'Your conversations',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (!widget.staff)
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      NewSupportTicket(uid: widget.uid, name: widget.name),
                ),
              ),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('New message', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      const SizedBox(height: 3),
      const Text(
        'Personal help from the Luvly team. Check replies here.',
        style: TextStyle(fontSize: 11, color: Color(0xFF827579)),
      ),
      const SizedBox(height: 14),
      ListSearchField(
        value: query,
        hint: 'Search conversations',
        onChanged: (v) => setState(() => query = v),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in ['Active', 'Closed', 'All'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => setState(() => filter = s),
                style: TextButton.styleFrom(
                  foregroundColor: filter == s
                      ? const Color(0xFF924653)
                      : const Color(0xFF827579),
                  backgroundColor: filter == s
                      ? const Color(0xFFF3E6E8)
                      : Colors.transparent,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(s, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ListFilterSelect(
            label: 'Topic',
            value: category,
            options: ['All categories', ...supportCategories],
            onChanged: (v) => setState(() => category = v),
          ),
          if (query.isNotEmpty ||
              filter != 'Active' ||
              category != 'All categories')
            ResetListFilters(
              onReset: () => setState(() {
                query = '';
                filter = 'Active';
                category = 'All categories';
              }),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (feed == null)
        const Text('Support is unavailable.')
      else
        StreamBuilder<List<SupportCase>>(
          stream: feed,
          builder: (c, s) {
            if (s.hasError) {
              return Column(
                children: [
                  const Text('Could not load conversations.'),
                  TextButton(
                    onPressed: () => setState(
                      () => feed = SupportScope.maybeOf(
                        context,
                      )?.cases(uid: widget.staff ? null : widget.uid),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = s.data!
                .where(
                  (t) =>
                      (filter == 'All' ||
                          (filter == 'Closed'
                              ? t.status == 'Closed'
                              : t.status != 'Closed')) &&
                      (category == 'All categories' ||
                          t.category == category) &&
                      matchesListSearch(query, [
                        t.subject,
                        t.category,
                        if (widget.staff) t.name,
                      ]),
                )
                .toList();
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No conversations match this view.'),
              );
            }
            return Column(
              children: rows
                  .map(
                    (t) => Card(
                      color: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: const BorderSide(color: Color(0xFFECE4E1)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        leading: const CircleAvatar(
                          radius: 19,
                          backgroundColor: Color(0xFFF8F2F0),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: Color(0xFFA65360),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          t.subject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${t.category} · ${t.status}${widget.staff ? '\n${t.name}' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF827579),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => SupportConversation(
                              id: t.id,
                              uid: widget.uid,
                              name: widget.name,
                              staff: widget.staff,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
    ],
  );
}

class NewSupportTicket extends StatefulWidget {
  const NewSupportTicket({
    super.key,
    required this.uid,
    required this.name,
    this.initialSubject = '',
    this.initialBody = '',
    this.initialCategory = 'Appointments',
  });
  final String uid, name;
  final String initialSubject, initialBody, initialCategory;
  @override
  State<NewSupportTicket> createState() => _NewSupportTicketState();
}

class _NewSupportTicketState extends State<NewSupportTicket> {
  final form = GlobalKey<FormState>();
  late final subject = TextEditingController(text: widget.initialSubject),
      body = TextEditingController(text: widget.initialBody);
  late String category = supportCategories.contains(widget.initialCategory)
      ? widget.initialCategory
      : 'Other';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await SupportScope.maybeOf(context)!.create(
        uid: widget.uid,
        name: widget.name,
        subject: subject.text,
        category: category,
        body: body.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              SupportConversation(id: id, uid: widget.uid, name: widget.name),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = supportError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AssistantExclusion(child: Text('Ask a question')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Your name and messages will be visible to authorised Luvly staff. Do not send passwords, card numbers or sensitive documents.',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: supportCategories
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: busy ? null : (s) => setState(() => category = s!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: subject,
                enabled: !busy,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Subject'),
                validator: (s) => supportTextError(s ?? '', 3, 120),
              ),
              TextFormField(
                controller: body,
                enabled: !busy,
                maxLength: 2000,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'How can we help?',
                ),
                validator: (s) => supportTextError(s ?? '', 1, 2000),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Sending…' : 'Send question'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SupportConversation extends StatefulWidget {
  const SupportConversation({
    super.key,
    required this.id,
    required this.uid,
    required this.name,
    this.staff = false,
  });
  final String id, uid, name;
  final bool staff;
  @override
  State<SupportConversation> createState() => _SupportConversationState();
}

class _SupportConversationState extends State<SupportConversation> {
  final input = TextEditingController();
  SupportRepository? repository;
  Stream<SupportCase?>? ticketFeed;
  Stream<List<SupportReply>>? messageFeed;
  bool busy = false;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    repository ??= SupportScope.maybeOf(context);
    ticketFeed ??= repository?.watch(widget.id);
    messageFeed ??= repository?.replies(widget.id);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final validation = supportTextError(input.text, 1, 2000);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repository!.reply(
        widget.id,
        actor: widget.uid,
        name: widget.name,
        staff: widget.staff,
        body: input.text,
      );
      if (mounted) input.clear();
    } catch (e) {
      if (mounted) setState(() => error = supportError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> closeCase(SupportCase t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close this conversation?'),
        content: const Text(
          'The history remains readable. Start a new ticket if you need more help.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep open'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Close conversation'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repository!.close(t, widget.uid);
    } catch (e) {
      if (mounted) setState(() => error = supportError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AssistantExclusion(child: Text('Conversation')),
    ),
    body: StreamBuilder<SupportCase?>(
      stream: ticketFeed,
      builder: (c, s) {
        if (s.hasError) {
          return const Center(
            child: Text('Unable to load this conversation. Go back and retry.'),
          );
        }
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final t = s.data;
        if (t == null) {
          return const Center(child: Text('Conversation unavailable.'));
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(t.subject, style: Theme.of(c).textTheme.titleLarge),
                      Text('${t.category} · ${t.status}'),
                      if (t.status != 'Closed')
                        TextButton(
                          onPressed: busy ? null : () => closeCase(t),
                          child: const Text('Close conversation'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<SupportReply>>(
                    stream: messageFeed,
                    builder: (c, m) {
                      if (m.hasError) {
                        return const Center(
                          child: Text(
                            'Unable to load messages. Go back and retry.',
                          ),
                        );
                      }
                      if (!m.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (m.data!.length == 100)
                            const Text('Showing the latest 100 messages.'),
                          for (final r in m.data!)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r.sender} · ${r.role == 'staff' ? 'Luvly team' : 'Bride'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SelectableText(r.body),
                                    if (r.sentAt != null)
                                      Text(
                                        '${r.sentAt!.toUtc().add(const Duration(hours: 8)).toString().substring(0, 16)} MYT',
                                        style: Theme.of(c).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: t.status == 'Closed'
                        ? const Text(
                            'This conversation is closed. Your history is saved.',
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: input,
                                  enabled: !busy,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 2000,
                                  decoration: const InputDecoration(
                                    labelText: 'Your reply',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Send reply',
                                onPressed: busy ? null : send,
                                icon: busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(),
                                      )
                                    : const Icon(Icons.send),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
