import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import '../planning/planning_api.dart';
import 'package_api.dart';
import 'fitting_assessment.dart';
import 'fitting_gown_change.dart';
import 'fitting_workbench.dart';
import '../catalogue/catalogue_repository.dart' show CatalogueDress;
import 'rental_date_fields.dart' show rentalDateLabel;

class FittingResultScreen extends StatefulWidget {
  const FittingResultScreen({
    super.key,
    required this.selection,
    required this.api,
  });
  final PackageSelection selection;
  final HttpPackageApi api;
  @override
  State<FittingResultScreen> createState() => _FittingResultState();
}

class _FittingResultState extends State<FittingResultScreen> {
  final notes = TextEditingController();
  late final requestId = packageRequestId();
  String? appointmentId, error;
  String outcome = 'Selected', adjustment = 'None';
  bool confirmed = false, busy = false, frozen = false;
  bool loadingGowns = false;
  FittingGownChangeDraft? gownChange;
  FittingAssessmentDraft? replacementAssessment;
  final retiredAssessments = <FittingAssessmentDraft>[];
  final formScroll = ScrollController();
  late final Future<List<CatalogueDress>> summaryGowns = widget.api.gowns();
  final feeDetails = <String, Future<Map<String, dynamic>>>{};
  List<Map<String, dynamic>> get visits => widget.selection.appointments
      .where(
        (a) =>
            a['type'] == 'Dress Trial' &&
            ['Confirmed', 'Completed'].contains(a['status']),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    if (visits.length == 1) appointmentId = visits.single['id'] as String;
  }

  bool get waived =>
      widget.selection.data['fittingChoice']?['mode'] == 'SkipFitting';
  late final assessment = FittingAssessmentDraft(
    widget.selection.selectedGowns,
  );
  bool get chosenOther => outcome == 'SelectedOther';
  bool get selected => outcome == 'Selected' || chosenOther;
  bool get needsAdjustments => selected && adjustment != 'None';
  FittingAssessmentDraft get activeAssessment =>
      chosenOther && replacementAssessment != null
      ? replacementAssessment!
      : assessment;
  @override
  void dispose() {
    notes.dispose();
    formScroll.dispose();
    assessment.dispose();
    replacementAssessment?.dispose();
    for (final draft in retiredAssessments) {
      draft.dispose();
    }
    super.dispose();
  }

  String get nextStep {
    if (!waived && visits.isEmpty) return 'Review the fitting appointment';
    if (!waived && appointmentId == null) return 'Select the attended visit';
    if (chosenOther && gownChange == null) {
      return 'Select the replacement gown and size';
    }
    return waived
        ? 'Prepare the proposal'
        : switch (outcome) {
            'Selected' || 'SelectedOther' =>
              needsAdjustments
                  ? 'Prepare the adjustment proposal'
                  : 'Prepare the proposal',
            'Reselect' => 'Customer chooses another gown',
            'Considering' => 'Await the customer’s decision',
            _ => 'Close this fitting without a rental booking',
          };
  }

  String get nextCaption {
    if (!waived && visits.isEmpty) {
      return 'A confirmed fitting is required before recording attendance.';
    }
    if (!waived && appointmentId == null) {
      return 'Link this record to the visit the customer attended.';
    }
    if (chosenOther && gownChange == null) {
      return 'Choose the new gown and size before saving this outcome.';
    }
    return selected
        ? 'Customer confirmation is required before the package deposit.'
        : 'Keep the attended visit in the history. No package deposit is issued.';
  }

  Widget replacementDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Previously: ${widget.selection.selectedGowns.map((g) => '${g['name']} · ${g['size']}').join(', ')}',
      ),
      if (gownChange == null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No replacement selected yet.'),
        ),
      for (final g in gownChange?.gowns ?? <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              FittingGownPhoto(gown: g),
              const SizedBox(width: 14),
              Expanded(
                child: Text('${g['name']} · ${g['size']}\n${g['colour']}'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: frozen || loadingGowns ? null : chooseReplacement,
        icon: const Icon(Icons.checkroom_outlined),
        label: Text(
          loadingGowns
              ? 'Checking availability…'
              : gownChange == null
              ? 'Select replacement gown & size'
              : 'Change replacement selection',
        ),
      ),
      const Text(
        'The package price is unchanged. Stock is checked again on save and is not reserved yet.',
      ),
      if (gownChange != null)
        const Text(
          'Body measurements are kept. Assess the replacement gowns separately.',
        ),
    ],
  );

  Widget fittingFeeStatus(Map linked) {
    if (linked['feeIncluded'] == true) {
      return const Text('Fitting fee · Included in package');
    }
    if (widget.selection.data['fittingOnly'] == true) {
      return Text(
        linked['feeVerified'] == true
            ? 'Fitting fee verified'
            : linked['feeRequired'] == true
            ? 'Fitting fee needs front desk review'
            : 'No fitting fee linked to this visit',
      );
    }
    final id = linked['fittingInvoiceId'];
    if (id is! String || id.isEmpty) {
      return const Text('Fitting fee · No payment record linked');
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: feeDetails.putIfAbsent(
        id,
        () => widget.api.transport
            .businessRequest('/v1/invoices/$id')
            .then((v) => Map<String, dynamic>.from(v)),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Fitting fee · Status unavailable. Review Payments before saving.',
          );
        }
        final fee = snapshot.data;
        if (fee == null) return const Text('Checking fitting payment…');
        final matches =
            fee['purpose'] == 'FittingFee' &&
            fee['appointmentId'] == linked['id'] &&
            fee['amountCents'] == 5000;
        final paid =
            matches &&
            fee['state'] == 'SandboxPaid' &&
            fee['environment'] == 'sandbox' &&
            fee['reviewReason'] == null &&
            fee['invoiceNo'] is String &&
            (fee['invoiceNo'] as String).trim().isNotEmpty;
        return Text(
          paid
              ? 'Fitting fee · RM 50.00 paid'
              : 'Fitting fee · Review payment status',
          style: TextStyle(
            color: paid ? const Color(0xFF2F6D58) : const Color(0xFF9A641D),
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }

  Widget summary() {
    final s = widget.selection, plan = s.data['rentalPlan'] as Map?;
    final linked = visits.where((a) => a['id'] == appointmentId).firstOrNull;
    final customer = s.data['customerName'] as String?;
    final reference = s.id.length > 8
        ? s.id.substring(s.id.length - 8).toUpperCase()
        : s.id.toUpperCase();
    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF84757B)),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
    return FittingSection(
      title: 'Customer & visit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customer?.trim().isNotEmpty == true ? customer! : 'Customer',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(s.name),
          const SizedBox(height: 6),
          Text(
            'Plan reference · $reference',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF84757B)),
          ),
          const Divider(height: 30),
          if (waived)
            detail('Visit preference', 'Renting without a fitting')
          else if (linked != null) ...[
            detail('Linked fitting visit', planningTime(linked['startAt'])),
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.event_available_outlined, size: 16),
              label: Text(
                linked['status'] == 'Completed'
                    ? 'Completed visit'
                    : 'Confirmed visit',
              ),
            ),
            const SizedBox(height: 10),
            fittingFeeStatus(linked),
          ] else
            detail(
              'Linked fitting visit',
              visits.isEmpty
                  ? 'No eligible visit'
                  : 'Choose a visit on the right',
            ),
          const Divider(height: 30),
          for (final g in s.selectedGowns)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<List<CatalogueDress>>(
                    future: summaryGowns,
                    builder: (context, snapshot) {
                      final photo = snapshot.data
                          ?.where((d) => d.id == g['dressId'])
                          .firstOrNull;
                      return FittingGownPhoto(
                        gown: {
                          ...g,
                          if (photo != null) 'imageUrl': photo.imageUrl,
                          if (photo != null)
                            'photoRevision': photo.photoRevision,
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${g['name']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text('Size ${g['size']}'),
                        if (g['colour'] != null) Text(g['colour']),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (plan != null) ...[
            const Divider(height: 24),
            detail(
              'Wedding / event',
              rentalDateLabel(plan['eventDate'] ?? 'Not set'),
            ),
            detail('Pickup', rentalDateLabel(plan['pickupDate'] ?? 'Not set')),
            detail('Return', rentalDateLabel(plan['returnDate'] ?? 'Not set')),
          ],
        ],
      ),
    );
  }

  Widget desktop() {
    final disabled = frozen || loadingGowns;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F9),
      appBar: AppBar(
        title: const Text('Fitting record'),
        backgroundColor: Colors.white,
      ),
      bottomNavigationBar: FittingSaveBar(
        next: nextStep,
        caption: nextCaption,
        error: error,
        label: busy
            ? 'Saving…'
            : waived
            ? 'Approve no-fitting request'
            : 'Save fitting outcome',
        onSave: busy || loadingGowns || !waived && visits.isEmpty ? null : save,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 310,
                  child: ListView(
                    key: const ValueKey('fitting-summary-scroll'),
                    primary: false,
                    children: [summary()],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: ListView(
                    key: const ValueKey('fitting-form-scroll'),
                    controller: formScroll,
                    primary: false,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (!waived && visits.isEmpty)
                        FittingSection(
                          title: 'No eligible fitting visit',
                          subtitle:
                              'This plan needs a confirmed Dress Trial before attendance can be recorded.',
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Back to customer rental'),
                          ),
                        ),
                      if (!waived && visits.length > 1)
                        FittingSection(
                          title: 'Select the attended visit',
                          child: DropdownButtonFormField<String>(
                            key: const ValueKey('fitting-visit'),
                            initialValue: appointmentId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Linked fitting visit',
                            ),
                            items: [
                              for (final a in visits)
                                DropdownMenuItem<String>(
                                  value: a['id'],
                                  child: Text(
                                    planningTime(a['startAt']),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: disabled
                                ? null
                                : (v) => setState(() => appointmentId = v),
                          ),
                        ),
                      if (waived)
                        const FittingSection(
                          title: 'Review no-fitting request',
                          child: Text(
                            'Review the gown, size and rental dates. The customer has acknowledged proceeding without a fitting.',
                          ),
                        )
                      else
                        FittingSection(
                          title: '1. Customer decision',
                          subtitle:
                              'What did the customer decide at this visit?',
                          child: FittingOptions(
                            key: const ValueKey('fitting-decision'),
                            value: outcome,
                            labels: fittingOutcomeLabels,
                            descriptions: const {
                              'Selected': 'Proceed with the current selection.',
                              'SelectedOther': 'Record the new gown and size.',
                              'Reselect': 'Keep the visit; no new gown agreed.',
                              'Considering': 'Allow time to decide.',
                              'NotProceeding':
                                  'Do not continue with a rental booking.',
                            },
                            onChanged: disabled
                                ? null
                                : (v) => setState(() => outcome = v),
                          ),
                        ),
                      if (chosenOther)
                        FittingSection(
                          title: 'Replacement selection',
                          child: replacementDetails(),
                        ),
                      if (selected)
                        FittingSection(
                          title: waived ? 'Fit review' : '2. Fit & adjustments',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittingOptions(
                                value: adjustment,
                                labels: fittingAdjustmentLabels,
                                onChanged: disabled
                                    ? null
                                    : (v) => setState(() => adjustment = v),
                              ),
                              if (!waived)
                                FittingAssessmentEditor(
                                  key: ObjectKey(activeAssessment),
                                  draft: activeAssessment,
                                  adjustments: needsAdjustments,
                                  enabled: !disabled,
                                  pickup: widget
                                      .selection
                                      .data['rentalPlan']?['pickupDate'],
                                  workbench: true,
                                ),
                            ],
                          ),
                        ),
                      if (!waived && !selected)
                        FittingSection(
                          title: '2. Visit assessment',
                          subtitle:
                              'Keep any useful measurements or fit observations from this visit.',
                          child: FittingAssessmentEditor(
                            key: ObjectKey(activeAssessment),
                            draft: activeAssessment,
                            adjustments: false,
                            enabled: !disabled,
                            workbench: true,
                          ),
                        ),
                      FittingSection(
                        title: waived ? 'Review notes' : '3. Service notes',
                        subtitle:
                            'Record the discussion and confirm the service record.',
                        child: Column(
                          children: [
                            TextField(
                              key: const ValueKey('fitting-notes'),
                              controller: notes,
                              enabled: !disabled,
                              minLines: 3,
                              maxLines: 5,
                              maxLength: 700,
                              decoration: InputDecoration(
                                labelText: waived
                                    ? 'Approval and fit discussion notes'
                                    : 'Fit, size and customer decision notes',
                                hintText:
                                    'Summarise the customer’s decision and any agreed work.',
                              ),
                            ),
                            CheckboxListTile(
                              key: const ValueKey('fitting-attendance'),
                              contentPadding: EdgeInsets.zero,
                              value: confirmed,
                              onChanged: disabled
                                  ? null
                                  : (v) =>
                                        setState(() => confirmed = v == true),
                              title: Text(
                                waived
                                    ? 'I reviewed the request and approve proceeding without a fitting.'
                                    : 'The customer actually attended this fitting. This is an accurate service record.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> chooseReplacement() async {
    if (loadingGowns || frozen) return;
    setState(() {
      loadingGowns = true;
      error = null;
    });
    try {
      final options = Map<String, dynamic>.from(
        await widget.api.transport.businessRequest(
          '/v1/package-selections/${widget.selection.id}/fitting-gown-options',
          body: {},
        ),
      );
      if (!mounted) return;
      // Never silently adopt changes made by another user while this form is open.
      if (options['selectionRevision'] !=
              (widget.selection.data['selectionRevision'] ?? 0) ||
          options['planRevision'] !=
              (widget.selection.data['rentalPlanRevision'] ?? 0)) {
        throw const PaymentFailure(
          'This plan changed. Reopen the fitting record before choosing a replacement.',
        );
      }
      final result = await Navigator.push<FittingGownChangeDraft>(
        context,
        MaterialPageRoute(
          builder: (_) => FittingGownChangePicker(
            options: options,
            original: widget.selection.selectedGowns,
            initial: gownChange?.gowns ?? const [],
          ),
        ),
      );
      if (result == null || !mounted) return;
      final draft = FittingAssessmentDraft(result.gowns);
      final previous = activeAssessment;
      draft.inches = previous.inches;
      draft.bodyCm.addAll(previous.bodyCm);
      for (final key in draft.body.keys) {
        draft.body[key]!.text = previous.body[key]!.text;
      }
      if (replacementAssessment != null) {
        retiredAssessments.add(replacementAssessment!);
      }
      setState(() {
        gownChange = result;
        replacementAssessment = draft;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not load replacement gowns. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loadingGowns = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    if (chosenOther && gownChange == null) {
      setState(
        () => error =
            'Select the replacement gown and size, or choose “Needs another gown · not chosen yet”.',
      );
      return;
    }
    if (!confirmed ||
        notes.text.trim().length < 10 ||
        (!waived && appointmentId == null)) {
      setState(
        () => error =
            'Select the visit, add a clear service note (at least 10 characters), and confirm the record.',
      );
      return;
    }
    final assessmentError = waived
        ? null
        : activeAssessment.validate(
            adjustments: needsAdjustments,
            pickup: widget.selection.data['rentalPlan']?['pickupDate'],
          );
    if (assessmentError != null) {
      setState(() => error = assessmentError);
      return;
    }
    setState(() {
      busy = true;
      frozen = true;
      error = null;
    });
    try {
      await widget.api.transport.businessRequest(
        '/v1/package-selections/${widget.selection.id}/fitting-result',
        body: {
          'requestId': requestId,
          'revision': widget.selection.data['fittingDecisionRevision'] ?? 0,
          'mode': waived ? 'Waived' : 'Attended',
          'outcome': chosenOther ? 'Selected' : outcome,
          'adjustment': selected ? adjustment : 'None',
          if (chosenOther) 'gownChange': gownChange!.toJson(),
          'appointmentId': waived ? null : appointmentId,
          'confirmed': confirmed,
          'note': notes.text.trim(),
          if (!waived)
            'assessment': activeAssessment.toJson(
              adjustments: needsAdjustments,
            ),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save. Retry the same request.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 1000 &&
        MediaQuery.sizeOf(context).height >= 600 &&
        MediaQuery.textScalerOf(context).scale(1) < 1.7) {
      return desktop();
    }
    final visits = widget.selection.appointments
        .where(
          (a) =>
              a['type'] == 'Dress Trial' &&
              ['Confirmed', 'Completed'].contains(a['status']),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          waived ? 'Review no-fitting request' : 'Record fitting outcome',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            key: const ValueKey('fitting-form-scroll'),
            controller: formScroll,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.selection.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final g in widget.selection.selectedGowns)
                        Text('${g['name']} · ${g['size']}'),
                      if (widget.selection.data['rentalPlan'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Event: ${widget.selection.data['rentalPlan']['eventDate']}',
                        ),
                        Text(
                          'Pickup: ${widget.selection.data['rentalPlan']['pickupDate']} · Return: ${widget.selection.data['rentalPlan']['returnDate']}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                waived
                    ? 'The customer has requested to rent without a fitting and acknowledged the fit risk. Review their selected gown, size and dates before approving.'
                    : 'Record the attended fitting and the customer’s next step. Early visits use the actual attendance date.',
              ),
              const SizedBox(height: 24),
              if (!waived) ...[
                if (visits.isEmpty)
                  const Text(
                    'A paid, confirmed Dress Trial is required. Review the appointment payment first.',
                  ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('fitting-visit'),
                  initialValue: appointmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Linked fitting visit',
                  ),
                  items: visits
                      .map(
                        (a) => DropdownMenuItem<String>(
                          value: a['id'],
                          child: Text(
                            planningTime(a['startAt']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: frozen
                      ? null
                      : (v) => setState(() => appointmentId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('fitting-decision'),
                  initialValue: outcome,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Customer decision',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Selected',
                      child: Text(
                        'Keep current gown selection',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'SelectedOther',
                      child: Text(
                        'Chosen a different gown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Reselect',
                      child: Text(
                        'Needs another gown · not chosen yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Considering',
                      child: Text(
                        'Still considering',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'NotProceeding',
                      child: Text(
                        'Not proceeding',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: frozen
                      ? null
                      : (v) => setState(() => outcome = v!),
                ),
              ],
              if (!waived && chosenOther) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replacement selection',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Previously: ${widget.selection.selectedGowns.map((g) => '${g['name']} · ${g['size']}').join(', ')}',
                        ),
                        if (gownChange == null)
                          const Text('No replacement selected yet.'),
                        for (final g
                            in gownChange?.gowns ??
                                <Map<String, dynamic>>[]) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              FittingGownPhoto(gown: g),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${g['name']} · ${g['size']}\n${g['colour']}',
                                ),
                              ),
                            ],
                          ),
                        ],
                        TextButton.icon(
                          onPressed: frozen || loadingGowns
                              ? null
                              : chooseReplacement,
                          icon: const Icon(Icons.checkroom_outlined),
                          label: Text(
                            loadingGowns
                                ? 'Checking availability…'
                                : gownChange == null
                                ? 'Select replacement gown & size'
                                : 'Change replacement selection',
                          ),
                        ),
                        const Text(
                          'Included package price is unchanged. The customer reviews the new selection in the proposal; stock is not reserved yet.',
                        ),
                        if (gownChange != null)
                          const Text(
                            'Body measurements are kept. Assess the fit of the replacement gowns separately.',
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!waived && outcome == 'Reselect') ...[
                const SizedBox(height: 12),
                const Text(
                  'No new gown is agreed yet. Save the attended visit, then ask the customer to update their selection. Do not issue a package deposit.',
                ),
              ],
              if (selected) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: adjustment,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Adjustment needs',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'None',
                      child: Text(
                        'No adjustment',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Basic',
                      child: Text(
                        'Basic fit adjustments',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Assessment',
                      child: Text(
                        'Special requests · needs assessment',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: frozen
                      ? null
                      : (v) => setState(() => adjustment = v!),
                ),
              ],
              if (!waived)
                FittingAssessmentEditor(
                  key: ObjectKey(activeAssessment),
                  draft: activeAssessment,
                  adjustments: needsAdjustments,
                  enabled: !frozen,
                  pickup: widget.selection.data['rentalPlan']?['pickupDate'],
                ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('fitting-notes'),
                controller: notes,
                enabled: !frozen,
                minLines: 3,
                maxLines: 5,
                maxLength: 700,
                decoration: InputDecoration(
                  labelText: waived
                      ? 'Approval and fit discussion notes'
                      : 'Fit, size and customer decision notes',
                  hintText:
                      'Record the actual discussion and any agreed adjustments.',
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('fitting-attendance'),
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: frozen
                    ? null
                    : (v) => setState(() => confirmed = v == true),
                title: Text(
                  waived
                      ? 'I reviewed the customer’s request and approve proceeding without a fitting.'
                      : 'The customer actually attended this fitting. This is an accurate service record.',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'For a chosen gown, prepare a proposal next. The customer confirms it before paying the package deposit.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy || loadingGowns || (!waived && visits.isEmpty)
                    ? null
                    : save,
                child: Text(
                  busy
                      ? 'Saving…'
                      : waived
                      ? 'Approve no-fitting request'
                      : 'Save fitting outcome',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
