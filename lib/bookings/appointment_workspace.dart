import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import '../src/design.dart' show CustomerUi, ink, line;
import '../support/assistant_launcher.dart' show AssistantAppBarAction;
import 'booking_repository.dart';
import 'booking_api.dart' show bookingDay;
import '../shared/list_controls.dart';
import 'appointment_package_note.dart';
import 'staff_appointment_workspace.dart';
import 'booking_time_history.dart';
export 'appointment_package_note.dart';

const _statuses = [
  'All',
  'Requested',
  'AwaitingPayment',
  'Expired',
  'Confirmed',
  'Completed',
  'Cancelled',
  'NoShow',
  'Declined',
];
const _activeStatuses = {'Requested', 'AwaitingPayment', 'Confirmed'};

enum _VisitAction {
  package('View my package', Icons.inventory_2_outlined),
  reschedule('Reschedule', Icons.event_repeat_outlined),
  cancel('Cancel appointment', Icons.event_busy_outlined);

  const _VisitAction(this.label, this.icon);
  final String label;
  final IconData icon;

  PopupMenuItem<_VisitAction> menuItem({bool enabled = true}) => PopupMenuItem(
    value: this,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

class AppointmentWorkspace extends StatefulWidget {
  const AppointmentWorkspace({
    super.key,
    required this.rows,
    required this.staff,
    required this.manager,
    this.boutiqueOperations = true,
    required this.onUpdate,
    required this.onRefresh,
    required this.onPackage,
    required this.onPayments,
    required this.onBook,
    this.busy,
    this.error,
    this.onRental,
    this.onFittingPayment,
    this.initialAppointmentId,
    this.onReschedule,
    this.refreshing = false,
    this.assistantInAppBar = false,
  });
  final List<BookingRequest> rows;
  final bool staff, manager, boutiqueOperations;
  final bool refreshing, assistantInAppBar;
  final String? busy, error;
  final String? initialAppointmentId;
  final void Function(BookingRequest, String) onUpdate;
  final ValueChanged<String> onPackage;
  final ValueChanged<BookingRequest>? onRental;
  final ValueChanged<BookingRequest>? onFittingPayment;
  final ValueChanged<BookingRequest>? onReschedule;
  final VoidCallback onRefresh, onPayments, onBook;
  @override
  State<AppointmentWorkspace> createState() => _AppointmentWorkspaceState();
}

class _AppointmentWorkspaceState extends State<AppointmentWorkspace> {
  String filter = 'All', query = '';
  late String? linkedAppointment = widget.initialAppointmentId;
  bool upcoming = false;
  String visitType = 'All visits';
  DateTimeRange? dateRange;

  @override
  void didUpdateWidget(AppointmentWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAppointmentId != widget.initialAppointmentId) {
      linkedAppointment = widget.initialAppointmentId;
    }
  }

  Widget status(String value) {
    final colour = switch (value) {
      'Requested' || 'AwaitingPayment' => CustomerUi.warning,
      'Confirmed' => CustomerUi.success,
      'Completed' => CustomerUi.information,
      'Declined' => const Color(0xFF9D4053),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        bookingStatusLabel(value),
        style: TextStyle(
          color: colour,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  String nextStep(BookingRequest b, bool package) => switch (b.status) {
    'AwaitingPayment' =>
      'Time held for 15 minutes. Pay the fitting fee to confirm. Unpaid holds expire automatically; paying after expiry requires staff review.',
    'Expired' =>
      'Payment time expired and the visit was not confirmed. Book a new time; if you already paid, check payment status and contact Luvly.',
    'Requested' =>
      'This older request is awaiting an available staffed time. Contact Luvly or cancel and book an available time. No payment is due.',
    'Confirmed' when b.type == makeupTrial =>
      'Your makeup trial is confirmed. Contact Luvly to confirm service pricing before your visit.',
    'Confirmed' =>
      package
          ? 'Your appointment is confirmed. Pay only when Luvly issues an invoice in Payments & receipts.'
          : 'Appointment confirmed. Any invoice and payment status is shown separately in Payments & receipts.',
    'Completed' when b.type == makeupTrial => 'Your makeup trial is complete.',
    'Completed' =>
      'Visit completed. View Payments & receipts for invoice and payment details.',
    'Cancelled' =>
      'Appointment cancelled. Any existing invoice or refund needs a separate review.',
    'Declined' =>
      'This request was declined. Choose another time or contact Luvly.',
    'NoShow' when b.data['refundReviewRequired'] == true =>
      'View Payments & receipts for the review of your fitting fee.',
    _ => '',
  };

  void details(BookingRequest b) {
    final package = b.type == makeupTrial
        ? null
        : AppointmentPackageNote.parse(b.notes);
    final notes = package?.customerNotes ?? b.notes;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Appointment details'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(b.type, style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(appointmentLabel(b.start)),
                if (b.hasActualAttendance)
                  Text(
                    'Actual attendance · originally scheduled ${appointmentLabel(b.scheduledStart)}',
                  ),
                const SizedBox(height: 12),
                status(b.status),
                const Divider(height: 28),
                Text('Customer', style: Theme.of(c).textTheme.labelLarge),
                Text('${b.name}\n${b.displayPhone}'),
                if (package != null) ...[
                  const SizedBox(height: 16),
                  Text('Package', style: Theme.of(c).textTheme.labelLarge),
                  Text(package.name),
                ],
                if (b.dressName.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Preferred gown',
                    style: Theme.of(c).textTheme.labelLarge,
                  ),
                  Text(b.dressName),
                ],
                const SizedBox(height: 16),
                Text('Customer notes', style: Theme.of(c).textTheme.labelLarge),
                Text(notes.isEmpty ? 'No additional notes.' : notes),
                if (b.response.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Message from Luvly',
                    style: Theme.of(c).textTheme.labelLarge,
                  ),
                  Text(b.response),
                ],
                const Divider(height: 28),
                Text(nextStep(b, package != null)),
                BookingTimeHistory(booking: b),
                if (b.status == 'Confirmed')
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Please arrive 10 minutes early for your appointment.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
          if (package != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                widget.onPackage(package.selectionId);
              },
              child: const Text('View package'),
            ),
        ],
      ),
    );
  }

  DateTime? _paymentDeadline(BookingRequest booking) {
    final value = booking.data['paymentExpiresAt'];
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is int && value > 0 && value < 4102444800000) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  Widget appointment(BookingRequest b, DateTime now) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final package = AppointmentPackageNote.parse(b.notes);
    final visitName = package?.name ?? b.dressName;
    final waiting = b.status == 'AwaitingPayment';
    final deadline = waiting ? _paymentDeadline(b) : null;
    final holdEnded = deadline != null && !deadline.isAfter(now);
    final invoice = b.data['fittingInvoiceId'];
    final canPay = invoice is String && invoice.trim().isNotEmpty && !holdEnded;
    final canReschedule =
        widget.onReschedule != null &&
        b.status == 'Confirmed' &&
        !b.hasActualAttendance &&
        b.scheduledStart.isAfter(now);
    final canCancel = canMoveBooking(b.status, 'Cancelled', staff: false);
    final label = Text(
      b.type,
      style: theme.textTheme.titleMedium?.copyWith(color: ink),
    );
    final badge = status(b.status);
    return Container(
      key: ValueKey('appointment-${b.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: waiting || canReschedule
          ? CustomerUi.softCard
          : BoxDecoration(
              color: CustomerUi.paper,
              borderRadius: CustomerUi.cardRadius,
              border: Border.all(color: CustomerUi.divider),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, size) =>
                MediaQuery.textScalerOf(context).scale(1) > 1.4 &&
                    size.maxWidth < 480
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, const SizedBox(height: 5), badge],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: label),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: size.maxWidth * .46,
                        ),
                        child: badge,
                      ),
                    ],
                  ),
          ),
          if (visitName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(visitName, style: body),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 17,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appointmentLabel(b.scheduledStart),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (b.status == 'Confirmed' && b.scheduledStart.isBefore(now))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Past appointment', style: body),
            ),
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                deadline == null
                    ? 'Fitting payment required to confirm your time.'
                    : holdEnded
                    ? 'Payment deadline passed · ${appointmentLabel(deadline)}'
                    : 'Payment deadline · ${appointmentLabel(deadline)}',
                style: body?.copyWith(
                  color: CustomerUi.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (widget.busy == b.id)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: LinearProgressIndicator(
                minHeight: 2,
                semanticsLabel: 'Updating appointment',
              ),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (waiting && widget.onFittingPayment != null)
                      FilledButton(
                        onPressed: widget.busy == null
                            ? () => widget.onFittingPayment!(b)
                            : null,
                        child: Text(
                          canPay ? 'Pay fitting fee' : 'Check payment',
                        ),
                      ),
                    TextButton(
                      onPressed: () => details(b),
                      child: const Text('View details'),
                    ),
                  ],
                ),
              ),
              if (package != null || canReschedule || canCancel)
                PopupMenuButton<_VisitAction>(
                  tooltip: 'More appointment actions',
                  position: PopupMenuPosition.under,
                  popUpAnimationStyle: CustomerUi.popupMotion(context),
                  clipBehavior: Clip.antiAlias,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    switch (action) {
                      case _VisitAction.package:
                        widget.onPackage(package!.selectionId);
                      case _VisitAction.reschedule:
                        widget.onReschedule!(b);
                      case _VisitAction.cancel:
                        widget.onUpdate(b, 'Cancelled');
                    }
                  },
                  itemBuilder: (_) => [
                    if (package != null) _VisitAction.package.menuItem(),
                    if (canReschedule)
                      _VisitAction.reschedule.menuItem(
                        enabled: widget.busy == null,
                      ),
                    if (canCancel)
                      _VisitAction.cancel.menuItem(
                        enabled: widget.busy == null,
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasAdvancedFilters =>
      visitType != 'All visits' || dateRange != null;
  bool get _hasCriteria =>
      query.trim().isNotEmpty ||
      linkedAppointment != null ||
      filter != 'All' ||
      _hasAdvancedFilters;

  void resetFilters() => setState(() {
    query = '';
    linkedAppointment = null;
    filter = 'All';
    upcoming = false;
    visitType = 'All visits';
    dateRange = null;
  });

  Future<void> openFilters() async {
    FocusScope.of(context).unfocus();
    final result =
        await showModalBottomSheet<({String type, DateTimeRange? dates})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          constraints: const BoxConstraints(maxWidth: 620),
          sheetAnimationStyle: CustomerUi.expansionMotion(context),
          builder: (_) => _VisitFiltersSheet(type: visitType, dates: dateRange),
        );
    if (result == null || !mounted) return;
    setState(() {
      visitType = result.type;
      dateRange = result.dates;
    });
  }

  Widget _chip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool timeFilter = false,
  }) => ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: timeFilter,
    selectedColor: timeFilter ? CustomerUi.linen : null,
    labelStyle: TextStyle(
      color: selected ? CustomerUi.activeText : ink,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    ),
    chipAnimationStyle: CustomerUi.chipMotion(context),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  Widget _bookingGuide() => DecoratedBox(
    decoration: CustomerUi.tintedCard,
    child: ExpansionTile(
      key: const PageStorageKey('appointment-fitting-guide'),
      minTileHeight: 48,
      expansionAnimationStyle: CustomerUi.expansionMotion(context),
      leading: const Icon(Icons.info_outline, size: 18),
      title: const Text('How package fittings work'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('1. Choose an available fitting time.'),
        Text('2. Pay the RM50 fitting fee within 15 minutes.'),
        Text(
          '3. Once payment is verified, your appointment is confirmed. Attend your fitting.',
        ),
        Text(
          '4. Book your package to apply the fitting credit, when eligible.',
        ),
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'New gown fittings require verified payment. Consultations and included follow-up fittings are free. Older appointments keep their original terms.',
          ),
        ),
      ],
    ),
  );

  Widget _header(BuildContext context, int count) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final searchHint = large && narrow
        ? 'Search'
        : large || narrow
        ? 'Search appointments'
        : 'Search appointments or packages';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    onPressed: widget.onBook,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Book an appointment'),
                  ),
                  TextButton(
                    onPressed: widget.onPayments,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Payments & receipts'),
                  ),
                ],
              ),
            ),
            if (!widget.assistantInAppBar) const AssistantAppBarAction(),
            IconButton(
              onPressed: widget.refreshing ? null : widget.onRefresh,
              tooltip: 'Refresh appointments',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Theme(
                data: theme.copyWith(
                  inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                    hintStyle: small?.copyWith(fontSize: 13),
                  ),
                ),
                child: ListSearchField(
                  value: query,
                  hint: searchHint,
                  compact: true,
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Filter appointments',
              onPressed: openFilters,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                backgroundColor: Colors.white,
                foregroundColor: ink,
                shape: RoundedRectangleBorder(
                  borderRadius: CustomerUi.controlRadius,
                ),
                side: const BorderSide(color: line),
              ),
              icon: Badge(
                isLabelVisible: _hasAdvancedFilters,
                label: Text(
                  '${(visitType == 'All visits' ? 0 : 1) + (dateRange == null ? 0 : 1)}',
                ),
                child: const Icon(Icons.tune, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          children: [
            _chip(
              label: 'Upcoming',
              selected: upcoming,
              onTap: () => setState(() => upcoming = true),
              timeFilter: true,
            ),
            _chip(
              label: 'All appointments',
              selected: !upcoming,
              onTap: () => setState(() => upcoming = false),
              timeFilter: true,
            ),
          ],
        ),
        Row(
          children: [
            Text('Status', style: small),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final value in _statuses)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: _chip(
                          key: ValueKey('appointment-status-$value'),
                          label: bookingStatusLabel(value),
                          selected: filter == value,
                          onTap: () => setState(() => filter = value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (linkedAppointment != null || _hasAdvancedFilters)
          Wrap(
            spacing: 6,
            children: [
              if (linkedAppointment != null)
                InputChip(
                  label: const Text('Linked appointment'),
                  onDeleted: () => setState(() => linkedAppointment = null),
                ),
              if (visitType != 'All visits')
                InputChip(
                  label: Text(visitType),
                  onDeleted: () => setState(() => visitType = 'All visits'),
                ),
              if (dateRange case final dates?)
                InputChip(
                  label: Text(
                    '${bookingDay(dates.start)} – ${bookingDay(dates.end)}',
                  ),
                  onDeleted: () => setState(() => dateRange = null),
                ),
            ],
          ),
        const SizedBox(height: 4),
        _bookingGuide(),
        const SizedBox(height: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '$count appointment${count == 1 ? '' : 's'}',
                    style: small,
                  ),
                ),
              ),
              if (_hasCriteria || upcoming)
                TextButton(
                  onPressed: resetFilters,
                  child: const Text('Reset filters'),
                ),
            ],
          ),
        ),
        if (widget.refreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: 'Refreshing appointments',
            ),
          ),
        if (widget.error case final error?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final noHistory = widget.rows.isEmpty;
    final noUpcoming = upcoming && !_hasCriteria;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.event_available_outlined, size: 28),
          const SizedBox(height: 8),
          Text(
            noHistory
                ? 'No appointments yet'
                : noUpcoming
                ? 'No upcoming appointments'
                : 'No matching appointments',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            noHistory
                ? 'Book a fitting or consultation to get started.'
                : noUpcoming
                ? 'Your previous visits are available under All appointments.'
                : 'Try adjusting your filters or search.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.staff) {
      return StaffAppointmentWorkspace(
        rows: widget.rows,
        busy: widget.busy,
        error: widget.error,
        initialAppointmentId: widget.initialAppointmentId,
        onRefresh: widget.onRefresh,
        onPayments: widget.boutiqueOperations ? widget.onPayments : null,
        onPackage: widget.onPackage,
        onRental: widget.onRental,
        onUpdate: widget.onUpdate,
      );
    }
    final now = DateTime.now();
    bool isUpcoming(BookingRequest b) =>
        _activeStatuses.contains(b.status) && b.start.isAfter(now);
    final rows =
        widget.rows
            .where(
              (b) =>
                  (linkedAppointment == null || b.id == linkedAppointment) &&
                  (filter == 'All' || b.status == filter) &&
                  (visitType == 'All visits' || b.type == visitType) &&
                  matchesMalaysiaDateRange(b.start, dateRange) &&
                  (!upcoming || isUpcoming(b)) &&
                  (query.trim().isEmpty ||
                      matchesListSearch(query, [
                        b.type,
                        AppointmentPackageNote.parse(b.notes)?.name,
                        b.dressName,
                        appointmentLabel(b.start),
                        if (b.hasActualAttendance)
                          appointmentLabel(b.scheduledStart),
                      ])),
            )
            .toList()
          ..sort((a, b) {
            final activeA = isUpcoming(a);
            if (activeA != isUpcoming(b)) return activeA ? -1 : 1;
            return activeA
                ? a.start.compareTo(b.start)
                : b.start.compareTo(a.start);
          });
    final indexes = {
      for (var i = 0; i < rows.length; i++) 'appointment-${rows[i].id}': i,
    };
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            key: const PageStorageKey('customer-appointments-list'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(child: _header(context, rows.length)),
                    if (rows.isNotEmpty)
                      SliverList.builder(
                        itemCount: rows.length,
                        findChildIndexCallback: (key) =>
                            indexes[(key as ValueKey<String>).value],
                        itemBuilder: (context, index) =>
                            appointment(rows[index], now),
                      )
                    else if (!widget.refreshing)
                      SliverToBoxAdapter(child: _empty(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisitFiltersSheet extends StatefulWidget {
  const _VisitFiltersSheet({required this.type, required this.dates});
  final String type;
  final DateTimeRange? dates;

  @override
  State<_VisitFiltersSheet> createState() => _VisitFiltersSheetState();
}

class _VisitFiltersSheetState extends State<_VisitFiltersSheet> {
  late String type = widget.type;
  late DateTimeRange? dates = widget.dates;
  Future<void> _pickDates() async {
    final result = await showDateRangePicker(
      context: context,
      initialDateRange: dates,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Visit dates',
      saveText: 'Apply dates',
      confirmText: 'Apply dates',
      builder: (context, child) => DatePickerTheme(
        data: DatePickerTheme.of(context).copyWith(
          rangePickerHeaderHeadlineStyle: Theme.of(
            context,
          ).textTheme.titleMedium,
        ),
        child: child!,
      ),
    );
    if (mounted && result != null) setState(() => dates = result);
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .78,
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Visit filters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close visit filters',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('visit-filter-options'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                ListFilterSelect(
                  label: 'Visit type',
                  value: type,
                  options: const ['All visits', ...appointmentTypes],
                  menuAnimationStyle: CustomerUi.popupMotion(context),
                  onChanged: (value) => setState(() => type = value),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: _pickDates,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      dates == null
                          ? 'Visit dates'
                          : '${bookingDay(dates!.start)} – ${bookingDay(dates!.end)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    type = 'All visits';
                    dates = null;
                  }),
                  child: const Text('Clear visit filters'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, (type: type, dates: dates)),
                  child: const Text('Apply filters'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
