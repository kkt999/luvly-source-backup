import 'package:flutter/material.dart';
import '../bookings/booking_repository.dart' show bookingStatusLabel;
import '../payments/payment_api.dart';
import '../src/design.dart' show CustomerUi, blush;
import 'package_api.dart';
import 'rental_workspace.dart';

enum CustomerPackageAction {
  details,
  fitting,
  includedFitting,
  appointment,
  payment,
  proposal,
}

class CustomerPackageStep {
  const CustomerPackageStep(
    this.status,
    this.description,
    this.label,
    this.action, {
    this.targetId,
    this.attention = false,
  });
  final String status, description, label;
  final CustomerPackageAction action;
  final String? targetId;
  final bool attention;
}

const _activeVisitStates = {'Confirmed', 'Requested', 'AwaitingPayment'};
const _closedVisitStates = {
  'Completed',
  'Cancelled',
  'Declined',
  'Expired',
  'NoShow',
};

int? _visitTime(Map<String, dynamic> visit) {
  final scheduled = visit['scheduledStartAt'];
  final attended = visit['actualAttendedAt'];
  final start = visit['startAt'];
  if (visit['status'] == 'Completed' && attended is int && attended > 0) {
    return attended;
  }
  if (scheduled is int && scheduled > 0) return scheduled;
  return start is int && start > 0 ? start : null;
}

bool _fittingHoldEnded(Map<String, dynamic> visit, DateTime now) {
  final end = visit['paymentExpiresAt'];
  final start = _visitTime(visit);
  final current = now.millisecondsSinceEpoch;
  return visit['status'] == 'AwaitingPayment' &&
      ((end is num && end <= current) || (start != null && start <= current));
}

Map<String, dynamic>? _activePackageVisit(
  PackageSelection selection,
  DateTime now,
) {
  final visits = selection.appointments
      .where((visit) => _activeVisitStates.contains(visit['status']))
      .toList();
  final cutoff = now.millisecondsSinceEpoch;
  int priority(Map<String, dynamic> visit) {
    if (_fittingHoldEnded(visit, now)) return 2;
    return (_visitTime(visit) ?? cutoff) > cutoff ? 0 : 1;
  }

  // Prefer the next live visit over historical or expired holds. The backend
  // can still require staff review when a past visit remains Confirmed.
  visits.sort((a, b) {
    final rank = priority(a);
    final order = rank.compareTo(priority(b));
    if (order != 0) return order;
    final aTime = _visitTime(a) ?? 0;
    final bTime = _visitTime(b) ?? 0;
    return rank == 0 ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
  });
  return visits.firstOrNull;
}

Map<String, dynamic>? _relevantPackageVisit(StaffRentalView view) {
  final selection = view.selection;
  final active = _activePackageVisit(selection, view.now);
  if (active != null) return active;
  final history = selection.appointments
      .where((visit) => _closedVisitStates.contains(visit['status']))
      .toList();
  final linkedId =
      view.rental['finalFitting']?['appointmentId'] ??
      selection.data['fittingDecision']?['appointmentId'] ??
      selection.data['reusedFittingAppointmentId'];
  if (linkedId is String) {
    final linked = history
        .where((visit) => visit['id'] == linkedId)
        .firstOrNull;
    if (linked != null) return linked;
  }
  int priority(Map<String, dynamic> visit) {
    if (visit['status'] == 'Completed' && visit['type'] == 'Dress Trial') {
      return 0;
    }
    return visit['status'] == 'Completed' ? 1 : 2;
  }

  history.sort((a, b) {
    final order = priority(a).compareTo(priority(b));
    return order != 0
        ? order
        : (_visitTime(b) ?? 0).compareTo(_visitTime(a) ?? 0);
  });
  return history.firstOrNull;
}

/// Customer-facing next step from the saved record; never confirms a payment,
/// a fitting, or physical readiness merely from the displayed amount/date.
CustomerPackageStep customerPackageStep(PackageSelection s, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final v = StaffRentalView(s, now: clock);
  final r = v.rental, stage = v.stage;
  const details = CustomerPackageAction.details;
  const payment = CustomerPackageAction.payment;
  CustomerPackageStep info(String status, String text) =>
      CustomerPackageStep(status, text, 'View details', details);
  if (stage == 'Cancelled') {
    return info(
      'Cancelled',
      'Your payment and refund history are kept in the details.',
    );
  }
  if (stage == 'Expired') {
    return info(
      'Reservation hold ended',
      'Contact Luvly to recheck your dates and availability.',
    );
  }
  SandboxInvoice? savedInvoice;
  try {
    savedInvoice = s.invoice;
  } on PaymentFailure {
    return info(
      'Payment details need review',
      'Please refresh this plan or contact Luvly before paying.',
    );
  }
  final reviewed = [s.data['invoice'], s.data['balanceInvoice']]
      .whereType<Map>()
      .any(
        (i) =>
            i['reviewResolution'] == null &&
            (i['reviewReason'] != null || i['state'] == 'ReviewRequired'),
      );
  if (stage == 'Needs review' ||
      reviewed ||
      r['reviewReason'] != null ||
      r['refundReviewRequired'] == true) {
    return CustomerPackageStep(
      'Team review needed',
      'Please check the existing payment before paying again.',
      'Check payment status',
      payment,
      targetId: savedInvoice?.id,
      attention: true,
    );
  }
  if (stage == 'Returned') {
    return info(
      'Returned',
      r['securityState'] == 'RefundDue'
          ? 'Your security deposit refund is awaiting the team.'
          : r['securityState'] == 'RefundRecorded'
          ? 'Your security deposit refund has been recorded.'
          : 'View your return inspection and security deposit details.',
    );
  }
  if (stage == 'Collected') {
    if (r['returnIssue']?['state'] == 'Open') {
      return info(
        'Return needs review',
        'Luvly is reviewing the reported return issue.',
      );
    }
    final today = clock
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    return info(
      v.dates['returnDate'] is String &&
              (v.dates['returnDate'] as String).compareTo(today) < 0
          ? 'Return overdue'
          : 'Collected',
      'Return your items by ${v.returned} for inspection.',
    );
  }
  if (v.extensionPending) {
    return CustomerPackageStep(
      'Date change pending',
      'Your current rental dates stay in place until the extension payment is verified.',
      'Review extension payment',
      payment,
      targetId: r['pendingExtension']['invoiceId'],
    );
  }
  if (stage == 'Awaiting deposit') {
    return CustomerPackageStep(
      'Booking deposit due',
      'Complete the booking deposit before the reservation hold ends.',
      savedInvoice?.canPay == true
          ? 'Pay booking deposit'
          : 'Check payment status',
      payment,
      targetId: savedInvoice?.id,
      attention: true,
    );
  }
  if (stage == 'Reserved') {
    if (v.needsReview) {
      return CustomerPackageStep(
        'Check payment details',
        'Confirm the existing payment status before continuing.',
        'Check payment status',
        payment,
        targetId: r['balanceInvoiceId'],
        attention: true,
      );
    }
    if (v.balance.due && (r['balanceCents'] as int? ?? 0) > 0) {
      if (r['balanceInvoiceId'] is! String) {
        return info(
          'Payment details needed',
          'Luvly needs to confirm the balance payment record.',
        );
      }
      return CustomerPackageStep(
        'Balance due',
        '${v.balance.amountLabel} remaining · due before pickup.',
        v.balance.status == 'Verifying' ||
                v.balance.status == 'Preparing payment'
            ? 'Check balance payment'
            : 'Pay remaining balance',
        payment,
        targetId: r['balanceInvoiceId'],
        attention: true,
      );
    }
    if (v.security.due) {
      if (r['securityInvoiceId'] is! String) {
        return info(
          'Payment details needed',
          'Luvly needs to confirm the security deposit payment record.',
        );
      }
      return CustomerPackageStep(
        'Security deposit due',
        '${v.security.amountLabel} refundable security · separate from the package price.',
        'Pay security deposit',
        payment,
        targetId: r['securityInvoiceId'],
        attention: true,
      );
    }
    if (v.finalFittingPending) {
      final visit = _activePackageVisit(s, clock);
      final target = visit?['id'];
      if (visit != null && (target is! String || target.isEmpty)) {
        return info(
          'Final fitting needed',
          'Open your package to review the linked appointment.',
        );
      }
      return CustomerPackageStep(
        'Final fitting needed',
        'Complete your final fitting before collecting your gown.',
        visit == null ? 'Arrange final fitting' : 'View appointment',
        visit == null
            ? CustomerPackageAction.includedFitting
            : CustomerPackageAction.appointment,
        targetId: target,
      );
    }
    return info(
      'Reserved',
      'Pickup is scheduled for ${v.pickup}. Luvly will confirm handover readiness.',
    );
  }
  if (savedInvoice != null) {
    return CustomerPackageStep(
      'Package payment',
      'View the payment and receipt for this package.',
      'View payment',
      payment,
      targetId: savedInvoice.id,
    );
  }
  final q = s.data['fittingQuote'] as Map?,
      decision = s.data['fittingDecision'] as Map?;
  if (q != null && ['AwaitingCustomer', 'Considering'].contains(q['state'])) {
    return const CustomerPackageStep(
      'Proposal ready',
      'Review your items, adjustments and final total before agreeing.',
      'Review fitting proposal',
      CustomerPackageAction.proposal,
    );
  }
  if (q?['state'] == 'Outdated') {
    return info(
      'Updated proposal needed',
      'Luvly needs to review the changes to your plan.',
    );
  }
  if (decision?['state'] == 'Reselect' ||
      decision?['state'] == 'NeedsChanges') {
    return const CustomerPackageStep(
      'Choose another gown',
      'Your fitting history and eligible credit stay with this plan.',
      'Review your selection',
      CustomerPackageAction.proposal,
    );
  }
  if (decision?['state'] == 'Considering') {
    return info(
      'Saved for later',
      'Your choices are saved, but stock is not reserved.',
    );
  }
  if (decision?['state'] == 'Declined') {
    return info(
      'Not proceeding',
      'No new booking deposit is issued. Your history is kept.',
    );
  }
  if (decision != null) {
    return info(
      decision['state'] == 'Approved'
          ? 'Awaiting reservation'
          : 'Awaiting team review',
      decision['state'] == 'Approved'
          ? 'Luvly will check stock and prepare your booking deposit.'
          : 'Luvly is reviewing your fitting and chosen items.',
    );
  }
  final a = _activePackageVisit(s, clock);
  if (a != null) {
    if (a['status'] == 'AwaitingPayment') {
      if (_fittingHoldEnded(a, clock)) {
        return info(
          'Fitting hold ended',
          'Check your appointment before arranging another time.',
        );
      }
      final invoiceId = a['fittingInvoiceId'];
      if (invoiceId is! String || invoiceId.isEmpty) {
        return info(
          'Fitting confirmation needed',
          'Luvly needs to confirm the payment record for your visit.',
        );
      }
      return CustomerPackageStep(
        'Fitting payment due',
        'Complete or check the fitting fee to confirm your time.',
        'Pay fitting fee',
        payment,
        targetId: invoiceId,
        attention: true,
      );
    }
    final scheduled = _visitTime(a);
    if (scheduled != null && scheduled <= clock.millisecondsSinceEpoch) {
      return info(
        'Visit awaiting update',
        'Luvly will update the outcome of your visit.',
      );
    }
    final target = a['id'];
    if (target is! String || target.isEmpty) {
      return info(
        'Appointment details needed',
        'Open your package to review the linked appointment.',
      );
    }
    return CustomerPackageStep(
      a['status'] != 'Confirmed'
          ? 'Appointment requested'
          : a['type'] == 'Dress Trial'
          ? 'Fitting booked'
          : 'Appointment booked',
      a['status'] == 'Requested'
          ? 'Luvly will confirm your appointment time.'
          : 'View the details for your confirmed appointment.',
      'View appointment',
      CustomerPackageAction.appointment,
      targetId: target,
    );
  }
  if (s.data['serviceOnly'] == true &&
      !s.appointments.any((item) => item['status'] == 'Completed')) {
    if (s.data['serviceAppointmentType'] is String) {
      return const CustomerPackageStep(
        'Service quote saved',
        'Choose an available appointment time for your service.',
        'Choose appointment time',
        CustomerPackageAction.fitting,
      );
    }
    return info(
      'Service quote saved',
      'Contact Luvly to arrange the timing and payment for your selected services.',
    );
  }
  if (s.data['fittingChoice']?['mode'] == 'SkipFitting') {
    return info(
      'No-fitting request sent',
      'Luvly will review your gown, size and dates.',
    );
  }
  if (s.appointments.any((a) => a['status'] == 'Completed')) {
    return info(
      'Awaiting team review',
      s.data['reusedFittingAppointmentId'] != null
          ? 'Your completed fitting is linked. Luvly will review your gown selection and prepare your proposal.'
          : 'Your visit is recorded. Luvly will review the next step.',
    );
  }
  final plan = s.data['rentalPlan'];
  final hasDates =
      plan is Map &&
      [
        'pickupDate',
        'eventDate',
        'returnDate',
      ].every((k) => plan[k] is String && (plan[k] as String).isNotEmpty);
  return CustomerPackageStep(
    hasDates ? 'Fitting not booked' : 'Plan incomplete',
    hasDates
        ? 'Choose a visit time, or request to rent without a fitting.'
        : 'Add rental dates to check your chosen items.',
    hasDates ? 'Arrange fitting' : 'Complete your plan',
    CustomerPackageAction.fitting,
  );
}

String selectedPackageGownLabel(Map<String, dynamic> gown) {
  final parts = [
    gown['name'],
    gown['size'],
  ].whereType<String>().where((value) => value.trim().isNotEmpty);
  return parts.isEmpty ? 'Selected gown' : parts.join(' · ');
}

class CustomerPackageCard extends StatelessWidget {
  const CustomerPackageCard({
    super.key,
    required this.selection,
    required this.onContinue,
    required this.onDetails,
    this.busy = false,
  });

  final PackageSelection selection;
  final VoidCallback onContinue, onDetails;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = StaffRentalView(selection);
    final step = customerPackageStep(selection, now: view.now);
    final visit = _relevantPackageVisit(view);
    final gowns = selection.selectedGowns;
    final accessories = selection.data['selectedAccessories'];
    final detailsOnly = step.action == CustomerPackageAction.details;
    final rentalStatus = switch (view.stage) {
      'Not reserved' when selection.data['rentalId'] != null =>
        'Status unavailable',
      'Not reserved'
          when gowns.isEmpty && (accessories is! List || accessories.isEmpty) =>
        null,
      final stage => stage,
    };

    return Card(
      color: CustomerUi.paper,
      elevation: 1,
      shadowColor: const Color(0x24382E31),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      shape: const RoundedRectangleBorder(borderRadius: CustomerUi.cardRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                selection.name,
                style: theme.textTheme.headlineMedium,
              ),
            ),
            if (gowns.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                gowns.length == 1
                    ? selectedPackageGownLabel(gowns.single)
                    : '${gowns.length} gowns selected',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  label: 'Plan progress: ${step.status}',
                  excludeSemantics: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: step.attention ? const Color(0xFFFFF3E5) : blush,
                      borderRadius: const BorderRadius.all(Radius.circular(50)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      child: Text(
                        step.status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: step.attention
                              ? rentalAmber
                              : CustomerUi.activeText,
                        ),
                      ),
                    ),
                  ),
                ),
                if (rentalStatus != null &&
                    selection.data['serviceOnly'] != true)
                  Semantics(
                    label: 'Package rental: $rentalStatus',
                    excludeSemantics: true,
                    child: Text(
                      'Rental · $rentalStatus',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const Divider(height: 20),
            if (selection.data['serviceOnly'] == true)
              Text('Event date · ${view.event}')
            else
              _PackageDates(view: view),
            if (visit != null) ...[
              const SizedBox(height: 10),
              _LinkedVisit(visit: visit, now: view.now),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Package total',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    packageMoney(selection.totalCents),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (visit == null ||
                ![
                  'Fitting booked',
                  'Appointment booked',
                ].contains(step.status)) ...[
              Text(step.description, style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
            FilledButton(
              onPressed: busy ? null : (detailsOnly ? onDetails : onContinue),
              child: Text(
                detailsOnly ? 'View package details' : step.label,
                textAlign: TextAlign.center,
              ),
            ),
            if (!detailsOnly)
              TextButton(
                onPressed: busy ? null : onDetails,
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text(
                  'View package details',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackageDates extends StatelessWidget {
  const _PackageDates({required this.view});
  final StaffRentalView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickup = view.pickup;
    final returned = view.returned;
    final missingPickup = pickup == 'Not set';
    final missingReturn = returned == 'Not set';
    final String rentalPeriod;
    if (missingPickup && missingReturn) {
      rentalPeriod = 'Not set';
    } else if (missingPickup) {
      rentalPeriod = 'Return $returned';
    } else if (missingReturn) {
      rentalPeriod = 'Pickup $pickup';
    } else if (pickup == returned) {
      rentalPeriod = pickup;
    } else {
      final pickupSpace = pickup.indexOf(' ');
      final returnSpace = returned.indexOf(' ');
      rentalPeriod =
          pickup.substring(pickupSpace) == returned.substring(returnSpace)
          ? '${pickup.substring(0, pickupSpace)}–$returned'
          : '$pickup – $returned';
    }

    Widget date(String label, String value, {String? semantics}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall,
          semanticsLabel: semantics,
        ),
      ],
    );
    final event = date('Wedding / event', view.event);
    final period = date(
      'Rental period',
      rentalPeriod,
      semantics: missingPickup || missingReturn
          ? null
          : 'Pickup $pickup. Return $returned.',
    );

    return LayoutBuilder(
      builder: (context, space) {
        final stack =
            space.maxWidth < MediaQuery.textScalerOf(context).scale(275);
        return Flex(
          direction: stack ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stack) event else Expanded(child: event),
            const SizedBox(width: 14, height: 7),
            if (stack) period else Expanded(child: period),
          ],
        );
      },
    );
  }
}

class _LinkedVisit extends StatelessWidget {
  const _LinkedVisit({required this.visit, required this.now});
  final Map<String, dynamic> visit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stamp = _visitTime(visit);
    final fitting = visit['type'] == 'Dress Trial';
    final past = stamp != null && stamp <= now.millisecondsSinceEpoch;
    final label = switch (visit['status']) {
      'Confirmed' when past =>
        fitting
            ? 'Confirmed fitting · awaiting update'
            : 'Confirmed appointment · awaiting update',
      'Confirmed' when stamp != null =>
        fitting ? 'Upcoming fitting' : 'Upcoming appointment',
      'Confirmed' => fitting ? 'Confirmed fitting' : 'Confirmed appointment',
      'Completed' => fitting ? 'Completed fitting' : 'Completed appointment',
      'Requested' => fitting ? 'Fitting requested' : 'Appointment requested',
      'AwaitingPayment' when _fittingHoldEnded(visit, now) =>
        'Fitting hold ended',
      'AwaitingPayment' => 'Fitting awaiting payment',
      final String status =>
        '${fitting ? 'Fitting' : 'Appointment'} · ${bookingStatusLabel(status)}',
      _ => fitting ? 'Fitting appointment' : 'Linked appointment',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CustomerUi.linen,
        borderRadius: CustomerUi.controlRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.event_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  if (stamp != null)
                    Text(
                      paymentDateLabel(stamp),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
