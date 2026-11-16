import '../payments/payment_api.dart';
import '../packages/package_api.dart' show packageRequestId;
import 'booking_api.dart' show bookingDay;
import 'booking_repository.dart' show appointmentHours, appointmentTypes;

String rescheduleReason(String? code) => switch (code) {
  'RESCHEDULE_PAYMENT_REQUIRED' =>
    'Complete the fitting payment before changing this appointment. An unpaid hold cannot be moved.',
  'RESCHEDULE_PAYMENT_REVIEW' =>
    'This fitting payment needs staff review before the appointment can be changed.',
  'RESCHEDULE_NOT_AVAILABLE' =>
    'Only a confirmed appointment that has not started can be rescheduled. Contact Luvly for help with this visit.',
  'BOOKING_RESERVATION_CHANGED' =>
    'This appointment’s reserved time needs staff review. Your original visit has not been changed.',
  'APPOINTMENT_PACKAGE_REVIEW_REQUIRED' =>
    'The linked package needs staff review before this appointment can be changed.',
  'FITTING_DATE_CONFLICT' =>
    'Choose a fitting within the dates allowed by your package, before the event and no later than the displayed fitting deadline.',
  _ =>
    'This appointment cannot be rescheduled right now. Contact Luvly for assistance.',
};

class RescheduleContext {
  const RescheduleContext({
    required this.id,
    required this.type,
    required this.start,
    required this.revision,
    required this.serverNow,
    required this.lastDay,
    required this.eligible,
    required this.feePreserved,
    this.reason,
  });
  final String id, type;
  final DateTime start, serverNow, lastDay;
  final int revision;
  final bool eligible, feePreserved;
  final String? reason;
  DateTime get firstDay {
    final myt = serverNow.add(const Duration(hours: 8));
    return DateTime(myt.year, myt.month, myt.day);
  }

  factory RescheduleContext.parse(dynamic raw, String id) {
    try {
      final d = Map<String, dynamic>.from(raw as Map);
      final date = DateTime.parse(d['latestDay'] as String);
      if (d['appointmentId'] != id ||
          d['revision'] is! int ||
          d['revision'] < 1 ||
          d['startAt'] is! int ||
          d['serverNow'] is! int ||
          !appointmentTypes.contains(d['type']) ||
          d['eligible'] is! bool ||
          d['feePreserved'] is! bool ||
          bookingDay(date) != d['latestDay'] ||
          d['eligible'] == true && d['reason'] != null) {
        throw const FormatException();
      }
      final result = RescheduleContext(
        id: id,
        type: d['type'],
        start: DateTime.fromMillisecondsSinceEpoch(d['startAt'], isUtc: true),
        revision: d['revision'],
        serverNow: DateTime.fromMillisecondsSinceEpoch(
          d['serverNow'],
          isUtc: true,
        ),
        lastDay: date,
        eligible: d['eligible'],
        feePreserved: d['feePreserved'],
        reason: d['reason'] as String?,
      );
      if (result.eligible &&
          (result.lastDay.isBefore(result.firstDay) ||
              !result.start.isAfter(result.serverNow))) {
        throw const FormatException();
      }
      return result;
    } catch (_) {
      throw const PaymentFailure(
        'Could not load the latest appointment. Reopen Bookings and try again.',
      );
    }
  }
}

class RescheduleResult {
  const RescheduleResult(this.start, this.status);
  final DateTime start;
  final String status;
}

class RescheduleApi {
  RescheduleApi({HttpPaymentApi? transport})
    : _transport = transport ?? HttpPaymentApi(),
      _owns = transport == null;
  final HttpPaymentApi _transport;
  final bool _owns;
  String requestId() => packageRequestId();
  Future<RescheduleContext> load(String id) async => RescheduleContext.parse(
    await _transport.businessRequest('/v1/appointments/$id/reschedule'),
    id,
  );
  Future<List<int>> hours(DateTime day, String type) async {
    final d = await _transport.businessRequest(
      '/v1/appointment-availability?day=${bookingDay(day)}&type=${Uri.encodeComponent(type)}',
    );
    if (d is! Map ||
        d['hours'] is! List ||
        (d['hours'] as List).any(
          (h) => h is! int || !appointmentHours.contains(h),
        )) {
      throw const PaymentFailure(
        'Could not load available times. Please try again.',
      );
    }
    return (List<int>.from(d['hours']).toSet().toList()..sort());
  }

  Future<RescheduleResult> save(
    RescheduleContext current,
    DateTime start,
    String requestId,
  ) async {
    final d = await _transport.businessRequest(
      '/v1/appointments/${current.id}/reschedule',
      body: {
        'revision': current.revision,
        'startAt': start.millisecondsSinceEpoch,
        'requestId': requestId,
      },
    );
    if (d is! Map ||
        d['appointmentId'] != current.id ||
        d['startAt'] is! int ||
        d['status'] is! String) {
      throw const PaymentFailure(
        'The update response could not be confirmed. Retry with this same time or reopen Bookings to check.',
      );
    }
    return RescheduleResult(
      DateTime.fromMillisecondsSinceEpoch(d['startAt'], isUtc: true),
      d['status'],
    );
  }

  void close() {
    if (_owns) _transport.close();
  }
}
