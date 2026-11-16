import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'package_api.dart';
import 'rental_workspace.dart';
import 'fitting_proposal_screen.dart' show fittingDecisionLabel;

const alterationStages = {
  'NotAssessed': 'Not assessed',
  'NotRequired': 'No alteration needed',
  'Pending': 'Alteration required',
  'InProgress': 'Alteration in progress',
  'Completed': 'Alteration completed',
};
const preparationStages = {
  'NotStarted': 'Not started',
  'Preparing': 'Preparing items',
  'Ready': 'Items prepared',
};

/// Internal preparation only. Never substitutes for verified payment, fitting
/// attendance, inventory reservation, handover or return inspection.
class RentalServiceProgressPanel extends StatelessWidget {
  const RentalServiceProgressPanel({
    super.key,
    required this.selection,
    this.onEdit,
    this.onAppointment,
  });
  final PackageSelection selection;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onAppointment;
  @override
  Widget build(BuildContext context) {
    final progress = selection.data['serviceProgress'] as Map?;
    final decision = selection.data['fittingDecision'] as Map?;
    final String fitting;
    if (selection.data['fittingWorkflowVersion'] == 2) {
      fitting = fittingDecisionLabel(decision);
    } else if (decision?['state'] == 'Approved') {
      fitting = decision?['mode'] == 'Waived'
          ? 'No-fitting request approved'
          : 'Fitting completed · satisfied';
    } else {
      fitting = decision == null
          ? 'Fitting outcome not recorded'
          : 'Fitting needs follow-up';
    }
    Widget step(IconData icon, String title, String status) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: rentalRose),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: rentalMuted),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('rental-service-progress'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8FA),
        border: Border.all(color: rentalLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service progress',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          step(Icons.fact_check_outlined, 'Fitting', fitting),
          step(
            Icons.content_cut,
            'Alterations',
            progress == null
                ? 'Not assessed'
                : alterationStages[progress['alteration']] ??
                      'Refresh to check status',
          ),
          step(
            Icons.checkroom_outlined,
            'Gown & accessory preparation',
            progress == null
                ? 'Not started'
                : preparationStages[progress['preparation']] ??
                      'Refresh to check status',
          ),
          if (progress?['note'] is String &&
              (progress!['note'] as String).isNotEmpty) ...[
            const Divider(height: 20),
            const Text(
              'Staff notes',
              style: TextStyle(fontSize: 11, color: rentalMuted),
            ),
            const SizedBox(height: 4),
            Text(progress['note'], style: const TextStyle(fontSize: 12)),
            if (progress['byName'] is String)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Updated by ${progress['byName']}',
                  style: const TextStyle(fontSize: 11, color: rentalMuted),
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (onEdit != null)
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Update preparation'),
            ),
          for (final visit in selection.appointments)
            if (onAppointment != null && visit['id'] is String)
              TextButton.icon(
                onPressed: () => onAppointment!(visit['id']),
                icon: const Icon(Icons.calendar_month_outlined, size: 16),
                label: Text('Open ${visit['type'] ?? 'linked appointment'}'),
              ),
        ],
      ),
    );
  }
}

Future<bool?> editRentalServiceProgress(
  BuildContext context, {
  required PackageSelection selection,
  required Future<void> Function(Map<String, dynamic>) save,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ProgressEditor(selection: selection, save: save),
);

class _ProgressEditor extends StatefulWidget {
  const _ProgressEditor({required this.selection, required this.save});
  final PackageSelection selection;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<_ProgressEditor> createState() => _ProgressEditorState();
}

class _ProgressEditorState extends State<_ProgressEditor> {
  late final progress = widget.selection.data['serviceProgress'] as Map?;
  late String alteration = alterationStages.containsKey(progress?['alteration'])
      ? progress!['alteration']
      : 'NotAssessed';
  late String preparation =
      preparationStages.containsKey(progress?['preparation'])
      ? progress!['preparation']
      : 'NotStarted';
  late final note = TextEditingController(
    text: progress?['note'] as String? ?? '',
  );
  final form = GlobalKey<FormState>();
  final requestId = packageRequestId();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || error != null || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.save({
        'requestId': requestId,
        'revision':
            progress?['revision'] ??
            widget.selection.data['serviceProgressRevision'] ??
            0,
        'alteration': alteration,
        'preparation': preparation,
        'note': note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save. Close and refresh the rental before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Update service preparation'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.selection.customer} · ${widget.selection.name}'),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: alteration,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Alteration status',
                  ),
                  items: alterationStages.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy || error != null
                      ? null
                      : (v) => setState(() => alteration = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: preparation,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Preparation status',
                  ),
                  items: preparationStages.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy || error != null
                      ? null
                      : (v) => setState(() => preparation = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: note,
                  enabled: !busy && error == null,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 700,
                  decoration: const InputDecoration(labelText: 'Staff notes'),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Add a preparation note.'
                      : null,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Preparation does not confirm payment or record collection. Fitting results are recorded separately.',
                  style: TextStyle(fontSize: 12, color: rentalMuted),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      '$error\nClose to refresh this rental before continuing.',
                      style: const TextStyle(color: rentalRose),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: busy || error != null ? null : submit,
          child: Text(busy ? 'Saving…' : 'Save preparation'),
        ),
      ],
    ),
  );
}
