import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'operations.dart';
import 'people.dart';
import 'export.dart';
import 'analytics_screen.dart';

class _SpecialistShortcut extends StatelessWidget {
  const _SpecialistShortcut({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: rose),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onNavigate});
  final ValueChanged<PortalPage> onNavigate;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (m.isLive && !m.boutiqueOperations) {
      return PageBody(
        children: [
          Heading(
            'Welcome back, ${m.current!.name}',
            'Your appointments and work schedule.',
          ),
          ResponsiveGrid(
            minWidth: 260,
            children: [
              _SpecialistShortcut(
                title: 'My appointments',
                icon: Icons.event_outlined,
                onTap: () => onNavigate(PortalPage.appointments),
              ),
              _SpecialistShortcut(
                title: 'Work tasks',
                icon: Icons.task_alt_outlined,
                onTap: () => onNavigate(PortalPage.tasks),
              ),
              _SpecialistShortcut(
                title: 'My availability',
                icon: Icons.calendar_month_outlined,
                onTap: () => onNavigate(PortalPage.schedule),
              ),
            ],
          ),
        ],
      );
    }
    if (m.isLive) {
      return BusinessAnalyticsPage(dashboard: true, onNavigate: onNavigate);
    }
    final today =
        m.visibleAppointments
            .where(
              (a) =>
                  DateUtils.isSameDay(a.date, m.today) &&
                  a.status == 'Confirmed',
            )
            .toList()
          ..sort((a, b) => a.hour.compareTo(b.hour));
    final active = m.visibleTasks
        .where((t) => !['Completed', 'Cancelled'].contains(t.status))
        .length;
    return PageBody(
      children: [
        Heading(
          'Welcome back, ${m.isLive ? m.current!.name : m.current!.name.split(' ').first}',
          m.isManager
              ? 'Your boutique at a glance. Here’s what needs your attention today.'
              : 'Here’s your day, your brides and your next priorities.',
          action: m.isManager
              ? FilledButton.icon(
                  onPressed: m.isLive ? null : () => openAppointmentForm(c),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('New appointment'),
                )
              : const Pill('Staff workspace'),
        ),
        ResponsiveGrid(
          children: [
            Metric(
              'Today’s appointments',
              '${today.length}',
              'Confirmed visits today',
              Icons.calendar_today_outlined,
            ),
            Metric(
              m.isManager ? 'Unassigned appointments' : 'My active tasks',
              '${m.isManager ? m.appointments.where((a) => a.staffId == null && a.status == 'Confirmed').length : active}',
              m.isManager
                  ? 'Ready for staff assignment'
                  : 'Your next milestones',
              Icons.assignment_ind_outlined,
            ),
            Metric(
              'Active support tickets',
              '${m.visibleTickets.where((t) => t.status != 'Closed').length}',
              'Conversations needing care',
              Icons.support_agent,
            ),
            Metric(
              'Completed tasks',
              '${m.visibleTasks.where((t) => t.status == 'Completed').length}',
              'Across your visible work',
              Icons.check_circle_outline,
            ),
          ],
        ),
        gap(28),
        _section(
          c,
          'Today’s schedule',
          'View appointments',
          () => onNavigate(PortalPage.appointments),
        ),
        gap(14),
        RecordTable(
          columns: const [
            'Time',
            'Bride',
            'Visit type',
            'Staff',
            'Status',
            'Action',
          ],
          rows: today
              .map(
                (a) => [
                  cell(hourText(a.hour)),
                  cell(m.brideName(a.brideId)),
                  cell(a.type),
                  cell(m.staffName(a.staffId)),
                  Pill(a.status),
                  TextButton(
                    onPressed: () => appointmentDetails(c, a),
                    child: const Text('Details'),
                  ),
                ],
              )
              .toList(),
          empty: 'No confirmed visits today. Enjoy a little breathing room.',
        ),
        gap(24),
        ResponsiveGrid(
          minWidth: 390,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(
                    c,
                    'Your next priorities',
                    'View customer rentals',
                    () => onNavigate(PortalPage.rentals),
                  ),
                  gap(18),
                  if (m.isLive)
                    const Text(
                      'Task updates are not connected yet.',
                      style: TextStyle(color: muted),
                    ),
                  for (final t
                      in m.visibleTasks
                          .where(
                            (t) =>
                                !['Completed', 'Cancelled'].contains(t.status),
                          )
                          .take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.radio_button_unchecked,
                              size: 18,
                              color: rose,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                gap(3),
                                Text(
                                  '${m.brideName(t.brideId)} · ${dateText(t.due)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Pill(t.status),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent activity',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  gap(18),
                  for (final a in m.visibleActivity.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(
                            radius: 13,
                            backgroundColor: blush,
                            child: Icon(Icons.history, size: 14, color: rose),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              a,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  gap(12),
                  if (m.isLive)
                    const Text(
                      'Activity history is not connected yet.',
                      style: TextStyle(color: muted),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: canvas,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.spa_outlined, color: rose),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            m.isManager
                                ? 'A little organisation makes room for extraordinary moments.'
                                : 'Your assigned work is private to your workspace.',
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(
    BuildContext c,
    String title,
    String action,
    VoidCallback tap,
  ) => Row(
    children: [
      Expanded(child: Text(title, style: Theme.of(c).textTheme.titleMedium)),
      TextButton(
        onPressed: tap,
        child: Text(action, style: const TextStyle(fontSize: 11)),
      ),
    ],
  );
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsState();
}

class _ReportsState extends State<ReportsPage> {
  String period = 'Last 30 days';
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (!m.canOpen(PortalPage.reports)) return const AccessDenied();
    final days = period == 'Last 7 days'
        ? 7
        : period == 'Last 30 days'
        ? 30
        : 90;
    final start = m.today.subtract(Duration(days: days - 1));
    bool within(DateTime d) =>
        !d.isBefore(start) && d.isBefore(m.today.add(const Duration(days: 1)));
    final payments = m.payments
        .where((p) => within(p.date) && p.status == 'Paid')
        .toList();
    final appts = m.appointments.where((a) => within(a.date)).toList();
    final revenue = payments.fold(0.0, (s, p) => s + p.amount);
    final complete = appts.where((a) => a.status == 'Completed').length;
    final cancelled = appts.where((a) => a.status == 'Cancelled').length;
    final bars = List<double>.filled(6, 0);
    for (final p in payments) {
      final bucket = ((p.date.difference(start).inDays / days) * 6)
          .floor()
          .clamp(0, 5);
      bars[bucket] += p.amount;
    }
    return PageBody(
      children: [
        Heading(
          'Reports overview',
          'Business insights from the current demo records.',
          action: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              filterSelect(period, [
                'Last 7 days',
                'Last 30 days',
                'Last 90 days',
              ], (v) => setState(() => period = v)),
              FilledButton.icon(
                onPressed: () {
                  m.managerOnly();
                  final csv =
                      'DEMO BUSINESS REPORT\nPeriod,$period\nStart,${dateText(start)}\nEnd,${dateText(m.today)}\nMetric,Value\nPaid revenue RM,${revenue.toStringAsFixed(2)}\nAppointments,${appts.length}\nCompleted appointments,$complete\nCancelled appointments,$cancelled\n\nPayment ID,Bride,Amount RM,Date\n${payments.map((p) => '${p.id},${m.brideName(p.brideId)},${p.amount.toStringAsFixed(2)},${dateText(p.date)}').join('\n')}';
                  final ok = downloadCsv(
                    'Luvly-demo-report-${dateInput(m.today)}.csv',
                    csv,
                  );
                  notice(
                    c,
                    ok
                        ? 'Report CSV downloaded.'
                        : 'CSV export is available when running in the browser.',
                  );
                },
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        ResponsiveGrid(
          children: [
            Metric(
              'Paid revenue',
              money(revenue),
              '${dateText(start)} – ${dateText(m.today)}',
              Icons.payments_outlined,
            ),
            Metric(
              'Appointments',
              '${appts.length}',
              'Scheduled within the selected period',
              Icons.calendar_month_outlined,
            ),
            Metric(
              'Completion rate',
              '${appts.isEmpty ? 0 : (complete / appts.length * 100).round()}%',
              'Completed / all appointments in period',
              Icons.task_alt,
            ),
            Metric(
              'Cancellations',
              '$cancelled',
              'Within the selected period',
              Icons.event_busy_outlined,
            ),
          ],
        ),
        gap(24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revenue across the selected period',
                style: Theme.of(c).textTheme.titleMedium,
              ),
              gap(5),
              const Text(
                'Paid transactions only · Six consecutive date groups',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              gap(24),
              SizedBox(
                height: 215,
                child: BarChart(
                  values: bars,
                  labels: List.generate(6, (i) {
                    final d = start.add(Duration(days: (i * days / 6).floor()));
                    return '${d.day} ${dateText(d).split(' ')[1]}';
                  }),
                ),
              ),
              gap(10),
            ],
          ),
        ),
        gap(24),
        ResponsiveGrid(
          minWidth: 390,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff workload',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  const Text(
                    'Current active tasks · Not date-filtered',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  gap(20),
                  for (final s in m.team.where((s) => s.active))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(s.name)),
                              Text(
                                '${m.tasks.where((t) => t.staffId == s.id && !['Completed', 'Cancelled'].contains(t.status)).length} tasks',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          gap(8),
                          LinearProgressIndicator(
                            value:
                                m.tasks
                                    .where(
                                      (t) =>
                                          t.staffId == s.id &&
                                          ![
                                            'Completed',
                                            'Cancelled',
                                          ].contains(t.status),
                                    )
                                    .length /
                                m.tasks.length,
                            backgroundColor: blush,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory availability',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  const Text(
                    'Current inventory · Not date-filtered',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  gap(14),
                  for (final status in gownStatuses)
                    Info(
                      status,
                      '${m.gowns.where((g) => g.status == status).length}',
                    ),
                ],
              ),
            ),
          ],
        ),
        gap(22),
        const Text(
          'These are descriptive totals of demo records, not forecasts. Date filters apply to revenue and appointment metrics; workload and inventory show the current snapshot.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    );
  }
}

class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;
  @override
  Widget build(BuildContext c) {
    final max = values.fold(1.0, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        values.length,
        (i) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  values[i].toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
                gap(7),
                Flexible(
                  child: Container(
                    height: values[i] == 0 ? 2 : 145 * values[i] / max,
                    width: 70,
                    decoration: BoxDecoration(
                      color: i == values.length - 1
                          ? rose
                          : const Color(0xFFCFA7AB),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
                gap(10),
                Text(
                  labels[i],
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
