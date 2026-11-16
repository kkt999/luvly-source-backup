import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'package_api.dart' show packageMoney;
import 'rental_date_change_screen.dart';
import 'rental_extension_status.dart';

/// Operational records, not a bank-refund API. Server validates every action.
class RentalHandoverScreen extends StatefulWidget {
  const RentalHandoverScreen({
    super.key,
    required this.rental,
    required this.api,
    this.manager = false,
  });
  final Map<String, dynamic> rental;
  final HttpPaymentApi api;
  final bool manager;
  @override
  State<RentalHandoverScreen> createState() => _RentalHandoverState();
}

class _RentalHandoverState extends State<RentalHandoverScreen> {
  late Map<String, dynamic> rental = widget.rental;
  final damage = TextEditingController(text: '0.00'),
      lateFee = TextEditingController(text: '0.00'),
      reason = TextEditingController(),
      reference = TextEditingController();
  bool busy = false, allReturned = false;
  String? error;
  int? amount(String value) =>
      RegExp(r'^0(?:\.0{1,2})?$').hasMatch(value.trim())
      ? 0
      : quoteAmountCents(value);
  @override
  void dispose() {
    for (final c in [damage, lateFee, reason, reference]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> act(String action) async {
    if (busy) return;
    final body = <String, dynamic>{'action': action};
    if (action == 'return') {
      final d = amount(damage.text), l = amount(lateFee.text);
      if (!allReturned ||
          d == null ||
          l == null ||
          d + l > (rental['securityCents'] as int) ||
          (d + l > 0 && reason.text.trim().length < 5)) {
        setState(
          () => error =
              'Confirm every item was returned. Enter valid deductions within the security amount, with a clear reason.',
        );
        return;
      }
      body.addAll({
        'damageCents': d,
        'lateCents': l,
        'allReturned': true,
        'reason': reason.text.trim(),
      });
    }
    if (action == 'record-refund') body['reference'] = reference.text.trim();
    if (action == 'report-return-issue') {
      if (reason.text.trim().length < 10) {
        setState(
          () => error =
              'Describe the missing items or inspection issue in at least 10 characters.',
        );
        return;
      }
      body['reason'] = reason.text.trim();
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          action == 'collect'
              ? 'Confirm handover?'
              : action == 'return'
              ? 'Save return inspection?'
              : action == 'report-return-issue'
              ? 'Record a return issue?'
              : 'Record security refund?',
        ),
        content: Text(
          action == 'collect'
              ? 'Confirm that you are handing the listed items to this customer. The server will check the pickup date and both payments.'
              : action == 'return'
              ? 'The inspection and any deductions will be saved to the customer record. Only save after all items have been checked.'
              : action == 'report-return-issue'
              ? 'This records an issue for manager review. It does not mark items returned, release stock, deduct security or charge the customer.'
              : 'Record only after the refund has been arranged and verified. This action records the refund; it does not issue a transfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await widget.api.businessRequest(
        '/v1/rentals/${rental['id']}/fulfil',
        body: body,
      );
      if (mounted) setState(() => rental = Map<String, dynamic>.from(next));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save. Refresh the package and check its status before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = rental['securityCents'] as int;
    final estimate =
        security - (amount(damage.text) ?? 0) - (amount(lateFee.text) ?? 0);
    final localNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today =
        '${localNow.year}-${localNow.month.toString().padLeft(2, '0')}-${localNow.day.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Pickup, return & security')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Rental handover',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'Pickup ${rental['pickupDate']} · Return ${rental['returnDate']}',
              ),
              for (final g in rental['gowns'] as List)
                ListTile(
                  leading: const Icon(Icons.checkroom),
                  title: Text('${g['name']} · ${g['size']}'),
                ),
              for (final a in rental['accessories'] as List? ?? [])
                ListTile(
                  leading: const Icon(Icons.diamond_outlined),
                  title: Text(a['name']),
                ),
              Text(
                'Package balance: ${packageMoney(rental['balanceCents'])} · ${rental['paymentState']}',
              ),
              Text(
                'Separate security: ${packageMoney(security)} · ${rental['securityState']}',
              ),
              const SizedBox(height: 16),
              RentalExtensionStatus(
                rental: rental,
                api: widget.api,
                staff: true,
                onChanged: (next) => setState(() => rental = next),
              ),
              if (rental['collectedAt'] == null) ...[
                const Text(
                  'Collection must match the agreed pickup date, after verified balance and security payments. For early pickup, adjust the reservation first so stock and rental days are checked.',
                ),
                if (rental['packageSelectionId'] != null)
                  OutlinedButton.icon(
                    onPressed:
                        busy ||
                            (rental['pendingExtension']?['expiresAt'] as int? ??
                                    0) >
                                DateTime.now().millisecondsSinceEpoch
                        ? null
                        : () async {
                            final next =
                                await Navigator.push<Map<String, dynamic>>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RentalDateChangeScreen(
                                      rental: rental,
                                      api: widget.api,
                                    ),
                                  ),
                                );
                            if (next != null && mounted) {
                              setState(() {
                                rental = next;
                                error = null;
                              });
                            }
                          },
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Adjust pickup & return dates'),
                  ),
                FilledButton(
                  onPressed:
                      busy ||
                          today != rental['pickupDate'] ||
                          (rental['pendingExtension']?['expiresAt'] as int? ??
                                  0) >
                              DateTime.now().millisecondsSinceEpoch
                      ? null
                      : () => act('collect'),
                  child: const Text('Confirm items collected'),
                ),
                if (today != rental['pickupDate'])
                  Text(
                    'Collection is scheduled for ${rental['pickupDate']}. Adjust the agreed dates first if the customer needs an earlier pickup.',
                  ),
              ] else if (rental['returnedAt'] == null) ...[
                Text(
                  'Return inspection',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allReturned,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => allReturned = v ?? false),
                  title: const Text(
                    'All listed gowns and accessories returned and inspected',
                  ),
                ),
                TextField(
                  controller: damage,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Agreed damage deduction (RM)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lateFee,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Agreed late-return deduction (RM)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  enabled: !busy,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Inspection notes / reason for each deduction',
                  ),
                ),
                const Text(
                  'No automatic penalties. Use only deductions already agreed with the customer, supported by this inspection. Missing items or charges above security require separate review; do not mark all items returned.',
                ),
                Text(
                  'Security refund after deductions: ${packageMoney(estimate)}',
                ),
                if (rental['returnIssue']?['state'] == 'Open')
                  Text(
                    'Return issue awaiting review: ${rental['returnIssue']['note']}',
                  ),
                OutlinedButton(
                  onPressed: busy ? null : () => act('report-return-issue'),
                  child: const Text('Record return issue for review'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => act('return'),
                  child: const Text('Save inspection'),
                ),
              ] else ...[
                Text(
                  'Return inspected · damage ${packageMoney(rental['damageCents'])} · late return ${packageMoney(rental['lateCents'])}',
                ),
                Text(rental['inspectionNote'] as String? ?? ''),
                Text(
                  'Security refund due: ${packageMoney(rental['refundDueCents'])}',
                ),
                Text('Refund status: ${rental['securityState']}'),
                if (widget.manager &&
                    rental['securityState'] == 'RefundDue') ...[
                  const Text(
                    'Record the verified refund reference after arranging the refund. Saving this record does not issue a bank transfer.',
                  ),
                  TextField(
                    controller: reference,
                    enabled: !busy,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Refund reference',
                    ),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => act('record-refund'),
                    child: const Text('Record refund reconciliation'),
                  ),
                ],
                if (rental['refundReference'] != null)
                  Text('Refund reference: ${rental['refundReference']}'),
              ],
              if ((rental['dateChangeHistory'] as List? ?? []).isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Rental date history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final change
                    in (rental['dateChangeHistory'] as List).reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${change['before']['pickupDate']} → ${change['before']['returnDate']}  /  ${change['after']['pickupDate']} → ${change['after']['returnDate']}',
                    ),
                    subtitle: Text(change['reason'] ?? ''),
                  ),
              ],
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
