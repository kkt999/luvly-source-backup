import 'package:flutter/material.dart';
import '../support/assistant_launcher.dart';
import '../payments/payment_api.dart';
import '../payments/payment_screen.dart';
import '../bookings/booking_screens.dart';
import '../bookings/appointment_payment_summary.dart'
    show boutiqueVisitMinutes, dressTrialFeeCents;
import '../src/design.dart' show ivory, line, Surface;
import '../src/model.dart';
import 'package_api.dart';
import 'rental_date_fields.dart';
import 'package_screen.dart' show PackageChoiceScreen;
import 'package_fitting_presentation.dart';
import 'rental_handover_screen.dart';
import 'fitting_result_screen.dart';
import 'fitting_proposal_screen.dart';
import 'rental_extension_status.dart';
import '../shared/list_controls.dart';
import '../catalogue/stock_filters.dart';

String rentalDay(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

enum _FittingMethod { completed, visit, skip }

typedef _CompletedVisit = ({String id, int attendedAt, int creditCents});

class PackageRentalScreen extends StatefulWidget {
  const PackageRentalScreen({
    super.key,
    required this.selection,
    required this.api,
    this.staff = false,
    this.onBookFitting,
    this.editDates = false,
  });
  final PackageSelection selection;
  final HttpPackageApi api;
  final bool staff;
  final bool editDates;
  final Future<bool> Function(Map<String, String> dates)? onBookFitting;
  @override
  State<PackageRentalScreen> createState() => _PackageRentalState();
}

class _PackageRentalState extends State<PackageRentalScreen> {
  late Map<String, String> savedDates = {...dates};
  late int planRevision = widget.selection.data['rentalPlanRevision'] ?? 0;
  late int choiceRevision = widget.selection.data['fittingChoiceRevision'] ?? 0;
  bool get hasSavedDates => savedDates.values.every((v) => v.isNotEmpty);
  bool get datesChanged =>
      !hasSavedDates || dates.entries.any((e) => savedDates[e.key] != e.value);
  bool get hasDates => dates.values.every((v) => v.isNotEmpty);
  bool get arrangeFitting => !widget.staff && !widget.editDates;
  late bool editingDates = widget.editDates || !hasSavedDates;
  List<Map<String, dynamic>>? stockItems;
  bool checkingStock = false;
  int stockRequest = 0;
  bool get needsStockCheck =>
      !widget.staff &&
      (widget.selection.selectedGowns.isNotEmpty ||
          (widget.selection.data['selectedAccessories'] as List? ?? [])
              .isNotEmpty) &&
      widget.selection.data['rentalId'] == null &&
      widget.selection.data['invoiceId'] == null;

  Future<bool> checkStock() async {
    if (!needsStockCheck) return true;
    if (dates.values.any((v) => v.isEmpty)) return false;
    final epoch = ++stockRequest;
    setState(() {
      checkingStock = true;
      stockItems = null;
      error = null;
    });
    try {
      final result = await widget.api.transport.businessRequest(
        '/v1/package-selections/${widget.selection.id}/check-plan',
        body: {...dates, 'revision': planRevision},
      );
      if (!mounted || epoch != stockRequest) return false;
      setState(() {
        checkingStock = false;
        stockItems = (result['items'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        if (arrangeFitting && result['available'] != true) {
          error =
              'Check availability for your selected items before continuing.';
        }
      });
      return result['available'] == true;
    } catch (e) {
      if (mounted && epoch == stockRequest) {
        setState(() {
          checkingStock = false;
          error = e is PaymentFailure
              ? e.message
              : 'Could not check availability. Please try again.';
        });
      }
      return false;
    }
  }

  String get completedFittingPath =>
      '/v1/package-selections/${widget.selection.id}/completed-fitting';
  List<_CompletedVisit> completedVisits = [];
  String? completedError, selectedVisitId;
  bool loadingCompleted = false, choosingVisit = false;
  int completedRequest = 0;
  _CompletedVisit? get selectedVisit =>
      completedVisits.where((visit) => visit.id == selectedVisitId).firstOrNull;

  bool get canCheckCompleted {
    final selection = widget.selection;
    return arrangeFitting &&
        hasSavedDates &&
        selection.selectedGowns.isNotEmpty &&
        selection.data['invoiceId'] == null &&
        selection.data['rentalId'] == null &&
        selection.data['fittingDecision'] == null &&
        selection.data['reusedFittingAppointmentId'] == null;
  }

  void invalidateCompletedFittings() {
    completedRequest++;
    loadingCompleted = false;
    completedVisits = [];
    completedError = null;
  }

  Future<void> loadCompletedFittings() async {
    if (!canCheckCompleted || datesChanged || loadingCompleted) return;
    final request = ++completedRequest;
    setState(() {
      loadingCompleted = true;
      completedVisits = [];
      completedError = null;
    });
    try {
      final result = await widget.api.transport.businessRequest(
        completedFittingPath,
      );
      final visits = [
        for (final visit in result['visits'] as List)
          (
            id: visit['id'] as String,
            attendedAt: visit['attendedAt'] as int,
            creditCents: visit['creditCents'] as int,
          ),
      ];
      if (!mounted || request != completedRequest) return;
      setState(() {
        loadingCompleted = false;
        completedVisits = visits;
      });
    } catch (e) {
      if (!mounted || request != completedRequest) return;
      setState(() {
        loadingCompleted = false;
        completedError = e is PaymentFailure
            ? e.message
            : 'Could not check your fittings. Try again.';
      });
    }
  }

  Future<void> chooseCompletedFitting() async {
    if (busy || choosingVisit || datesChanged || completedVisits.isEmpty) {
      return;
    }
    final request = completedRequest;
    choosingVisit = true;
    try {
      final id = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Select a completed fitting'),
          children: [
            for (final visit in completedVisits)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, visit.id),
                child: Text(paymentDateLabel(visit.attendedAt)),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (id == null || !mounted || request != completedRequest) return;
      setState(() {
        selectedVisitId = id;
        error = null;
      });
    } finally {
      choosingVisit = false;
    }
  }

  Future<void> linkCompletedFitting(_CompletedVisit visit) async {
    if (busy || datesChanged || method != _FittingMethod.completed) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.transport.businessRequest(
        completedFittingPath,
        body: {
          'appointmentId': visit.id,
          'planRevision': planRevision,
          'selectionRevision': widget.selection.data['selectionRevision'] ?? 0,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fitting linked. Luvly will review your chosen gown and prepare your proposal.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        if (e is PaymentFailure && e.code == 'COMPLETED_FITTING_UNAVAILABLE') {
          selectedVisitId = null;
          await loadCompletedFittings();
          if (!mounted) return;
        }
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not check your fitting. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeGowns() async {
    setState(() => busy = true);
    try {
      final packages = await widget.api.catalogue();
      final matches = packages.where(
        (p) => p.id == widget.selection.data['packageId'],
      );
      if (matches.isEmpty) throw StateError('Package unavailable');
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PackageChoiceScreen(
            package: matches.first,
            api: widget.api,
            revising: widget.selection,
            initialRentalPlan: {...dates},
          ),
        ),
      );
      if (mounted && saved == true) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not open your package. Refresh your plans and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final deposit = TextEditingController();
  final form = GlobalKey<FormState>();
  late final requestId = packageRequestId();
  late Map<String, String> dates = {
    for (final k in ['pickupDate', 'eventDate', 'returnDate'])
      k: widget.selection.data['rentalPlan']?[k] ?? '',
  };
  String? appointmentId, error;
  bool busy = false, frozen = false;
  late _FittingMethod method =
      widget.selection.data['fittingChoice']?['mode'] == 'SkipFitting'
      ? _FittingMethod.skip
      : _FittingMethod.visit;
  late bool consent =
      widget.selection.data['fittingChoice']?['accepted'] == true;
  String? get skipBlockedReason {
    final selection = widget.selection;
    if (selection.data['reusedFittingAppointmentId'] != null) {
      return 'A completed fitting is already linked to this package.';
    }
    final rental = selection.data['rental'];
    if (rental is Map && !['Expired', 'Cancelled'].contains(rental['state'])) {
      return 'This package already has a rental reservation.';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeVisit = selection.appointments.any((visit) {
      final status = visit['status'];
      final expiry = visit['paymentExpiresAt'];
      return status == 'Confirmed' ||
          status == 'Requested' ||
          (status == 'AwaitingPayment' && expiry is num && expiry > now);
    });
    return activeVisit
        ? 'Cancel your active appointment before requesting this.'
        : null;
  }

  @override
  void initState() {
    super.initState();
    loadCompletedFittings();
  }

  bool get waived =>
      widget.selection.data['fittingDecision']?['mode'] == 'Waived' &&
      widget.selection.data['fittingDecision']?['state'] == 'Approved';
  int? previewDeposit;
  bool get policy => widget.selection.data['paymentPolicyVersion'] == 1;
  int get fittingCredit =>
      widget.selection.appointments.any(
        (b) => (b['availableCreditCents'] as int? ?? 0) > 0,
      )
      ? dressTrialFeeCents
      : 0;
  int get policyDeposit =>
      (widget.selection.totalCents / 2).round() - fittingCredit;
  int get allowedRentalDays =>
      3 + widget.selection.services.where((s) => s.addsRentalDay).length;
  @override
  void dispose() {
    deposit.dispose();
    super.dispose();
  }

  Future<void> pick(String key) async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime(now.year, now.month, now.day);
    final event = DateTime.tryParse(dates['eventDate'] ?? ''),
        pickup = DateTime.tryParse(dates['pickupDate'] ?? '');
    var first = today, last = today.add(const Duration(days: 365));
    if (key == 'pickupDate') {
      if (event == null) {
        setState(() => error = 'Choose your wedding / event date first.');
        return;
      }
      last = event;
      final earliest = event.subtract(Duration(days: allowedRentalDays - 1));
      if (earliest.isAfter(first)) first = earliest;
    } else if (key == 'returnDate') {
      if (event == null || pickup == null) {
        setState(() => error = 'Choose the event and pickup dates first.');
        return;
      }
      first = event;
      last = pickup.add(Duration(days: allowedRentalDays - 1));
    }
    if (first.isAfter(last)) {
      setState(
        () => error = 'Review the wedding and pickup dates before continuing.',
      );
      return;
    }
    var initial = DateTime.tryParse(dates[key] ?? '') ?? today;
    if (initial.isBefore(first) || initial.isAfter(last)) {
      initial = first;
    }
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (value != null && mounted) {
      final next = rentalDay(value);
      if (dates[key] == next) return;
      setState(() {
        stockRequest++;
        checkingStock = false;
        stockItems = null;
        invalidateCompletedFittings();
        dates[key] = next;
        error = null;
        final event = DateTime.tryParse(dates['eventDate'] ?? ''),
            pickup = DateTime.tryParse(dates['pickupDate'] ?? ''),
            returned = DateTime.tryParse(dates['returnDate'] ?? '');
        if (event != null &&
            pickup != null &&
            (pickup.isAfter(event) ||
                event.difference(pickup).inDays >= allowedRentalDays)) {
          dates['pickupDate'] = '';
          dates['returnDate'] = '';
        } else if (event != null &&
            returned != null &&
            (returned.isBefore(event) ||
                (pickup != null &&
                    returned.difference(pickup).inDays >= allowedRentalDays))) {
          dates['returnDate'] = '';
        }
      });
      if (!datesChanged) loadCompletedFittings();
      if (needsStockCheck && dates.values.every((v) => v.isNotEmpty)) {
        await checkStock();
      }
    }
  }

  Future<void> saveRentalDates() async {
    final result = await widget.api.transport.businessRequest(
      '/v1/package-selections/${widget.selection.id}/plan',
      body: {...dates, 'revision': planRevision},
    );
    planRevision = result['revision'] as int? ?? planRevision + 1;
    savedDates = {...dates};
  }

  void restoreRentalDates() {
    setState(() {
      dates = {...savedDates};
      editingDates = false;
      stockRequest++;
      stockItems = null;
      checkingStock = false;
      error = null;
    });
    loadCompletedFittings();
  }

  Future<void> submit() async {
    if (busy || checkingStock) return;
    if (widget.staff) {
      if ((!policy && !form.currentState!.validate()) ||
          (!waived && appointmentId == null)) {
        setState(
          () => error =
              'Choose the completed fitting. The package deposit is calculated automatically.',
        );
        return;
      }
    } else if (dates.values.any((v) => v.isEmpty)) {
      setState(() => error = 'Choose pickup, event and return dates.');
      return;
    }
    if (arrangeFitting &&
        method == _FittingMethod.skip &&
        (skipBlockedReason != null || !consent)) {
      setState(
        () => error =
            skipBlockedReason ??
            'Acknowledge the fit guidance before requesting no fitting.',
      );
      return;
    }
    if (!widget.staff &&
        (dates['pickupDate']!.compareTo(dates['eventDate']!) > 0 ||
            dates['eventDate']!.compareTo(dates['returnDate']!) > 0)) {
      setState(() => error = 'Dates must follow pickup → event → return.');
      return;
    }
    if (arrangeFitting && method == _FittingMethod.completed && !datesChanged) {
      if (selectedVisit case final visit? when !loadingCompleted) {
        await linkCompletedFitting(visit);
      } else {
        await chooseCompletedFitting();
      }
      return;
    }
    setState(() {
      busy = true;
      error = null;
      if (widget.staff) frozen = true;
    });
    try {
      if (!await checkStock()) return;
      if (widget.staff) {
        await widget.api.transport.businessRequest(
          '/v1/package-selections/${widget.selection.id}/confirm-rental',
          body: {
            'appointmentId': waived ? '' : appointmentId,
            if (widget.selection.data['fittingDecision'] != null)
              'fittingRevision':
                  widget.selection.data['fittingDecisionRevision'],
            'requestId': requestId,
            'depositCents': policy
                ? policyDeposit
                : quoteAmountCents(deposit.text),
            'planRevision': planRevision,
          },
        );
      } else if (datesChanged) {
        await saveRentalDates();
      }
      if (!mounted) return;
      if (arrangeFitting && method == _FittingMethod.completed) {
        setState(() => editingDates = false);
        await loadCompletedFittings();
        return;
      }
      if (arrangeFitting) {
        final result = await widget.api.transport.businessRequest(
          '/v1/package-selections/${widget.selection.id}/fitting-choice',
          body: {
            'mode': method == _FittingMethod.skip ? 'SkipFitting' : 'TryOn',
            'accepted': consent,
            'revision': choiceRevision,
          },
        );
        choiceRevision =
            result['fittingChoiceRevision'] as int? ?? choiceRevision;
      }
      if (!mounted) return;
      if (widget.staff) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Inventory held for 15 minutes. Customer can now pay the booking deposit.',
            ),
          ),
        );
      }
      if (arrangeFitting &&
          method == _FittingMethod.visit &&
          widget.onBookFitting != null) {
        setState(() => editingDates = false);
        final booked = await widget.onBookFitting!({...dates});
        if (!mounted || !booked) return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save the rental. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get canChooseCompleted =>
      !datesChanged && !loadingCompleted && completedVisits.isNotEmpty;

  String get completedDescription {
    if (datesChanged) {
      return 'Save your rental dates to check eligible fittings.';
    }
    if (loadingCompleted) return 'Checking your eligible fittings…';
    if (completedError != null) {
      return 'We couldn’t check your previous fittings.';
    }
    if (completedVisits.isEmpty) {
      return 'No eligible fitting for these dates. Paid visits appear after attendance is recorded.';
    }
    return 'Continue with an eligible previous fitting.';
  }

  String get fittingActionLabel => switch (method) {
    _FittingMethod.completed when datesChanged => 'Save rental dates',
    _FittingMethod.completed when selectedVisit == null =>
      'Select completed fitting',
    _FittingMethod.completed => 'Continue with selected fitting',
    _FittingMethod.skip => 'Request staff review',
    _FittingMethod.visit when widget.onBookFitting != null =>
      'Choose fitting time',
    _FittingMethod.visit => 'Save fitting preference',
  };

  bool get fittingActionReady =>
      !busy &&
      !checkingStock &&
      hasDates &&
      switch (method) {
        _FittingMethod.completed => datesChanged || canChooseCompleted,
        _FittingMethod.skip => consent && skipBlockedReason == null,
        _FittingMethod.visit => true,
      };

  Widget fittingPreferences(BuildContext context) {
    final theme = Theme.of(context);
    final visit = selectedVisit;
    final blocked = skipBlockedReason;
    final included = widget.selection.data['rental']?['state'] == 'Locked';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'How would you like to proceed?',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 10),
        RadioGroup<_FittingMethod>(
          groupValue: method,
          onChanged: (value) {
            if (busy || value == null || value == method) return;
            setState(() {
              method = value;
              consent = false;
              error = null;
            });
          },
          child: Column(
            children: [
              if (canCheckCompleted) ...[
                FittingPreferenceCard(
                  value: _FittingMethod.completed,
                  selected: method == _FittingMethod.completed,
                  enabled: !busy && canChooseCompleted,
                  title: 'Use a completed fitting',
                  description: completedDescription,
                ),
                if (loadingCompleted)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      semanticsLabel: 'Checking eligible completed fittings',
                    ),
                  ),
                if (completedError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: busy ? null : loadCompletedFittings,
                      child: const Text('Retry fitting check'),
                    ),
                  ),
              ],
              FittingPreferenceCard(
                value: _FittingMethod.visit,
                selected: method == _FittingMethod.visit,
                enabled: !busy,
                title: 'Visit for a fitting',
                description: 'Try gowns and confirm your fit with our team.',
              ),
              FittingPreferenceCard(
                value: _FittingMethod.skip,
                selected: method == _FittingMethod.skip,
                enabled: !busy && blocked == null,
                title: 'Rent without a fitting',
                description:
                    blocked ??
                    'Request staff review of your chosen gown and size.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (method == _FittingMethod.visit)
          fittingInformation(
            context,
            title: included
                ? 'Included · $boutiqueVisitMinutes-minute fitting'
                : '${packageMoney(dressTrialFeeCents)} · $boutiqueVisitMinutes-minute fitting',
            detail: included
                ? 'Your reserved package covers this visit.'
                : 'One fee covers the visit. Pay within 15 minutes or before the visit starts, whichever comes first, to confirm the fitting. After attendance, an eligible fee can be credited once towards the booking deposit.',
          ),
        if (method == _FittingMethod.completed && canChooseCompleted)
          fittingInformation(
            context,
            title: visit == null
                ? 'Choose a previous visit'
                : paymentDateLabel(visit.attendedAt),
            detail: visit == null
                ? 'Link an eligible visit to this package. No new fitting fee is due.'
                : 'No new fitting fee. Your ${packageMoney(visit.creditCents)} credit goes towards the booking deposit after Luvly reviews your selection.',
            action: visit == null
                ? null
                : TextButton(
                    onPressed: busy ? null : chooseCompletedFitting,
                    child: const Text('Change fitting'),
                  ),
          ),
        if (method == _FittingMethod.skip && blocked == null) ...[
          fittingInformation(
            context,
            title: 'Staff review required',
            detail:
                'No fitting fee. Luvly will review your gown, size and dates before issuing a booking deposit.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: consent,
            onChanged: busy ? null : (v) => setState(() => consent = v == true),
            title: Text(
              'I choose to rent without a fitting and understand that size guidance does not guarantee fit.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Fitting & payment terms'),
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Further visits before booking show their fee before payment; follow-up fittings covered by a reserved package have no new fitting fee. Renting without a fitting creates no new fitting credit. Agree to the final items and adjustments before the 50% booking deposit. Stock is held for 15 minutes when that deposit is issued. Balance and refundable security are due before pickup.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget fittingInformation(
    BuildContext context, {
    required String title,
    required String detail,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Surface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(detail, style: theme.textTheme.bodyMedium),
          ?action,
        ],
      ),
    );
  }

  Widget fittingFooter(BuildContext context) {
    final theme = Theme.of(context);
    final hint = busy || checkingStock
        ? null
        : !hasDates
        ? 'Choose the wedding, pickup and return dates to continue.'
        : method == _FittingMethod.skip && !consent
        ? 'Acknowledge the fit guidance to request staff review.'
        : null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ivory,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 652),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((error ?? hint) case final message?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: error == null
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: fittingActionReady ? submit : null,
                  child: Text(
                    busy
                        ? 'Saving…'
                        : checkingStock
                        ? 'Checking availability…'
                        : fittingActionLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selection,
        bookings = s.appointments
            .where(
              (b) =>
                  b['type'] == 'Dress Trial' &&
                  (policy ? ['Completed'] : ['Confirmed', 'Completed'])
                      .contains(b['status']),
            )
            .toList();
    final extra = s.services.where((v) => v.addsRentalDay).length;
    return Scaffold(
      appBar: AppBar(
        title: AssistantExclusion(
          child: Text(
            widget.staff
                ? 'Confirm package rental'
                : widget.editDates
                ? 'Change rental dates'
                : 'Arrange your fitting',
          ),
        ),
      ),
      bottomNavigationBar: arrangeFitting ? fittingFooter(context) : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: arrangeFitting
                  ? const EdgeInsets.fromLTRB(20, 8, 20, 16)
                  : const EdgeInsets.all(24),
              children: [
                if (arrangeFitting)
                  FittingGownSummary(selection: s)
                else ...[
                  Text(
                    s.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Package total ${packageMoney(s.totalCents)}'),
                  for (final g in s.selectedGowns)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.checkroom),
                      title: Text('${g['name']} · ${g['size']}'),
                    ),
                  for (final a
                      in (s.data['selectedAccessories'] as List? ?? []))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.diamond_outlined),
                      title: Text(a['name']),
                    ),
                ],
                const SizedBox(height: 16),
                if (widget.staff || editingDates) ...[
                  Text(
                    'Rental period: up to ${3 + extra} calendar days, including pickup and return.',
                  ),
                  const SizedBox(height: 12),
                ],
                if (!widget.staff && !editingDates)
                  if (arrangeFitting)
                    PackageRentalDatesCard(
                      dates: dates,
                      onEdit: busy
                          ? null
                          : () => setState(() => editingDates = true),
                    )
                  else
                    RentalDatesSummary(
                      dates: dates,
                      onEdit: busy
                          ? null
                          : () => setState(() => editingDates = true),
                    ),
                if (!widget.staff && editingDates && hasSavedDates)
                  TextButton(
                    onPressed: busy ? null : restoreRentalDates,
                    child: const Text('Keep saved dates'),
                  ),
                if (!widget.staff && !hasSavedDates)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This saved package has no rental dates yet. Add them once to continue.',
                    ),
                  ),
                if (widget.staff || editingDates)
                  for (final entry in {
                    'eventDate': 'Wedding / event date',
                    'pickupDate': 'Pickup date',
                    'returnDate': 'Return date',
                  }.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(entry.value),
                      subtitle: Text(
                        dates[entry.key]!.isEmpty
                            ? 'Choose a date'
                            : arrangeFitting
                            ? rentalDateLabel(dates[entry.key]!)
                            : dates[entry.key]!,
                      ),
                      trailing: widget.staff
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: widget.staff || busy
                          ? null
                          : () => pick(entry.key),
                    ),
                if (needsStockCheck) ...[
                  if (checkingStock) const LinearProgressIndicator(),
                  if (stockItems != null)
                    for (final item in stockItems!)
                      if (item['status'] != 'Available')
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.info_outline),
                          title: Text(
                            '${item['name']}${item['size'] == null ? '' : ' · ${item['size']}'}',
                          ),
                          subtitle: Text(
                            item['status'] == 'Unavailable'
                                ? 'Unavailable for these dates. Choose another size, gown or rental period.'
                                : 'Availability needs confirmation. Contact Luvly or choose another size or gown.',
                          ),
                        ),
                  if (stockItems?.any((r) => r['status'] != 'Available') ==
                      true)
                    OutlinedButton.icon(
                      onPressed: busy ? null : changeGowns,
                      icon: const Icon(Icons.checkroom),
                      label: const Text('Change gown selection'),
                    ),
                ],
                if (widget.staff) ...[
                  const Divider(height: 32),
                  if (waived)
                    const Text(
                      'No fitting · customer request approved by staff. No fitting fee is charged.',
                    ),
                  if (bookings.isEmpty && !waived)
                    const Text(
                      'Complete the fitting visit before confirming the package rental.',
                    ),
                  if (!waived)
                    DropdownButtonFormField<String>(
                      initialValue: appointmentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: policy
                            ? 'Completed fitting'
                            : 'Confirmed appointment',
                      ),
                      items: bookings
                          .map(
                            (b) => DropdownMenuItem<String>(
                              value: b['id'],
                              child: Text(
                                '${b['type']} · ${DateTime.fromMillisecondsSinceEpoch(b['startAt']).toLocal()}',
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
                  if (policy)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '50% package booking deposit: ${packageMoney((s.totalCents / 2).round())}',
                            ),
                            Text(
                              'Paid fitting credit: −${packageMoney(fittingCredit)}',
                            ),
                            Text(
                              'Booking deposit to pay now: ${packageMoney(policyDeposit)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Balance before pickup: ${packageMoney(s.totalCents - (s.totalCents / 2).round())}',
                            ),
                            Text(
                              'Separate refundable security: ${packageMoney(s.selectedGowns.length * packageGownSecurityCents)} (${s.selectedGowns.length} gown(s) × RM300)',
                            ),
                            const Text(
                              'Fitting credit is applied once, only after attendance. Security is not part of the package price.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!policy)
                    Form(
                      key: form,
                      child: TextFormField(
                        controller: deposit,
                        enabled: !frozen,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Agreed booking deposit (RM)',
                        ),
                        onChanged: (v) => setState(
                          () => previewDeposit = quoteAmountCents(v),
                        ),
                        validator: (v) {
                          final cents = quoteAmountCents(v ?? '');
                          return cents == null ||
                                  cents > s.totalCents ||
                                  (s.totalCents - cents > 0 &&
                                      s.totalCents - cents < 100)
                              ? 'Enter RM1 up to the package total; remaining balance must be RM0 or at least RM1.'
                              : null;
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (previewDeposit != null && previewDeposit! <= s.totalCents)
                    Text(
                      'Remaining balance: ${packageMoney(s.totalCents - previewDeposit!)}',
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirmation checks all items and begins a 15-minute hold. Verified deposit payment locks inventory. The deposit is deducted from the package total.',
                  ),
                ] else if (arrangeFitting) ...[
                  const SizedBox(height: 20),
                  fittingPreferences(context),
                ],
                if (!arrangeFitting && error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!arrangeFitting) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed:
                        busy ||
                            checkingStock ||
                            (!widget.staff &&
                                widget.editDates &&
                                !datesChanged) ||
                            (widget.staff &&
                                ((!waived && bookings.isEmpty) ||
                                    dates.values.any((v) => v.isEmpty)))
                        ? null
                        : submit,
                    child: Text(
                      busy
                          ? 'Saving…'
                          : widget.staff
                          ? 'Confirm & hold for 15 minutes'
                          : 'Save date changes',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AccessoryStockScreen extends StatefulWidget {
  const AccessoryStockScreen({super.key, required this.api});
  final HttpPackageApi api;
  @override
  State<AccessoryStockScreen> createState() => _AccessoryStockState();
}

class _AccessoryStockState extends State<AccessoryStockScreen> {
  late Future<dynamic> feed = load();
  bool busy = false;
  String query = '',
      category = 'All categories',
      quantityFilter = 'All quantities';
  Future<dynamic> load() =>
      widget.api.transport.businessRequest('/v1/accessory-stock');
  Future<void> edit(Map<String, dynamic> item) async {
    final text = TextEditingController(
      text: item['quantity']?.toString() ?? '',
    );
    final form = GlobalKey<FormState>();
    final count = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(item['name']),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the total units in your project inventory, including reserved items. Unset quantities are unknown.',
              ),
              TextFormField(
                controller: text,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total quantity'),
                validator: (v) =>
                    v != null &&
                        RegExp(r'^\d{1,3}$').hasMatch(v) &&
                        int.parse(v) <= 100
                    ? null
                    : 'Enter 0–100 whole units.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(c, int.parse(text.text));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (count == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.transport.businessRequest(
        '/v1/accessory-stock',
        body: {
          'id': item['id'],
          'quantity': count,
          'revision': item['revision'],
        },
      );
      if (mounted) setState(() => feed = load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PaymentFailure ? e.message : 'Could not save stock.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Accessory stock'),
      actions: [
        IconButton(
          onPressed: busy ? null : () => setState(() => feed = load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<dynamic>(
      future: feed,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => feed = load()),
              child: const Text('Could not load stock · Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = (snapshot.data['items'] as List)
            .where(
              (i) =>
                  matchesListSearch(query, [
                    i['name'],
                    i['category'],
                    i['size'],
                  ]) &&
                  (category == 'All categories' || category == i['category']) &&
                  matchesStockQuantity(i, quantityFilter),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Available quantities are checked for the selected rental dates.',
            ),
            const SizedBox(height: 16),
            ListSearchField(
              value: query,
              hint: 'Search accessories',
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ListFilterSelect(
                  label: 'Category',
                  value: category,
                  options: [
                    'All categories',
                    ...{
                      for (final i in snapshot.data['items'] as List)
                        i['category'] as String,
                    },
                  ],
                  onChanged: (v) => setState(() => category = v),
                ),
                ListFilterSelect(
                  label: 'Stock quantity',
                  value: quantityFilter,
                  options: stockQuantityFilters
                      .where((s) => s != 'Custom order')
                      .toList(),
                  onChanged: (v) => setState(() => quantityFilter = v),
                ),
                if (query.isNotEmpty ||
                    category != 'All categories' ||
                    quantityFilter != 'All quantities')
                  ResetListFilters(
                    onReset: () => setState(() {
                      query = '';
                      category = 'All categories';
                      quantityFilter = 'All quantities';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No accessories match your search and filters.'),
              ),
            for (final item in items)
              ListTile(
                leading: Image.asset(
                  item['image'],
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
                title: Text(item['name']),
                subtitle: Text(
                  '${item['category']} · Total: ${item['quantity'] ?? 'Not configured'}',
                ),
                trailing: TextButton(
                  onPressed: busy
                      ? null
                      : () => edit(Map<String, dynamic>.from(item)),
                  child: const Text('Edit stock'),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class PackageRentalSummary extends StatelessWidget {
  const PackageRentalSummary({
    super.key,
    required this.selection,
    required this.api,
    required this.staff,
    required this.reload,
    this.manager = false,
    this.actionsOnly = false,
    this.showCancel = true,
    this.showCustomerPlanningActions = true,
    this.showProposal = true,
    this.showNavigationActions = true,
  });
  final PackageSelection selection;
  final HttpPackageApi api;
  final bool staff;
  final bool manager;
  final bool actionsOnly, showCancel;
  final bool showCustomerPlanningActions, showProposal;
  final bool showNavigationActions;
  final VoidCallback reload;
  @override
  Widget build(BuildContext context) {
    final s = selection,
        r = s.data['rental'] as Map?,
        plan = s.data['rentalPlan'] as Map?;
    final state =
        r?['state'] == 'Held' &&
            (r!['expiresAt'] as int) <= DateTime.now().millisecondsSinceEpoch
        ? 'Expired'
        : r?['state'];
    final editable = r == null || ['Cancelled', 'Expired'].contains(state);
    final legacyInvoice = r == null && s.invoice != null;
    final resultReady = s.data['fittingWorkflowVersion'] == 2
        ? s.data['fittingReady'] == true
        : s.data['fittingWorkflowVersion'] != 1 ||
              s.data['fittingDecision']?['state'] == 'Approved';
    final balance = s.data['balanceInvoice'];
    void open(bool confirm, {bool editDates = false}) => Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PackageRentalScreen(
          selection: s,
          api: api,
          staff: confirm,
          editDates: !confirm && editDates,
          onBookFitting:
              confirm ||
                  editDates ||
                  s.appointments.any(
                    (b) => [
                      'Requested',
                      'Confirmed',
                      'AwaitingPayment',
                    ].contains(b['status']),
                  )
              ? null
              : (dates) async {
                  final model = AppScope.of(context);
                  final requestId = packageRequestId();
                  var booked = false;
                  final cutoff = DateTime.parse(
                    dates['pickupDate']!,
                  ).subtract(const Duration(days: 1));
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BookingRequestForm(
                        uid: model.accountId!,
                        name: model.name,
                        phone: model.phone,
                        packageName: s.name,
                        fittingIncluded: s.data['rental']?['state'] == 'Locked',
                        latestAppointmentDay: cutoff,
                        onSubmitted: () => booked = true,
                        submitRequest: (type, start, notes) =>
                            api.book(s.id, type, start, notes, requestId),
                      ),
                    ),
                  );
                  return booked;
                },
        ),
      ),
    ).then((_) => reload());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!actionsOnly) ...[
          const SizedBox(height: 12),
          if (legacyInvoice)
            const Text(
              'This package already has an invoice. Staff must review that payment before arranging inventory; no extra deposit will be issued here.',
            ),
          if (plan != null)
            Text(
              'Rental: ${plan['pickupDate']} → ${plan['returnDate']} · Event ${plan['eventDate']}',
            ),
          if (s.data['fittingChoice']?['mode'] == 'SkipFitting')
            Text(
              s.data['fittingDecision']?['state'] == 'Approved'
                  ? 'No fitting · request approved'
                  : 'No fitting · awaiting staff review',
            ),
          if (s.data['fittingDecision']?['mode'] == 'Attended' &&
              s.data['fittingWorkflowVersion'] != 2)
            Text(
              s.data['fittingDecision']?['state'] == 'Approved'
                  ? 'Fitting outcome: satisfied · ready to book'
                  : 'Fitting outcome: changes required · review the selection',
            ),
          if (r != null) ...[
            RentalExtensionStatus(
              rental: Map<String, dynamic>.from(r),
              api: api.transport,
              staff: staff,
              onChanged: (_) => reload(),
            ),
            Text(
              'Inventory: ${state == 'Held' ? 'Awaiting booking deposit' : state}',
            ),
            if (state == 'Held')
              Text(
                'Pay deposit before ${DateTime.fromMillisecondsSinceEpoch(r['expiresAt']).toLocal()}',
              ),
            if (state == 'Expired')
              const Text(
                'Hold expired. Staff can check stock and confirm again.',
              ),
            if (state == 'PaymentReview')
              const Text(
                'Payment needs staff review. Inventory is not locked.',
              ),
            Text(
              'Deposit ${packageMoney(r['depositCents'])} · Balance ${packageMoney(r['balanceCents'])}',
            ),
            if (r['policyVersion'] == 1) ...[
              Text(
                '50% deposit ${packageMoney(r['depositTargetCents'])} = fitting credit ${packageMoney(r['fittingCreditCents'])} + booking payment ${packageMoney(r['depositCents'])}',
              ),
              Text(
                'Refundable security: ${packageMoney(r['securityCents'])} · ${r['securityState'] ?? 'Due after deposit'}',
              ),
              const Text(
                'Pay balance and security before pickup (ideally 1–3 days earlier). Items cannot be handed over until both are verified paid.',
              ),
              if (r['fulfilment'] != null) Text('Items: ${r['fulfilment']}'),
              if (r['refundDueCents'] != null)
                Text(
                  'Security refund: ${packageMoney(r['refundDueCents'])} · ${r['securityState']}',
                ),
            ],
            if (balance != null)
              Text(
                'Balance payment: ${SandboxInvoice.fromJson(Map<String, dynamic>.from(balance)).statusLabel}',
              ),
          ],
        ],
        if (showProposal && s.data['fittingWorkflowVersion'] == 2)
          FittingProposalPanel(
            selection: s,
            api: api,
            staff: staff,
            manager: manager,
            reload: reload,
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (staff &&
                editable &&
                !legacyInvoice &&
                (s.data['fittingWorkflowVersion'] != 2 ||
                    (s.data['invoiceId'] == null &&
                        s.data['rentalId'] == null)))
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  s.data['fittingChoice']?['mode'] == 'SkipFitting'
                      ? 'Review no-fitting request'
                      : 'Record fitting outcome',
                ),
                onPressed: plan == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (_) =>
                              FittingResultScreen(selection: s, api: api),
                        ),
                      ).then((_) => reload()),
              ),
            if (!staff && editable && showCustomerPlanningActions)
              OutlinedButton(
                onPressed: () => open(false, editDates: plan != null),
                child: Text(
                  plan == null ? 'Set rental dates' : 'Change rental dates',
                ),
              ),
            if (!staff &&
                showCustomerPlanningActions &&
                editable &&
                !legacyInvoice &&
                plan != null &&
                !s.appointments.any(
                  (b) => [
                    'Requested',
                    'Confirmed',
                    'AwaitingPayment',
                  ].contains(b['status']),
                ))
              OutlinedButton(
                onPressed: () => open(false),
                child: const Text('Fitting options'),
              ),
            if (staff &&
                editable &&
                !legacyInvoice &&
                s.invoice?.state != 'SandboxPaid')
              FilledButton(
                onPressed: plan == null || !resultReady
                    ? null
                    : () => open(true),
                child: const Text('Confirm package rental'),
              ),
            if (staff && editable && !resultReady)
              const Text(
                'Record the fitting decision and obtain customer agreement to the current proposal before confirming the rental. No fitting visit is required for an approved no-fitting request.',
              ),
            if (staff && plan == null)
              const Text('Customer must set rental dates first.'),
            if (staff &&
                showCancel &&
                r != null &&
                r['collectedAt'] == null &&
                ['Held', 'Locked', 'PaymentReview'].contains(state))
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Cancel this rental?'),
                      content: const Text(
                        'Items will be released. Paid amounts require staff refund review.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Keep rental'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Cancel rental'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await api.transport.businessRequest(
                      '/v1/rentals/${r['id']}/cancel',
                      body: {},
                    );
                    reload();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is PaymentFailure
                                ? e.message
                                : 'Could not cancel rental.',
                          ),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Cancel rental'),
              ),
            if (showNavigationActions && r != null)
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LivePaymentsScreen(
                      staff: staff,
                      manager: manager,
                      initialInvoiceId: state == 'Held'
                          ? r['invoiceId']
                          : r['paymentState'] != 'Paid'
                          ? r['balanceInvoiceId']
                          : r['securityInvoiceId'],
                    ),
                  ),
                ).then((_) => reload()),
                child: const Text('Payments & security deposit'),
              ),
            if (showNavigationActions &&
                staff &&
                r?['policyVersion'] == 1 &&
                state == 'Locked')
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RentalHandoverScreen(
                      rental: Map<String, dynamic>.from(r!),
                      api: api.transport,
                      manager: manager,
                    ),
                  ),
                ).then((_) => reload()),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Pickup, return & security'),
              ),
          ],
        ),
      ],
    );
  }
}
