import 'package:flutter/material.dart';
import '../src/design.dart' show CustomerUi, blush, ink, ivory, line;
import 'payment_api.dart';

enum PaymentListStatus { all, toPay, processing, paid, closed, review }

enum PaymentListType {
  all,
  fitting,
  deposit,
  balance,
  security,
  extension,
  other,
}

String paymentStatusName(PaymentListStatus value) => switch (value) {
  PaymentListStatus.all => 'All payments',
  PaymentListStatus.toPay => 'To pay',
  PaymentListStatus.processing => 'Processing',
  PaymentListStatus.paid => 'Paid receipts',
  PaymentListStatus.closed => 'Expired / cancelled',
  PaymentListStatus.review => 'Needs review',
};
String paymentTypeName(PaymentListType value) => switch (value) {
  PaymentListType.all => 'All payment types',
  PaymentListType.fitting => 'Fitting fee',
  PaymentListType.deposit => 'Booking deposit',
  PaymentListType.balance => 'Package balance',
  PaymentListType.security => 'Refundable security',
  PaymentListType.extension => 'Rental extension',
  PaymentListType.other => 'Other payments',
};
PaymentListStatus paymentListStatus(SandboxInvoice i) {
  if (i.reviewReason != null || i.state == 'ReviewRequired') {
    return PaymentListStatus.review;
  }
  if (i.state == 'SandboxPaid') return PaymentListStatus.paid;
  if (i.paymentBlocked || i.holdExpired) return PaymentListStatus.closed;
  if (['Pending', 'Creating'].contains(i.state)) {
    return PaymentListStatus.processing;
  }
  return PaymentListStatus.toPay;
}

PaymentListType paymentListType(SandboxInvoice i) => switch (i.purpose) {
  'FittingFee' => PaymentListType.fitting,
  'BookingDeposit' || 'AppointmentDeposit' => PaymentListType.deposit,
  'PackageBalance' => PaymentListType.balance,
  'SecurityDeposit' => PaymentListType.security,
  'RentalExtension' => PaymentListType.extension,
  _ => PaymentListType.other,
};
int? paymentRecordTime(SandboxInvoice i) => i.paidAt ?? i.createdAt;
int dateKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
String paymentRangeLabel(DateTimeRange range) {
  String day(DateTime d) => paymentDateLabel(
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch,
  ).split(' · ').first;
  return '${day(range.start)} – ${day(range.end)}';
}

/// Read-only filtering. Never infers payment success from a date or search term.
class PaymentListFilter {
  const PaymentListFilter({
    this.query = '',
    this.status = PaymentListStatus.all,
    this.type = PaymentListType.all,
    this.dates,
  });
  final String query;
  final PaymentListStatus status;
  final PaymentListType type;
  final DateTimeRange? dates;
  int get activeCount =>
      (status == PaymentListStatus.all ? 0 : 1) +
      (type == PaymentListType.all ? 0 : 1) +
      (dates == null ? 0 : 1);
  bool get active => query.trim().isNotEmpty || activeCount > 0;
  PaymentListFilter copyWith({
    String? query,
    PaymentListStatus? status,
    PaymentListType? type,
    DateTimeRange? dates,
    bool clearDates = false,
  }) => PaymentListFilter(
    query: query ?? this.query,
    status: status ?? this.status,
    type: type ?? this.type,
    dates: clearDates ? null : dates ?? this.dates,
  );
  bool matches(SandboxInvoice i, {bool staff = false}) {
    if (status != PaymentListStatus.all && paymentListStatus(i) != status) {
      return false;
    }
    if (type != PaymentListType.all && paymentListType(i) != type) return false;
    if (dates case final range?) {
      final ms = paymentRecordTime(i);
      if (ms == null) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).add(const Duration(hours: 8));
      if (dateKey(d) < dateKey(range.start) ||
          dateKey(d) > dateKey(range.end)) {
        return false;
      }
    }
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty);
    final haystack = [
      i.title,
      i.purposeLabel,
      i.invoiceNo ?? '',
      i.amountLabel,
      paymentTypeName(paymentListType(i)),
      paymentStatusName(paymentListStatus(i)),
      if (i.appointment != null) paymentDateLabel(i.appointment!.startAt),
      if (staff) ...[i.customerName ?? '', i.id, i.appointmentId],
    ].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }
}

class PaymentSearchControls extends StatelessWidget {
  const PaymentSearchControls({
    super.key,
    required this.controller,
    required this.filter,
    required this.onChanged,
    required this.onFilters,
    required this.staff,
  });
  final TextEditingController controller;
  final PaymentListFilter filter;
  final ValueChanged<PaymentListFilter> onChanged;
  final VoidCallback onFilters;
  final bool staff;
  String _searchHint(BuildContext context) {
    if (staff) return 'Search customer, payment or receipt';
    final width = MediaQuery.sizeOf(context).width;
    if (MediaQuery.textScalerOf(context).scale(1) <= 1.4 || width >= 460) {
      return 'Search payments or receipts';
    }
    return width < 360 ? 'Search' : 'Search payments';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (v) => onChanged(filter.copyWith(query: v)),
              maxLength: 120,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
                hintMaxLines: 1,
                hintText: _searchHint(context),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onChanged(filter.copyWith(query: ''));
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Filter payments',
            onPressed: onFilters,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(48),
              backgroundColor: Colors.white,
              foregroundColor: ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: line),
            ),
            icon: Badge(
              isLabelVisible: filter.activeCount > 0,
              label: Text('${filter.activeCount}'),
              child: const Icon(Icons.tune, size: 20),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in [
              PaymentListStatus.all,
              PaymentListStatus.toPay,
              PaymentListStatus.paid,
              PaymentListStatus.processing,
              PaymentListStatus.closed,
              PaymentListStatus.review,
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  label: Text(
                    status == PaymentListStatus.all
                        ? 'All'
                        : paymentStatusName(status),
                  ),
                  selected: filter.status == status,
                  showCheckmark: false,
                  selectedColor: blush,
                  backgroundColor: ivory,
                  side: const BorderSide(color: line),
                  labelStyle: const TextStyle(color: ink),
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => onChanged(filter.copyWith(status: status)),
                ),
              ),
          ],
        ),
      ),
      if (filter.type != PaymentListType.all || filter.dates != null) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (filter.type != PaymentListType.all)
              InputChip(
                label: Text(paymentTypeName(filter.type)),
                onDeleted: () =>
                    onChanged(filter.copyWith(type: PaymentListType.all)),
              ),
            if (filter.dates != null)
              InputChip(
                label: Text(paymentRangeLabel(filter.dates!)),
                onDeleted: () => onChanged(filter.copyWith(clearDates: true)),
              ),
          ],
        ),
      ],
    ],
  );
}

Future<PaymentListFilter?> showPaymentFilters(
  BuildContext context,
  PaymentListFilter filter,
) => showModalBottomSheet<PaymentListFilter>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  sheetAnimationStyle: CustomerUi.expansionMotion(context),
  builder: (_) => FractionallySizedBox(
    heightFactor: .9,
    child: _PaymentFiltersSheet(initial: filter),
  ),
);

class _PaymentFiltersSheet extends StatefulWidget {
  const _PaymentFiltersSheet({required this.initial});
  final PaymentListFilter initial;
  @override
  State<_PaymentFiltersSheet> createState() => _PaymentFiltersState();
}

class _PaymentFiltersState extends State<_PaymentFiltersSheet> {
  late PaymentListFilter filter = widget.initial;
  Future<void> pickDates() async {
    final utc = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime(utc.year, utc.month, utc.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: filter.dates,
      helpText: 'Paid or issued date · MYT',
      saveText: 'Apply dates',
    );
    if (range != null && mounted) {
      setState(() => filter = filter.copyWith(dates: range));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(String label, bool selected, VoidCallback change, Key key) =>
        ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: const TextStyle(fontSize: 12),
          backgroundColor: Colors.white,
          selectedColor: Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: .08),
            theme.colorScheme.surface,
          ),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          onSelected: (_) => setState(change),
        );
    return SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter payments',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close filters',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('payment-filter-options'),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              children: [
                Text('Payment status', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final v in PaymentListStatus.values)
                      option(
                        paymentStatusName(v),
                        filter.status == v,
                        () => filter = filter.copyWith(status: v),
                        ValueKey('payment-filter-status-${v.name}'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Payment type', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final v in PaymentListType.values)
                      option(
                        paymentTypeName(v),
                        filter.type == v,
                        () => filter = filter.copyWith(type: v),
                        ValueKey('payment-filter-type-${v.name}'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Paid or issued date · Malaysia time',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: pickDates,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    filter.dates == null
                        ? 'Any date'
                        : paymentRangeLabel(filter.dates!),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (filter.dates != null)
                  TextButton(
                    onPressed: () => setState(
                      () => filter = filter.copyWith(clearDates: true),
                    ),
                    child: const Text('Remove date range'),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 24, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => filter = PaymentListFilter(query: filter.query),
                  ),
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, filter),
                    child: const Text(
                      'Apply filters',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
