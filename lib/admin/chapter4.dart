import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'operations.dart';

void scheduleForm(BuildContext c, ServiceTask t) {
  final m = PortalScope.of(c);
  if (!m.isManager || m.isLive) return;
  editForm(
    c,
    'Assign Schedule',
    [
      FieldSpec(
        'staff',
        'Staff member',
        t.staffId ?? m.team.first.id,
        options: {for (final s in m.team.where((s) => s.active)) s.id: s.name},
      ),
      FieldSpec(
        'date',
        'Date',
        dateInput(t.due.isBefore(m.today) ? m.today : t.due),
        date: true,
      ),
      FieldSpec(
        'start',
        'Start time',
        '${t.startHour}',
        options: {for (var h = 8; h < 20; h++) '$h': hourText(h)},
      ),
      FieldSpec(
        'end',
        'End time',
        '${t.endHour}',
        options: {for (var h = 9; h <= 20; h++) '$h': hourText(h)},
      ),
    ],
    (v) => m.scheduleTask(
      t,
      v['staff']!,
      DateTime.parse(v['date']!),
      int.parse(v['start']!),
      int.parse(v['end']!),
    ),
    submitLabel: 'Check & Save Assignment',
  );
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _ScheduleState();
}

class _ScheduleState extends State<SchedulePage> {
  String tab = 'Staff Availability';
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    final entries = m.availability
        .where((a) => m.isManager || a.staffId == m.current!.id)
        .toList();
    return PageBody(
      children: [
        Heading(
          m.isManager ? 'Workload & Scheduling' : 'My Availability & Schedule',
          'Publish availability and review scheduled work.',
          action: FilledButton.icon(
            onPressed: m.isLive
                ? null
                : () => editForm(
                    c,
                    'Update Availability',
                    [
                      if (m.isManager)
                        FieldSpec(
                          'staff',
                          'Staff member',
                          m.current!.id,
                          options: {
                            for (final s in m.team.where((s) => s.active))
                              s.id: s.name,
                          },
                        ),
                      FieldSpec('date', 'Date', dateInput(m.today), date: true),
                      FieldSpec(
                        'start',
                        'Start time',
                        '9',
                        options: {
                          for (var h = 0; h < 24; h++) '$h': hourText(h),
                        },
                      ),
                      FieldSpec(
                        'end',
                        'End time',
                        '18',
                        options: {
                          for (var h = 1; h <= 24; h++) '$h': hourText(h),
                        },
                      ),
                      FieldSpec(
                        'available',
                        'Availability',
                        'Available',
                        options: choices(['Available', 'Unavailable']),
                      ),
                    ],
                    (v) => m.saveAvailability(
                      Availability(
                        v['staff'] ?? m.current!.id,
                        DateTime.parse(v['date']!),
                        int.parse(v['start']!),
                        int.parse(v['end']!),
                        v['available'] == 'Available',
                      ),
                    ),
                  ),
            icon: const Icon(Icons.edit_calendar_outlined, size: 18),
            label: const Text('Update availability'),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final t in [
              'Staff Availability',
              'Assigned Schedule',
              if (m.isManager) 'Workload Overview',
            ])
              ChoiceChip(
                label: Text(t),
                selected: tab == t,
                onSelected: (_) => setState(() => tab = t),
              ),
          ],
        ),
        gap(24),
        if (tab == 'Staff Availability') ...[
          RecordTable(
            columns: const [
              'Staff',
              'Date',
              'Start time',
              'End time',
              'Availability',
            ],
            rows: entries
                .map(
                  (a) => [
                    cell(m.staffName(a.staffId)),
                    cell(dateText(a.date)),
                    cell(hourText(a.startHour)),
                    cell(hourText(a.endHour)),
                    Pill(a.available ? 'Available' : 'Unavailable'),
                  ],
                )
                .toList(),
            empty:
                'No availability published yet. Add an available or unavailable time window.',
          ),
          gap(16),
          Text(
            m.isLive
                ? 'Availability and scheduling are not connected yet.'
                : 'One availability window per person per day in this UI demo. Saving replaces that day’s window. Existing appointments and assigned tasks are also checked for conflicts.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ] else if (tab == 'Assigned Schedule')
          RecordTable(
            columns: const [
              'Service / task',
              'Staff',
              'Date',
              'Time',
              'Action',
            ],
            rows: m.visibleTasks
                .map(
                  (t) => [
                    cell(t.title),
                    cell(m.staffName(t.staffId)),
                    cell(dateText(t.due)),
                    cell(
                      t.scheduled
                          ? '${hourText(t.startHour)} – ${hourText(t.endHour)}'
                          : 'Time not assigned',
                    ),
                    if (m.isManager)
                      TextButton(
                        onPressed: () => scheduleForm(c, t),
                        child: const Text('Assign schedule'),
                      )
                    else
                      Pill(t.status),
                  ],
                )
                .toList(),
          )
        else
          RecordTable(
            columns: const [
              'Staff',
              'Appointments',
              'Active tasks',
              'Completion rate',
            ],
            rows: m.team.map((s) {
              final ts = m.tasks.where((t) => t.staffId == s.id).toList();
              final done = ts.where((t) => t.status == 'Completed').length;
              return [
                cell(s.name),
                cell(
                  '${m.appointments.where((a) => a.staffId == s.id && a.status == 'Confirmed').length}',
                ),
                cell(
                  '${ts.where((t) => !['Completed', 'Cancelled'].contains(t.status)).length}',
                ),
                cell(
                  ts.isEmpty
                      ? 'No tasks'
                      : '${(done / ts.length * 100).round()}%',
                ),
              ];
            }).toList(),
          ),
      ],
    );
  }
}

void trialForm(BuildContext c, Appointment a) {
  final m = PortalScope.of(c);
  editForm(
    c,
    'Record Trial Outcome',
    [
      FieldSpec(
        'outcome',
        'Trial Outcome',
        a.trialOutcome.isEmpty
            ? 'Interested – Proceed to Alteration'
            : a.trialOutcome,
        options: choices([
          'Interested – Proceed to Alteration',
          'Further Fitting Required',
          'Not Selected',
        ]),
      ),
      FieldSpec('notes', 'Notes', a.trialNotes, multiline: true),
    ],
    (v) => m.recordTrial(a, v['outcome']!, v['notes']!),
    submitLabel: 'Save Outcome',
  );
}

class AppointmentRecordPage extends StatelessWidget {
  const AppointmentRecordPage({super.key, required this.appointment});
  final Appointment appointment;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c), a = appointment;
    if (!m.visibleAppointments.contains(a)) {
      return const Center(
        child: Text('This appointment is not assigned to you.'),
      );
    }
    final bride = m.brides.firstWhere((b) => b.id == a.brideId);
    return PageBody(
      children: [
        Heading(
          'Appointment Details & Bride Preferences',
          '${a.id} · ${a.type}',
          action: Pill(a.status),
        ),
        ResponsiveGrid(
          minWidth: 340,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appointment Information',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  gap(18),
                  Info('Bride', bride.name),
                  Info('Type', a.type),
                  Info('Date', dateText(a.date)),
                  Info('Time', hourText(a.hour)),
                  Info('Staff', m.staffName(a.staffId)),
                  Info('Notes', a.notes.isEmpty ? 'No notes' : a.notes),
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bride Preferences',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  gap(18),
                  Info('Preferred Style', bride.preferredStyle),
                  Info('Preferred Colour', bride.preferredColour),
                  Info('Size', bride.size),
                  Info(
                    'Notes',
                    bride.notes.isEmpty ? 'No additional notes' : bride.notes,
                  ),
                ],
              ),
            ),
          ],
        ),
        gap(20),
        if (a.trialOutcome.isNotEmpty)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Info('Trial outcome', a.trialOutcome),
                Info('Notes', a.trialNotes),
              ],
            ),
          ),
        gap(20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (m.isManager)
              FilledButton(
                onPressed: () => openAppointmentForm(c, existing: a),
                child: const Text('Assign Staff / Edit'),
              ),
            if (a.type == 'Dress Trial' && a.status != 'Cancelled')
              OutlinedButton(
                onPressed: () => trialForm(c, a),
                child: const Text('Record Trial Outcome'),
              ),
            if (a.status == 'Confirmed')
              OutlinedButton(
                onPressed: () =>
                    perform(c, () => m.appointmentStatus(a, 'Completed')),
                child: const Text('Mark completed'),
              ),
          ],
        ),
      ],
    );
  }
}

void alterationForm(BuildContext c, ServiceTask t) {
  final m = PortalScope.of(c);
  editForm(
    c,
    'Update Alteration Status',
    [
      FieldSpec(
        'required',
        'Alteration Required?',
        t.alterationRequired ? 'Yes' : 'No',
        options: choices(['Yes', 'No']),
      ),
      FieldSpec(
        'stage',
        'Alteration Status',
        t.alterationStatus,
        options: choices([
          'Not Started',
          'First Alteration',
          'Second Alteration',
          'Final Fitting',
          'Completed',
        ]),
      ),
    ],
    (v) => m.updateAlteration(t, v['required'] == 'Yes', v['stage']!),
  );
}
