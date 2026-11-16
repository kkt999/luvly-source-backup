import 'package:flutter/material.dart';
import 'payment_api.dart';
import '../packages/package_api.dart' show packageRequestId, packageMoney;

Future<bool?> showPaymentReview(
  BuildContext context,
  SandboxInvoice invoice,
  HttpPaymentApi api,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _Review(invoice: invoice, api: api),
);

class _Review extends StatefulWidget {
  const _Review({required this.invoice, required this.api});
  final SandboxInvoice invoice;
  final HttpPaymentApi api;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  final amount = TextEditingController(text: '0.00'),
      reason = TextEditingController(),
      reference = TextEditingController();
  final requestId = packageRequestId();
  bool confirmed = false, busy = false;
  String? error;
  int? get cents =>
      RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(amount.text.trim())
      ? (double.parse(amount.text.trim()) * 100).round()
      : null;
  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || error != null) return;
    setState(() => busy = true);
    try {
      await widget.api.businessRequest(
        '/v1/invoices/${widget.invoice.id}/resolve-review',
        body: {
          'requestId': requestId,
          'refundCents': cents,
          'reason': reason.text.trim(),
          'reference': cents == 0 ? '' : reference.text.trim(),
          'confirmed': confirmed,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save. Close and refresh before continuing.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refund = cents,
        valid =
            refund != null &&
            refund >= 0 &&
            refund <= widget.invoice.amountCents;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Close payment review'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.invoice.title}\nVerified payment: ${widget.invoice.amountLabel}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Record the approved outcome after reviewing the agreed cancellation terms. For a refund, arrange it separately and enter its verified reference. This action does not transfer money.',
                ),
                TextField(
                  controller: amount,
                  enabled: !busy && error == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Refund recorded (RM; 0 if retaining the fee)',
                  ),
                ),
                if (valid)
                  Text(
                    'Amount retained: ${packageMoney(widget.invoice.amountCents - refund)}',
                  ),
                TextField(
                  controller: reason,
                  enabled: !busy && error == null,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 700,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText:
                        'Decision and agreed policy / customer discussion',
                  ),
                ),
                if (refund != null && refund > 0)
                  TextField(
                    controller: reference,
                    enabled: !busy && error == null,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Verified refund reference',
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: busy || error != null
                      ? null
                      : (v) => setState(() => confirmed = v == true),
                  title: const Text(
                    'I verified this outcome and any refund reference.',
                  ),
                ),
                if (error != null)
                  Text(
                    '$error\nClose and refresh before continuing.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed:
                busy ||
                    error != null ||
                    !valid ||
                    !confirmed ||
                    reason.text.trim().length < 10 ||
                    refund > 0 && reference.text.trim().length < 5
                ? null
                : save,
            child: Text(busy ? 'Saving…' : 'Save reviewed outcome'),
          ),
        ],
      ),
    );
  }
}
