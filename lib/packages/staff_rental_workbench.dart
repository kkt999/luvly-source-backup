part of 'staff_rental_details.dart';

const _rentalTabs = [
  'Overview',
  'Fitting & preparation',
  'Payments',
  'Pickup & return',
  'Items',
  'History',
];

int _nextRentalTab(StaffRentalView v) {
  if (v.needsReview ||
      v.stage == 'Awaiting deposit' ||
      v.hasUnpaid ||
      v.extensionPending ||
      v.stage == 'Cancelled') {
    return 2;
  }
  if (['Collected', 'Returned'].contains(v.stage)) return 3;
  if (v.stage == 'Reserved') return v.finalFittingPending ? 1 : 3;
  return 1;
}

Widget _rentalDetailLayout(_StaffRentalDetailsState s) {
  final context = s.context,
      view = StaffRentalView(s.selection),
      full = s.widget.workspace;
  final header = AppBar(
    backgroundColor: Colors.white,
    automaticallyImplyLeading: full,
    title: Text(full ? 'Rental workspace' : 'Rental details'),
    actions: [
      IconButton(
        tooltip: 'Refresh rental details',
        onPressed: s.loading ? null : s.refresh,
        icon: const Icon(Icons.refresh),
      ),
      if (s.widget.api is HttpPackageApi && view.canCancel)
        PopupMenuButton<String>(
          tooltip: 'More rental actions',
          enabled: !s.blocked,
          onSelected: (_) => s.cancel(),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'cancel',
              child: Text('Cancel rental', style: TextStyle(color: rentalRose)),
            ),
          ],
        ),
      IconButton(
        tooltip: full ? 'Close rental workspace' : 'Close rental details',
        onPressed: s.loading ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      const SizedBox(width: 8),
    ],
  );
  final error = s.error == null
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.error!, style: const TextStyle(color: rentalRose)),
              TextButton(
                onPressed: s.loading ? null : s.refresh,
                child: const Text('Refresh record'),
              ),
            ],
          ),
        );
  final summary = _rentalIdentity(s, view, full: full);
  Widget main() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      error,
      if (s.operationMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(s.operationMessage!),
        ),
      if (!full) ...[
        _rentalNextSummary(view),
        FittingSection(title: 'Rental dates', child: _rentalDates(view)),
        FittingSection(
          title: 'Payment summary',
          child: _rentalPayments(s, view, actions: false),
        ),
        ExpansionTile(
          title: const Text('Gowns & accessories'),
          children: [_rentalItems(s.selection, services: false)],
        ),
      ] else ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _rentalTabs.length; i++)
              ChoiceChip(
                key: ValueKey('rental-tab-$i'),
                label: Text(_rentalTabs[i]),
                selected: s.tab == i,
                onSelected: (_) => s.selectTab(i),
              ),
          ],
        ),
        const SizedBox(height: 20),
        ..._rentalTabContents(s, view),
      ],
      const SizedBox(height: 24),
    ],
  );
  return Scaffold(
    backgroundColor: full ? const Color(0xFFFAF8F9) : Colors.white,
    appBar: header,
    bottomNavigationBar: full
        ? FittingSaveBar(
            next: view.nextStep,
            icon: Icons.arrow_forward,
            showAction: s.tab != _nextRentalTab(view),
            caption: s.blocked
                ? 'Refresh this record before taking action.'
                : view.nextStep == 'Await customer confirmation'
                ? 'Customer: open this package in the app and choose Review & accept proposal. Staff can confirm the rental after acceptance.'
                : 'Use the actions in ${_rentalTabs[_nextRentalTab(view)].toLowerCase()} to continue.',
            label: 'Open ${_rentalTabs[_nextRentalTab(view)].toLowerCase()}',
            onSave: s.blocked ? null : () => s.selectTab(_nextRentalTab(view)),
          )
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton.icon(
                key: const ValueKey('open-rental-workspace'),
                onPressed: s.blocked ? null : s.openWorkspace,
                icon: const Icon(Icons.open_in_full_outlined, size: 18),
                label: const Text('Open rental workspace'),
              ),
            ),
          ),
    body: Column(
      children: [
        if (s.loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide =
                  full &&
                  c.maxWidth >= 1050 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.7;
              if (wide) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 300,
                            child: ListView(
                              primary: false,
                              key: const ValueKey('rental-context-scroll'),
                              children: [summary],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey('rental-content-scroll'),
                              primary: false,
                              child: main(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SingleChildScrollView(
                key: const ValueKey('rental-content-scroll'),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, main()],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

Widget _rentalIdentity(
  _StaffRentalDetailsState s,
  StaffRentalView view, {
  required bool full,
}) {
  final selection = s.selection;
  final id = selection.id,
      reference = id.length > 8
          ? id.substring(id.length - 8).toUpperCase()
          : id.toUpperCase();
  final items = selection.selectedGowns;
  return FittingSection(
    title: full ? 'Customer & rental' : 'Customer',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selection.customer,
          style: Theme.of(
            s.context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(selection.name),
        if (selection.data['packageType'] == 'Custom')
          const Text('Custom package'),
        const SizedBox(height: 8),
        Text(
          'Plan reference · $reference',
          style: const TextStyle(fontSize: 12, color: rentalMuted),
        ),
        const SizedBox(height: 12),
        RentalStageBadge(view: view),
        if (full) ...[
          const Divider(height: 28),
          _rentalDates(view, vertical: true),
          const Divider(height: 28),
          for (final g in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittingGownPhoto(gown: g),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${g['name']}\nSize ${g['size']}\n${g['colour'] ?? ''}',
                    ),
                  ),
                ],
              ),
            ),
          if (items.isEmpty) const Text('No gown selected.'),
          const Divider(height: 24),
          Text(
            selection.data['agreedTotalCents'] is int
                ? 'Agreed package total'
                : 'Package total',
            style: const TextStyle(fontSize: 12, color: rentalMuted),
          ),
          Text(
            packageMoney(selection.totalCents),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const Text(
            'Refundable security is separate.',
            style: TextStyle(fontSize: 12, color: rentalMuted),
          ),
        ],
      ],
    ),
  );
}

Widget _rentalDates(StaffRentalView v, {bool vertical = false}) {
  final tiles = [
    _DateTile('Pickup', v.pickup, Icons.shopping_bag_outlined),
    _DateTile('Wedding / event', v.event, Icons.favorite_border),
    _DateTile('Return', v.returned, Icons.assignment_return_outlined),
  ];
  return LayoutBuilder(
    builder: (context, c) =>
        !vertical &&
            c.maxWidth >= 480 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.7
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final t in tiles) Expanded(child: t)],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles),
  );
}

Widget _rentalNextSummary(StaffRentalView v) => FittingSection(
  title: 'Next step',
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        v.nextStep,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(v.paymentSummary),
    ],
  ),
);

List<Widget> _rentalTabContents(_StaffRentalDetailsState s, StaffRentalView v) {
  final selection = s.selection,
      http = s.widget.api is HttpPackageApi
          ? s.widget.api as HttpPackageApi
          : null;
  final closed = [
    'Cancelled',
    'Expired',
    'Needs review',
    'Collected',
    'Returned',
  ].contains(v.stage);
  Widget protected(Widget child) => AbsorbPointer(
    absorbing: s.blocked,
    child: Opacity(opacity: s.blocked ? 0.5 : 1, child: child),
  );
  Widget preparation({bool edit = true}) => RentalServiceProgressPanel(
    selection: selection,
    onEdit: edit && http != null && !closed && !s.blocked
        ? s.editPreparation
        : null,
    onAppointment:
        edit && !s.blocked && PortalScope.maybeOf(s.context)?.current != null
        ? s.openAppointment
        : null,
  );
  switch (s.tab) {
    case 0:
      return [
        _rentalNextSummary(v),
        FittingSection(
          title: 'Service summary',
          child: preparation(edit: false),
        ),
        FittingSection(
          title: 'Payment summary',
          child: _rentalPayments(s, v, actions: false),
        ),
      ];
    case 1:
      return [
        FittingSection(
          title: 'Fitting & preparation',
          subtitle:
              'Record the real visit, agree the selection, then prepare the items.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fittingLabel(selection),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (http != null)
                protected(
                  PackageRentalSummary(
                    selection: selection,
                    api: http,
                    staff: true,
                    manager: s.widget.manager,
                    reload: s.refresh,
                    actionsOnly: true,
                    showProposal: false,
                    showCancel: false,
                    showNavigationActions: false,
                  ),
                )
              else
                const Text(
                  'Refresh the connected workspace to manage fitting and reservation.',
                ),
            ],
          ),
        ),
        if (http != null && selection.data['fittingWorkflowVersion'] == 2)
          protected(
            FittingProposalPanel(
              selection: selection,
              api: http,
              staff: true,
              manager: s.widget.manager,
              reload: s.refresh,
            ),
          ),
        preparation(),
        if (http != null && !s.blocked)
          FinalFittingPanel(
            key: ValueKey(
              '${selection.id}-${v.rental['finalFitting']?['recordedAt']}-${selection.data['serviceProgress']?['revision']}',
            ),
            selection: selection,
            api: http,
            onSaved: s.refresh,
          ),
        FittingSection(
          title: 'Linked appointments',
          child: _rentalAppointments(s),
        ),
      ];
    case 2:
      return [
        FittingSection(
          title: 'Payments & security',
          subtitle: 'Package payments and refundable security remain separate.',
          child: _rentalPayments(s, v),
        ),
        if (http != null && v.rental.isNotEmpty)
          protected(
            RentalExtensionStatus(
              rental: Map<String, dynamic>.from(v.rental),
              api: http.transport,
              staff: true,
              onChanged: (_) => s.refresh(),
            ),
          ),
      ];
    case 3:
      return [
        FittingSection(
          title: 'Pickup & return',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.nextStep,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _rentalDates(v),
              const Divider(height: 28),
              Text(
                'Balance: ${v.balance.status} · Security: ${v.security.status}',
              ),
              const SizedBox(height: 10),
              if (v.rental['collectedAt'] != null)
                const Text('Collection has been recorded.'),
              if (v.rental['returnedAt'] != null)
                const Text('Return inspection has been recorded.'),
              if (v.rental['returnIssue']?['state'] == 'Open')
                Text('Return issue: ${v.rental['returnIssue']['note']}'),
              const SizedBox(height: 16),
              if (http != null &&
                  v.rental['state'] == 'Locked' &&
                  v.rental['policyVersion'] == 1)
                FilledButton.icon(
                  onPressed: s.blocked ? null : s.openHandover,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(
                    v.stage == 'Returned'
                        ? 'Review inspection & security'
                        : v.stage == 'Collected'
                        ? 'Open return inspection'
                        : 'Open pickup checklist',
                  ),
                )
              else
                const Text(
                  'A confirmed rental is required before pickup or return can be recorded.',
                ),
              const SizedBox(height: 10),
              const Text(
                'Review collection, return inspection and security refund records in the checklist.',
              ),
            ],
          ),
        ),
      ];
    case 4:
      return [
        FittingSection(
          title: 'Gowns & accessories',
          child: _rentalItems(selection),
        ),
      ];
    default:
      return [
        FittingSection(
          title: 'Fitting & appointment history',
          child: _rentalAppointments(s, history: true),
        ),
        FittingSection(
          title: 'Selection & date changes',
          child: _rentalHistory(selection),
        ),
      ];
  }
}

Widget _rentalPayments(
  _StaffRentalDetailsState s,
  StaffRentalView v, {
  bool actions = true,
}) {
  final promotion = s.selection.data['promotion'] as Map?;
  final lines = [v.deposit, v.balance, v.security],
      ids = [
        v.rental['invoiceId'],
        v.rental['balanceInvoiceId'],
        v.rental['securityInvoiceId'],
      ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        packageMoney(s.selection.totalCents),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const Text(
        'Package total · refundable security is separate',
        style: TextStyle(fontSize: 12, color: rentalMuted),
      ),
      if (v.rental.isNotEmpty)
        for (var i = 0; i < lines.length; i++) ...[
          _PaymentRow(
            lines[i],
            showAction: actions && ids[i] is String,
            onView: s.blocked ? null : () => s.openPayments(ids[i]),
          ),
        ]
      else ...[
        const SizedBox(height: 16),
        Text(
          s.selection.invoice == null
              ? 'No package invoice issued yet.'
              : 'Package payment: ${s.selection.invoice!.statusLabel}',
        ),
        if (actions && s.selection.invoice != null)
          TextButton(
            onPressed: s.blocked ? null : s.openPayments,
            child: const Text('View payment details'),
          ),
        if (actions &&
            s.selection.invoice == null &&
            s.selection.selectedGowns.isEmpty &&
            (s.selection.data['selectedAccessories'] as List? ?? []).isEmpty)
          FilledButton(
            onPressed: s.blocked ? null : s.issueInvoice,
            child: const Text('Issue package invoice'),
          ),
      ],
      if ((actions ? s.selection.data['pricingSnapshot'] : null)
          case final Map pricing) ...[
        const SizedBox(height: 16),
        const Text('Selection pricing'),
        for (final line in [
          ...pricing['gownLines'] as List? ?? [],
          ...pricing['lines'] as List? ?? [],
        ])
          if (s.selection.data['packageType'] == 'Custom' &&
              line['amountCents'] is int)
            _AmountRow(line['name'], packageMoney(line['amountCents'])),
        if (pricing['discountCents'] is int && pricing['discountCents'] > 0)
          _AmountRow(
            'Bundle discount',
            '− ${packageMoney(pricing['discountCents'])}',
          ),
        if (pricing['accessoryAdjustmentCents'] is int)
          _AmountRow(
            'Veil and accessory adjustments',
            packageMoney(pricing['accessoryAdjustmentCents']),
          ),
      ],
      if (actions &&
          (promotion != null || v.rental['fittingCreditCents'] is int)) ...[
        const SizedBox(height: 20),
        const Text(
          'Price breakdown',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        if (promotion?['subtotalCents'] is int)
          _AmountRow(
            'Package subtotal',
            packageMoney(promotion!['subtotalCents']),
          ),
        if (promotion?['discountCents'] is int)
          _AmountRow(
            'Promotion · ${promotion!['code']}',
            '− ${packageMoney(promotion['discountCents'])}',
          ),
        if (v.rental['depositTargetCents'] is int)
          _AmountRow(
            '50% booking deposit',
            packageMoney(v.rental['depositTargetCents']),
          ),
        if (v.rental['fittingCreditCents'] is int)
          _AmountRow(
            'Fitting credit toward deposit',
            '− ${packageMoney(v.rental['fittingCreditCents'])}',
          ),
        if (v.rental['depositCents'] is int)
          _AmountRow(
            'Booking deposit payment',
            packageMoney(v.rental['depositCents']),
          ),
        if (v.rental['refundDueCents'] is int)
          _AmountRow(
            'Security refund due',
            packageMoney(v.rental['refundDueCents']),
          ),
      ],
    ],
  );
}

Widget _rentalItems(
  PackageSelection selection, {
  bool services = true,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (selection.selectedGowns.isEmpty &&
        (selection.data['selectedAccessories'] as List? ?? []).isEmpty)
      const Text('No gown or accessory selected.'),
    for (final g in selection.selectedGowns)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            FittingGownPhoto(gown: g),
            const SizedBox(width: 14),
            Expanded(
              child: Text('${g['name']} · ${g['size']}\n${g['colour'] ?? ''}'),
            ),
          ],
        ),
      ),
    for (final a in selection.data['selectedAccessories'] as List? ?? [])
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.diamond_outlined, color: rentalRose),
        title: Text('${a['name']}'),
        subtitle: Text('${a['category']} · ${a['size']}'),
      ),
    for (final charge in selection.data['accessoryCharges'] as List? ?? [])
      Text(switch (charge['pricing']) {
        'per-item' =>
          '${charge['serviceName']} · ${packageMoney(charge['extraCents'])}',
        'package' =>
          (charge['extraCents'] as int? ?? 0) > 0
              ? 'Veil upgrade · + ${packageMoney(charge['extraCents'])}'
              : '${charge['serviceName']} · Included',
        _ =>
          '${charge['serviceName']}: allowance ${packageMoney(charge['appliedAllowanceCents'])} · extra ${packageMoney(charge['extraCents'])}',
      }),
    if (services) ...[
      const Divider(height: 28),
      const Text(
        'Included services',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      for (final service in selection.services)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.check_circle_outline,
            color: rentalGreen,
            size: 18,
          ),
          title: Text(service.name),
          subtitle: service.kind == 'Add-on' ? const Text('Add-on') : null,
        ),
    ],
  ],
);

Widget _rentalAppointments(
  _StaffRentalDetailsState s, {
  bool history = false,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (s.selection.appointments.isEmpty)
      const Text('No appointment linked to this plan.'),
    for (final visit in s.selection.appointments)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined, color: rentalRose),
        title: Text(
          '${visit['type'] ?? 'Visit'} · ${bookingStatusLabel(visit['status'])}',
        ),
        subtitle: Text(
          visit['startAt'] is int
              ? appointmentLabel(
                  DateTime.fromMillisecondsSinceEpoch(
                    visit['startAt'],
                    isUtc: true,
                  ),
                )
              : 'Date unavailable',
        ),
        trailing: !s.blocked && PortalScope.maybeOf(s.context)?.current != null
            ? IconButton(
                tooltip: 'Open linked appointment',
                onPressed: () => s.openAppointment(visit['id']),
                icon: const Icon(Icons.open_in_new, size: 18),
              )
            : null,
      ),
    if (history)
      for (final d in [
        ...s.selection.data['fittingDecisionHistory'] as List? ?? [],
        if (s.selection.data['fittingDecision'] is Map)
          s.selection.data['fittingDecision'],
      ].reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _recordedDate(d['recordedAt']),
                style: const TextStyle(fontSize: 12, color: rentalMuted),
              ),
              Text(_fittingHistoryLabel(d)),
              if (d['note'] is String) Text(d['note']),
              if (d['gownChange'] is Map)
                FittingGownChangeSummary(change: d['gownChange']),
            ],
          ),
        ),
  ],
);

String _recordedDate(dynamic value) {
  if (value is! int || value <= 0) return 'Date not recorded';
  return appointmentLabel(
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
  );
}

String _fittingHistoryLabel(Map decision) {
  final outcome = decision['outcome'] ?? decision['state'];
  return switch (outcome) {
    'Selected' => 'Gown selected',
    'Reselect' => 'Needs another gown',
    'Considering' => 'Still considering',
    'Declined' || 'NotProceeding' => 'Not proceeding',
    'Satisfied' || 'Approved' => 'Fitting completed · satisfied',
    'NeedsChanges' || 'ChangesRequested' => 'Changes requested',
    'QuoteNeeded' => 'Chosen gown · proposal needed',
    'AwaitingCustomer' => 'Awaiting customer confirmation',
    _ => 'Fitting review',
  };
}

Widget _rentalHistory(PackageSelection selection) {
  final changes = selection.data['selectionHistory'] as List? ?? [],
      dates = selection.data['rental']?['dateChangeHistory'] as List? ?? [];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (changes.isEmpty && dates.isEmpty)
        const Text('No selection or rental date changes recorded.'),
      for (final change in changes.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _recordedDate(change['at']),
                style: const TextStyle(color: rentalMuted, fontSize: 12),
              ),
              Text('Previous selection · ${change['name'] ?? selection.name}'),
              for (final g in change['selectedGowns'] as List? ?? [])
                Text('${g['name']} · ${g['size']}'),
              if (change['totalCents'] is int)
                Text('Package total: ${packageMoney(change['totalCents'])}'),
            ],
          ),
        ),
      for (final change in dates.reversed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${rentalDateLabel(change['before']?['pickupDate'])} – ${rentalDateLabel(change['before']?['returnDate'])}\n${rentalDateLabel(change['after']?['pickupDate'])} – ${rentalDateLabel(change['after']?['returnDate'])}',
          ),
          subtitle: Text(change['reason'] ?? ''),
        ),
    ],
  );
}
