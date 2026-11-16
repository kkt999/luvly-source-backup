import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import '../payments/payment_screen.dart';
import 'package_api.dart' show packageMoney;

class RentalExtensionStatus extends StatelessWidget {
  const RentalExtensionStatus({
    super.key,
    required this.rental,
    required this.api,
    required this.staff,
    required this.onChanged,
    this.now,
  });
  final Map<String, dynamic> rental;
  final HttpPaymentApi api;
  final DateTime Function()? now;
  final bool staff;
  final void Function(Map<String, dynamic>) onChanged;
  Future<void> refresh(BuildContext context) async {
    try {
      final next = await api.businessRequest('/v1/rentals/${rental['id']}');
      onChanged(Map<String, dynamic>.from(next));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PaymentFailure ? e.message : 'Could not refresh the rental.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = rental['pendingExtension'] as Map?,
        paid = rental['extensionPaidCents'] as int? ?? 0;
    if (pending == null &&
        paid == 0 &&
        rental['lastExtensionOutcome'] == null) {
      return const SizedBox.shrink();
    }
    final expired =
        pending != null &&
        (pending['expiresAt'] as int) <=
            (now?.call() ?? DateTime.now()).millisecondsSinceEpoch;
    return Card(
      elevation: 0,
      color: const Color(0xFFFCF6F7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8DFDC)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rental date changes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (paid > 0)
              Text(
                'Additional rental days paid: ${packageMoney(paid)} · original package price unchanged',
              ),
            if (pending != null) ...[
              const SizedBox(height: 8),
              Text(
                expired
                    ? 'Extension payment hold ended'
                    : 'Extension awaiting payment · ${packageMoney(pending['amountCents'])}',
              ),
              Text(
                'Requested pickup ${pending['pickupDate']} · Return ${pending['returnDate']}',
              ),
              Text(
                'Current dates remain ${rental['pickupDate']} to ${rental['returnDate']} until payment is verified.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LivePaymentsScreen(
                              staff: staff,
                              initialInvoiceId: pending['invoiceId'],
                            ),
                          ),
                        ).then((_) {
                          if (context.mounted) refresh(context);
                        }),
                    child: Text(
                      staff
                          ? 'View extension invoice'
                          : 'Review extension payment',
                    ),
                  ),
                  if (staff)
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Cancel pending extension?'),
                            content: const Text(
                              'The original rental remains reserved. Only the extra date hold is released. Any payment already submitted needs a status check and possible staff refund review.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Keep request'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Cancel extension'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true || !context.mounted) return;
                        try {
                          final next = await api.businessRequest(
                            '/v1/rentals/${rental['id']}/cancel-extension',
                            body: {'extensionId': pending['id']},
                          );
                          onChanged(Map<String, dynamic>.from(next));
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is PaymentFailure
                                      ? e.message
                                      : 'Could not cancel. Refresh first.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('Cancel pending extension'),
                    ),
                ],
              ),
            ] else if ([
              'Expired',
              'Cancelled',
              'PaymentReview',
            ].contains(rental['lastExtensionOutcome']))
              Text(
                rental['lastExtensionOutcome'] == 'PaymentReview'
                    ? 'The extension payment needs staff review; the requested dates were not applied. Do not pay again.'
                    : 'The last extension request ended without changing the rental dates.',
              ),
            TextButton.icon(
              onPressed: () => refresh(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh rental status'),
            ),
          ],
        ),
      ),
    );
  }
}
