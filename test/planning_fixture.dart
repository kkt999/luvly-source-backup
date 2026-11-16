// Isolated UI fixtures only. Never imported by the application.
import 'dart:convert';
import 'package:luvly_app/planning/planning_api.dart';
import 'package:luvly_app/payments/payment_api.dart';

Map<String, dynamic> planningFixture({
  bool empty = false,
  String uid = 'bride',
}) {
  final now = DateTime.utc(2026, 10, 16, 2).millisecondsSinceEpoch;
  Map<String, dynamic> payment(String state, int? amount, String? id) => {
    'state': state,
    'amountCents': amount,
    'invoiceId': id,
    'expiresAt': null,
  };
  final visit = {
    'id': 'next-visit',
    'type': 'Bridal Consultation',
    'status': 'Confirmed',
    'startAt': now + 86400000,
    'expiresAt': null,
    'fittingPayment': payment('NotIssued', null, null),
  };
  final next = {
    'type': 'payments',
    'title': 'Settle your package balance',
    'detail': 'The package balance must be verified paid before pickup.',
    'targetId': 'balance-invoice',
  };
  final plan = {
    'id': '0123456789abcdef0123456789abcdef',
    'name': 'Bridal Essentials',
    'createdAt': now - 86400000,
    'totalCents': 89900,
    'eventDate': '2026-10-21',
    'pickupDate': '2026-10-20',
    'returnDate': '2026-10-22',
    'daysToEvent': 5,
    'rentalState': 'Locked',
    'needsReview': false,
    'completed': false,
    'deposit': payment('Paid', 44950, 'deposit-invoice'),
    'balance': payment('AwaitingPayment', 44950, 'balance-invoice'),
    'security': payment('AwaitingPayment', 30000, 'security-invoice'),
    'gowns': [
      {'name': 'Ivory satin gown', 'size': 'M', 'colour': 'Ivory'},
    ],
    'accessoriesCount': 2,
    'appointmentIds': ['completed-visit', 'next-visit'],
    'nextVisit': visit,
    'nextAction': next,
    'steps': [
      {
        'key': 'selection',
        'title': 'Package selection',
        'state': 'Saved',
        'detail': 'Gown preferences saved. This is not a stock reservation.',
      },
      {
        'key': 'dates',
        'title': 'Rental dates',
        'state': 'Saved',
        'detail': '2026-10-20 → 2026-10-22',
      },
      {
        'key': 'fitting',
        'title': 'Consultation & fitting',
        'state': 'Completed',
        'detail': 'Staff recorded a completed Dress Trial.',
      },
      {
        'key': 'deposit',
        'title': 'Booking deposit & reservation',
        'state': 'Reserved',
        'detail': 'Inventory is locked for the agreed rental period.',
      },
      {
        'key': 'balance',
        'title': 'Package balance',
        'state': 'AwaitingPayment',
        'detail': 'Balance and refundable security are separate payments.',
      },
      {
        'key': 'security',
        'title': 'Refundable security',
        'state': 'AwaitingPayment',
        'detail': 'Refunds follow return inspection; they are not automatic.',
      },
      {
        'key': 'pickup',
        'title': 'Gown pickup',
        'state': 'Scheduled',
        'detail': 'Agreed pickup: 2026-10-20',
      },
      {
        'key': 'return',
        'title': 'Return & inspection',
        'state': 'NotCollected',
        'detail': 'Agreed return: 2026-10-22',
      },
    ],
  };
  return {
    'uid': uid,
    'environment': 'sandbox',
    'timezone': 'Asia/Kuala_Lumpur',
    'generatedAt': now,
    'today': '2026-10-16',
    'plans': empty ? [] : [plan],
    'appointments': empty
        ? []
        : [
            visit,
            {
              'id': 'completed-visit',
              'type': 'Dress Trial',
              'status': 'Completed',
              'startAt': now - 86400000,
              'expiresAt': null,
              'fittingPayment': payment('Paid', 5000, 'fitting-invoice'),
            },
          ],
    'nextAppointment': empty ? null : visit,
    'nextAction': empty
        ? {
            'type': 'packages',
            'title': 'Start your bridal plan',
            'detail': 'Explore packages, choose your gown and plan your dates.',
            'targetId': null,
          }
        : next,
    'warnings': {'undatedAppointments': 0, 'reviewPayments': 0},
  };
}

class FakePlanningApi implements PlanningApi {
  FakePlanningApi({Map<String, dynamic>? body})
    : body = body ?? planningFixture();
  Map<String, dynamic> body;
  bool fail = false, closed = false;
  int calls = 0;
  Future<PlanningSnapshot> Function(String uid)? onLoad;
  @override
  Future<PlanningSnapshot> load(String uid) async {
    calls++;
    if (onLoad != null) return onLoad!(uid);
    if (fail) throw const PaymentFailure('Cannot connect to Luvly right now.');
    final copy = Map<String, dynamic>.from(jsonDecode(jsonEncode(body)))
      ..['uid'] = uid;
    return PlanningSnapshot(copy, uid: uid);
  }

  @override
  void close() {
    closed = true;
  }
}
