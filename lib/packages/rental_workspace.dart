import 'package:flutter/material.dart';
import 'package_api.dart';

const rentalInk = Color(0xFF382B30);
const rentalMuted = Color(0xFF7F7278);
const rentalLine = Color(0xFFE9DFDF);
const rentalRose = Color(0xFF9E5063);
const rentalGreen = Color(0xFF386B59);
const rentalAmber = Color(0xFF94601F);

String customerRentalStage(PackageSelection selection, {DateTime? now}) {
  final rental = selection.data['rental'];
  if (rental is! Map) return 'Not reserved';
  if (rental['state'] == 'Cancelled') return 'Cancelled';
  if (rental['state'] == 'PaymentReview') return 'Needs review';
  if (rental['fulfilment'] == 'Returned') return 'Returned';
  if (rental['fulfilment'] == 'Collected') return 'Collected';
  if (rental['state'] == 'Locked') return 'Reserved';
  if (rental['state'] == 'Expired') return 'Expired';
  if (rental['state'] == 'Held') {
    final expiry = rental['expiresAt'];
    if (expiry is num &&
        expiry <= (now ?? DateTime.now()).millisecondsSinceEpoch) {
      return 'Expired';
    }
    return 'Awaiting deposit';
  }
  return 'Needs review';
}

String rentalDateLabel(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(value)) {
    return 'Not set';
  }
  final date = DateTime.tryParse(value);
  if (date == null) return 'Not set';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class RentalPaymentLine {
  const RentalPaymentLine(this.label, this.amount, this.status);
  final String label, status;
  final int? amount;
  bool get paid => [
    'Paid',
    'Held',
    'Refund due',
    'Refund recorded',
    'Deducted',
    'Not required',
  ].contains(status);
  bool get review => status == 'Needs review' || status == 'Check status';
  bool get due =>
      ['Awaiting payment', 'Verifying', 'Preparing payment'].contains(status);
  String get amountLabel => amount == null ? '—' : packageMoney(amount!);
}

/// Read-only presentation of authoritative rental/payment snapshots. This does
/// not mark attendance, confirm stock or infer payment from a displayed amount.
class StaffRentalView {
  StaffRentalView(this.selection, {DateTime? now})
    : now = now ?? DateTime.now();
  final PackageSelection selection;
  final DateTime now;
  Map get rental => selection.data['rental'] is Map
      ? selection.data['rental'] as Map
      : const {};
  Map get dates => {...?selection.data['rentalPlan'] as Map?, ...rental};
  String get stage => customerRentalStage(selection, now: now);
  String get pickup => rentalDateLabel(dates['pickupDate']);
  String get returned => rentalDateLabel(dates['returnDate']);
  String get event => rentalDateLabel(dates['eventDate']);
  int? cents(dynamic value) => value is int && value >= 0 ? value : null;
  String invoiceStatus(dynamic invoice, {String fallback = 'Check status'}) {
    if (invoice is! Map) return fallback;
    if (invoice['reviewReason'] != null ||
        invoice['state'] == 'ReviewRequired') {
      return 'Needs review';
    }
    return switch (invoice['state']) {
      'SandboxPaid' => 'Paid',
      'Pending' => 'Verifying',
      'Creating' => 'Preparing payment',
      'Quoted' || 'Unpaid' =>
        invoice['paymentBlocked'] == true ? 'Unavailable' : 'Awaiting payment',
      'Expired' => 'Expired',
      'Cancelled' => 'Cancelled',
      _ => 'Check status',
    };
  }

  RentalPaymentLine get deposit => RentalPaymentLine(
    'Booking deposit',
    cents(rental['depositCents']),
    invoiceStatus(
      selection.data['invoice'],
      fallback: rental['state'] == 'Locked'
          ? 'Paid'
          : stage == 'Awaiting deposit'
          ? 'Awaiting payment'
          : 'Not issued',
    ),
  );
  RentalPaymentLine get balance => RentalPaymentLine(
    'Remaining balance',
    cents(rental['balanceCents']),
    invoiceStatus(
      selection.data['balanceInvoice'],
      fallback: rental['paymentState'] == 'Paid'
          ? 'Paid'
          : rental['paymentState'] == 'DepositPaid'
          ? 'Awaiting payment'
          : 'Not issued',
    ),
  );
  RentalPaymentLine get security => RentalPaymentLine(
    'Refundable security',
    cents(rental['securityCents']),
    switch (rental['securityState']) {
      'Paid' => 'Held',
      'AwaitingPayment' => 'Awaiting payment',
      'RefundDue' => 'Refund due',
      'RefundRecorded' => 'Refund recorded',
      'Deducted' => 'Deducted',
      'NotRequired' => 'Not required',
      _ => 'Not issued',
    },
  );
  bool get extensionPending =>
      rental['pendingExtension'] is Map &&
      rental['pendingExtension']['expiresAt'] is num &&
      rental['pendingExtension']['expiresAt'] > now.millisecondsSinceEpoch;
  bool get needsReview =>
      stage == 'Needs review' ||
      deposit.review ||
      (stage == 'Reserved' &&
          (balance.review || rental['paymentState'] == null)) ||
      rental['lastExtensionOutcome'] == 'PaymentReview' ||
      rental['refundReviewRequired'] == true;
  bool get hasUnpaid =>
      stage == 'Awaiting deposit' ||
      stage == 'Reserved' && (balance.due || security.due);
  bool get readyForPickup =>
      stage == 'Reserved' &&
      !finalFittingPending &&
      !needsReview &&
      !extensionPending &&
      balance.paid &&
      security.paid &&
      deposit.status == 'Paid';
  bool get finalFittingPending =>
      rental['fittingQuote']?['adjustmentPlan']?['followUp'] == 'Required' &&
      rental['finalFitting']?['state'] != 'Completed';
  bool get canCancel =>
      ['Awaiting deposit', 'Reserved', 'Needs review'].contains(stage) &&
      ['Held', 'Locked', 'PaymentReview'].contains(rental['state']) &&
      rental.isNotEmpty &&
      rental['collectedAt'] == null &&
      rental['returnedAt'] == null;
  String get nextStep {
    if (needsReview) return 'Review payment status';
    if (stage == 'Cancelled') return 'Review any refund due';
    if (stage == 'Expired') return 'Recheck dates & stock';
    if (stage == 'Returned') {
      return security.status == 'Refund due'
          ? 'Arrange security refund'
          : 'Return recorded';
    }
    if (stage == 'Collected') {
      return rental['returnIssue']?['state'] == 'Open'
          ? 'Review reported return issue'
          : 'Await return & inspection';
    }
    if (extensionPending) return 'Review date-change payment';
    if (stage == 'Awaiting deposit') return 'Collect booking deposit';
    if (stage == 'Reserved') {
      if (balance.due && security.due) return 'Collect balance & security';
      if (balance.due) return 'Collect remaining balance';
      if (security.due) return 'Collect security deposit';
      if (finalFittingPending) return 'Arrange final fitting';
      return readyForPickup ? 'Arrange pickup' : 'Review payment status';
    }
    if (selection.data['rentalPlan'] == null) {
      return 'Await customer rental dates';
    }
    if (selection.data['fittingWorkflowVersion'] == 2 &&
        selection.data['fittingReady'] != true) {
      return switch (selection.data['fittingDecision']?['state']) {
        'QuoteNeeded' => 'Prepare fitting proposal',
        'AwaitingCustomer' => 'Await customer confirmation',
        'Reselect' => 'Customer choosing another gown',
        'Considering' => 'Customer is considering',
        'Declined' => 'No booking requested',
        _ => 'Review selection & adjustments',
      };
    }
    if (selection.data['fittingDecision']?['state'] == 'Approved') {
      return 'Check stock & reserve';
    }
    if (selection.data['fittingChoice']?['mode'] == 'SkipFitting') {
      return 'Review no-fitting request';
    }
    if (selection.appointments.any((a) => a['status'] == 'Confirmed')) {
      return 'Record fitting outcome';
    }
    return 'Arrange fitting';
  }

  String get paymentSummary {
    if (needsReview) return 'Payment review needed';
    if (stage == 'Cancelled' || stage == 'Expired') {
      return 'Open details for payment history';
    }
    if (stage == 'Awaiting deposit') {
      return '${deposit.amountLabel} deposit due';
    }
    if (rental.isEmpty) {
      return selection.data['invoice'] == null
          ? 'Not invoiced'
          : 'View payment record';
    }
    if (stage == 'Returned') {
      return security.status == 'Refund due'
          ? '${rental['refundDueCents'] is int ? packageMoney(rental['refundDueCents']) : security.amountLabel} refund due'
          : security.status;
    }
    final lines = <String>[
      if (balance.due)
        '${balance.amountLabel} balance · ${balance.status == 'Verifying' ? 'verifying' : 'due'}',
      if (security.due) '${security.amountLabel} security due',
    ];
    if (lines.isNotEmpty) return lines.join('\n');
    return balance.paid && security.paid
        ? 'Package paid · security ${security.status.toLowerCase()}'
        : 'Check payment details';
  }

  Color get tone => needsReview
      ? rentalRose
      : hasUnpaid
      ? rentalAmber
      : ['Reserved', 'Collected', 'Returned'].contains(stage)
      ? rentalGreen
      : rentalMuted;
  String get badge => stage == 'Reserved'
      ? 'Stock reserved'
      : stage == 'Collected'
      ? 'Collected'
      : stage;
}

class RentalStageBadge extends StatelessWidget {
  const RentalStageBadge({super.key, required this.view});
  final StaffRentalView view;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: view.tone.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        view.badge,
        style: TextStyle(
          color: view.tone,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class StaffRentalWorkspace extends StatefulWidget {
  const StaffRentalWorkspace({
    super.key,
    required this.selections,
    required this.onOpen,
    this.focusedId,
    this.onShowAll,
  });
  final List<PackageSelection> selections;
  final ValueChanged<PackageSelection> onOpen;
  final String? focusedId;
  final VoidCallback? onShowAll;
  @override
  State<StaffRentalWorkspace> createState() => _StaffRentalWorkspaceState();
}

class _StaffRentalWorkspaceState extends State<StaffRentalWorkspace> {
  final search = TextEditingController();
  String stage = 'All';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.selections
        .where((s) => widget.focusedId == null || s.id == widget.focusedId)
        .toList();
    final filtered = rows.where((s) {
      final view = StaffRentalView(s);
      return (stage == 'All' ||
              (stage == 'Needs review'
                  ? view.needsReview
                  : view.stage == stage)) &&
          '${s.customer} ${s.name} ${view.dates['pickupDate']} ${view.dates['returnDate']} ${view.dates['eventDate']} ${view.pickup} ${view.returned} ${view.event}'
              .toLowerCase()
              .contains(search.text.trim().toLowerCase());
    }).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final table =
            box.maxWidth >= 1050 &&
            MediaQuery.textScalerOf(context).scale(14) <= 18;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: ListView(
              padding: EdgeInsets.all(box.maxWidth < 600 ? 16 : 24),
              children: [
                Text(
                  'Customer rentals',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Track each customer’s next step, from fitting to return.',
                  style: TextStyle(color: rentalMuted),
                ),
                const SizedBox(height: 20),
                if (widget.focusedId != null)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Package linked to this appointment'),
                      TextButton(
                        onPressed: widget.onShowAll,
                        child: const Text('Show all selections'),
                      ),
                    ],
                  ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: rentalLine),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search customer, package or date',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () =>
                                      setState(() => search.clear()),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final label in [
                            'All',
                            'Not reserved',
                            'Awaiting deposit',
                            'Reserved',
                            'Collected',
                            'Returned',
                            'Expired',
                            'Cancelled',
                            'Needs review',
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: stage == label,
                              onSelected: (_) => setState(() => stage = label),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${filtered.length} ${filtered.length == 1 ? 'record' : 'records'}',
                  style: const TextStyle(color: rentalMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 32,
                          color: rentalMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.focusedId != null && rows.isEmpty
                              ? 'This linked package selection is unavailable. Refresh or contact the manager.'
                              : rows.isEmpty
                              ? 'Customer package selections will appear here.'
                              : 'No customer rentals match your search and filters.',
                        ),
                        if (search.text.isNotEmpty || stage != 'All')
                          TextButton(
                            onPressed: () => setState(() {
                              search.clear();
                              stage = 'All';
                            }),
                            child: const Text('Clear filters'),
                          ),
                      ],
                    ),
                  ),
                if (table && filtered.isNotEmpty)
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: rentalLine),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Container(
                          color: const Color(0xFFFAF7F6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: const Row(
                            children: [
                              Expanded(
                                flex: 18,
                                child: _ColumnTitle('CUSTOMER / PACKAGE'),
                              ),
                              Expanded(
                                flex: 15,
                                child: _ColumnTitle('PICKUP / RETURN'),
                              ),
                              Expanded(
                                flex: 21,
                                child: _ColumnTitle('PAYMENT'),
                              ),
                              Expanded(
                                flex: 24,
                                child: _ColumnTitle('STATUS / NEXT STEP'),
                              ),
                              SizedBox(width: 132),
                            ],
                          ),
                        ),
                        for (final s in filtered)
                          _RentalTableRow(
                            selection: s,
                            onOpen: () => widget.onOpen(s),
                          ),
                      ],
                    ),
                  ),
                if (!table)
                  for (final s in filtered)
                    _RentalCompactRow(
                      selection: s,
                      onOpen: () => widget.onOpen(s),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColumnTitle extends StatelessWidget {
  const _ColumnTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      letterSpacing: 1,
      color: rentalMuted,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _RentalTableRow extends StatelessWidget {
  const _RentalTableRow({required this.selection, required this.onOpen});
  final PackageSelection selection;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final view = StaffRentalView(selection);
    return Container(
      key: ValueKey('rental-row-${selection.id}'),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: rentalLine)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 18,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selection.customer,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: rentalInk,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      selection.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: rentalMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 15,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(view.pickup),
                  const SizedBox(height: 5),
                  Text(
                    'Return: ${view.returned}',
                    style: const TextStyle(color: rentalMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 21,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  view.paymentSummary,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: view.hasUnpaid ? rentalAmber : rentalMuted,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 24,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RentalStageBadge(view: view),
                    const SizedBox(height: 7),
                    Text(
                      view.nextStep,
                      style: const TextStyle(fontSize: 12, color: rentalInk),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 132,
              child: OutlinedButton(
                onPressed: onOpen,
                child: const Text('View details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RentalCompactRow extends StatelessWidget {
  const _RentalCompactRow({required this.selection, required this.onOpen});
  final PackageSelection selection;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final view = StaffRentalView(selection);
    return Container(
      key: ValueKey('rental-row-${selection.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: rentalLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selection.customer,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(selection.name, style: const TextStyle(color: rentalMuted)),
          const SizedBox(height: 12),
          RentalStageBadge(view: view),
          const SizedBox(height: 12),
          Text(
            'Pickup: ${view.pickup} · Return: ${view.returned}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            view.paymentSummary,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Next: ${view.nextStep}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onOpen, child: const Text('View details')),
        ],
      ),
    );
  }
}
