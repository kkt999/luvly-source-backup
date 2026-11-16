import 'package:flutter/material.dart';
import 'payment_api.dart';

/// Calendar-based pickup deadlines and actual expiring reservation holds are
/// different concepts. This widget never changes payment eligibility/status.
class PaymentTiming extends StatelessWidget {
  const PaymentTiming({
    super.key,
    required this.invoice,
    this.now,
    this.compact = false,
  });
  final SandboxInvoice invoice;
  final DateTime? now;
  final bool compact;

  Widget _recordedDate(BuildContext context) {
    final paidAt = invoice.state == 'SandboxPaid' && _validDate(invoice.paidAt)
        ? invoice.paidAt
        : null;
    final instant = paidAt ?? invoice.createdAt;
    if (!_validDate(instant)) return const SizedBox.shrink();
    final date = paymentDateLabel(instant!);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Semantics(
        label: paidAt == null ? 'Issued on $date' : 'Paid on $date',
        excludeSemantics: true,
        child: Text(
          paidAt == null ? 'Issued · $date' : date,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  bool _validDate(int? value) =>
      value != null && value > 0 && value < 4102444800000;
  @override
  Widget build(BuildContext context) {
    final paid = invoice.state == 'SandboxPaid';
    if (compact && paid) return _recordedDate(context);
    if (invoice.reviewReason != null ||
        invoice.state == 'ReviewRequired' ||
        invoice.paymentBlocked) {
      return compact ? _recordedDate(context) : const SizedBox.shrink();
    }
    final instant = (now ?? DateTime.now()).toUtc();
    String title, value;
    String? extra;
    bool warning = false;
    IconData icon = Icons.event_outlined;
    if (paid) {
      final timestamp = invoice.paidAt;
      if (!_validDate(timestamp)) return const SizedBox.shrink();
      title = 'Paid on';
      value = paymentDateLabel(timestamp!);
      icon = Icons.check_circle_outline;
    } else if (invoice.holdExpiresAt != null) {
      final expiry = invoice.holdExpiresAt!;
      if (!_validDate(expiry)) {
        return compact ? _recordedDate(context) : const SizedBox.shrink();
      }
      final seconds = ((expiry - instant.millisecondsSinceEpoch) / 1000).ceil();
      title = switch (invoice.purpose) {
        'FittingFee' => 'Fitting payment deadline',
        'BookingDeposit' => 'Reservation payment deadline',
        'RentalExtension' => 'Date-change payment deadline',
        _ => 'Payment link expiry',
      };
      value = paymentDateLabel(expiry);
      extra = seconds <= 0
          ? compact
                ? null
                : 'Payment window ended · check status if you paid'
          : 'Time left · ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      warning = seconds <= 900;
      icon = Icons.schedule_outlined;
    } else if ([
      'PackageBalance',
      'SecurityDeposit',
    ].contains(invoice.purpose)) {
      title = 'Payment due';
      final due = parsePickupDueDate({
        'kind': 'BeforePickup',
        'date': invoice.pickupDueDate,
      });
      if (due == null) {
        value = 'Before pickup';
        extra = 'See your agreed pickup date in My packages.';
      } else {
        final day = DateTime.parse('${due}T00:00:00Z');
        final local = instant.add(const Duration(hours: 8));
        final days = day
            .difference(DateTime.utc(local.year, local.month, local.day))
            .inDays;
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
        value =
            'Before pickup · ${day.day} ${months[day.month - 1]} ${day.year}';
        warning = days <= 3;
        if (days == 0) extra = 'Please pay before collecting your items today.';
        if (days < 0) extra = 'Pickup date has passed. Contact our team.';
      }
    } else {
      return compact ? _recordedDate(context) : const SizedBox.shrink();
    }
    final colour = paid
        ? const Color(0xFF386953)
        : warning
        ? const Color(0xFF8B591C)
        : const Color(0xFF783A4C);
    if (compact) {
      return Padding(
        key: const Key('payment-timing'),
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title · $value',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colour,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (extra != null)
              Text(
                extra,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colour),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        key: const Key('payment-timing'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paid
              ? const Color(0xFFEEF5F0)
              : warning
              ? const Color(0xFFFAF0E2)
              : const Color(0xFFF7EEF0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 19, color: colour),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colour,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colour,
                    ),
                  ),
                  if (extra != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        extra,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: colour,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
