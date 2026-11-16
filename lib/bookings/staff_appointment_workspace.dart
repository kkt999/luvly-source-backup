import 'package:flutter/material.dart';
import '../admin/design.dart';
import '../shared/list_controls.dart';
import 'appointment_package_note.dart';
import 'booking_repository.dart';
import 'booking_time_history.dart';

Widget sectionTitle(String text) => Text(
  text,
  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
);

bool sameMalaysiaDay(DateTime a, DateTime b) {
  final x = a.toUtc().add(const Duration(hours: 8));
  final y = b.toUtc().add(const Duration(hours: 8));
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String staffVisitNextStep(BookingRequest b) => switch (b.status) {
  'Confirmed' => 'Prepare for visit',
  'AwaitingPayment' => 'Awaiting fitting payment',
  'Requested' => 'Review legacy request',
  'Completed' => 'Review visit record',
  'NoShow' => 'Review non-attendance',
  'Cancelled' => 'Review cancellation',
  'Expired' => 'Hold expired',
  'Declined' => 'Request declined',
  _ => 'Review details',
};

class StaffAppointmentWorkspace extends StatefulWidget {
  const StaffAppointmentWorkspace({
    super.key,
    required this.rows,
    required this.onUpdate,
    required this.onRefresh,
    required this.onPackage,
    required this.onPayments,
    this.onRental,
    this.busy,
    this.error,
    this.initialAppointmentId,
    this.now,
  });
  final List<BookingRequest> rows;
  final void Function(BookingRequest, String) onUpdate;
  final VoidCallback onRefresh;
  final VoidCallback? onPayments;
  final ValueChanged<String> onPackage;
  final ValueChanged<BookingRequest>? onRental;
  final String? busy, error, initialAppointmentId;

  /// Deterministic presentation clock. The server still validates transitions.
  final DateTime? now;
  @override
  State<StaffAppointmentWorkspace> createState() =>
      _StaffAppointmentWorkspaceState();
}

class _StaffAppointmentWorkspaceState extends State<StaffAppointmentWorkspace> {
  String query = '', status = 'All', type = 'All visits', period = 'All dates';
  String sort = 'Upcoming first';
  late String? linkedId = widget.initialAppointmentId;
  String? selectedId;
  DateTimeRange? range;
  int page = 0;
  DateTime get now => widget.now ?? DateTime.now();
  void reset() => setState(() {
    query = '';
    status = 'All';
    type = 'All visits';
    period = 'All dates';
    sort = 'Upcoming first';
    linkedId = null;
    range = null;
    page = 0;
  });
  void change(VoidCallback update) => setState(() {
    update();
    page = 0;
  });
  Future<void> pickDates() async {
    final result = await showDateRangePicker(
      context: context,
      initialDateRange: range,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (result != null && mounted) {
      change(() {
        range = result;
        period = 'Custom dates';
      });
    }
  }

  Widget viewButton(BookingRequest b) => TextButton(
    key: ValueKey('view-visit-${b.id}'),
    onPressed: () => setState(() => selectedId = b.id),
    child: const Text('View details'),
  );
  Widget visitName(BookingRequest b) => cell(
    b.type,
    sub: b.type == makeupTrial
        ? 'In-boutique service'
        : AppointmentPackageNote.parse(b.notes)?.name ?? 'Independent visit',
  );
  Widget detail(BookingRequest b) {
    final isMakeupTrial = b.type == makeupTrial;
    final package = isMakeupTrial
        ? null
        : AppointmentPackageNote.parse(b.notes);
    final notes = package?.customerNotes ?? b.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          b.name,
          '${b.type} · ${appointmentLabel(b.scheduledStart)}',
          action: Pill(bookingStatusLabel(b.status)),
        ),
        ResponsiveGrid(
          minWidth: 340,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle('Visit details'),
                  gap(16),
                  Info('Customer', b.name),
                  Info('Phone', b.displayPhone),
                  Info('Scheduled', appointmentLabel(b.scheduledStart)),
                  BookingTimeHistory(booking: b),
                  if (b.hasActualAttendance)
                    Info('Attended', appointmentLabel(b.start)),
                  if (package != null) Info('Package', package.name),
                  if (b.dressName.isNotEmpty)
                    Info('Preferred gown', b.dressName),
                  gap(12),
                  const Text(
                    'Customer notes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(6),
                  Text(notes.isEmpty ? 'No additional notes.' : notes),
                  if (b.response.isNotEmpty) ...[
                    gap(16),
                    const Text(
                      'Message from Luvly',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    gap(6),
                    Text(b.response),
                  ],
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle('Next action'),
                  gap(12),
                  Text(
                    staffVisitNextStep(b),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(8),
                  Text(switch (b.status) {
                    'Confirmed' when isMakeupTrial =>
                      'Review the customer’s notes and record completion after the makeup trial.',
                    'Completed' when isMakeupTrial =>
                      'The makeup trial has been recorded as completed.',
                    'NoShow' when isMakeupTrial =>
                      'The customer did not attend this makeup trial.',
                    'Cancelled' when isMakeupTrial =>
                      'This makeup trial has been cancelled.',
                    'Confirmed' when package != null =>
                      'Open the customer rental to record the fitting outcome and agree gown changes or adjustments. Completing this visit alone does not reserve stock or confirm a package payment.',
                    'Confirmed' =>
                      'Record completion only after the customer attends. Create or review a gown rental separately if needed.',
                    'AwaitingPayment' =>
                      'The visit is not confirmed yet. Check the fitting invoice; do not record attendance or ask for a duplicate payment.',
                    'Requested' =>
                      'This is a legacy request, not a confirmed visit. Review availability before advising the customer.',
                    'Completed' =>
                      'Attendance is recorded. Review any fitting outcome, proposal and payment separately.',
                    'NoShow' =>
                      'No attendance is recorded. Any paid fitting fee needs a separate review; no fitting credit is implied.',
                    'Cancelled' =>
                      'Any invoice or refund needs a separate review.',
                    'Expired' =>
                      'The unpaid time hold expired. If the customer already paid, review Payments & receipts before arranging another visit.',
                    _ =>
                      'Review the visit record before advising the customer.',
                  }),
                  gap(18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (package != null &&
                          (widget.onPayments != null ||
                              (b.type == 'Dress Trial' &&
                                  [
                                    'Confirmed',
                                    'Completed',
                                  ].contains(b.status))))
                        FilledButton.icon(
                          onPressed: widget.busy == null
                              ? () => widget.onPackage(package.selectionId)
                              : null,
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text(
                            widget.onPayments == null
                                ? 'Record fitting'
                                : 'Review package',
                          ),
                        ),
                      if (!isMakeupTrial &&
                          package == null &&
                          widget.onRental != null &&
                          ['Confirmed', 'Completed'].contains(b.status))
                        OutlinedButton(
                          onPressed: widget.busy == null
                              ? () => widget.onRental!(b)
                              : null,
                          child: const Text('Gown rental'),
                        ),
                      if (!isMakeupTrial && widget.onPayments != null)
                        OutlinedButton(
                          onPressed: widget.busy == null
                              ? widget.onPayments
                              : null,
                          child: const Text('Payments & receipts'),
                        ),
                    ],
                  ),
                  if ([
                    'Confirmed',
                    'Requested',
                    'AwaitingPayment',
                  ].contains(b.status)) ...[
                    const Divider(height: 32),
                    const Text(
                      'Visit administration',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    gap(8),
                    const Text(
                      'Actions require confirmation. Payment, refund and stock status are checked separately.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    gap(12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final target in [
                          'Completed',
                          'NoShow',
                          'Cancelled',
                        ])
                          if (canMoveBooking(b.status, target, staff: true))
                            Tooltip(
                              message: target == 'NoShow'
                                  ? 'Available one hour after the scheduled start. A reason is required.'
                                  : target == 'Completed'
                                  ? 'Only record a visit that has actually happened.'
                                  : 'Review cancellation before confirming.',
                              child: OutlinedButton(
                                key: ValueKey('visit-action-$target'),
                                onPressed:
                                    widget.busy != null ||
                                        (target == 'Completed' &&
                                            b.scheduledStart.isAfter(now)) ||
                                        (target == 'NoShow' &&
                                            b.scheduledStart
                                                .add(const Duration(hours: 1))
                                                .isAfter(now))
                                    ? null
                                    : () => widget.onUpdate(b, target),
                                child: Text(
                                  {
                                    'Completed': 'Mark completed',
                                    'NoShow': 'Did not attend',
                                    'Cancelled': 'Cancel',
                                  }[target]!,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (selectedId != null) {
      BookingRequest? selected;
      for (final b in widget.rows) {
        if (b.id == selectedId) selected = b;
      }
      return PageBody(
        key: PageStorageKey('staff-appointment-detail-$selectedId'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selectedId = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to appointments'),
            ),
          ),
          gap(16),
          if (widget.error != null) ...[
            Text(widget.error!, style: const TextStyle(color: Colors.red)),
            gap(12),
          ],
          if (widget.busy != null) const LinearProgressIndicator(),
          if (selected == null)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle('Appointment unavailable'),
                  gap(8),
                  const Text(
                    'This visit may have been reassigned. Contact a manager if you need to access it.',
                  ),
                  TextButton(
                    onPressed: widget.onRefresh,
                    child: const Text('Refresh appointments'),
                  ),
                ],
              ),
            )
          else
            detail(selected),
        ],
      );
    }
    final clock = now;
    final filtered = widget.rows
        .where(
          (b) =>
              (linkedId == null || b.id == linkedId) &&
              (status == 'All' || b.status == status) &&
              (type == 'All visits' || b.type == type) &&
              matchesMalaysiaDateRange(b.scheduledStart, range) &&
              (period != 'Today' || sameMalaysiaDay(b.scheduledStart, clock)) &&
              (period != 'Upcoming' ||
                  b.scheduledStart.isAfter(clock) &&
                      [
                        'Confirmed',
                        'Requested',
                        'AwaitingPayment',
                      ].contains(b.status)) &&
              matchesListSearch(query, [
                b.name,
                b.displayPhone,
                b.type,
                b.dressName,
                AppointmentPackageNote.parse(b.notes)?.name,
                appointmentLabel(b.scheduledStart),
                bookingStatusLabel(b.status),
              ]),
        )
        .toList();
    filtered.sort((a, b) {
      int result;
      if (sort == 'Customer: A–Z') {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else if (sort == 'Newest first') {
        result = b.scheduledStart.compareTo(a.scheduledStart);
      } else if (sort == 'Oldest first') {
        result = a.scheduledStart.compareTo(b.scheduledStart);
      } else {
        bool upcoming(BookingRequest x) =>
            !x.scheduledStart.isBefore(clock) &&
            ['Confirmed', 'AwaitingPayment', 'Requested'].contains(x.status);
        final x = upcoming(a), y = upcoming(b);
        result = x != y
            ? (x ? -1 : 1)
            : x
            ? a.scheduledStart.compareTo(b.scheduledStart)
            : b.scheduledStart.compareTo(a.scheduledStart);
      }
      return result != 0 ? result : a.id.compareTo(b.id);
    });
    final last = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ 20;
    final current = page.clamp(0, last),
        shown = filtered.skip(current * 20).take(20).toList();
    return PageBody(
      key: const PageStorageKey('staff-appointment-list'),
      children: [
        Heading(
          widget.onPayments == null ? 'My appointments' : 'Appointments',
          'Prepare for visits, record attendance and follow up with customers. All times are MYT.',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.onPayments != null)
                OutlinedButton.icon(
                  onPressed: widget.onPayments,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Payments & receipts'),
                ),
              IconButton(
                onPressed: widget.onRefresh,
                tooltip: 'Refresh appointments',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        ResponsiveGrid(
          minWidth: 240,
          children: [
            Metric(
              'Confirmed today',
              '${widget.rows.where((b) => b.status == 'Confirmed' && sameMalaysiaDay(b.scheduledStart, clock)).length}',
              'Scheduled for today · MYT',
              Icons.today_outlined,
              connected: true,
            ),
            Metric(
              'Attendance to record',
              '${widget.rows.where((b) => b.status == 'Confirmed' && !b.scheduledStart.isAfter(clock)).length}',
              'Started visits still marked confirmed',
              Icons.fact_check_outlined,
              connected: true,
            ),
            Metric(
              'Awaiting payment',
              '${widget.rows.where((b) => b.status == 'AwaitingPayment').length}',
              'Not confirmed · check invoice status',
              Icons.payments_outlined,
              connected: true,
            ),
          ],
        ),
        gap(20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListSearchField(
                value: query,
                hint: 'Search customer, phone, package or visit',
                onChanged: (v) => change(() => query = v),
              ),
              gap(12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ListFilterSelect(
                    label: 'Visit type',
                    value: type,
                    options: [
                      'All visits',
                      ...{
                        ...appointmentTypes,
                        ...widget.rows.map((b) => b.type),
                      },
                    ],
                    onChanged: (v) => change(() => type = v),
                  ),
                  ListFilterSelect(
                    label: 'Status',
                    value: bookingStatusLabel(status),
                    options: const [
                      'All',
                      'Confirmed',
                      'AwaitingPayment',
                      'Requested',
                      'Completed',
                      'Cancelled',
                      'NoShow',
                      'Expired',
                      'Declined',
                    ].map(bookingStatusLabel).toList(),
                    onChanged: (v) => change(
                      () => status = v == 'Awaiting payment'
                          ? 'AwaitingPayment'
                          : v == 'Did not attend'
                          ? 'NoShow'
                          : v,
                    ),
                  ),
                  ListFilterSelect(
                    label: 'Sort by',
                    value: sort,
                    options: const [
                      'Upcoming first',
                      'Newest first',
                      'Oldest first',
                      'Customer: A–Z',
                    ],
                    onChanged: (v) => change(() => sort = v),
                  ),
                  ResetListFilters(onReset: reset),
                ],
              ),
              gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in ['All dates', 'Today', 'Upcoming'])
                    ChoiceChip(
                      label: Text(p),
                      selected: period == p,
                      onSelected: (_) => change(() {
                        period = p;
                        range = null;
                      }),
                    ),
                  OutlinedButton.icon(
                    onPressed: pickDates,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      range == null
                          ? 'Date range'
                          : '${range!.start.day}/${range!.start.month}/${range!.start.year} – ${range!.end.day}/${range!.end.month}/${range!.end.year}',
                    ),
                  ),
                  if (linkedId != null)
                    InputChip(
                      label: const Text('Linked appointment'),
                      onDeleted: () => change(() => linkedId = null),
                    ),
                ],
              ),
            ],
          ),
        ),
        gap(16),
        if (widget.error != null) ...[
          Text(widget.error!, style: const TextStyle(color: Colors.red)),
          gap(12),
        ],
        Text(
          '${filtered.length} ${filtered.length == 1 ? 'appointment' : 'appointments'}',
          style: const TextStyle(color: muted),
        ),
        gap(12),
        if (shown.isEmpty)
          const Panel(child: Text('No appointments match this view.'))
        else
          LayoutBuilder(
            builder: (context, bounds) =>
                bounds.maxWidth >= 1000 &&
                    MediaQuery.textScalerOf(context).scale(14) < 22
                ? RecordTable(
                    connected: true,
                    minWidth: 1000,
                    columns: const [
                      'SCHEDULED · MYT',
                      'CUSTOMER',
                      'VISIT / PACKAGE',
                      'STATUS',
                      '',
                    ],
                    rows: [
                      for (final b in shown)
                        [
                          cell(appointmentLabel(b.scheduledStart)),
                          cell(b.name, sub: b.displayPhone),
                          SizedBox(width: 220, child: visitName(b)),
                          Pill(bookingStatusLabel(b.status)),
                          viewButton(b),
                        ],
                    ],
                  )
                : Column(
                    children: [
                      for (final b in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appointmentLabel(b.scheduledStart),
                                  style: const TextStyle(color: muted),
                                ),
                                gap(10),
                                Text(
                                  b.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(b.displayPhone),
                                gap(10),
                                visitName(b),
                                gap(12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Pill(bookingStatusLabel(b.status)),
                                    viewButton(b),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        gap(12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              shown.isEmpty
                  ? '0 shown'
                  : '${current * 20 + 1}–${current * 20 + shown.length} of ${filtered.length}',
            ),
            TextButton(
              onPressed: current > 0
                  ? () => setState(() => page = current - 1)
                  : null,
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: current < last
                  ? () => setState(() => page = current + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}
