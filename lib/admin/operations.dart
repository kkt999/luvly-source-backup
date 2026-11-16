import 'package:flutter/material.dart';
import '../payments/payment_screen.dart';
import 'design.dart';
import 'model.dart';
import 'export.dart';
import 'chapter4.dart';

void openAppointmentForm(BuildContext c, {Appointment? existing}) {
  final m = PortalScope.of(c);
  if (m.isLive) {
    notice(c, 'Appointments are not connected yet.');
    return;
  }
  if (!m.isManager) return;
  editForm(
    c,
    existing == null ? 'New appointment' : 'Edit appointment',
    [
      FieldSpec(
        'bride',
        'Bride',
        existing?.brideId ?? m.brides.first.id,
        options: {for (final b in m.brides) b.id: b.name},
      ),
      FieldSpec(
        'type',
        'Appointment type',
        existing?.type ?? 'Dress Trial',
        options: choices([
          'Dress Trial',
          'Bridal Consultation',
          'Final Fitting',
          'Pre-wedding Photoshoot',
        ]),
      ),
      FieldSpec(
        'date',
        'Date (YYYY-MM-DD)',
        dateInput(existing?.date ?? m.today),
        date: true,
      ),
      FieldSpec(
        'hour',
        'Time',
        '${existing?.hour ?? 10}',
        options: {
          for (final h in [10, 11, 12, 14, 15, 16]) '$h': hourText(h),
        },
      ),
      FieldSpec(
        'staff',
        'Assigned staff',
        existing?.staffId ?? '',
        options: staffChoices(m),
      ),
      FieldSpec(
        'notes',
        'Notes',
        existing?.notes ?? '',
        multiline: true,
        optional: true,
      ),
    ],
    (v) {
      final d = DateTime.parse(v['date']!);
      if (d.isBefore(m.today)) {
        throw StateError('Choose today or a future date.');
      }
      m.saveAppointment(
        Appointment(
          existing?.id ?? 'APT-${101 + m.appointments.length}',
          v['bride']!,
          v['type']!,
          d,
          int.parse(v['hour']!),
          v['staff']!.isEmpty ? null : v['staff'],
          status: existing?.status ?? 'Confirmed',
          notes: v['notes']!,
        ),
        existing: existing,
      );
    },
  );
}

void appointmentDetails(BuildContext c, Appointment a) {
  final m = PortalScope.of(c);
  showDialog<void>(
    context: c,
    builder: (d) => AnimatedBuilder(
      animation: m,
      builder: (d, _) => AlertDialog(
        title: Text('${a.id} · ${a.type}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill(a.status),
                gap(),
                Info('Bride', m.brideName(a.brideId)),
                Info('Date', dateText(a.date)),
                Info('Time', '${hourText(a.hour)} MYT'),
                Info('Staff', m.staffName(a.staffId)),
                Info('Notes', a.notes.isEmpty ? 'No notes yet.' : a.notes),
                const Divider(),
                const Text(
                  'Google Calendar sync is not connected in this UI preview.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
          if (a.status == 'Confirmed')
            FilledButton(
              onPressed: () =>
                  perform(c, () => m.appointmentStatus(a, 'Completed')),
              child: const Text('Mark completed'),
            ),
          if (m.isManager && a.status == 'Confirmed')
            OutlinedButton(
              onPressed: () async {
                if (await confirm(
                      d,
                      'Cancel appointment?',
                      'This will cancel the demo booking for ${m.brideName(a.brideId)}.',
                    ) &&
                    c.mounted) {
                  perform(c, () => m.appointmentStatus(a, 'Cancelled'));
                }
              },
              child: const Text('Cancel appointment'),
            ),
        ],
      ),
    ),
  );
}

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});
  @override
  State<AppointmentsPage> createState() => _AppointmentsState();
}

class _AppointmentsState extends State<AppointmentsPage> {
  String query = '', status = 'All statuses', day = 'All dates';
  Appointment? selected;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (selected != null) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Daily Schedule'),
            ),
          ),
          Expanded(child: AppointmentRecordPage(appointment: selected!)),
        ],
      );
    }
    final rows =
        m.visibleAppointments
            .where(
              (a) =>
                  (status == 'All statuses' || a.status == status) &&
                  (day == 'All dates' ||
                      DateUtils.isSameDay(a.date, m.today)) &&
                  '${a.id} ${m.brideName(a.brideId)} ${a.type} ${m.staffName(a.staffId)}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return PageBody(
      children: [
        Heading(
          m.isManager ? 'Appointments & trials' : 'My appointments',
          m.isManager
              ? 'Plan each visit and match every bride with the right stylist.'
              : 'Your assigned visits, fitting notes and completion status.',
          action: m.isManager
              ? FilledButton.icon(
                  onPressed: m.isLive ? null : () => openAppointmentForm(c),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New appointment'),
                )
              : null,
        ),
        Toolbar(
          onSearch: (s) => setState(() => query = s),
          hint: 'Search bride, staff or appointment',
          filters: [
            filterSelect(status, [
              'All statuses',
              'Confirmed',
              'Completed',
              'Cancelled',
            ], (v) => setState(() => status = v)),
            filterSelect(day, [
              'All dates',
              'Today',
            ], (v) => setState(() => day = v)),
          ],
        ),
        RecordTable(
          columns: const [
            'Appointment',
            'Bride',
            'Date & time',
            'Assigned to',
            'Status',
            'Actions',
          ],
          rows: rows
              .map(
                (a) => [
                  cell(a.type, sub: a.id),
                  cell(m.brideName(a.brideId)),
                  cell(dateText(a.date), sub: hourText(a.hour)),
                  a.staffId == null
                      ? const Pill('Unassigned')
                      : cell(m.staffName(a.staffId)),
                  Pill(a.status),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => selected = a),
                        child: const Text('View'),
                      ),
                      if (m.isManager && a.status == 'Confirmed')
                        IconButton(
                          tooltip: 'Edit ${a.id}',
                          onPressed: () => openAppointmentForm(c, existing: a),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                    ],
                  ),
                ],
              )
              .toList(),
        ),
        gap(12),
        Text(
          m.isLive
              ? 'Appointments are not connected yet · Malaysia time (MYT)'
              : 'Showing ${rows.length} appointments · Malaysia time (MYT)',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ProgressPage> createState() => _ProgressState();
}

class _ProgressState extends State<ProgressPage> {
  String query = '', status = 'All statuses';
  ServiceTask? selected;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    final detail = selected;
    if (detail != null) {
      return PageBody(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Customer rentals'),
            ),
          ),
          Heading(
            'Service Progress Details',
            detail.title,
            action: Pill(detail.status),
          ),
          ResponsiveGrid(
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Service Overview',
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    gap(),
                    Info('Bride', m.brideName(detail.brideId)),
                    Info('Service ID', detail.id),
                    Info('Assigned Staff', m.staffName(detail.staffId)),
                    Info('Target Date', dateText(detail.due)),
                    Info(
                      'Progress Notes',
                      detail.note.isEmpty ? 'No notes recorded' : detail.note,
                    ),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alteration Information',
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    gap(),
                    Info(
                      'Alteration Required',
                      detail.alterationRequired ? 'Yes' : 'No',
                    ),
                    Info(
                      'Current Stage',
                      detail.alterationRequired
                          ? detail.alterationStatus
                          : 'Not applicable',
                    ),
                    OutlinedButton(
                      onPressed: () => alterationForm(c, detail),
                      child: const Text('Update Alteration'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          gap(24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () => editForm(
                  c,
                  'Update Service Status',
                  [
                    FieldSpec(
                      'status',
                      'Status',
                      detail.status,
                      options: choices(taskStatuses),
                    ),
                    FieldSpec(
                      'note',
                      'Progress Notes',
                      detail.note,
                      multiline: true,
                      optional: true,
                    ),
                  ],
                  (v) => m.updateTask(detail, v['status']!, v['note']!),
                ),
                child: const Text('Update Status'),
              ),
              if (m.isManager)
                OutlinedButton(
                  onPressed: () => scheduleForm(c, detail),
                  child: const Text('Assign Schedule'),
                ),
            ],
          ),
        ],
      );
    }
    final tasks = m.visibleTasks
        .where(
          (t) =>
              (status == 'All statuses' || t.status == status) &&
              '${t.title} ${m.brideName(t.brideId)}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return PageBody(
      children: [
        Heading(
          widget.embedded
              ? 'Customer rentals'
              : m.isManager
              ? 'Service progress'
              : 'My service tasks',
          'Keep every bridal milestone moving, one detail at a time.',
        ),
        ResponsiveGrid(
          children: [
            Metric(
              'Assigned tasks',
              '${m.visibleTasks.length}',
              'Within your role’s scope',
              Icons.assignment_outlined,
            ),
            Metric(
              'In progress',
              '${m.visibleTasks.where((t) => t.status == 'In Progress').length}',
              'Currently being handled',
              Icons.timelapse,
            ),
            Metric(
              'Completed',
              '${m.visibleTasks.where((t) => t.status == 'Completed').length}',
              'Milestones finished',
              Icons.check_circle_outline,
            ),
            Metric(
              'Delayed',
              '${m.visibleTasks.where((t) => t.status == 'Delayed').length}',
              'Needs attention',
              Icons.schedule,
            ),
          ],
        ),
        gap(26),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search bride or service',
          filters: [
            filterSelect(status, [
              'All statuses',
              ...taskStatuses,
            ], (v) => setState(() => status = v)),
          ],
        ),
        RecordTable(
          columns: const [
            'Service / task',
            'Bride',
            'Target date',
            'Staff',
            'Status',
            'Actions',
          ],
          rows: tasks
              .map(
                (t) => [
                  cell(t.title, sub: t.id),
                  cell(m.brideName(t.brideId)),
                  cell(dateText(t.due)),
                  t.staffId == null
                      ? const Pill('Unassigned')
                      : cell(m.staffName(t.staffId)),
                  Pill(t.status),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => selected = t),
                        child: const Text('Details'),
                      ),
                      TextButton(
                        onPressed: () => editForm(
                          c,
                          'Update service progress',
                          [
                            FieldSpec(
                              'status',
                              'Status',
                              t.status,
                              options: choices(taskStatuses),
                            ),
                            FieldSpec(
                              'note',
                              'Progress notes',
                              t.note,
                              multiline: true,
                              optional: true,
                            ),
                          ],
                          (v) => m.updateTask(t, v['status']!, v['note']!),
                        ),
                        child: const Text('Update'),
                      ),
                      if (m.isManager)
                        TextButton(
                          onPressed: () => editForm(
                            c,
                            'Assign service task',
                            [
                              FieldSpec(
                                'staff',
                                'Assigned staff',
                                t.staffId ?? '',
                                options: staffChoices(m),
                              ),
                            ],
                            (v) => m.assignTask(
                              t,
                              v['staff']!.isEmpty ? null : v['staff'],
                            ),
                          ),
                          child: const Text('Assign'),
                        ),
                      IconButton(
                        tooltip: 'Alteration details',
                        onPressed: () => alterationForm(c, t),
                        icon: const Icon(Icons.content_cut, size: 18),
                      ),
                    ],
                  ),
                ],
              )
              .toList(),
        ),
        gap(18),
        const Text(
          'Bride timeline updates will be shared through the backend in the next stage. This preview changes local task state only.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsState();
}

class _PaymentsState extends State<PaymentsPage> {
  String query = '', status = 'All statuses';
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (m.isLive) {
      return LivePaymentsScreen(manager: m.isManager, staff: true);
    }
    final all = m.visiblePayments;
    final rows = all
        .where(
          (p) =>
              (status == 'All statuses' || p.status == status) &&
              '${p.id} ${m.brideName(p.brideId)}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return PageBody(
      children: [
        Heading(
          'Payments & receipts',
          m.isLive
              ? 'Payment records are not connected yet.'
              : m.isManager
              ? 'A clear view of your boutique’s demo payment records.'
              : 'Payment status for brides linked to your assigned work. No financial editing access.',
        ),
        ResponsiveGrid(
          children: [
            Metric(
              'Payments received',
              money(
                all
                    .where((p) => p.status == 'Paid')
                    .fold(0.0, (s, p) => s + p.amount),
              ),
              m.isManager
                  ? 'All paid demo transactions'
                  : 'Assigned brides only',
              Icons.payments_outlined,
            ),
            Metric(
              'Pending payments',
              '${all.where((p) => p.status == 'Pending').length}',
              'Awaiting confirmation',
              Icons.schedule,
            ),
            Metric(
              'Receipts available',
              '${all.where((p) => p.status == 'Paid').length}',
              'Demo records, not real receipts',
              Icons.receipt_long_outlined,
            ),
          ],
        ),
        gap(26),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search payment or bride',
          filters: [
            filterSelect(status, [
              'All statuses',
              'Paid',
              'Pending',
            ], (v) => setState(() => status = v)),
          ],
        ),
        RecordTable(
          columns: const [
            'Payment ID',
            'Bride',
            'Date',
            'Method',
            'Amount',
            'Status',
            'Action',
          ],
          rows: rows
              .map(
                (p) => [
                  cell(p.id),
                  cell(m.brideName(p.brideId)),
                  cell(dateText(p.date)),
                  cell(p.method),
                  cell(money(p.amount)),
                  Pill(p.status),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: c,
                      builder: (d) => AlertDialog(
                        title: Text(
                          p.status == 'Paid'
                              ? 'Demo receipt'
                              : 'Payment details',
                        ),
                        content: SizedBox(
                          width: 430,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Pill(p.status),
                              gap(),
                              Info('Payment', p.id),
                              Info('Bride', m.brideName(p.brideId)),
                              Info('Date', dateText(p.date)),
                              Info('Amount', money(p.amount)),
                              Info('Method', p.method),
                              gap(),
                              const Text(
                                'DEMO RECORD · NOT A VALID RECEIPT',
                                style: TextStyle(
                                  color: rose,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('Close'),
                          ),
                          if (p.status == 'Paid')
                            FilledButton.icon(
                              onPressed: () {
                                final csv =
                                    'Demo receipt — not valid for payment\nReference,${p.id}\nAmount,${p.amount}\nStatus,${p.status}\n';
                                final ok = downloadCsv('${p.id}-DEMO.csv', csv);
                                notice(
                                  c,
                                  ok
                                      ? 'Demo receipt CSV downloaded.'
                                      : 'CSV downloads are available in the browser.',
                                );
                              },
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 17,
                              ),
                              label: const Text('Download demo CSV'),
                            ),
                        ],
                      ),
                    ),
                    child: Text(p.status == 'Paid' ? 'Receipt' : 'View'),
                  ),
                ],
              )
              .toList(),
        ),
      ],
    );
  }
}
