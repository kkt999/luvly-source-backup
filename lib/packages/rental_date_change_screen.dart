import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'package_api.dart' show packageRequestId, packageMoney;

/// Staff amendment of a real rental; never changes payment amounts or event date.
class RentalDateChangeScreen extends StatefulWidget {
  const RentalDateChangeScreen({
    super.key,
    required this.rental,
    required this.api,
    this.now,
  });
  final Map<String, dynamic> rental;
  final HttpPaymentApi api;

  /// Injectable clock for deterministic date-boundary and layout checks.
  final DateTime Function()? now;
  @override
  State<RentalDateChangeScreen> createState() => _RentalDateChangeState();
}

class _RentalDateChangeState extends State<RentalDateChangeScreen> {
  late String pickup = widget.rental['pickupDate'],
      returned = widget.rental['returnDate'];
  late final requestId = packageRequestId();
  final reason = TextEditingController();
  Map<String, dynamic>? preview;
  bool busy = false, agreed = false, frozen = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void changed() {
    setState(() {
      preview = null;
      agreed = false;
      error = null;
    });
  }

  Future<void> pick(bool isPickup) async {
    final now = (widget.now?.call() ?? DateTime.now()).toUtc().add(
      const Duration(hours: 8),
    );
    final today = DateTime(now.year, now.month, now.day),
        event = DateTime.parse(widget.rental['eventDate']);
    final first = isPickup ? today : event,
        last = isPickup
            ? event
            : DateTime.parse(pickup).add(const Duration(days: 30));
    if (first.isAfter(last)) {
      setState(
        () => error =
            'Review the rental dates with the customer. The event date cannot be changed here.',
      );
      return;
    }
    var initial = DateTime.parse(isPickup ? pickup : returned);
    if (initial.isBefore(first) || initial.isAfter(last)) initial = first;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date == null || !mounted) return;
    final value =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    setState(() {
      if (isPickup) {
        pickup = value;
      } else {
        returned = value;
      }
      preview = null;
      agreed = false;
      error = null;
    });
  }

  Future<void> submit(bool previewOnly) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    if (reason.text.trim().length < 10) {
      setState(
        () => error =
            'Add a clear reason and customer discussion note (at least 10 characters).',
      );
      return;
    }
    if (!previewOnly && (!agreed || preview?['canConfirm'] != true)) return;
    setState(() {
      busy = true;
      error = null;
      if (previewOnly) preview = null;
      if (!previewOnly) frozen = true;
    });
    try {
      final result = await widget.api.businessRequest(
        '/v1/rentals/${widget.rental['id']}/change-dates',
        body: {
          'requestId': requestId,
          'revision': widget.rental['dateRevision'] ?? 0,
          'pickupDate': pickup,
          'returnDate': returned,
          'reason': reason.text.trim(),
          'customerAgreed': agreed,
          'previewOnly': previewOnly,
          if (!previewOnly && preview?['requiresPayment'] == true) ...{
            'quoteRateCents': preview!['dayRateCents'],
            'quotePackageRevision': preview!['quotePackageRevision'],
          },
        },
      );
      if (!mounted) return;
      if (previewOnly) {
        setState(() => preview = Map<String, dynamic>.from(result));
      } else {
        Navigator.pop(context, Map<String, dynamic>.from(result));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not check or save dates. Reload the rental before changing this request.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Adjust pickup & return dates')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Agree on a new rental period',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('Current pickup: ${widget.rental['pickupDate']}'),
            Text('Current return: ${widget.rental['returnDate']}'),
            Text('Wedding / event: ${widget.rental['eventDate']} (unchanged)'),
            const SizedBox(height: 16),
            const Text(
              'Early pickup is possible only after the full new period passes stock and fitting checks. The event date, paid invoices and package price are not changed by this action.',
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('New pickup date'),
              subtitle: Text(pickup),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy || frozen ? null : () => pick(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('New return date'),
              subtitle: Text(returned),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy || frozen ? null : () => pick(false),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              enabled: !busy && !frozen,
              minLines: 2,
              maxLines: 4,
              maxLength: 700,
              decoration: const InputDecoration(
                labelText: 'Reason / customer discussion notes',
              ),
              onChanged: (_) => changed(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy || frozen ? null : () => submit(true),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Check dates & availability'),
            ),
            if (preview != null) ...[
              const SizedBox(height: 16),
              Card(
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
                        preview!['canConfirm'] == true
                            ? 'Dates and stock checked'
                            : 'Additional rental days need review',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'New rental: ${preview!['rentalDays']} calendar days · Included / purchased: ${preview!['allowedRentalDays']} days',
                      ),
                      if (preview!['canConfirm'] == true) ...[
                        if (preview!['requiresPayment'] == true) ...[
                          Text(
                            '${preview!['extraDaysRequired']} additional day(s) × ${packageMoney(preview!['dayRateCents'])} per package/day',
                          ),
                          Text(
                            'Additional payment: ${packageMoney(preview!['additionalChargeCents'])}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'Create a separate invoice with a 15-minute stock hold. The customer must agree and pay; only verified payment changes the rental dates. Original dates and receipts stay unchanged until then.',
                          ),
                        ] else
                          const Text(
                            'Additional charge: RM0.00 · all existing invoices remain unchanged.',
                          ),
                        Text(
                          'Available again after cleaning: ${preview!['availableAgain']}',
                        ),
                        const Text(
                          'Availability will be checked again when you save.',
                        ),
                      ] else ...[
                        Text(
                          '${preview!['extraDaysRequired']} extra day(s) beyond the purchased rental period.',
                        ),
                        const Text(
                          'No extra fee has been quoted or charged. This amendment cannot be saved. Choose dates within the purchased period or arrange a separate priced extension with the team.',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (preview!['canConfirm'] == true) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: agreed,
                  onChanged: busy || frozen
                      ? null
                      : (v) => setState(() => agreed = v == true),
                  title: const Text(
                    'The customer agreed to these exact pickup and return dates. I have recorded their agreement above.',
                  ),
                ),
                FilledButton(
                  onPressed: busy || !agreed ? null : () => submit(false),
                  child: Text(
                    busy
                        ? 'Saving…'
                        : preview!['requiresPayment'] == true
                        ? 'Create extension invoice & hold'
                        : 'Confirm agreed date change',
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            const Text(
              'This changes the reservation only. Record actual collection separately on the newly agreed pickup date, after all required payments are verified.',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
