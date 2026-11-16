import 'package:flutter/material.dart';
import '../shared/list_controls.dart';
import '../payments/payment_api.dart' show PaymentFailure, paymentDateLabel;
import 'analytics_api.dart';
import 'design.dart';

const analyticsDetailTitles = {
  'service': 'Service collections',
  'security': 'Refundable security collected',
  'selections': 'Package selections',
  'conversion': 'Fitting conversion',
};

class AnalyticsBreakdown {
  AnalyticsBreakdown(this.snapshot, this.kind) {
    if (!analyticsDetailTitles.containsKey(kind)) _invalid();
    final details = snapshot.data['details'];
    if (details is! Map || !details.containsKey(kind)) {
      throw const PaymentFailure(
        'The reporting service has not supplied verified detail rows. Refresh after the backend is updated; no breakdown is estimated.',
      );
    }
    final source = details[kind];
    if (financial) {
      if (source is! Map ||
          source['receipts'] is! List ||
          source['totalCents'] != total) {
        _invalid();
      }
      records = (source['receipts'] as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      if (records.any(
        (r) =>
            r['id'] is! String ||
            r['receipt'] is! String ||
            r['amountCents'] is! int ||
            r['amountCents'] <= 0 ||
            r['paidAt'] is! int,
      )) {
        _invalid();
      }
      if (records.fold<int>(0, (sum, r) => sum + (r['amountCents'] as int)) !=
          total) {
        _invalid();
      }
    } else {
      if (source is! List) _invalid();
      records = (source).map((r) => Map<String, dynamic>.from(r)).toList();
      if (records.any(
        (r) =>
            r['id'] is! String ||
            r[kind == 'selections' ? 'createdAt' : 'attendedAt'] is! int ||
            r[kind == 'selections' ? 'paidBooking' : 'converted'] is! bool,
      )) {
        _invalid();
      }
      if (records.length !=
          snapshot.total(
            kind == 'selections' ? 'packageSelections' : 'completedFittings',
          )) {
        _invalid();
      }
      if (records
              .where(
                (r) =>
                    r[kind == 'selections' ? 'paidBooking' : 'converted'] ==
                    true,
              )
              .length !=
          snapshot.total(
            kind == 'selections' ? 'paidPackageBookings' : 'convertedFittings',
          )) {
        _invalid();
      }
    }
    if (records.any(
      (r) =>
          r['customer'] is! String ||
          (financial && (r['title'] is! String || r['category'] is! String)) ||
          (kind == 'selections' && r['name'] is! String),
    )) {
      _invalid();
    }
    if (records.map((r) => r['id']).toSet().length != records.length) {
      _invalid();
    }
    for (final r in records) {
      final ms =
          r[financial
                  ? 'paidAt'
                  : kind == 'selections'
                  ? 'createdAt'
                  : 'attendedAt']
              as int;
      final day = analyticsDate(
        DateTime.fromMillisecondsSinceEpoch(
          ms,
          isUtc: true,
        ).add(const Duration(hours: 8)),
      );
      if (ms > snapshot.data['generatedAt'] ||
          day.compareTo(snapshot.data['range']['from']) < 0 ||
          day.compareTo(snapshot.data['range']['to']) > 0) {
        _invalid();
      }
    }
    if (kind == 'conversion') {
      final expected = records.isEmpty
          ? 0
          : (records.where((r) => r['converted'] == true).length *
                        1000 /
                        records.length)
                    .round() /
                10;
      if (expected != snapshot.totals['conversionPercent']) _invalid();
    }
  }
  Never _invalid() => throw const PaymentFailure(
    'These detail rows do not reconcile with the displayed total. Refresh the report; no partial breakdown is shown.',
  );
  final AnalyticsSnapshot snapshot;
  final String kind;
  late final List<Map<String, dynamic>> records;
  bool get financial => kind == 'service' || kind == 'security';
  int get total =>
      snapshot.total(kind == 'security' ? 'securityCents' : 'serviceCents');
  String get value => financial
      ? analyticsMoney(total)
      : kind == 'selections'
      ? '${records.length} selections'
      : records.isEmpty
      ? 'Not applicable · no completed fittings (dashboard displays 0%)'
      : '${snapshot.total('convertedFittings')} ÷ ${snapshot.total('completedFittings')} × 100 = ${snapshot.totals['conversionPercent']}%';
  String get basis => switch (kind) {
    'service' =>
      'Sum of verified service receipts paid within the selected MYT period. Includes fitting fees, booking deposits, balances, dress payments and rental extensions. Pending/failed payments, refundable security and review/unclassified receipts are excluded. Fitting credit is not added a second time. This is gross collections from test payments, not net profit; manual refund notes are not bank outflows.',
    'security' =>
      'Sum of verified refundable-security receipts paid within the selected MYT period, excluding review/unclassified receipts. This is security collected, not service income or the current unrefunded balance. Any refund needs separate reconciliation.',
    'selections' =>
      'Each saved selection created within the selected MYT period is counted once. A selection is not reserved stock. Paid bookings are distinct selections with a verified linked package deposit/payment as of this snapshot, not necessarily a payment within the selected period.',
    _ =>
      'Denominator: completed Dress Trial visits in the selected MYT period, using actual attendance when recorded, otherwise the scheduled date. Numerator: those visits with a verified linked package deposit/payment after attendance, as of this snapshot. No-fitting approvals and non-attendance are excluded. Zero completed fittings displays 0%, not an invented conversion.',
  };
}

class AnalyticsDetailPage extends StatefulWidget {
  const AnalyticsDetailPage({
    super.key,
    required this.snapshot,
    required this.kind,
    required this.revision,
    required this.reload,
    required this.onRecord,
  });
  final AnalyticsSnapshot snapshot;
  final String kind;
  final ValueNotifier<int> revision;
  final Future<AnalyticsSnapshot> Function() reload;
  final void Function(String kind, String id) onRecord;
  @override
  State<AnalyticsDetailPage> createState() => _AnalyticsDetailPageState();
}

class _AnalyticsDetailPageState extends State<AnalyticsDetailPage> {
  late AnalyticsSnapshot snapshot = widget.snapshot;
  late int revision = widget.revision.value;
  String query = '';
  int page = 0;
  bool busy = false;
  String? error;
  Future<void> reload() async {
    final startedRevision = widget.revision.value;
    setState(() => busy = true);
    try {
      final next = await widget.reload();
      AnalyticsBreakdown(next, widget.kind);
      if (mounted) {
        setState(() {
          snapshot = next;
          revision = startedRevision;
          error = null;
          page = 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = analyticsError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsBreakdown? breakdown;
    try {
      breakdown = AnalyticsBreakdown(snapshot, widget.kind);
    } catch (e) {
      error = analyticsError(e);
    }
    final data = breakdown;
    final rows =
        data?.records
            .where((r) => matchesListSearch(query, r.values))
            .toList() ??
        <Map<String, dynamic>>[];
    final current = page.clamp(0, rows.isEmpty ? 0 : (rows.length - 1) ~/ 20);
    final shown = rows.skip(current * 20).take(20).toList();
    Widget link(Map<String, dynamic> r) => TextButton(
      key: ValueKey('analytics-source-${r['id']}'),
      onPressed: busy || error != null
          ? null
          : () => widget.onRecord(widget.kind, r['id']),
      child: Text(
        data!.financial
            ? 'View receipt'
            : widget.kind == 'selections'
            ? 'View rental'
            : 'View appointment',
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${analyticsDetailTitles[widget.kind]} details'),
      ),
      body: PageBody(
        children: [
          Heading(
            analyticsDetailTitles[widget.kind]!,
            'Test transactions · ${snapshot.data['range']['from']} to ${snapshot.data['range']['to']} · Malaysia time',
            action: OutlinedButton.icon(
              onPressed: busy ? null : reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload details'),
            ),
          ),
          Text(
            'Snapshot updated ${paymentDateLabel(snapshot.data['generatedAt'])}. This view stays fixed until you reload.',
            style: const TextStyle(color: muted),
          ),
          gap(14),
          ValueListenableBuilder<int>(
            valueListenable: widget.revision,
            builder: (context, value, _) => value == revision
                ? const SizedBox.shrink()
                : const Panel(
                    child: Text(
                      'Source data changed while you were viewing these details. Reload details to see the latest snapshot.',
                    ),
                  ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) ...[
            Panel(
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
            gap(12),
          ],
          if (data != null && error == null) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.value,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  gap(12),
                  Text(data.basis),
                  if (data.financial) ...[
                    gap(16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 10,
                      children: [
                        for (final category
                            in data.records.map((r) => r['category']).toSet())
                          Text(
                            '$category: ${analyticsMoney(data.records.where((r) => r['category'] == category).fold<int>(0, (sum, r) => sum + (r['amountCents'] as int)))}',
                          ),
                      ],
                    ),
                    gap(8),
                    Text(
                      '${data.records.length} verified receipts · sum ${analyticsMoney(data.total)}',
                    ),
                  ],
                ],
              ),
            ),
            gap(20),
            ListSearchField(
              value: query,
              hint: 'Search these detail rows',
              onChanged: (v) => setState(() {
                query = v;
                page = 0;
              }),
            ),
            gap(16),
            if (rows.isEmpty)
              const Panel(
                child: Text('No records match this snapshot and search.'),
              )
            else
              LayoutBuilder(
                builder: (context, b) =>
                    b.maxWidth >= 1050 &&
                        MediaQuery.textScalerOf(context).scale(14) < 22
                    ? RecordTable(
                        connected: true,
                        minWidth: 1000,
                        columns: data.financial
                            ? const [
                                'RECEIPT / CUSTOMER',
                                'DESCRIPTION',
                                'PAID · MYT',
                                'AMOUNT',
                                '',
                              ]
                            : widget.kind == 'selections'
                            ? const [
                                'PACKAGE',
                                'CUSTOMER',
                                'CREATED · MYT',
                                'BOOKING',
                                '',
                              ]
                            : const [
                                'CUSTOMER',
                                'FITTING · MYT',
                                'OUTCOME',
                                '',
                              ],
                        rows: [
                          for (final r in shown)
                            data.financial
                                ? [
                                    cell(r['receipt'], sub: r['customer']),
                                    SizedBox(
                                      width: 240,
                                      child: Tooltip(
                                        message:
                                            '${r['title']} · ${r['category']}',
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r['title'],
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              r['category'],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: muted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    cell(paymentDateLabel(r['paidAt'])),
                                    cell(analyticsMoney(r['amountCents'])),
                                    link(r),
                                  ]
                                : widget.kind == 'selections'
                                ? [
                                    SizedBox(
                                      width: 220,
                                      child: Tooltip(
                                        message: r['name'],
                                        child: Text(
                                          r['name'],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    cell(r['customer']),
                                    cell(paymentDateLabel(r['createdAt'])),
                                    cell(
                                      r['paidBooking']
                                          ? 'Verified deposit'
                                          : 'Not yet paid',
                                    ),
                                    link(r),
                                  ]
                                : [
                                    cell(r['customer']),
                                    cell(paymentDateLabel(r['attendedAt'])),
                                    cell(
                                      r['converted']
                                          ? 'Converted'
                                          : 'Not yet converted',
                                    ),
                                    link(r),
                                  ],
                        ],
                      )
                    : Column(
                        children: [
                          for (final r in shown)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data.financial
                                          ? r['receipt']
                                          : widget.kind == 'selections'
                                          ? r['name']
                                          : r['customer'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    gap(6),
                                    if (widget.kind != 'conversion')
                                      Text(r['customer']),
                                    if (data.financial) ...[
                                      Text(r['title']),
                                      Text(r['category']),
                                      Text(paymentDateLabel(r['paidAt'])),
                                      gap(8),
                                      Text(analyticsMoney(r['amountCents'])),
                                    ] else if (widget.kind == 'selections') ...[
                                      Text(paymentDateLabel(r['createdAt'])),
                                      Text(
                                        r['paidBooking']
                                            ? 'Verified deposit'
                                            : 'Not yet paid',
                                      ),
                                    ] else ...[
                                      Text(paymentDateLabel(r['attendedAt'])),
                                      Text(
                                        r['converted']
                                            ? 'Converted'
                                            : 'Not yet converted',
                                      ),
                                    ],
                                    gap(8),
                                    link(r),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            gap(12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  rows.isEmpty
                      ? '0 matching rows'
                      : '${current * 20 + 1}–${current * 20 + shown.length} of ${rows.length} matching rows',
                ),
                TextButton(
                  onPressed: current > 0
                      ? () => setState(() => page = current - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: (current + 1) * 20 < rows.length
                      ? () => setState(() => page = current + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
