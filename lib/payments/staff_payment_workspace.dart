import 'package:flutter/material.dart';
import '../admin/design.dart';
import '../shared/list_controls.dart';
import 'payment_api.dart';
import 'payment_filters.dart';

enum StaffPaymentStage {
  all,
  review,
  processing,
  unpaid,
  paid,
  resolved,
  closed,
}

String staffPaymentStageName(StaffPaymentStage stage) => switch (stage) {
  StaffPaymentStage.all => 'All payments',
  StaffPaymentStage.review => 'Needs review',
  StaffPaymentStage.processing => 'Verification pending',
  StaffPaymentStage.unpaid => 'Awaiting payment',
  StaffPaymentStage.paid => 'Paid receipts',
  StaffPaymentStage.resolved => 'Review completed',
  StaffPaymentStage.closed => 'Expired / cancelled',
};
StaffPaymentStage staffPaymentStage(SandboxInvoice i) {
  if (i.reviewResolution != null) return StaffPaymentStage.resolved;
  return switch (paymentListStatus(i)) {
    PaymentListStatus.review => StaffPaymentStage.review,
    PaymentListStatus.processing => StaffPaymentStage.processing,
    PaymentListStatus.toPay => StaffPaymentStage.unpaid,
    PaymentListStatus.paid => StaffPaymentStage.paid,
    _ => StaffPaymentStage.closed,
  };
}

String staffPaymentStatusLabel(SandboxInvoice i) =>
    switch (staffPaymentStage(i)) {
      StaffPaymentStage.resolved => i.statusLabel,
      StaffPaymentStage.processing =>
        i.state == 'Creating' ? 'Preparing payment' : 'Verification pending',
      StaffPaymentStage.closed =>
        i.paymentBlocked ? 'Cancelled / blocked' : 'Payment window ended',
      StaffPaymentStage.paid => 'Paid',
      _ => staffPaymentStageName(staffPaymentStage(i)),
    };
String staffPaymentDate(SandboxInvoice i) {
  bool valid(int? ms) => ms != null && ms > 0 && ms < 4102444800000;
  if (i.state == 'SandboxPaid' && valid(i.paidAt)) {
    return 'Paid · ${paymentDateLabel(i.paidAt!)}';
  }
  if (i.reviewResolution != null) return 'Original payment retained';
  if (valid(i.holdExpiresAt)) {
    return 'Deadline · ${paymentDateLabel(i.holdExpiresAt!)}';
  }
  if (['PackageBalance', 'SecurityDeposit'].contains(i.purpose)) {
    return i.pickupDueDate == null
        ? 'Before pickup · date not recorded'
        : 'Before pickup · ${i.pickupDueDate}';
  }
  return !valid(i.createdAt)
      ? 'Date not recorded'
      : 'Issued · ${paymentDateLabel(i.createdAt!)}';
}

List<SandboxInvoice> sortStaffPayments(
  Iterable<SandboxInvoice> source,
  String sort,
) {
  final rows = source.toList();
  int attention(SandboxInvoice i) => switch (staffPaymentStage(i)) {
    StaffPaymentStage.review => 0,
    StaffPaymentStage.processing => 1,
    StaffPaymentStage.unpaid => 2,
    StaffPaymentStage.paid => 3,
    StaffPaymentStage.resolved => 4,
    _ => 5,
  };
  rows.sort((a, b) {
    final result = switch (sort) {
      'Amount: high to low' => b.amountCents.compareTo(a.amountCents),
      'Amount: low to high' => a.amountCents.compareTo(b.amountCents),
      'Newest record' => (paymentRecordTime(b) ?? 0).compareTo(
        paymentRecordTime(a) ?? 0,
      ),
      _ => attention(a).compareTo(attention(b)),
    };
    if (result != 0) return result;
    final recent = (paymentRecordTime(b) ?? 0).compareTo(
      paymentRecordTime(a) ?? 0,
    );
    return recent != 0 ? recent : a.id.compareTo(b.id);
  });
  return rows;
}

/// Staff-only presentation. Reading, searching and sorting never write invoices.
class StaffPaymentListState {
  PaymentListFilter filter = const PaymentListFilter();
  StaffPaymentStage stage = StaffPaymentStage.all;
  String sort = 'Attention first';
  int page = 0;
}

class StaffPaymentIdentity extends StatelessWidget {
  const StaffPaymentIdentity({super.key, required this.invoice});
  final SandboxInvoice invoice;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invoice.customerName?.isNotEmpty == true
                ? invoice.customerName!
                : 'Customer name not recorded',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          gap(6),
          Text(invoice.purposeLabel),
          gap(10),
          Text('Invoice ID', style: Theme.of(context).textTheme.bodySmall),
          SelectableText(invoice.id),
          gap(10),
          Text(staffPaymentDate(invoice), style: const TextStyle(color: muted)),
          if (invoice.purpose == 'SecurityDeposit') ...[
            gap(8),
            const Text(
              'Refundable security is separate from package revenue. Review inspection and refund records in Customer rentals.',
              style: TextStyle(color: muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class StaffPaymentWorkspace extends StatefulWidget {
  const StaffPaymentWorkspace({
    super.key,
    required this.invoices,
    required this.busy,
    required this.onOpen,
    this.onIssue,
    this.viewState,
  });
  final List<SandboxInvoice> invoices;
  final bool busy;
  final ValueChanged<SandboxInvoice> onOpen;
  final VoidCallback? onIssue;
  final StaffPaymentListState? viewState;
  @override
  State<StaffPaymentWorkspace> createState() => _StaffPaymentWorkspaceState();
}

class _StaffPaymentWorkspaceState extends State<StaffPaymentWorkspace> {
  late final view = widget.viewState ?? StaffPaymentListState();
  PaymentListFilter get filter => view.filter;
  set filter(PaymentListFilter value) => view.filter = value;
  StaffPaymentStage get stage => view.stage;
  set stage(StaffPaymentStage value) => view.stage = value;
  String get sort => view.sort;
  set sort(String value) => view.sort = value;
  int get page => view.page;
  set page(int value) => view.page = value;
  void reset() => setState(() {
    filter = const PaymentListFilter();
    stage = StaffPaymentStage.all;
    sort = 'Attention first';
    page = 0;
  });
  Future<void> dates() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: filter.dates,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (range != null && mounted) {
      setState(() {
        filter = filter.copyWith(dates: range);
        page = 0;
      });
    }
  }

  Widget status(SandboxInvoice i) {
    final stage = staffPaymentStage(i),
        colour = switch (stage) {
          StaffPaymentStage.paid => sage,
          StaffPaymentStage.review ||
          StaffPaymentStage.processing => const Color(0xFF95601E),
          _ => muted,
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        staffPaymentStatusLabel(i),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colour,
        ),
      ),
    );
  }

  Widget textCell(String title, String subtitle, double width) => SizedBox(
    width: width,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    ),
  );
  Widget open(SandboxInvoice i) => TextButton(
    key: ValueKey('open-invoice-${i.id}'),
    onPressed: widget.busy ? null : () => widget.onOpen(i),
    child: const Text('View details'),
  );
  @override
  Widget build(BuildContext context) {
    final rows = sortStaffPayments(
      widget.invoices.where(
        (i) =>
            (stage == StaffPaymentStage.all || staffPaymentStage(i) == stage) &&
            filter.matches(i, staff: true),
      ),
      sort,
    );
    final last = rows.isEmpty ? 0 : (rows.length - 1) ~/ 20,
        current = page.clamp(0, last),
        shown = rows.skip(current * 20).take(20).toList();
    return PageBody(
      children: [
        Heading(
          'Payment workspace',
          'Review customer invoices, payment status and receipts in one place.',
          action: widget.onIssue == null
              ? null
              : FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onIssue,
                  icon: const Icon(Icons.add),
                  label: const Text('Issue invoice'),
                ),
        ),
        ResponsiveGrid(
          children: [
            for (final summary in [
              (StaffPaymentStage.review, 'Needs review', Icons.error_outline),
              (
                StaffPaymentStage.processing,
                'Verification pending',
                Icons.sync,
              ),
              (
                StaffPaymentStage.unpaid,
                'Awaiting payment',
                Icons.receipt_long_outlined,
              ),
            ])
              Panel(
                child: InkWell(
                  onTap: () => setState(() {
                    stage = summary.$1;
                    page = 0;
                  }),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              summary.$2,
                              style: const TextStyle(color: muted),
                            ),
                          ),
                          Icon(summary.$3, color: rose, size: 20),
                        ],
                      ),
                      gap(10),
                      Text(
                        '${widget.invoices.where((i) => staffPaymentStage(i) == summary.$1).length}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      gap(4),
                      Text(switch (summary.$1) {
                        StaffPaymentStage.review =>
                          'Check before requesting another payment',
                        StaffPaymentStage.processing =>
                          'Await server verification',
                        _ => 'Open invoices · security listed separately',
                      }, style: const TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        gap(20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListSearchField(
                value: filter.query,
                hint: 'Search customer, payment or receipt',
                onChanged: (v) => setState(() {
                  filter = filter.copyWith(query: v);
                  page = 0;
                }),
              ),
              gap(12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ListFilterSelect(
                    label: 'Payment status',
                    value: staffPaymentStageName(stage),
                    options: StaffPaymentStage.values
                        .map(staffPaymentStageName)
                        .toList(),
                    onChanged: (v) => setState(() {
                      stage = StaffPaymentStage.values.firstWhere(
                        (s) => staffPaymentStageName(s) == v,
                      );
                      page = 0;
                    }),
                  ),
                  ListFilterSelect(
                    label: 'Payment type',
                    value: paymentTypeName(filter.type),
                    options: PaymentListType.values
                        .map(paymentTypeName)
                        .toList(),
                    onChanged: (v) => setState(() {
                      filter = filter.copyWith(
                        type: PaymentListType.values.firstWhere(
                          (t) => paymentTypeName(t) == v,
                        ),
                      );
                      page = 0;
                    }),
                  ),
                  OutlinedButton.icon(
                    onPressed: dates,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: const Text('Record dates'),
                  ),
                  if (filter.active ||
                      stage != StaffPaymentStage.all ||
                      sort != 'Attention first')
                    ResetListFilters(onReset: reset),
                ],
              ),
              if (filter.dates != null) ...[
                gap(10),
                InputChip(
                  label: Text(paymentRangeLabel(filter.dates!)),
                  onDeleted: () => setState(() {
                    filter = filter.copyWith(clearDates: true);
                    page = 0;
                  }),
                ),
              ],
            ],
          ),
        ),
        gap(16),
        const Text(
          'Refundable security is tracked separately from package payments.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        gap(16),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${rows.length} matching test payments · MYT',
              style: const TextStyle(color: muted),
            ),
            ListFilterSelect(
              label: 'Sort by',
              value: sort,
              options: const [
                'Attention first',
                'Newest record',
                'Amount: high to low',
                'Amount: low to high',
              ],
              onChanged: (v) => setState(() {
                sort = v;
                page = 0;
              }),
            ),
          ],
        ),
        gap(12),
        if (widget.busy) const LinearProgressIndicator(),
        LayoutBuilder(
          builder: (context, bounds) {
            if (rows.isEmpty) {
              return Panel(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    widget.invoices.isEmpty
                        ? 'No invoices have been issued yet.'
                        : 'No payments match your search and filters.',
                  ),
                ),
              );
            }
            if (bounds.maxWidth < 1000) {
              return Column(
                children: [
                  for (final i in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i.customerName?.isNotEmpty == true
                                  ? i.customerName!
                                  : 'Customer name not recorded',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            gap(6),
                            Text(
                              i.amountLabel,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(i.purposeLabel),
                            if (i.purpose == 'SecurityDeposit')
                              const Text(
                                'Refundable security · not package price',
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            Text(i.title, style: const TextStyle(color: muted)),
                            gap(10),
                            status(i),
                            gap(8),
                            Text(
                              staffPaymentDate(i),
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                            open(i),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }
            return RecordTable(
              connected: true,
              minWidth: 1100,
              columns: const [
                'Customer / reference',
                'Payment for',
                'Amount',
                'Due / paid date (MYT)',
                'Status',
                'Action',
              ],
              rows: [
                for (final i in shown)
                  [
                    textCell(
                      i.customerName?.isNotEmpty == true
                          ? i.customerName!
                          : 'Name not recorded',
                      i.invoiceNo ??
                          'Invoice ${i.id.length > 8 ? '${i.id.substring(0, 8)}…' : i.id}',
                      150,
                    ),
                    textCell(i.purposeLabel, i.title, 205),
                    textCell(
                      i.amountLabel,
                      i.purpose == 'SecurityDeposit'
                          ? 'Refundable security'
                          : paymentListType(i) == PaymentListType.other
                          ? 'Other payment'
                          : 'Package / service',
                      115,
                    ),
                    SizedBox(
                      width: 180,
                      child: Text(
                        staffPaymentDate(i),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: 145,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: status(i),
                      ),
                    ),
                    open(i),
                  ],
              ],
            );
          },
        ),
        gap(12),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              rows.isEmpty
                  ? '0 records'
                  : 'Page ${current + 1} of ${last + 1} · 20 per page',
            ),
            IconButton(
              tooltip: 'Previous payment page',
              onPressed: current > 0
                  ? () => setState(() => page = current - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next payment page',
              onPressed: current < last
                  ? () => setState(() => page = current + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
