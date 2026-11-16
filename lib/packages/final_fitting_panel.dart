import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'package_api.dart';

class FinalFittingPanel extends StatefulWidget {
  const FinalFittingPanel({
    super.key,
    required this.selection,
    required this.api,
    required this.onSaved,
  });
  final PackageSelection selection;
  final HttpPackageApi api;
  final VoidCallback onSaved;
  @override
  State<FinalFittingPanel> createState() => _FinalFittingPanelState();
}

class _FinalFittingPanelState extends State<FinalFittingPanel> {
  String? appointmentId, error;
  final note = TextEditingController();
  final requestId = packageRequestId();
  bool confirmed = false, busy = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy ||
        error != null ||
        appointmentId == null ||
        !confirmed ||
        note.text.trim().length < 10) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.api.transport.businessRequest(
        '/v1/package-selections/${widget.selection.id}/final-fitting',
        body: {
          'requestId': requestId,
          'rentalId': widget.selection.data['rentalId'],
          'appointmentId': appointmentId,
          'confirmed': true,
          'note': note.text.trim(),
        },
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save. Refresh this rental before continuing.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.selection.data['rental'] as Map?,
        p = widget.selection.data['serviceProgress'] as Map?;
    if (r?['fittingQuote']?['adjustmentPlan']?['followUp'] != 'Required') {
      return const SizedBox.shrink();
    }
    final done =
        r?['finalFitting']?['state'] == 'Completed' &&
        p?['alteration'] == 'Completed' &&
        r?['finalFitting']?['alterationVersion'] ==
            (p?['alterationVersion'] ?? p?['revision']);
    final visits = widget.selection.appointments
        .where(
          (b) =>
              b['id'] != r?['appointmentId'] &&
              b['type'] == 'Dress Trial' &&
              b['feeIncluded'] == true &&
              ['Confirmed', 'Completed'].contains(b['status']),
        )
        .toList();
    final editable =
        r?['state'] == 'Locked' &&
        r?['collectedAt'] == null &&
        r?['returnedAt'] == null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Final fitting',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              done
                  ? 'Final fit checked and accepted at the attended visit.'
                  : 'A final fitting is required before collection.',
            ),
            if (done && r?['finalFitting']?['note'] is String)
              Text(r!['finalFitting']['note']),
            if (!done && editable) ...[
              const SizedBox(height: 12),
              if (visits.isEmpty)
                const Text(
                  'Ask the customer to book a linked Dress Trial in My packages. Post-booking fittings are included; no new RM50 fee is issued.',
                ),
              if (visits.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: appointmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Follow-up visit',
                  ),
                  items: visits
                      .map(
                        (b) => DropdownMenuItem<String>(
                          value: b['id'],
                          child: Text(
                            paymentDateLabel(
                              b['scheduledStartAt'] ?? b['startAt'],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy || error != null
                      ? null
                      : (v) => setState(() => appointmentId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                enabled: !busy && error == null,
                maxLength: 700,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Fit check notes'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: busy || error != null
                    ? null
                    : (v) => setState(() => confirmed = v == true),
                title: const Text(
                  'The customer attended, checked the altered gown and accepted the fit.',
                ),
              ),
              if (p?['alteration'] != 'Completed')
                const Text(
                  'Complete the agreed alterations before recording the final fitting.',
                ),
              FilledButton(
                onPressed:
                    busy ||
                        error != null ||
                        appointmentId == null ||
                        !confirmed ||
                        note.text.trim().length < 10 ||
                        p?['alteration'] != 'Completed'
                    ? null
                    : save,
                child: Text(busy ? 'Saving…' : 'Record final fitting'),
              ),
            ],
            if (error != null)
              Text(
                '$error\nClose and refresh the rental before continuing.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
