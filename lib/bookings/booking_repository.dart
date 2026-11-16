import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:stream_transform/stream_transform.dart';
import '../payments/payment_api.dart';
import '../src/contact_validation.dart';
import '../packages/package_api.dart' show packageRequestId;
import 'booking_outcome.dart';
export 'booking_outcome.dart';

const makeupTrial = 'Makeup Trial';
const gownAppointmentTypes = ['Dress Trial', 'Bridal Consultation'];
const appointmentTypes = [...gownAppointmentTypes, makeupTrial];
const appointmentHours = [10, 11, 12, 14, 15, 16];
String bookingStatusLabel(String status) => status == 'AwaitingPayment'
    ? 'Awaiting payment'
    : status == 'NoShow'
    ? 'Did not attend'
    : status;
DateTime malaysiaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
DateTime appointmentUtc(DateTime day, int hour) =>
    DateTime.utc(day.year, day.month, day.day, hour - 8);
String appointmentLabel(DateTime utc) {
  final d = utc.toUtc().add(const Duration(hours: 8));
  return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} MYT';
}

bool validAppointmentTime(DateTime value, DateTime now) {
  final local = value.toUtc().add(const Duration(hours: 8));
  return value.isAfter(now) &&
      value.isBefore(now.add(const Duration(days: 180))) &&
      appointmentHours.contains(local.hour) &&
      local.minute == 0 &&
      local.second == 0 &&
      local.millisecond == 0 &&
      local.microsecond == 0;
}

bool hasBookingContactDetails(String name, String phone) {
  final nameLength = name.trim().length;
  final phoneLength = phone.trim().length;
  return nameLength > 0 &&
      nameLength <= 100 &&
      phoneLength >= 9 &&
      phoneLength <= 25;
}

bool canMoveBooking(String from, String to, {required bool staff}) => staff
    ? (['Requested', 'AwaitingPayment'].contains(from) && to == 'Cancelled') ||
          (from == 'Confirmed' &&
              ['Completed', 'Cancelled', 'NoShow'].contains(to))
    : ['Requested', 'Confirmed', 'AwaitingPayment'].contains(from) &&
          to == 'Cancelled';

class BookingRequest {
  BookingRequest(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get uid => data['uid'] as String;
  String get name => data['name'] as String;
  String get phone => data['phone'] as String;
  String get displayPhone => formatContactPhone(phone);
  String get type => data['type'] as String;
  String get status => data['status'] as String;
  String get notes => data['notes'] as String;
  String get dressName => data['dressName'] as String;
  String get response => data['response'] as String;
  String get slotKey => data['slotKey'] as String;
  int get revision => data['revision'] as int;
  DateTime get scheduledStart =>
      (data['startAt'] as Timestamp).toDate().toUtc();
  bool get hasActualAttendance => data['actualAttendedAt'] is Timestamp;
  DateTime get start => hasActualAttendance
      ? (data['actualAttendedAt'] as Timestamp).toDate().toUtc()
      : scheduledStart;
}

abstract class BookingRepository {
  Stream<List<BookingRequest>> watch({
    String? uid,
    String? staffUid,
    bool manager = false,
  });
  Future<BookingOutcome?> create({
    required String uid,
    required String name,
    required String phone,
    required String type,
    required DateTime start,
    required String notes,
    String dressId = '',
    String dressName = '',
    String? requestId,
  });
  Future<void> transition(
    BookingRequest booking,
    String status, {
    required String actor,
    required bool staff,
    String response = '',
  });
}

class FirebaseBookingRepository implements BookingRepository {
  FirebaseBookingRepository({FirebaseFirestore? database})
    : _database = database;
  final FirebaseFirestore? _database;
  FirebaseFirestore get db => _database ?? FirebaseFirestore.instance;
  @override
  Stream<List<BookingRequest>> watch({
    String? uid,
    String? staffUid,
    bool manager = false,
  }) {
    final appointments = db.collection('appointments');
    if (uid != null) return _rows(appointments.where('uid', isEqualTo: uid));
    if (staffUid == null || manager) {
      return _rows(appointments, requireServer: true);
    }
    final assigned = appointments.where('assignedStaffId', isEqualTo: staffUid);
    return db
        .collection('staffScheduling')
        .doc(staffUid)
        .snapshots(includeMetadataChanges: true)
        .map(
          (profile) =>
              !profile.metadata.isFromCache &&
              !profile.metadata.hasPendingWrites &&
              profile.data()?['jobRole'] == 'FrontDesk',
        )
        .distinct()
        .switchMap((frontDesk) async* {
          // Drop the previous scope's rows before loading the replacement.
          yield const <BookingRequest>[];
          yield* _rows(
            frontDesk ? appointments : assigned,
            requireServer: true,
          );
        });
  }

  Stream<List<BookingRequest>> _rows(
    Query<Map<String, dynamic>> query, {
    bool requireServer = false,
  }) => query.snapshots(includeMetadataChanges: requireServer).map((snapshot) {
    if (requireServer &&
        (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites)) {
      return const <BookingRequest>[];
    }
    final rows = snapshot.docs
        .map((d) => BookingRequest(d.id, d.data()))
        .toList();
    rows.sort((a, b) => b.start.compareTo(a.start));
    return rows;
  });

  @override
  Future<BookingOutcome?> create({
    required String uid,
    required String name,
    required String phone,
    required String type,
    required DateTime start,
    required String notes,
    String dressId = '',
    String dressName = '',
    String? requestId,
  }) async {
    if (!appointmentTypes.contains(type) ||
        (type == makeupTrial && dressId.isNotEmpty) ||
        !validAppointmentTime(start, DateTime.now().toUtc()) ||
        !hasBookingContactDetails(name, phone) ||
        notes.trim().length > 1000 ||
        dressName.length > 100) {
      throw StateError(
        'Check your appointment details and choose a future time.',
      );
    }
    final api = HttpPaymentApi();
    try {
      return BookingOutcome.fromJson(
        await api.businessRequest(
          '/v1/appointments',
          body: {
            'requestId': requestId ?? packageRequestId(),
            'type': type,
            'startAt': start.millisecondsSinceEpoch,
            'notes': notes.trim(),
            'dressId': dressId,
            'feePolicyVersion': 1,
          },
        ),
      );
    } finally {
      api.close();
    }
  }

  @override
  Future<void> transition(
    BookingRequest booking,
    String status, {
    required String actor,
    required bool staff,
    String response = '',
  }) async {
    if (!canMoveBooking(booking.status, status, staff: staff) ||
        response.trim().length > 500) {
      throw StateError('This appointment cannot be changed that way.');
    }
    final api = HttpPaymentApi();
    try {
      await api.businessRequest(
        '/v1/appointments/${booking.id}/transition',
        body: {
          'status': status,
          'response': staff ? response.trim() : booking.response,
          'revision': booking.revision,
        },
      );
    } finally {
      api.close();
    }
  }
}

String bookingError(Object error) {
  if (error is PaymentFailure) return error.message;
  if (error is StateError) return error.message.toString();
  return 'Unable to update appointments. Check your connection and try again. If it continues, contact Luvly.';
}

class BookingScope extends InheritedWidget {
  const BookingScope({
    super.key,
    required this.repository,
    this.availableHours,
    this.availableHoursForType,
    required super.child,
  });
  final BookingRepository repository;
  final Future<List<int>> Function(DateTime)? availableHours;
  final Future<List<int>> Function(DateTime, String)? availableHoursForType;
  static BookingScope? scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BookingScope>();
  static BookingRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BookingScope>()?.repository;
  @override
  bool updateShouldNotify(BookingScope oldWidget) =>
      repository != oldWidget.repository ||
      availableHoursForType != oldWidget.availableHoursForType;
}
