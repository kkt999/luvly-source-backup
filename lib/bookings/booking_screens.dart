import 'package:flutter/material.dart';
import '../support/assistant_launcher.dart';
import '../src/contact_validation.dart';
import '../catalogue/rental_screen.dart';
import 'booking_repository.dart';
import '../payments/payment_api.dart';
import '../payments/payment_screen.dart';
import '../packages/package_screen.dart';
import 'appointment_workspace.dart';
import '../packages/package_api.dart';
import '../packages/fitting_result_screen.dart';
import '../packages/final_fitting_panel.dart';
import 'appointment_payment_summary.dart';
import 'reschedule_screen.dart';
import 'reschedule_api.dart';

class LiveBookingDashboard extends StatefulWidget {
  const LiveBookingDashboard({
    super.key,
    required this.name,
    required this.onOpen,
  });
  final String name;
  final VoidCallback onOpen;
  @override
  State<LiveBookingDashboard> createState() => _LiveBookingDashboardState();
}

class _LiveBookingDashboardState extends State<LiveBookingDashboard> {
  Stream<List<BookingRequest>>? feed;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    feed ??= BookingScope.maybeOf(context)?.watch();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Welcome back, ${widget.name}',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      const Text(
        'View automatically confirmed visits and keep brides informed.',
      ),
      const SizedBox(height: 24),
      StreamBuilder<List<BookingRequest>>(
        stream: feed,
        builder: (c, snapshot) {
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Could not load appointment totals.'),
                TextButton(
                  onPressed: () => setState(
                    () => feed = BookingScope.maybeOf(context)?.watch(),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final now = malaysiaNow();
          final today = rows.where((b) {
            final day = b.start.add(const Duration(hours: 8));
            return b.status == 'Confirmed' &&
                day.year == now.year &&
                day.month == now.month &&
                day.day == now.day;
          }).length;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final item in [
                (
                  'Legacy requests',
                  rows.where((b) => b.status == 'Requested').length,
                ),
                ('Confirmed visits today', today),
                (
                  'Completed visits',
                  rows.where((b) => b.status == 'Completed').length,
                ),
              ])
                SizedBox(
                  width: 260,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$1),
                          const SizedBox(height: 12),
                          Text(
                            '${item.$2}',
                            style: Theme.of(c).textTheme.headlineLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: widget.onOpen,
          icon: const Icon(Icons.calendar_month),
          label: const Text('Manage appointments'),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Manage fitting and rental progress in Customer rentals, and invoices in Payments & receipts.',
      ),
    ],
  );
}

class LiveAppointments extends StatefulWidget {
  const LiveAppointments({
    super.key,
    required this.uid,
    required this.name,
    this.phone = '',
    this.staff = false,
    this.manager = false,
    this.boutiqueOperations = true,
    this.initialAppointmentId,
    this.assistantInAppBar = false,
  });
  final String uid, name, phone;
  final bool staff, manager, boutiqueOperations, assistantInAppBar;
  final String? initialAppointmentId;
  @override
  State<LiveAppointments> createState() => _LiveAppointmentsState();
}

class _LiveAppointmentsState extends State<LiveAppointments> {
  Stream<List<BookingRequest>>? feed;
  BookingRepository? repository;
  String? busy, error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = BookingScope.maybeOf(context);
    if (repository != next) {
      repository = next;
      feed = watchAppointments();
    }
  }

  @override
  void didUpdateWidget(covariant LiveAppointments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.staff != widget.staff ||
        oldWidget.manager != widget.manager) {
      feed = watchAppointments();
    }
  }

  Stream<List<BookingRequest>>? watchAppointments() => repository?.watch(
    uid: widget.staff ? null : widget.uid,
    staffUid: widget.staff ? widget.uid : null,
    manager: widget.manager,
  );

  Future<void> update(BookingRequest b, String status) async {
    final controller = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$status appointment?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${b.type}\n${appointmentLabel(b.start)}'),
              if (b.hasActualAttendance)
                Text(
                  'Attended · originally scheduled ${appointmentLabel(b.scheduledStart)}',
                ),
              if (status == 'Confirmed')
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Confirming reserves the visit time only. Review package and gown arrangements before issuing a package invoice. No payment is taken by this action.',
                  ),
                ),
              if (widget.staff)
                TextField(
                  controller: controller,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: status == 'NoShow'
                        ? 'Reason for non-attendance (at least 10 characters)'
                        : 'Message to bride (optional)',
                  ),
                ),
              if (status == 'Cancelled')
                Text(
                  widget.staff
                      ? 'The customer can use Reschedule in Bookings to move an eligible confirmed visit and keep its verified fitting fee. Cancelling is separate: paid fees need staff refund review.'
                      : 'To keep an eligible confirmed visit and its verified fitting fee, use Reschedule instead. Cancelling is separate: paid fitting fees require staff refund review and are not automatically refunded.',
                ),
              if (status == 'NoShow')
                const Text(
                  'Record a missed visit only after its scheduled hour has ended. Add a clear reason below. Any paid fee will go to manager review; no fitting credit is earned by absence.',
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
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              status == 'Cancelled'
                  ? 'Cancel appointment'
                  : status == 'NoShow'
                  ? 'Record non-attendance'
                  : 'Mark completed',
            ),
          ),
        ],
      ),
    );
    final response = controller.text;
    controller.dispose();
    if (approved != true || !mounted) return;
    setState(() {
      busy = b.id;
      error = null;
    });
    try {
      await repository!.transition(
        b,
        status,
        actor: widget.uid,
        staff: widget.staff,
        response: response,
      );
    } catch (e) {
      if (mounted) setState(() => error = bookingError(e));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> reschedule(BookingRequest booking) async {
    if (busy != null) return;
    setState(() {
      busy = booking.id;
      error = null;
    });
    try {
      final result = await Navigator.of(context).push<RescheduleResult>(
        MaterialPageRoute(
          builder: (_) =>
              RescheduleAppointmentScreen(appointmentId: booking.id),
        ),
      );
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.status == 'Confirmed'
                  ? 'Appointment rescheduled to ${appointmentLabel(result.start)}. Calendar will sync shortly.'
                  : 'This visit has since changed. Check its latest status in Bookings.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void openPackage(String selectionId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LivePackageScreen(
        staff: widget.staff,
        manager: widget.manager,
        initialSelections: true,
        initialSelectionId: selectionId,
      ),
    ),
  );

  Future<void> openAssignedFitting(String selectionId) async {
    final api = HttpPackageApi();
    try {
      final row = await api.transport.businessRequest(
        '/v1/package-selections/$selectionId/assigned-fitting',
      );
      if (!mounted) return;
      final fitting = PackageSelection(row);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => fitting.data['rentalId'] == null
              ? FittingResultScreen(selection: fitting, api: api)
              : Scaffold(
                  appBar: AppBar(title: const Text('Final fitting')),
                  body: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: FinalFittingPanel(
                            selection: fitting,
                            api: api,
                            onSaved: () => Navigator.pop(routeContext),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(bookingError(e))));
      }
    } finally {
      api.close();
    }
  }

  void openPayments() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          LivePaymentsScreen(staff: widget.staff, manager: widget.manager),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final standalone = !widget.staff && Scaffold.maybeOf(context) == null;
    final body = appointmentList(
      assistantInAppBar: standalone || widget.assistantInAppBar,
    );
    return standalone
        ? Scaffold(
            appBar: AppBar(
              title: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('My appointments'),
              ),
              actions: const [AssistantAppBarAction()],
            ),
            body: body,
          )
        : body;
  }

  Widget appointmentList({required bool assistantInAppBar}) {
    if (feed == null) {
      return const Center(child: Text('Appointment service is unavailable.'));
    }
    return StreamBuilder<List<BookingRequest>>(
      key: widget.staff
          ? ObjectKey(feed)
          : ValueKey((widget.uid, widget.manager, repository)),
      stream: feed,
      builder: (context, snapshot) {
        final refreshing = snapshot.connectionState == ConnectionState.waiting;
        if (snapshot.hasError && !refreshing) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not load appointments. Check your connection and retry.',
                ),
                TextButton(
                  onPressed: () => setState(() => feed = watchAppointments()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return AppointmentWorkspace(
          initialAppointmentId: widget.initialAppointmentId,
          assistantInAppBar: assistantInAppBar,
          refreshing: refreshing,
          rows: snapshot.data!,
          staff: widget.staff,
          manager: widget.manager,
          boutiqueOperations: widget.boutiqueOperations,
          busy: busy,
          error: error,
          onUpdate: update,
          onReschedule: widget.staff ? null : reschedule,
          onPackage: widget.staff && !widget.boutiqueOperations
              ? openAssignedFitting
              : openPackage,
          onPayments: openPayments,
          onFittingPayment: (b) => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => LivePaymentsScreen(
                initialInvoiceId: switch (b.data['fittingInvoiceId']) {
                  final String id when id.trim().isNotEmpty => id,
                  _ => null,
                },
              ),
            ),
          ),
          onRental: widget.staff && !widget.boutiqueOperations
              ? null
              : (booking) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RentalScreen(appointment: booking),
                  ),
                ),
          onRefresh: () => setState(() => feed = watchAppointments()),
          onBook: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BookingRequestForm(
                uid: widget.uid,
                name: widget.name,
                phone: widget.phone,
              ),
            ),
          ),
        );
      },
    );
  }
}

class BookingRequestForm extends StatefulWidget {
  const BookingRequestForm({
    super.key,
    required this.uid,
    required this.name,
    required this.phone,
    this.dressId = '',
    this.dressName = '',
    this.packageName = '',
    this.submitRequest,
    this.latestAppointmentDay,
    this.packageAppointmentType,
    this.fittingIncluded = false,
    this.onSubmitted,
  });
  final String uid, name, phone, dressId, dressName;
  final String packageName;
  final DateTime? latestAppointmentDay;
  final String? packageAppointmentType;
  final bool fittingIncluded;
  final VoidCallback? onSubmitted;
  final Future<BookingOutcome?> Function(
    String type,
    DateTime start,
    String notes,
  )?
  submitRequest;
  @override
  State<BookingRequestForm> createState() => _BookingRequestFormState();
}

class _BookingRequestFormState extends State<BookingRequestForm> {
  final form = GlobalKey<FormState>();
  final notes = TextEditingController();
  String requestId = packageRequestId();
  List<int> available = [];
  bool loadingSlots = false, loaded = false;
  String? slotError;
  int slotGeneration = 0;
  Future<void> loadSlots({bool clearError = true}) async {
    final scope = BookingScope.scopeOf(context);
    final load = scope?.availableHours;
    final typedLoad = scope?.availableHoursForType;
    final selectedDay = day;
    final selectedType = type;
    final preferredHour = clearError ? hour : null;
    final generation = ++slotGeneration;
    setState(() {
      loadingSlots = true;
      slotError = null;
      available = [];
      if (clearError) error = null;
    });
    try {
      if (typedLoad == null && (load == null || selectedType == makeupTrial)) {
        throw StateError(
          'Appointment availability is unavailable. Please reopen Bookings.',
        );
      }
      final values = typedLoad != null
          ? await typedLoad(selectedDay, selectedType)
          : await load!(selectedDay);
      if (mounted && generation == slotGeneration) {
        setState(() {
          available = values;
          hour =
              preferredHour != null &&
                  values.contains(preferredHour) &&
                  validAppointmentTime(
                    appointmentUtc(selectedDay, preferredHour),
                    DateTime.now().toUtc(),
                  )
              ? preferredHour
              : null;
        });
      }
    } catch (e) {
      if (mounted && generation == slotGeneration) {
        setState(() => slotError = bookingError(e));
      }
    } finally {
      if (mounted && generation == slotGeneration) {
        setState(() => loadingSlots = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      if (hasDateWindow) loadSlots();
    }
  }

  DateTime day = malaysiaNow().add(const Duration(days: 1));
  int? hour;
  late String type = widget.packageAppointmentType ?? appointmentTypes.first;
  List<String> get availableTypes => widget.packageAppointmentType != null
      ? [widget.packageAppointmentType!]
      : widget.submitRequest != null || widget.dressId.isNotEmpty
      ? gownAppointmentTypes
      : appointmentTypes;
  bool busy = false, termsAccepted = false;
  String? error;
  DateTime get today {
    final now = malaysiaNow();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get lastDay {
    final normal = today.add(const Duration(days: 179));
    final cutoff = widget.latestAppointmentDay;
    return cutoff != null && cutoff.isBefore(normal) ? cutoff : normal;
  }

  bool get hasDateWindow =>
      !lastDay.isBefore(today) &&
      appointmentUtc(
        lastDay,
        appointmentHours.last,
      ).isAfter(DateTime.now().toUtc());

  bool get chargeable => type == 'Dress Trial' && !widget.fittingIncluded;
  bool get included => type == 'Dress Trial' && widget.fittingIncluded;
  int get notesLimit => widget.submitRequest == null ? 1000 : 700;
  bool get validNotes => notes.text.trim().length <= notesLimit;
  bool get validDetails =>
      hasBookingContactDetails(widget.name, widget.phone) &&
      (widget.submitRequest != null || widget.dressName.length <= 100);

  bool canSelectHour(int value) =>
      !loadingSlots &&
      hasDateWindow &&
      !day.isBefore(today) &&
      !day.isAfter(lastDay) &&
      available.contains(value) &&
      validAppointmentTime(appointmentUtc(day, value), DateTime.now().toUtc());

  DateTime? get selectedStart {
    final value = hour;
    return value != null && canSelectHour(value)
        ? appointmentUtc(day, value)
        : null;
  }

  String? get continueHint {
    if (busy || loadingSlots || !hasDateWindow || error != null) return null;
    if (!validDetails) {
      return 'Check your contact details in Personal profile before booking.';
    }
    if (slotError != null) return 'Refresh available times to try again.';
    if (selectedStart == null && available.isEmpty) {
      return 'Choose another date to look for an available time.';
    }
    if (selectedStart == null && available.isNotEmpty) {
      return 'Choose an available time to continue.';
    }
    if (selectedStart != null && !termsAccepted) {
      return 'Agree to the booking terms to continue.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    day = DateTime(day.year, day.month, day.day);
    if (day.isAfter(lastDay)) day = hasDateWindow ? lastDay : today;
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!termsAccepted) {
      setState(
        () => error = 'Please read and accept the booking and payment terms.',
      );
      return;
    }
    if (!form.currentState!.validate()) return;
    if (!validDetails || !availableTypes.contains(type)) {
      setState(
        () => error =
            'Check your contact details in Personal profile before booking.',
      );
      return;
    }
    if (!hasDateWindow || day.isBefore(today) || day.isAfter(lastDay)) {
      setState(
        () => error =
            'Your fitting must be before pickup and the wedding. Change your rental dates or contact Luvly.',
      );
      return;
    }
    final start = selectedStart;
    if (start == null) {
      setState(
        () => error = 'This time is no longer available. Choose another time.',
      );
      if (!loadingSlots) await loadSlots(clearError: false);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Creation rechecks the selected slot atomically. Retrying the same
      // request can return the existing hold if its first response was lost.
      BookingOutcome? outcome;
      if (widget.submitRequest != null) {
        outcome = await widget.submitRequest!(type, start, notes.text);
      } else {
        outcome = await BookingScope.maybeOf(context)!.create(
          uid: widget.uid,
          name: widget.name,
          phone: widget.phone,
          type: type,
          start: start,
          notes: notes.text,
          dressId: widget.dressId,
          dressName: widget.dressName,
          requestId: requestId,
        );
      }
      if (!mounted) return;
      widget.onSubmitted?.call();
      if (outcome?.invoiceId != null) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                LivePaymentsScreen(initialInvoiceId: outcome!.invoiceId),
          ),
        );
        if (!mounted) return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome?.status == 'Confirmed' && outcome?.invoiceId == null
                ? 'Appointment confirmed. View it under Bookings.'
                : 'View your appointment and payment status under Bookings.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final slotUnavailable =
          e is PaymentFailure &&
          (e.code == 'SLOT_UNAVAILABLE' || e.code == 'NO_STAFF_AVAILABLE');
      setState(() {
        if (slotUnavailable) hour = null;
        error = slotUnavailable
            ? 'This time is no longer available. Choose another time.'
            : bookingError(e);
        busy = false;
      });
      if (slotUnavailable) await loadSlots(clearError: false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const AssistantExclusion(child: Text('Book an appointment')),
      ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : AppointmentBookingFooter(
              chargeable: chargeable,
              included: included,
              busy: busy,
              error: error,
              hint: continueHint,
              onContinue:
                  !busy &&
                      selectedStart != null &&
                      termsAccepted &&
                      availableTypes.contains(type) &&
                      validDetails &&
                      validNotes
                  ? submit
                  : null,
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(
                  'Your boutique visit',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.person_outline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.name} · ${formatContactPhone(widget.phone)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (widget.dressName.isNotEmpty)
                  Text('Interested dress: ${widget.dressName}'),
                if (widget.latestAppointmentDay != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      hasDateWindow
                          ? 'Choose a fitting on or before ${lastDay.day}/${lastDay.month}/${lastDay.year}, before pickup and your wedding.'
                          : 'No fitting date is available before pickup. Change your rental dates or contact Luvly.',
                    ),
                  ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Appointment type',
                  ),
                  items: availableTypes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (s) {
                          if (s == null || s == type) return;
                          setState(() {
                            type = s;
                            hour = null;
                            termsAccepted = false;
                            requestId = packageRequestId();
                          });
                          if (hasDateWindow) loadSlots();
                        },
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text('${day.day}/${day.month}/${day.year}'),
                  onPressed: busy || !hasDateWindow
                      ? null
                      : () async {
                          final now = malaysiaNow();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: day,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: lastDay,
                          );
                          if (date != null &&
                              mounted &&
                              !DateUtils.isSameDay(date, day)) {
                            setState(() {
                              day = date;
                              hour = null;
                              requestId = packageRequestId();
                            });
                            await loadSlots();
                          }
                        },
                ),
                const Text(
                  'Available times (MYT) · $boutiqueVisitMinutes-minute visit',
                ),
                if (loadingSlots) const LinearProgressIndicator(),
                if (!loadingSlots &&
                    available.isEmpty &&
                    slotError == null &&
                    hasDateWindow)
                  Text(
                    type == makeupTrial
                        ? 'No makeup artist is available for a trial on this day. Choose another date or contact Luvly.'
                        : 'No appointments available on this day. The times are booked or staff are unavailable. Choose another date.',
                  ),
                if (slotError != null)
                  Text(
                    slotError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                TextButton(
                  onPressed: busy || loadingSlots || !hasDateWindow
                      ? null
                      : loadSlots,
                  child: const Text('Refresh available times'),
                ),
                Wrap(
                  spacing: 8,
                  children: appointmentHours
                      .map(
                        (h) => ChoiceChip(
                          label: Text('$h:00'),
                          selected: hour == h,
                          onSelected: busy || !canSelectHour(h)
                              ? null
                              : (selected) {
                                  if (!selected || hour == h) return;
                                  setState(() {
                                    hour = h;
                                    requestId = packageRequestId();
                                    error = null;
                                  });
                                },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: notes,
                  enabled: !busy,
                  maxLength: notesLimit,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Anything we should know? (optional)',
                    counterText: '',
                  ),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  onChanged: (_) => setState(() {}),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (_) =>
                      validNotes ? null : 'Please shorten your notes.',
                ),
                const SizedBox(height: 20),
                AppointmentPaymentSummary(
                  chargeable: chargeable,
                  included: included,
                  serviceLabel: type,
                  linkedToPackage: widget.submitRequest != null,
                  visitStart: selectedStart,
                  packageName: widget.packageName,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I agree to the booking terms.'),
                  value: termsAccepted,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => termsAccepted = v ?? false),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
