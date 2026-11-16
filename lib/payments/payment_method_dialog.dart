import 'package:flutter/material.dart';
import 'payment_api.dart';

class PaymentMethodDialog extends StatefulWidget {
  const PaymentMethodDialog({super.key, required this.invoice});
  final SandboxInvoice invoice;
  @override
  State<PaymentMethodDialog> createState() => _MethodState();
}

class _MethodState extends State<PaymentMethodDialog> {
  bool selected = false;
  bool extensionAccepted = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: const Color(0xFF332B2D),
    ),
    title: const Text('Confirm payment'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.invoice.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.invoice.amountLabel,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (widget.invoice.extensionDetails case final e?) ...[
              const SizedBox(height: 12),
              Text(
                'Requested pickup: ${e['pickupDate']} · Return: ${e['returnDate']}',
              ),
              Text(
                '${e['extraDays']} additional day(s) × RM ${(e['dayRateCents'] / 100).toStringAsFixed(2)} per package/day',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: extensionAccepted,
                onChanged: (v) => setState(() => extensionAccepted = v == true),
                title: const Text(
                  'I agree to these dates and the additional fee. The original rental dates remain until payment is verified.',
                ),
              ),
              const Text(
                'If dates are later shortened or cancelled, any refund requires staff review; it is not automatic.',
              ),
            ],
            const Divider(height: 28),
            Text(
              'Choose payment method',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('FPX online banking'),
              subtitle: const Text('Choose your bank securely on ToyyibPay.'),
              trailing: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => setState(() => selected = true),
            ),
            const SizedBox(height: 12),
            const Text(
              'Test checkout with ToyyibPay. No money will be charged.',
            ),
            if (widget.invoice.holdExpiresAt != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Pay before the deadline to keep your booking.'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            !selected ||
                widget.invoice.holdExpired ||
                (widget.invoice.purpose == 'RentalExtension' &&
                    !extensionAccepted)
            ? null
            : () => Navigator.pop(context, 'FPX'),
        child: const Text('Continue'),
      ),
    ],
  );
}
