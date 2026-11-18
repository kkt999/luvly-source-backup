import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'people.dart';
import 'export.dart';
import 'analytics_screen.dart';

const reportTypes = [
  'Package Popularity Report',
  'Appointment Conversion Report',
  'Revenue Summary Report',
  'Body Type Distribution Report',
];
const reportIcons = [
  Icons.workspace_premium_outlined,
  Icons.event_available_outlined,
  Icons.bar_chart_outlined,
  Icons.pie_chart_outline,
];

class ReportData {
  ReportData(this.headers, this.rows, this.summary);
  final List<String> headers;
  final List<List<String>> rows;
  final String summary;
}

ReportData calculateReport(
  PortalModel m,
  String type,
  DateTime from,
  DateTime to,
) {
  m.managerOnly();
  bool within(DateTime d) =>
      !d.isBefore(from) && d.isBefore(to.add(const Duration(days: 1)));
  if (type == reportTypes[0]) {
    final records = m.packageBookings.where((b) => within(b.date)).toList();
    final counts = {
      for (final p in m.packages)
        p.id: records.where((r) => r.packageId == p.id).length,
    };
    final packages = [...m.packages]
      ..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));
    return ReportData(
      ['Package', 'Bookings', '% of Total'],
      packages
          .map(
            (p) => [
              p.name,
              '${counts[p.id]}',
              records.isEmpty
                  ? '0%'
                  : '${(100 * counts[p.id]! / records.length).toStringAsFixed(1)}%',
            ],
          )
          .toList(),
      '${records.length} recorded package selections',
    );
  }
  if (type == reportTypes[1]) {
    final list = m.appointments.where((a) => within(a.date)).toList();
    final converted = list.where((a) => a.converted).length;
    return ReportData(
      ['Appointment', 'Bride', 'Conversion'],
      list
          .map(
            (a) => [
              a.id,
              m.brideName(a.brideId),
              a.converted ? 'Converted' : 'Not converted',
            ],
          )
          .toList(),
      '${list.length} appointments · $converted converted · ${list.isEmpty ? '0' : (converted / list.length * 100).toStringAsFixed(1)}% conversion rate',
    );
  }
  if (type == reportTypes[2]) {
    final paid = m.payments
        .where((p) => p.status == 'Paid' && within(p.date))
        .toList();
    return ReportData(
      ['Payment', 'Date', 'Bride', 'Revenue (RM)'],
      paid
          .map(
            (p) => [
              p.id,
              dateText(p.date),
              m.brideName(p.brideId),
              p.amount.toStringAsFixed(2),
            ],
          )
          .toList(),
      '${money(paid.fold(0.0, (sum, p) => sum + p.amount))} from ${paid.length} successful payments',
    );
  }
  final recorded = m.brides
      .where((b) => b.bodyShape != 'Not recorded')
      .toList();
  final shapes = [
    'Hourglass',
    'Pear',
    'Rectangle',
    'Inverted Triangle',
    'Apple',
  ];
  return ReportData(
    ['Body Type', 'Brides', '% of Classified Brides'],
    shapes.map((s) {
      final count = recorded.where((b) => b.bodyShape == s).length;
      return [
        s,
        '$count',
        recorded.isEmpty
            ? '0%'
            : '${(count / recorded.length * 100).toStringAsFixed(1)}%',
      ];
    }).toList(),
    '${recorded.length} classified brides · ${m.brides.length - recorded.length} not recorded · Current snapshot, not date-filtered',
  );
}

class ChapterReportsPage extends StatefulWidget {
  const ChapterReportsPage({
    super.key,
    this.selectedReport,
    this.onSelectReport,
  });
  final ManagerReport? selectedReport;
  final ValueChanged<ManagerReport>? onSelectReport;
  @override
  State<ChapterReportsPage> createState() => _ReportsState();
}

class _ReportsState extends State<ChapterReportsPage> {
  String? selected;
  bool results = false;
  DateTime? from, to;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (!m.isManager) return const AccessDenied();
    if (m.isLive) {
      return BusinessAnalyticsPage(
        selectedReport: widget.selectedReport,
        onSelectReport: widget.onSelectReport,
      );
    }
    from ??= m.today.subtract(const Duration(days: 29));
    to ??= m.today;
    if (selected == null) {
      return PageBody(
        children: [
          const Heading(
            'Analytics Dashboard',
            'Overview of key business performance',
          ),
          ResponsiveGrid(
            children: [
              Metric(
                'Total Brides',
                '${m.brides.length}',
                'Current customer records',
                Icons.people_outline,
              ),
              Metric(
                'Total Appointments',
                '${m.appointments.length}',
                'Recorded appointments',
                Icons.calendar_month,
              ),
              Metric(
                'Total Revenue (RM)',
                money(
                  m.payments
                      .where((p) => p.status == 'Paid')
                      .fold(0.0, (s, p) => s + p.amount),
                ),
                'Successful payments only',
                Icons.payments_outlined,
              ),
              Metric(
                'Customer Records',
                '${m.brides.length}',
                'Bridal profiles',
                Icons.people_outline,
              ),
            ],
          ),
          gap(28),
          Text('Report Selection', style: Theme.of(c).textTheme.headlineMedium),
          gap(8),
          const Text('Choose a report type to generate.'),
          gap(22),
          ResponsiveGrid(
            minWidth: 380,
            children: [
              for (var i = 0; i < reportTypes.length; i++)
                Panel(
                  color: canvas,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(reportIcons[i], size: 36, color: rose),
                      gap(20),
                      Text(
                        reportTypes[i],
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                      gap(12),
                      Text(
                        [
                          'Compare package selections and popularity.',
                          'Review converted and non-converted appointments.',
                          'Review successful payments and revenue.',
                          'View the distribution of recorded body shapes.',
                        ][i],
                        style: const TextStyle(color: muted),
                      ),
                      gap(22),
                      OutlinedButton(
                        onPressed: () =>
                            setState(() => selected = reportTypes[i]),
                        child: const Text('Select Report'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    }
    final data = m.isLive
        ? ReportData([], [], 'Reports are not connected yet.')
        : calculateReport(m, selected!, from!, to!);
    return PageBody(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              selected = null;
              results = false;
            }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to Report Selection'),
          ),
        ),
        Heading(
          results ? selected! : 'Report Filters',
          results
              ? '${dateText(from!)} – ${dateText(to!)}'
              : 'Set the filters for your report.',
        ),
        if (!results)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected!, style: Theme.of(c).textTheme.titleLarge),
                gap(25),
                if (selected != reportTypes[3])
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('From: ${dateText(from!)}'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: c,
                            initialDate: from!,
                            firstDate: DateTime(2020),
                            lastDate: m.today,
                          );
                          if (d != null) setState(() => from = d);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('To: ${dateText(to!)}'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: c,
                            initialDate: to!,
                            firstDate: DateTime(2020),
                            lastDate: m.today,
                          );
                          if (d != null) setState(() => to = d);
                        },
                      ),
                    ],
                  )
                else
                  const Text(
                    'Body types show the current profile snapshot. Profiles without a recorded body type are excluded from percentages.',
                  ),
                gap(24),
                FilledButton(
                  onPressed: m.isLive
                      ? null
                      : () {
                          if (from!.isAfter(to!)) {
                            notice(c, 'Start date must not be after end date.');
                            return;
                          }
                          setState(() => results = true);
                        },
                  child: const Text('Generate Report'),
                ),
              ],
            ),
          )
        else ...[
          Panel(
            color: canvas,
            child: Text(data.summary, style: Theme.of(c).textTheme.titleMedium),
          ),
          gap(22),
          if (selected == reportTypes[0] || selected == reportTypes[3])
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected == reportTypes[0]
                        ? 'Booking Distribution'
                        : 'Body Type Distribution',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  gap(20),
                  for (final row in data.rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(row[0])),
                              Text('${row[1]} · ${row[2]}'),
                            ],
                          ),
                          gap(8),
                          LinearProgressIndicator(
                            value:
                                (double.tryParse(row[2].replaceAll('%', '')) ??
                                    0) /
                                100,
                            minHeight: 8,
                            backgroundColor: blush,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          gap(22),
          RecordTable(
            columns: data.headers,
            minWidth: 650,
            rows: data.rows.map((r) => r.map((v) => cell(v)).toList()).toList(),
            empty: 'No records match the selected date range.',
          ),
          gap(22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => results = false),
                child: const Text('Edit Filters'),
              ),
              FilledButton.icon(
                onPressed: () {
                  String quote(String s) => '"${s.replaceAll('"', '""')}"';
                  final csv = [
                    'DEMO - $selected',
                    '${dateText(from!)} to ${dateText(to!)}',
                    data.summary,
                    data.headers.map(quote).join(','),
                    ...data.rows.map((r) => r.map(quote).join(',')),
                  ].join('\n');
                  notice(
                    c,
                    downloadCsv('Luvly-report.csv', csv)
                        ? 'Demo CSV downloaded.'
                        : 'Downloads are available in the browser.',
                  );
                },
                icon: const Icon(Icons.download, size: 17),
                label: const Text('Export CSV'),
              ),
              OutlinedButton(
                onPressed: () => notice(
                  c,
                  'PDF and Excel report generation is not connected in this UI prototype. CSV is available.',
                ),
                child: const Text('PDF / Excel export'),
              ),
            ],
          ),
          gap(16),
          const Text(
            'Demo records only. Appointment conversion uses an explicit conversion flag, not appointment completion. Production conversion and profile-history tracking will come from the backend.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
