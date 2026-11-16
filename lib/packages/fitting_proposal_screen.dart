import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import '../support/assistant_launcher.dart';
import 'package_api.dart';
import 'package_screen.dart' show PackageChoiceScreen;
import 'fitting_assessment.dart';
import 'fitting_gown_change.dart';

const fittingDecisionLabels = {
  'QuoteNeeded': 'Chosen gown · prepare proposal',
  'AwaitingCustomer': 'Awaiting customer confirmation',
  'Reselect': 'Customer wants another gown',
  'AwaitingReview': 'Selection awaiting team review',
  'Considering': 'Customer is considering',
  'Declined': 'Not proceeding with a booking',
  'ChangesRequested': 'Customer requested changes',
  'Approved': 'Selection agreed',
  'NeedsChanges': 'Review gown selection',
};
String fittingDecisionLabel(Map? decision) =>
    fittingDecisionLabels[decision?['state']] ?? 'Fitting outcome not recorded';

class FittingProposalPanel extends StatefulWidget {
  const FittingProposalPanel({
    super.key,
    required this.selection,
    required this.api,
    required this.staff,
    required this.manager,
    required this.reload,
  });
  final PackageSelection selection;
  final HttpPackageApi api;
  final bool staff, manager;
  final VoidCallback reload;
  @override
  State<FittingProposalPanel> createState() => _FittingProposalPanelState();
}

class _FittingProposalPanelState extends State<FittingProposalPanel> {
  bool busy = false, uncertain = false;
  String? error;
  Future<void> send(String route, Map<String, dynamic> body) async {
    if (busy || uncertain) return;
    setState(() => busy = true);
    try {
      await widget.api.transport.businessRequest(
        '/v1/package-selections/${widget.selection.id}/$route',
        body: body,
      );
      widget.reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is PaymentFailure
              ? e.message
              : 'Could not save. Refresh this plan before trying again.';
          uncertain = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit({bool switchPackage = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final p = (await widget.api.catalogue())
          .where(
            (p) =>
                p.active &&
                (switchPackage
                    ? p.includedGownCount > 0 &&
                          p.id != widget.selection.data['packageId']
                    : p.id == widget.selection.data['packageId']),
          )
          .toList();
      if (!mounted) return;
      if (p.isEmpty) {
        throw const PaymentFailure(
          'This package is no longer available. Contact Luvly to discuss an alternative.',
        );
      }
      BridalPackage? chosen = p.first;
      if (switchPackage) {
        chosen = await showDialog<BridalPackage>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Choose another package'),
            children: [
              for (final option in p)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, option),
                  child: Text(
                    '${option.name} · ${packageMoney(option.basePriceCents)}',
                  ),
                ),
            ],
          ),
        );
        if (chosen == null || !mounted) return;
      }
      final selected = chosen;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PackageChoiceScreen(
            package: selected,
            api: widget.api,
            revising: widget.selection,
          ),
        ),
      );
      widget.reload();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not open your selection. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> accept(Map q) async {
    var checked = false;
    final servicePlan = q['servicePlan'] as List? ?? const [];
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Confirm your fitting proposal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Agreed total: ${packageMoney(q['totalCents'])}. The booking deposit is 50% of this total, less eligible fitting credit. Your refundable gown security is separate.',
                ),
                if (servicePlan.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PackageServicePlan(rows: servicePlan),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  onChanged: (v) => update(() => checked = v == true),
                  title: Text(
                    servicePlan.isEmpty
                        ? 'I agree to the selected gowns, accessories, adjustment details and total shown.'
                        : 'I agree to the selected items, adjustments, service arrangements and total shown.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: checked ? () => Navigator.pop(c, true) : null,
              child: const Text('Agree to proposal'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) {
      await send('fitting-response', {
        'revision': q['revision'],
        'response': 'Accept',
        if (q['adjustmentPlan'] != null) 'adjustmentPlanVersion': 1,
        if (servicePlan.isNotEmpty) 'servicePlanVersion': 1,
      });
    }
  }

  Future<void> response(String value) async {
    final q = widget.selection.data['fittingQuote'] as Map?;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          value == 'Decline'
              ? 'Not proceeding?'
              : value == 'Changes'
              ? 'Request changes?'
              : 'Save for later?',
        ),
        content: const Text(
          'No package deposit is created by this action. Your attended fitting and payment history are kept. This does not refund a payment or reserve stock.',
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
    if (yes != true || !mounted) return;
    if (q != null && ['AwaitingCustomer', 'Considering'].contains(q['state'])) {
      await send('fitting-response', {
        'revision': q['revision'],
        'response': value,
      });
    } else {
      await send('fitting-intent', {
        'revision': widget.selection.data['fittingDecisionRevision'] ?? 0,
        'action': value == 'Decline'
            ? 'Decline'
            : value == 'Considering'
            ? 'Consider'
            : 'Review',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selection,
        d = s.data['fittingDecision'] as Map?,
        q = s.data['fittingQuote'] as Map?;
    if (d == null) return const SizedBox.shrink();
    final editable = s.data['rentalId'] == null && s.data['invoiceId'] == null;
    final waiting =
        q != null && ['AwaitingCustomer', 'Considering'].contains(q['state']);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF0F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your fitting & next step',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(fittingDecisionLabel(d)),
          if (d['gownChange'] is Map)
            FittingGownChangeSummary(change: d['gownChange']),
          if (widget.staff && d['assessment'] is Map)
            FittingAssessmentSummary(
              assessment: d['assessment'],
              gowns: s.selectedGowns,
            ),
          const SizedBox(height: 8),
          Text(
            q?['state'] == 'Outdated'
                ? 'Your selection, dates or price changed. Request an updated proposal before proceeding.'
                : d['state'] == 'Reselect'
                ? 'Choose another gown or update your accessories. Your attended fitting and eligible credit stay with this plan.'
                : d['state'] == 'Considering'
                ? 'Your preferences are saved. You can return when ready; items are not reserved.'
                : d['state'] == 'Declined'
                ? 'No new package deposit will be issued. Your appointment and payment history remain available.'
                : d['state'] == 'QuoteNeeded'
                ? 'The team will confirm any adjustments and prepare the final proposal.'
                : d['state'] == 'AwaitingReview'
                ? 'The team will review your updated choices. You do not need another paid visit just to request a review.'
                : 'Review the details below before continuing. A chosen gown may still need adjustments.',
          ),
          if (q != null) ...[
            const Divider(),
            for (final g in s.selectedGowns)
              Text('${g['name']} · ${g['size']}'),
            for (final a in s.data['selectedAccessories'] as List? ?? [])
              Text('${a['name']}'),
            Text('Package & selected items: ${packageMoney(q['baseCents'])}'),
            for (final l in q['lines'] as List)
              Text('${l['description']}: ${packageMoney(l['amountCents'])}'),
            const SizedBox(height: 8),
            Text(q['note'] as String),
            if (q['adjustmentPlan'] is Map)
              FittingAdjustmentPlan(plan: q['adjustmentPlan']),
            if (q['servicePlan'] case final List rows) ...[
              const SizedBox(height: 12),
              _PackageServicePlan(rows: rows),
            ],
            const SizedBox(height: 8),
            Text(
              'Proposed total: ${packageMoney(q['totalCents'])}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Text(
              'No payment is taken by accepting. Stock is checked when the rental is confirmed.',
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (uncertain)
            TextButton(
              onPressed: widget.reload,
              child: const Text('Refresh plan before continuing'),
            ),
          if (editable && !uncertain)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.staff &&
                    d['outcome'] == 'Selected' &&
                    d['state'] != 'Declined')
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FittingQuoteEditor(
                                  selection: s,
                                  api: widget.api,
                                  manager: widget.manager,
                                ),
                              ),
                            );
                            widget.reload();
                          },
                    child: const Text('Prepare / revise proposal'),
                  ),
                if (!widget.staff) ...[
                  if (waiting)
                    FilledButton(
                      onPressed: busy ? null : () => accept(q),
                      child: const Text('Review & accept proposal'),
                    ),
                  OutlinedButton(
                    onPressed: busy ? null : edit,
                    child: const Text('Change gown or accessories'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => edit(switchPackage: true),
                    child: const Text('Change package'),
                  ),
                  if (waiting)
                    TextButton(
                      onPressed: busy ? null : () => response('Changes'),
                      child: const Text('Request changes'),
                    ),
                  if (d['state'] != 'Considering')
                    TextButton(
                      onPressed: busy ? null : () => response('Considering'),
                      child: const Text('Decide later'),
                    ),
                  if (d['state'] != 'Declined')
                    TextButton(
                      onPressed: busy ? null : () => response('Decline'),
                      child: const Text('Not proceeding'),
                    ),
                  if ([
                        'Considering',
                        'Declined',
                        'Reselect',
                        'ChangesRequested',
                      ].contains(d['state']) &&
                      !waiting)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => send('fitting-intent', {
                              'revision':
                                  s.data['fittingDecisionRevision'] ?? 0,
                              'action': 'Review',
                            }),
                      child: const Text('Request team review'),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _PackageServicePlan extends StatelessWidget {
  const _PackageServicePlan({required this.rows});

  final List<dynamic> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Agreed service arrangements',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${row['name']} · ${row['timing']}'),
        ),
    ],
  );
}

class FittingQuoteEditor extends StatefulWidget {
  const FittingQuoteEditor({
    super.key,
    required this.selection,
    required this.api,
    required this.manager,
  });
  final PackageSelection selection;
  final HttpPackageApi api;
  final bool manager;
  @override
  State<FittingQuoteEditor> createState() => _FittingQuoteEditorState();
}

class _QuoteLine {
  final description = TextEditingController(),
      amount = TextEditingController(text: '0.00');
  void dispose() {
    description.dispose();
    amount.dispose();
  }
}

class _FittingQuoteEditorState extends State<FittingQuoteEditor> {
  final note = TextEditingController();
  final lines = <_QuoteLine>[];
  final serviceTiming = <PackageServiceItem, TextEditingController>{};

  late final missingAccessories =
      widget.selection.data['selectionFlowVersion'] == 1
      ? widget.selection.services
            .where(
              (service) =>
                  service.requiresStockSelection &&
                  !(widget.selection.data['selectedAccessories'] as List? ??
                          const [])
                      .any((item) => item['serviceId'] == service.id),
            )
            .toList()
      : <PackageServiceItem>[];
  late final requestId = packageRequestId();
  bool busy = false, frozen = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final saved =
        widget.selection.data['fittingQuote']?['servicePlan'] as List? ??
        const [];
    for (final service in widget.selection.services.where(
      (s) => s.requiresTeamScheduling,
    )) {
      serviceTiming[service] = TextEditingController(
        text: saved
            .where((row) => row['serviceId'] == service.id)
            .map((row) => row['timing'] as String)
            .firstOrNull,
      );
    }
    final a = widget.selection.data['fittingDecision']?['assessment'];
    if (a is Map &&
        widget.selection.data['fittingDecision']?['adjustment'] != 'None') {
      for (final g in a['gowns'] as List) {
        if ((g['adjustmentNotes'] as String).isEmpty) continue;
        final name =
            widget.selection.selectedGowns
                .where((s) => s['dressId'] == g['dressId'])
                .map((s) => s['name'])
                .firstOrNull ??
            'Gown';
        lines.add(_QuoteLine()..description.text = '$name · ${g['size']}');
      }
    }
    if (lines.isEmpty &&
        widget.selection.data['fittingDecision']?['adjustment'] != 'None') {
      lines.add(_QuoteLine());
    }
  }

  @override
  void dispose() {
    note.dispose();
    for (final controller in serviceTiming.values) {
      controller.dispose();
    }
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (missingAccessories.isNotEmpty) return;
    if (serviceTiming.values.any(
      (controller) => controller.text.trim().length < 8,
    )) {
      setState(
        () => error = 'Enter the confirmed timing for each selected service.',
      );
      return;
    }
    if (!widget.manager &&
        widget.selection.data['fittingDecision']?['adjustment'] ==
            'Assessment') {
      return;
    }
    int? cents(String s) => RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(s.trim())
        ? (double.parse(s.trim()) * 100).round()
        : null;
    if (note.text.trim().length < 10 ||
        lines.any(
          (l) =>
              l.description.text.trim().length < 3 ||
              cents(l.amount.text) == null,
        )) {
      setState(
        () => error =
            'Add a clear customer-facing summary and valid adjustment amounts.',
      );
      return;
    }
    setState(() {
      busy = true;
      frozen = true;
      error = null;
    });
    try {
      await widget.api.transport.businessRequest(
        '/v1/package-selections/${widget.selection.id}/fitting-quote',
        body: {
          'requestId': requestId,
          'revision': widget.selection.data['fittingQuoteRevision'] ?? 0,
          'decisionRevision':
              widget.selection.data['fittingDecisionRevision'] ?? 0,
          'note': note.text.trim(),
          if (serviceTiming.isNotEmpty)
            'serviceConfirmations': [
              for (final entry in serviceTiming.entries)
                {'serviceId': entry.key.id, 'timing': entry.value.text.trim()},
            ],
          'lines': [
            for (final l in lines)
              {
                'description': l.description.text.trim(),
                'amountCents': cents(l.amount.text),
              },
          ],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save. Retry the same request or close and refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AssistantExclusion(child: Text('Prepare fitting proposal')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.selection.customer,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.selection.name),
            if (widget.selection.data['fittingDecision']?['assessment'] is Map)
              FittingAssessmentSummary(
                assessment:
                    widget.selection.data['fittingDecision']['assessment'],
                gowns: widget.selection.selectedGowns,
              ),
            const SizedBox(height: 12),
            Text(
              'Selected package & items: ${packageMoney(widget.selection.data['totalCents'])}',
            ),
            const Text(
              'Quote garment adjustments here. Physical accessories and package extras must be selected from the catalogue so pricing and stock are tracked. Confirm feasibility and timing with the customer before sharing.',
            ),
            const SizedBox(height: 16),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    TextField(
                      controller: l.description,
                      enabled: !frozen,
                      maxLength: 150,
                      decoration: const InputDecoration(
                        labelText: 'Agreed adjustment and completion timing',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: l.amount,
                      enabled: widget.manager && !frozen,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Additional fee (RM)',
                      ),
                    ),
                  ],
                ),
              ),
            if (lines.isNotEmpty && !widget.manager)
              const Text(
                'Staff may record included adjustments at RM0. A manager must prepare a proposal with additional fees.',
              ),
            if (lines.isNotEmpty && lines.length < 8)
              TextButton(
                onPressed: frozen
                    ? null
                    : () => setState(() => lines.add(_QuoteLine())),
                child: const Text('Add another adjustment'),
              ),
            if (missingAccessories.isNotEmpty) ...[
              Text(
                '${missingAccessories.map((service) => service.name).join(', ')} needs an available selection. Ask the customer to choose styles or remove the service in Change gown or accessories.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            if (serviceTiming.isNotEmpty) ...[
              Text(
                'Service arrangements',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Check availability with the team first. Enter the agreed date and time or service window, and the artist or team handling it. If a service is unavailable, ask the customer to revise the package.',
              ),
              const SizedBox(height: 12),
              for (final entry in serviceTiming.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: entry.value,
                    enabled: !frozen,
                    maxLength: 180,
                    decoration: InputDecoration(
                      labelText: entry.key.name,
                      hintText: 'Agreed date, time and team',
                    ),
                  ),
                ),
            ],
            TextField(
              controller: note,
              enabled: !frozen,
              minLines: 3,
              maxLines: 5,
              maxLength: 700,
              decoration: const InputDecoration(
                labelText: 'Proposal summary for the customer',
                hintText:
                    'Explain the agreed items, adjustment scope and next fitting if required.',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sending a proposal does not take payment or reserve stock. The customer must accept this exact proposal before a deposit can be issued.',
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 20),
            if (!widget.manager &&
                widget.selection.data['fittingDecision']?['adjustment'] ==
                    'Assessment')
              const Text(
                'A manager must assess special alteration feasibility and prepare this proposal, even when no extra fee is charged.',
              ),
            FilledButton(
              onPressed:
                  busy ||
                      missingAccessories.isNotEmpty ||
                      !widget.manager &&
                          widget
                                  .selection
                                  .data['fittingDecision']?['adjustment'] ==
                              'Assessment'
                  ? null
                  : save,
              child: Text(busy ? 'Saving…' : 'Send for customer confirmation'),
            ),
          ],
        ),
      ),
    ),
  );
}
