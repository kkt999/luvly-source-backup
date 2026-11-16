import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/bookings/booking_screens.dart';
import 'package:luvly_app/bookings/staff_appointment_workspace.dart';

class MemoryBookings implements BookingRepository {
  final rows = <BookingRequest>[];
  final changes = StreamController<void>.broadcast();
  final frontDesk = <String>{};

  @override
  Stream<List<BookingRequest>> watch({
    String? uid,
    String? staffUid,
    bool manager = false,
  }) async* {
    List<BookingRequest> visible() => rows.where((b) {
      if (uid != null) return b.uid == uid;
      if (staffUid == null || manager || frontDesk.contains(staffUid)) {
        return true;
      }
      return b.data['assignedStaffId'] == staffUid;
    }).toList();
    yield visible();
    await for (final _ in changes.stream) {
      yield visible();
    }
  }

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
    rows.add(
      BookingRequest('request-${rows.length}', {
        'uid': uid,
        'name': name,
        'phone': phone,
        'type': type,
        'startAt': Timestamp.fromDate(start),
        'slotKey': '${start.millisecondsSinceEpoch}',
        'notes': notes,
        'dressName': dressName,
        'response': '',
        'status': 'Confirmed',
        'assignedStaffId': 'staff',
        'revision': 1,
      }),
    );
    changes.add(null);
    return BookingOutcome(appointmentId: rows.last.id, status: 'Confirmed');
  }

  @override
  Future<void> transition(
    BookingRequest b,
    String status, {
    required String actor,
    required bool staff,
    String response = '',
  }) async {
    if (!canMoveBooking(b.status, status, staff: staff)) {
      throw StateError('Invalid transition');
    }
    rows[rows.indexOf(b)] = BookingRequest(b.id, {
      ...b.data,
      'status': status,
      'revision': b.revision + 1,
      'response': response,
    });
    changes.add(null);
  }
}

void main() {
  testWidgets('staff appointment list scopes roles and follows reassignment', (
    t,
  ) async {
    final repo = MemoryBookings()..frontDesk.add('desk');
    addTearDown(repo.changes.close);
    final start = appointmentUtc(
      DateTime.now().add(const Duration(days: 2)),
      10,
    );
    await repo.create(
      uid: 'bride',
      name: 'Assigned customer',
      phone: '0123456789',
      type: 'Dress Trial',
      start: start,
      notes: '',
    );
    await repo.create(
      uid: 'other',
      name: 'Other customer',
      phone: '0123456789',
      type: 'Dress Trial',
      start: start,
      notes: '',
    );
    repo.rows.first.data['assignedStaffId'] = 'artist';
    Widget app(String uid, {bool manager = false}) => BookingScope(
      repository: repo,
      child: MaterialApp(
        home: Scaffold(
          body: LiveAppointments(
            uid: uid,
            name: 'Employee',
            staff: true,
            manager: manager,
          ),
        ),
      ),
    );
    await t.pumpWidget(app('artist'));
    await t.pumpAndSettle();
    final list = find.byType(StaffAppointmentWorkspace);
    List<String> names() => t
        .widget<StaffAppointmentWorkspace>(list)
        .rows
        .map((visit) => visit.name)
        .toList();
    expect(names(), ['Assigned customer']);
    repo.rows.first.data['assignedStaffId'] = 'staff';
    repo.changes.add(null);
    await t.pumpAndSettle();
    expect(names(), isEmpty);
    for (final uid in ['desk', 'manager']) {
      await t.pumpWidget(app(uid, manager: uid == 'manager'));
      await t.pumpAndSettle();
      expect(names(), unorderedEquals(['Assigned customer', 'Other customer']));
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'bride books an available time, immediately sees confirmation and cancels it',
    (t) async {
      final repo = MemoryBookings();
      addTearDown(repo.changes.close);
      Widget app(bool staff) => BookingScope(
        repository: repo,
        availableHours: (_) async => appointmentHours,
        child: MaterialApp(
          home: Scaffold(
            body: LiveAppointments(
              key: ValueKey(staff),
              uid: staff ? 'staff' : 'bride',
              name: 'Jane',
              phone: '0123456789',
              staff: staff,
            ),
          ),
        ),
      );
      await t.pumpWidget(app(false));
      await t.pumpAndSettle();
      await t.tap(find.text('Book an appointment'));
      await t.pumpAndSettle();
      await t.tap(find.text('10:00'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byType(CheckboxListTile),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.ensureVisible(find.text('Continue to payment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Continue to payment'));
      await t.pumpAndSettle();
      expect(repo.rows.single.status, 'Confirmed');
      expect(
        find.text('Appointment confirmed. View it under Bookings.'),
        findsOneWidget,
      );
      await t.pumpWidget(app(true));
      await t.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Decline'), findsNothing);
      expect(repo.rows.single.status, 'Confirmed');
      await t.pumpWidget(app(false));
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Mark completed'),
        findsNothing,
      );
      await t.scrollUntilVisible(
        find.byTooltip('More appointment actions'),
        250,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('More appointment actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel appointment'));
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Cancel appointment'),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.rows.single.status, 'Cancelled');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('request form requires a time and fits a narrow display', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = MemoryBookings();
    addTearDown(repo.changes.close);
    await t.pumpWidget(
      BookingScope(
        repository: repo,
        availableHours: (_) async => appointmentHours,
        child: const MaterialApp(
          home: BookingRequestForm(
            uid: 'bride',
            name: 'Jane',
            phone: '0123456789',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final terms = find.byType(CheckboxListTile);
    await t.scrollUntilVisible(
      terms.hitTestable(),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.tap(terms.hitTestable());
    await t.ensureVisible(find.text('Continue to payment'));
    await t.pumpAndSettle();
    expect(t.widget<CheckboxListTile>(terms).value, isTrue);
    expect(repo.rows, isEmpty);
    final continueButton = find.widgetWithText(
      FilledButton,
      'Continue to payment',
    );
    expect(t.widget<FilledButton>(continueButton).onPressed, isNull);
    expect(find.text('Choose an available time to continue.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
