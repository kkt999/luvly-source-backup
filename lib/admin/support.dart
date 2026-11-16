import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportState();
}

class _SupportState extends State<SupportPage> {
  String query = '', filter = 'All statuses';
  SupportTicket? selected;
  final reply = TextEditingController();
  bool internal = false;
  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (selected != null) {
      if (!m.visibleTickets.contains(selected)) {
        selected = null;
      } else {
        return _detail(c, m, selected!);
      }
    }
    final tickets = m.visibleTickets
        .where(
          (t) =>
              (filter == 'All statuses' || t.status == filter) &&
              '${t.id} ${t.subject} ${m.brideName(t.brideId)}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return PageBody(
      children: [
        Heading(
          'Customer support',
          m.isManager
              ? 'Every conversation, thoughtfully handled. Assign and oversee support tickets.'
              : 'Respond to your assigned tickets and keep brides informed.',
        ),
        ResponsiveGrid(
          children: [
            Metric(
              'Open tickets',
              '${m.visibleTickets.where((t) => t.status == 'Open').length}',
              'Waiting for a first response',
              Icons.mark_chat_unread_outlined,
            ),
            Metric(
              'In progress',
              '${m.visibleTickets.where((t) => t.status == 'In Progress').length}',
              'Conversations being handled',
              Icons.forum_outlined,
            ),
            Metric(
              'Closed',
              '${m.visibleTickets.where((t) => t.status == 'Closed').length}',
              'Read-only conversations',
              Icons.task_alt,
            ),
          ],
        ),
        gap(26),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search ticket, bride or subject',
          filters: [
            filterSelect(filter, [
              'All statuses',
              ...ticketStatuses,
            ], (v) => setState(() => filter = v)),
          ],
        ),
        RecordTable(
          columns: const [
            'Ticket',
            'Bride',
            'Assigned to',
            'Priority',
            'Status',
            'Action',
          ],
          rows: tickets
              .map(
                (t) => [
                  cell(t.subject, sub: t.id),
                  cell(m.brideName(t.brideId)),
                  t.staffId == null
                      ? const Pill('Unassigned')
                      : cell(m.staffName(t.staffId)),
                  Pill(t.priority),
                  Pill(t.status),
                  TextButton(
                    onPressed: () => setState(() => selected = t),
                    child: const Text('View ticket'),
                  ),
                ],
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _detail(BuildContext c, PortalModel m, SupportTicket t) => PageBody(
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            selected = null;
            reply.clear();
          }),
          icon: const Icon(Icons.arrow_back, size: 17),
          label: const Text('Back to tickets'),
        ),
      ),
      gap(8),
      Heading(
        t.subject,
        '${t.id} · ${m.brideName(t.brideId)} · ${t.category}',
        action: Pill(t.status),
      ),
      LayoutBuilder(
        builder: (c, b) {
          final conversation = Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conversation', style: Theme.of(c).textTheme.titleMedium),
                gap(20),
                for (final msg in t.messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Align(
                      alignment: msg.sender == m.brideName(t.brideId)
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: msg.internal
                              ? const Color(0xFFFFF6E7)
                              : msg.sender == m.brideName(t.brideId)
                              ? canvas
                              : blush.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${msg.sender}${msg.internal ? ' · Internal note' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                            gap(7),
                            Text(msg.text),
                          ],
                        ),
                      ),
                    ),
                  ),
                const Divider(),
                if (t.status == 'Closed')
                  const Text(
                    'This ticket is closed. The conversation is read-only.',
                    style: TextStyle(color: muted),
                  )
                else ...[
                  TextField(
                    controller: reply,
                    maxLines: 4,
                    minLines: 3,
                    decoration: InputDecoration(
                      labelText: internal
                          ? 'Write an internal note'
                          : 'Write your reply',
                      hintText: internal
                          ? 'Only visible to team members in this demo.'
                          : 'How can we help this bride?',
                    ),
                  ),
                  gap(12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: internal,
                            onChanged: (v) => setState(() => internal = v!),
                          ),
                          const Text(
                            'Internal note',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          try {
                            m.reply(t, reply.text, internal: internal);
                            reply.clear();
                            notice(
                              c,
                              'Saved locally. No live message was sent.',
                            );
                          } on StateError catch (e) {
                            notice(c, e.message);
                          }
                        },
                        icon: const Icon(Icons.send_outlined, size: 17),
                        label: Text(internal ? 'Save note' : 'Send demo reply'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
          final actions = Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ticket information',
                  style: Theme.of(c).textTheme.titleMedium,
                ),
                gap(12),
                Info('Bride', m.brideName(t.brideId)),
                Info('Category', t.category),
                Info('Assigned to', m.staffName(t.staffId)),
                Info('Priority', t.priority),
                const Divider(),
                if (m.isManager)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => editForm(
                        c,
                        'Assign ticket',
                        [
                          FieldSpec(
                            'staff',
                            'Assigned staff',
                            t.staffId ?? '',
                            options: staffChoices(m),
                          ),
                        ],
                        (v) => m.assignTicket(
                          t,
                          v['staff']!.isEmpty ? null : v['staff'],
                        ),
                      ),
                      child: const Text('Assign staff'),
                    ),
                  ),
                if (t.status != 'Closed') ...[
                  gap(10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => editForm(
                        c,
                        'Update ticket status',
                        [
                          FieldSpec(
                            'status',
                            'Status',
                            t.status,
                            options: choices(
                              ticketStatuses
                                  .where((s) => s != 'Closed')
                                  .toList(),
                            ),
                          ),
                        ],
                        (v) => m.ticketStatus(t, v['status']!),
                      ),
                      child: const Text('Update status'),
                    ),
                  ),
                  gap(10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        if (await confirm(
                              c,
                              'Close this ticket?',
                              'The conversation will become read-only. Confirm that the issue has been addressed.',
                            ) &&
                            c.mounted) {
                          perform(c, () => m.ticketStatus(t, 'Closed'));
                        }
                      },
                      child: const Text('Close ticket'),
                    ),
                  ),
                ],
                gap(18),
                const Text(
                  'Replies and internal notes are demo records. Nothing is sent to the bride app until the backend is connected.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          );
          return b.maxWidth < 850
              ? Column(children: [actions, gap(18), conversation])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: conversation),
                    const SizedBox(width: 20),
                    SizedBox(width: 310, child: actions),
                  ],
                );
        },
      ),
    ],
  );
}
