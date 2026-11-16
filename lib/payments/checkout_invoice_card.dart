import 'package:flutter/material.dart';
import '../src/design.dart' show CustomerUi, ink, line;
import 'payment_api.dart';
import 'payment_filters.dart' show PaymentListStatus, paymentListStatus;
import 'payment_timing.dart';
import 'receipt_document.dart' show ReceiptDocument;

/// Presentation of a server-verified invoice; never infers success from redirects.
class CheckoutInvoiceCard extends StatelessWidget {
  const CheckoutInvoiceCard({
    super.key,
    required this.invoice,
    required this.staff,
    required this.busy,
    this.focused = false,
    this.compact = false,
    this.onPay,
    this.onCheck,
    this.onReceipt,
    this.onDone,
    this.onReview,
    this.now,
    this.showStaffCustomer = true,
  });
  final SandboxInvoice invoice;
  final bool staff, busy, focused, compact;
  final bool showStaffCustomer;
  final VoidCallback? onPay, onCheck, onReceipt, onDone, onReview;
  final DateTime? now;
  static const _securityTerms =
      'Refundable after return inspection, less agreed deductions. This is separate from your package price.';
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), paid = invoice.state == 'SandboxPaid';
    final review =
        (invoice.reviewResolution == null || !staff) &&
        (invoice.reviewReason != null || invoice.state == 'ReviewRequired');
    final verified = paid && !review && invoice.reviewResolution == null;
    final colour = review
        ? const Color(0xFF94611B)
        : verified
        ? const Color(0xFF386953)
        : theme.colorScheme.primary;
    String? detail;
    if (review) {
      detail = staff
          ? 'Review the saved transaction before asking the customer to pay again. Only an authorised manager can close a payment review.'
          : 'Please contact Luvly before paying again.';
    } else if (invoice.reviewResolution case final resolution?) {
      final refund = resolution['refundCents'];
      detail = refund is int
          ? 'Review completed · refund recorded: ${_amount(refund)}. Original payment and receipt are kept in your history.'
          : 'Review completed. Original payment and receipt are kept in your history.';
    } else if (invoice.paymentBlocked) {
      detail = invoice.purpose == 'RentalExtension'
          ? 'This extension request ended. Original rental dates are unchanged. Check any submitted payment before requesting another invoice.'
          : 'This appointment was cancelled. Do not pay this invoice.';
    } else if (invoice.holdExpired && !paid) {
      detail = invoice.purpose == 'RentalExtension'
          ? 'The extension deadline passed; original rental dates remain unchanged. If you already paid, check status and contact the team before requesting another invoice.'
          : 'The payment deadline has passed. If you already paid, check status; otherwise rebook or contact Luvly.';
    } else if (invoice.purpose == 'FittingFee') {
      detail = verified
          ? staff
                ? 'The fitting fee is verified. Review the linked visit in Appointments.'
                : 'Your fitting payment has been verified. View the appointment in Bookings.'
          : 'RM50 covers one 60-minute fitting appointment, not one gown. You may try multiple gowns within the visit. After attendance, RM50 can be credited once towards a package.';
    } else if (invoice.purpose == 'SecurityDeposit') {
      detail = _securityTerms;
    } else if (invoice.purpose == 'RentalExtension') {
      detail = verified
          ? staff
                ? 'Verified extension payment. Refresh Customer rentals to see the updated dates.'
                : 'Verified extension payment. Refresh My packages to see the updated dates.'
          : 'Original rental dates remain in place until this extension payment is verified.';
    } else if (invoice.purpose == 'BookingDeposit' && verified) {
      detail = staff
          ? 'Review the rental and remaining balance in Customer rentals.'
          : 'View your rental and remaining balance in My packages.';
    }
    if (compact && !staff && !focused) {
      return _compactCard(context, paid: paid, review: review, detail: detail);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DFDC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (focused && verified) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEEF5F0),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF386953),
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Payment successful',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Icon(
                review
                    ? Icons.info_outline
                    : verified
                    ? Icons.verified_outlined
                    : Icons.receipt_long_outlined,
                size: 18,
                color: colour,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review ? 'Review required' : invoice.statusLabel,
                  style: theme.textTheme.labelLarge?.copyWith(color: colour),
                ),
              ),
              if (staff)
                const Text(
                  'Test payment',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: Color(0xFF81767A),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (staff)
            Text(
              invoice.amountLabel,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            _PaymentAmount(
              cents: invoice.amountCents,
              label: _amountCaption(paymentListStatus(invoice)),
            ),
          const SizedBox(height: 6),
          Text(invoice.title, style: theme.textTheme.titleMedium),
          PaymentTiming(invoice: invoice, now: now),
          if (invoice.extensionDetails case final e?) ...[
            const SizedBox(height: 12),
            ..._extensionInfo(e),
          ],
          if (staff && showStaffCustomer && invoice.customerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(invoice.customerName!),
            ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          if (staff && invoice.reviewReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                invoice.reviewReason!,
                style: theme.textTheme.bodySmall?.copyWith(color: colour),
              ),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!staff && invoice.canPay)
                FilledButton.icon(
                  onPressed: busy ? null : onPay,
                  icon: const Icon(Icons.lock_outline, size: 17),
                  label: const Text('Pay now'),
                ),
              if (paid)
                FilledButton.icon(
                  onPressed: onReceipt,
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: const Text('View receipt'),
                ),
              if (staff && invoice.canResolveReview && onReview != null)
                OutlinedButton(
                  onPressed: busy ? null : onReview,
                  child: const Text('Close payment review'),
                ),
              if (invoice.hasBill && (!verified || !focused))
                OutlinedButton(
                  onPressed: busy ? null : onCheck,
                  child: const Text('Check status'),
                ),
              if (focused && verified && onDone != null)
                OutlinedButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'Payment details',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              _Detail(label: 'Payment for', value: invoice.purposeLabel),
              ..._appointmentDetails(),
              if (staff)
                _Detail(label: 'Amount', value: invoice.amountLabel)
              else
                _Detail.money(label: 'Amount', cents: invoice.amountCents),
              _Detail(
                label: 'Status',
                value: review
                    ? staff
                          ? 'Manager review required'
                          : 'Contact our team'
                    : invoice.statusLabel,
              ),
              ..._receiptDetails(),
              if (staff) _Detail(label: 'Invoice ID', value: invoice.id),
              if (staff)
                _Detail(
                  label: invoice.appointmentId.isEmpty
                      ? 'Package reference'
                      : 'Appointment',
                  value: invoice.appointmentId.isEmpty
                      ? invoice.packageSelectionId ?? 'Unavailable'
                      : invoice.appointmentId,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _amount(int cents) =>
      staff ? 'RM ${(cents / 100).toStringAsFixed(2)}' : _ringgit(cents);

  String _amountCaption(PaymentListStatus status) {
    if (invoice.reviewResolution != null) return 'Original amount paid';
    return switch (status) {
      PaymentListStatus.paid => 'Amount paid',
      PaymentListStatus.toPay when invoice.canPay => 'Amount due',
      PaymentListStatus.processing => 'Payment amount',
      _ => 'Amount',
    };
  }

  List<Widget> _extensionInfo(Map<String, dynamic> e) {
    final rate = e['dayRateCents'];
    return [
      Text('Requested pickup: ${e['pickupDate']} · Return: ${e['returnDate']}'),
      if (rate is int)
        Text(
          '${e['extraDays']} additional day(s) × ${_amount(rate)} per package/day',
          style: staff ? null : _financialDigits,
        ),
    ];
  }

  List<Widget> _appointmentDetails() => [
    if (invoice.appointment case final appointment?) ...[
      _Detail(
        label: 'Appointment',
        value: paymentDateLabel(appointment.startAt),
      ),
      _Detail(
        label: 'Duration',
        value: '${appointment.durationMinutes} minutes',
      ),
    ],
  ];

  List<Widget> _receiptDetails({bool history = false}) => [
    if (invoice.methodLabel case final method?)
      _Detail(label: 'Method', value: method),
    if (invoice.paidAt case final paidAt? when !history)
      _Detail(label: 'Paid on', value: paymentDateLabel(paidAt)),
    if (invoice.invoiceNo case final number? when number.isNotEmpty)
      _Detail(label: 'Receipt no.', value: number),
  ];

  String? get _invoiceContext {
    final title = invoice.title.trim();
    if (title.isEmpty ||
        title.toLowerCase() == invoice.purposeLabel.toLowerCase()) {
      return null;
    }
    // These prefixes are part of the saved invoice titles. Purpose always
    // comes from the structured field, even for older titles.
    final prefix = switch (invoice.purpose) {
      'BookingDeposit' => 'Booking deposit: ',
      'PackageBalance' => 'Remaining balance: ',
      'SecurityDeposit' => 'Refundable gown security deposit: ',
      'RentalExtension' => 'Additional rental days: ',
      'DressPayment' => 'Dress payment: ',
      _ => null,
    };
    if (prefix != null && title.startsWith(prefix)) {
      return title.substring(prefix.length);
    }
    if (invoice.appointment case final visit?
        when invoice.purpose == 'FittingFee') {
      return '${visit.type} · ${visit.durationMinutes} minutes';
    }
    return title;
  }

  Widget _compactCard(
    BuildContext context, {
    required bool paid,
    required bool review,
    required String? detail,
  }) {
    final theme = Theme.of(context);
    final resolution = invoice.reviewResolution;
    final refunded = resolution?['refundCents'];
    final retained = resolution?['retainedCents'];
    final historyNote = resolution != null
        ? 'Your original payment and receipt are kept in your history.'
        : detail;
    final status = paymentListStatus(invoice);
    final urgent =
        resolution == null &&
        (review || (!paid && (invoice.holdExpired || invoice.paymentBlocked)));
    final badgeText = resolution != null
        ? invoice.statusLabel
        : switch (status) {
            PaymentListStatus.review => 'Review required',
            PaymentListStatus.closed =>
              invoice.paymentBlocked ? 'Payment unavailable' : 'Expired',
            _ => invoice.statusLabel,
          };
    final tone = resolution != null
        ? const Color(0xFF4A5C70)
        : switch (status) {
            PaymentListStatus.paid => CustomerUi.success,
            PaymentListStatus.processing ||
            PaymentListStatus.review => CustomerUi.warning,
            PaymentListStatus.closed => theme.colorScheme.onSurfaceVariant,
            _ => CustomerUi.activeText,
          };
    final contextLabel = _invoiceContext;
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasReceipt = onReceipt != null && ReceiptDocument.canRender(invoice);
    final canPay =
        onPay != null && invoice.canPay && !review && resolution == null;
    final canCheck =
        onCheck != null &&
        invoice.hasBill &&
        (!paid || review) &&
        resolution == null;
    final checkFirst =
        canCheck && (invoice.state == 'Pending' || !canPay) && !hasReceipt;
    final primary = hasReceipt
        ? (label: 'View receipt', onTap: onReceipt)
        : checkFirst
        ? (label: 'Check status', onTap: onCheck)
        : canPay
        ? (label: 'Pay now', onTap: onPay)
        : null;
    final second = canPay && checkFirst
        ? (label: 'Pay now', onTap: onPay)
        : canCheck && !checkFirst
        ? (label: 'Check status', onTap: onCheck)
        : null;
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          badgeText,
          style: theme.textTheme.labelMedium?.copyWith(
            color: tone,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    final title = Text(
      invoice.purposeLabel,
      style: theme.textTheme.titleMedium?.copyWith(color: ink, height: 1.3),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: CustomerUi.paper,
        borderRadius: CustomerUi.cardRadius,
        border: Border.all(color: CustomerUi.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, size) =>
                MediaQuery.textScalerOf(context).scale(1) > 1.4 &&
                    size.maxWidth < 500
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 5), badge],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: size.maxWidth * .45,
                        ),
                        child: badge,
                      ),
                    ],
                  ),
          ),
          if (contextLabel != null) ...[
            const SizedBox(height: 3),
            Text(
              contextLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle,
            ),
          ],
          const SizedBox(height: 6),
          _PaymentAmount(
            cents: invoice.amountCents,
            label: _amountCaption(status),
          ),
          PaymentTiming(invoice: invoice, now: now, compact: true),
          if (invoice.state == 'Pending' && checkFirst)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Already paid? Check status to see if your payment was verified.',
                style: bodyStyle,
              ),
            ),
          if (urgent && detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(detail, style: bodyStyle?.copyWith(color: tone)),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          _CompactActions(
            id: invoice.id,
            primary: primary == null
                ? null
                : FilledButton(
                    onPressed: busy ? null : primary.onTap,
                    child: Text(primary.label),
                  ),
            secondary: second == null
                ? null
                : TextButton(
                    onPressed: busy ? null : second.onTap,
                    child: Text(second.label),
                  ),
            details: [
              if (contextLabel != null)
                _Detail(label: 'Invoice', value: invoice.title),
              ..._appointmentDetails(),
              ..._receiptDetails(history: true),
              if (refunded is int && refunded > 0)
                _Detail.money(label: 'Refund recorded', cents: refunded),
              if (retained is int)
                _Detail.money(label: 'Amount retained', cents: retained),
              if (resolution?['recordedAt'] case final int recordedAt
                  when recordedAt > 0 && recordedAt < 4102444800000)
                _Detail(
                  label: 'Review recorded',
                  value: paymentDateLabel(recordedAt),
                ),
              if (invoice.extensionDetails case final e?) ..._extensionInfo(e),
              if (invoice.purpose == 'SecurityDeposit')
                Text(_securityTerms, style: bodyStyle),
              if (historyNote != null &&
                  !urgent &&
                  historyNote != _securityTerms)
                Text(historyNote, style: bodyStyle),
              if (contextLabel == null &&
                  invoice.appointment == null &&
                  invoice.methodLabel == null &&
                  invoice.invoiceNo == null &&
                  historyNote == null)
                _Detail(label: 'Payment for', value: invoice.purposeLabel),
            ],
          ),
        ],
      ),
    );
  }
}

const _financialDigits = TextStyle(
  fontFamily: 'LuvlySans',
  color: ink,
  fontFeatures: [FontFeature.tabularFigures()],
);

final _thousandsGroups = RegExp(r'(\d)(?=(?:\d{3})+$)');

String _ringgit(int cents) {
  final whole = (cents ~/ 100).abs().toString();
  final grouped = whole.replaceAllMapped(
    _thousandsGroups,
    (digit) => '${digit[1]},',
  );
  final fraction = cents.remainder(100).abs().toString().padLeft(2, '0');
  final sign = cents < 0 ? '-' : '';
  return 'RM $sign$grouped.$fraction';
}

class _PaymentAmount extends StatelessWidget {
  const _PaymentAmount({required this.cents, required this.label});
  final int cents;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = _ringgit(cents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: amount.substring(0, 3),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(text: amount.substring(3)),
              ],
            ),
            semanticsLabel: amount,
            maxLines: 1,
            style: _financialDigits.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              height: 1.1,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactActions extends StatefulWidget {
  const _CompactActions({
    required this.id,
    required this.primary,
    required this.secondary,
    required this.details,
  });
  final String id;
  final Widget? primary, secondary;
  final List<Widget> details;

  @override
  State<_CompactActions> createState() => _CompactActionsState();
}

class _CompactActionsState extends State<_CompactActions> {
  final controller = ExpansibleController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Expansible(
    key: PageStorageKey('payment-details-${widget.id}'),
    controller: controller,
    maintainState: false,
    duration: CustomerUi.motion(context, CustomerUi.expansion),
    curve: Curves.easeInOutCubic,
    headerBuilder: (context, _) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: widget.primary == null && widget.secondary == null
              ? WrapAlignment.end
              : WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            ?widget.primary,
            ?widget.secondary,
            Semantics(
              label: 'Payment details',
              expanded: controller.isExpanded,
              child: TextButton(
                onPressed: () => controller.isExpanded
                    ? controller.collapse()
                    : controller.expand(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(child: Text('Details')),
                    const SizedBox(width: 3),
                    Icon(
                      controller.isExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    bodyBuilder: (context, _) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 10, color: line),
          ...widget.details,
        ],
      ),
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value}) : monetary = false;
  _Detail.money({required this.label, required int cents})
    : value = _ringgit(cents),
      monetary = true;
  final String label, value;
  final bool monetary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            style: monetary
                ? Theme.of(context).textTheme.bodySmall?.merge(_financialDigits)
                : Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
