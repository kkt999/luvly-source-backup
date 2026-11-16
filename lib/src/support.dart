import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import '../support/support_screens.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key, this.active = true});
  final bool active;
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    if (m.accountId != null) {
      return LiveSupportScreen(uid: m.accountId!, name: m.name, active: active);
    }
    return PageList(
      children: [
        Text(
          'A little help,\nwhenever you need it.',
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        gap(12),
        const Text(
          'From your first question to your final fitting, we’re here for you.',
          style: TextStyle(color: muted),
        ),
        gap(24),
        Surface(
          color: blush,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.auto_awesome, color: rose),
              ),
              gap(14),
              Text(
                'Meet your Luvly assistant',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              gap(8),
              const Text(
                'Questions about dresses, appointments or your package? Let’s talk.',
                style: TextStyle(color: muted),
              ),
              gap(18),
              Primary(
                'Start a conversation',
                () => go(c, const AssistantScreen()),
              ),
            ],
          ),
        ),
        const Section('Talk to our team'),
        MenuTile(
          Icons.add_comment_outlined,
          'Create a support ticket',
          'Let us know how we can help',
          () => go(c, const CreateTicketScreen()),
        ),
        MenuTile(
          Icons.forum_outlined,
          'My support tickets',
          '${m.tickets.where((t) => t.status != 'Closed').length} active conversations',
          () => go(c, const TicketsScreen()),
        ),
        const Section('A few helpful answers'),
        for (final q in [
          (
            'What should I bring to a fitting?',
            'Bring inspiration photos, comfortable undergarments and any accessories you plan to wear.',
          ),
          (
            'Can I reschedule an appointment?',
            'For a confirmed visit that has not started, use Reschedule in Bookings and choose a new available time. The same appointment and verified fitting fee are kept. Complete any unpaid fitting payment first. Paid cancellations still need team review.',
          ),
          (
            'Where are my payment records?',
            'You can find Payments & receipts in your profile or the home screen shortcuts.',
          ),
        ])
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              q.$1,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            children: [Text(q.$2, style: const TextStyle(color: muted))],
          ),
        const DemoNote(),
      ],
    );
  }
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends State<AssistantScreen> {
  final input = TextEditingController(), scroll = ScrollController();
  final messages = <ChatMessage>[
    const ChatMessage(
      'Hello, lovely! I’m your Luvly demo assistant. What would you like to know about your bridal journey?',
      false,
    ),
  ];
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send([String? text]) {
    final question = (text ?? input.text).trim();
    if (question.isEmpty) return;
    final lower = question.toLowerCase();
    final answer = lower.contains('appoint') || lower.contains('book')
        ? 'Open Bookings to choose a visit type, date and time. Use Reschedule for a confirmed visit that has not started. It keeps the same appointment and verified fitting fee; paid cancellations remain subject to team review.'
        : lower.contains('dress') || lower.contains('fitting')
        ? 'Explore Dresses, save your favourites with the heart icon, and preview a try-on. For a real fitting, book a Dress Trial appointment.'
        : lower.contains('pay')
        ? 'Your Payments & receipts screen shows your sample balance and demo payment records. No real charges are made in this prototype.'
        : lower.contains('package')
        ? 'Open Packages from Home to compare packages, choose optional extras and review the total.'
        : 'I can show sample help for dresses, appointments, packages and payments. For other questions, create a support ticket below.';
    setState(() {
      messages.add(ChatMessage(question, true));
      messages.add(ChatMessage(answer, false));
      input.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Luvly assistant',
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: DemoNote(
            text:
                'Scripted UI demo • Replies are sample responses, not live AI.',
          ),
        ),
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              for (final msg in messages) MessageBubble(msg),
              if (messages.length == 1)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final q in [
                      'Book an appointment',
                      'Find a dress',
                      'Package options',
                    ])
                      ActionChip(label: Text(q), onPressed: () => send(q)),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextButton.icon(
            onPressed: () => go(c, const CreateTicketScreen()),
            icon: const Icon(Icons.support_agent, size: 18),
            label: const Text('Need our team? Create a ticket'),
          ),
        ),
        Composer(controller: input, onSend: send),
      ],
    ),
  );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble(this.message, {super.key});
  final ChatMessage message;
  @override
  Widget build(BuildContext c) => Align(
    alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: EdgeInsets.only(
        bottom: 14,
        left: message.mine ? 30 : 0,
        right: message.mine ? 0 : 30,
      ),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: message.mine ? blush : Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(message.mine ? 16 : 3),
          bottomRight: Radius.circular(message.mine ? 3 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.mine ? 'You' : 'Luvly',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: rose,
            ),
          ),
          gap(5),
          Text(message.text),
        ],
      ),
    ),
  );
}

class Composer extends StatelessWidget {
  const Composer({super.key, required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Write your message…'),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send message',
          onPressed: onSend,
          icon: const Icon(Icons.arrow_upward),
        ),
      ],
    ),
  );
}

class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});
  @override
  State<CreateTicketScreen> createState() => _CreateTicketState();
}

class _CreateTicketState extends State<CreateTicketScreen> {
  final form = GlobalKey<FormState>(),
      subject = TextEditingController(),
      description = TextEditingController();
  String category = 'Appointments';
  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Create a support ticket',
    bottom: Primary('Submit demo ticket', () {
      if (!form.currentState!.validate()) return;
      final m = AppScope.of(c);
      final t = Ticket(
        'LV-${1000 + m.tickets.length}',
        subject.text.trim(),
        category,
        [ChatMessage(description.text.trim(), true)],
      );
      m.tickets.insert(0, t);
      m.changed();
      Navigator.of(c).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => TicketDetailScreen(ticket: t)),
      );
      toast(c, 'Demo ticket created. No message was sent to staff.');
    }),
    child: PageList(
      children: [
        Text('We’re listening.', style: Theme.of(c).textTheme.headlineMedium),
        gap(10),
        const Text(
          'Tell us a little about your question and our team will know where to start.',
          style: TextStyle(color: muted),
        ),
        gap(24),
        Form(
          key: form,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items:
                    ['Appointments', 'Dresses', 'Packages', 'Payments', 'Other']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => setState(() => category = v!),
              ),
              gap(),
              TextFormField(
                controller: subject,
                decoration: const InputDecoration(labelText: 'Subject'),
                maxLength: 100,
                validator: (v) => (v ?? '').trim().length < 4
                    ? 'Enter a subject of at least 4 characters'
                    : null,
              ),
              gap(),
              TextFormField(
                controller: description,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'How can we help?',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v ?? '').trim().length < 10
                    ? 'Please give a little more detail (at least 10 characters)'
                    : null,
              ),
            ],
          ),
        ),
        const DemoNote(
          text:
              'Tickets and replies are stored in memory for this demo session only. They are not sent to a support team.',
        ),
      ],
    ),
  );
}

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});
  @override
  State<TicketsScreen> createState() => _TicketsState();
}

class _TicketsState extends State<TicketsScreen> {
  String filter = 'All', query = '';
  @override
  Widget build(BuildContext c) {
    final tickets = AppScope.of(c).tickets
        .where(
          (t) =>
              (filter == 'All' || t.status == filter) &&
              t.subject.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return PageFrame(
      title: 'My support tickets',
      actions: [
        IconButton(
          tooltip: 'Create ticket',
          onPressed: () => go(c, const CreateTicketScreen()),
          icon: const Icon(Icons.add),
        ),
      ],
      child: PageList(
        children: [
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: 'Search tickets',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          gap(14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final v in ['All', 'Open', 'In Progress', 'Closed'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(v),
                      selected: filter == v,
                      onSelected: (_) => setState(() => filter = v),
                    ),
                  ),
              ],
            ),
          ),
          gap(18),
          if (tickets.isEmpty)
            const EmptyState(
              Icons.forum_outlined,
              'No matching tickets',
              'Try another filter or create a new ticket.',
            ),
          for (final t in tickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: InkWell(
                onTap: () => go(c, TicketDetailScreen(ticket: t)),
                child: Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.id,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          StatusPill(t.status),
                        ],
                      ),
                      gap(12),
                      Text(t.subject, style: Theme.of(c).textTheme.titleMedium),
                      gap(6),
                      Text(
                        t.messages.last.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted),
                      ),
                      gap(10),
                      Text(
                        '${t.category} · ${t.messages.length} messages',
                        style: const TextStyle(fontSize: 11, color: rose),
                      ),
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

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.ticket});
  final Ticket ticket;
  @override
  State<TicketDetailScreen> createState() => _TicketDetailState();
}

class _TicketDetailState extends State<TicketDetailScreen> {
  final input = TextEditingController(), scroll = ScrollController();
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c), t = widget.ticket;
    return PageFrame(
      title: t.id,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.subject, style: Theme.of(c).textTheme.titleMedium),
                  gap(10),
                  StatusPill(t.status),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [for (final msg in t.messages) MessageBubble(msg)],
            ),
          ),
          if (t.status == 'Closed')
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This ticket is closed. Please create a new ticket if you need more help.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            )
          else
            Composer(
              controller: input,
              onSend: () {
                if (input.text.trim().isEmpty) return;
                t.messages.add(ChatMessage(input.text.trim(), true));
                input.clear();
                m.changed();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scroll.hasClients) {
                    scroll.jumpTo(scroll.position.maxScrollExtent);
                  }
                });
              },
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: DemoNote(
              text: 'Demo conversation • Messages are not sent to staff.',
            ),
          ),
        ],
      ),
    );
  }
}
