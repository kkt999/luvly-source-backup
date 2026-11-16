import 'package:flutter/material.dart';
import '../payments/payment_api.dart';

String planningMoney(int? cents) =>
    cents == null ? 'Not issued' : 'RM ${(cents / 100).toStringAsFixed(2)}';
String planningDay(String? value) {
  if (value == null) return 'Not set';
  final date = DateTime.parse(value);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String planningTime(int value) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    value,
    isUtc: true,
  ).add(const Duration(hours: 8));
  return '${planningDay(date.toIso8601String().substring(0, 10))} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} MYT';
}

String planningStatus(String value) => switch (value) {
  'Saved' => 'Saved',
  'PackageSaved' => 'Package saved',
  'NotSet' => 'Not set',
  'Confirmed' => 'Confirmed',
  'Completed' => 'Completed',
  'Waived' => 'No fitting · approved',
  'WaiverRequested' => 'No fitting · under review',
  'ChangesRequired' => 'Selection changes needed',
  'NotBooked' => 'Not booked',
  'ConsultationBooked' => 'Consultation booked',
  'AwaitingUpdate' => 'Awaiting staff update',
  'AwaitingPayment' => 'Awaiting payment',
  'PendingVerification' => 'Checking payment',
  'Paid' => 'Paid',
  'NeedsReview' => 'Team review needed',
  'NotIssued' => 'Not issued',
  'Closed' => 'Review completed',
  'NotRequired' => 'Not required',
  'Held' => 'Temporarily held',
  'NotReserved' => 'Not reserved',
  'Reserved' || 'Locked' => 'Reserved',
  'Expired' => 'Expired',
  'Cancelled' => 'Cancelled',
  'DatePassed' => 'Date passed',
  'Scheduled' => 'Scheduled',
  'ReadyForPickup' => 'Pickup today',
  'Collected' => 'Collected',
  'NotCollected' => 'Not collected',
  'AwaitingReturn' => 'Awaiting return',
  'Returned' => 'Returned',
  'Overdue' => 'Overdue',
  'RefundDue' => 'Refund awaiting team',
  'RefundRecorded' => 'Refund recorded',
  'Deducted' => 'Inspection deductions',
  'Requested' => 'Request recorded',
  'Declined' => 'Declined',
  _ => 'Check with our team',
};
bool planningDone(String value) => const {
  'Saved',
  'Completed',
  'Reserved',
  'Locked',
  'Paid',
  'Collected',
  'Returned',
  'RefundRecorded',
  'NotRequired',
  'Waived',
}.contains(value);

class PlanningAction {
  PlanningAction(this.data);
  final Map<String, dynamic> data;
  String get type => data['type'];
  String get title => data['title'];
  String get detail => data['detail'];
  String? get targetId => data['targetId'];
}

class PlanningPayment {
  PlanningPayment(this.data);
  final Map<String, dynamic> data;
  String get state => data['state'];
  int? get amount => data['amountCents'];
  String? get invoiceId => data['invoiceId'];
  int? get expiresAt => data['expiresAt'];
}

class PlanningVisit {
  PlanningVisit(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get type => data['type'];
  String get status => data['status'];
  int? get startAt => data['startAt'];
  PlanningPayment get payment =>
      PlanningPayment(Map<String, dynamic>.from(data['fittingPayment']));
}

class BridalPlan {
  BridalPlan(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get name => data['name'];
  String? get eventDate => data['eventDate'];
  int? get daysToEvent => data['daysToEvent'];
  String get rentalState => data['rentalState'];
  bool get completed => data['completed'];
  List<Map<String, dynamic>> get steps =>
      (data['steps'] as List).map((v) => Map<String, dynamic>.from(v)).toList();
  List<Map<String, dynamic>> get gowns =>
      (data['gowns'] as List).map((v) => Map<String, dynamic>.from(v)).toList();
  PlanningAction get next =>
      PlanningAction(Map<String, dynamic>.from(data['nextAction']));
  PlanningPayment payment(String key) =>
      PlanningPayment(Map<String, dynamic>.from(data[key]));
}

class PlanningSnapshot {
  PlanningSnapshot(this.data, {required String uid}) {
    if (data['uid'] != uid ||
        data['environment'] != 'sandbox' ||
        data['timezone'] != 'Asia/Kuala_Lumpur' ||
        data['generatedAt'] is! int ||
        data['plans'] is! List ||
        data['appointments'] is! List ||
        data['nextAction'] is! Map) {
      throw const PaymentFailure(
        'Could not verify your planning information. Please refresh.',
      );
    }
    for (final plan in plans) {
      if (plan.id.isEmpty ||
          plan.name.isEmpty ||
          plan.steps.length != 8 ||
          plan.data['appointmentIds'] is! List ||
          plan.data['completed'] is! bool) {
        throw const PaymentFailure(
          'Some planning details need to be reloaded. Please refresh.',
        );
      }
      for (final key in ['eventDate', 'pickupDate', 'returnDate']) {
        final date = plan.data[key];
        if (date != null &&
            (date is! String ||
                DateTime.tryParse(date) == null ||
                DateTime.parse(date).toIso8601String().substring(0, 10) !=
                    date)) {
          throw const PaymentFailure(
            'Could not verify the saved dates. Please refresh.',
          );
        }
      }
      for (final key in ['deposit', 'balance', 'security']) {
        final payment = plan.payment(key);
        if (!const {
              'Paid',
              'NeedsReview',
              'Expired',
              'AwaitingPayment',
              'NotIssued',
              'Closed',
              'NotRequired',
              'PendingVerification',
            }.contains(payment.state) ||
            (payment.amount != null && payment.amount! < 0)) {
          throw const PaymentFailure(
            'Could not verify payment status. Please refresh.',
          );
        }
      }
      plan.next.type;
      plan.gowns;
    }
    visits;
  }
  final Map<String, dynamic> data;
  int get generatedAt => data['generatedAt'];
  List<BridalPlan> get plans => (data['plans'] as List)
      .map((v) => BridalPlan(Map<String, dynamic>.from(v)))
      .toList();
  List<PlanningVisit> get visits => (data['appointments'] as List)
      .map((v) => PlanningVisit(Map<String, dynamic>.from(v)))
      .toList();
  PlanningVisit? get nextVisit => data['nextAppointment'] == null
      ? null
      : PlanningVisit(Map<String, dynamic>.from(data['nextAppointment']));
  PlanningAction get next =>
      PlanningAction(Map<String, dynamic>.from(data['nextAction']));
  int get reviewPayments =>
      (data['warnings'] as Map?)?['reviewPayments'] as int? ?? 0;
  List<int> get deadlines => [
    for (final plan in plans)
      for (final key in ['deposit', 'balance', 'security'])
        if (plan.payment(key).expiresAt case final int expiry) expiry,
    for (final visit in visits)
      if (visit.data['expiresAt'] case final int expiry) expiry,
  ].where((expiry) => expiry > generatedAt).toList();
}

abstract class PlanningApi {
  Future<PlanningSnapshot> load(String uid);
  void close();
}

class HttpPlanningApi implements PlanningApi {
  HttpPlanningApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi(),
      owns = transport == null;
  final HttpPaymentApi transport;
  final bool owns;
  @override
  Future<PlanningSnapshot> load(String uid) async => PlanningSnapshot(
    Map<String, dynamic>.from(
      await transport.businessRequest('/v1/my-planning'),
    ),
    uid: uid,
  );
  @override
  void close() {
    if (owns) transport.close();
  }
}

String planningError(Object error) {
  if (error is PaymentFailure &&
      !error.message.startsWith('Cannot connect to Luvly') &&
      !error.message.startsWith('Unable to complete')) {
    return error.message;
  }
  return 'We could not load your saved plan. Check your connection and refresh. Your records have not been changed.';
}

class PlanningNavigationScope extends InheritedWidget {
  const PlanningNavigationScope({
    super.key,
    required this.observer,
    required super.child,
  });
  final RouteObserver<PageRoute<dynamic>> observer;
  static RouteObserver<PageRoute<dynamic>>? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PlanningNavigationScope>()?.observer;
  @override
  bool updateShouldNotify(PlanningNavigationScope oldWidget) =>
      observer != oldWidget.observer;
}
