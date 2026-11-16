import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/bookings/appointment_workspace.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/bookings/booking_screens.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart'
    show CatalogueScope;
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/shared/list_controls.dart';
import 'package:luvly_app/src/design.dart' show CustomerUi, luvlyTheme;
import 'package:luvly_app/src/home.dart' show HomeShell;
import 'package:luvly_app/src/model.dart' show AppModel, AppScope;
import 'package:luvly_app/support/assistant_screen.dart';

import 'assistant_launcher_test.dart' show host;
import 'booking_flow_test.dart' show MemoryBookings;
import 'checkout_redesign_test.dart' show viewport;
import 'fake_catalogue.dart' show FakeCatalogue;

const selectionId = '0123456789abcdef0123456789abcdef';
BookingRequest sample(
  String id,
  String status, {
  String name = 'Alyssa Tan',
  DateTime? start,
  String type = 'Dress Trial',
  String package = 'Signature Bridal',
}) => BookingRequest(id, {
  'uid': 'bride',
  'name': name,
  'phone': '0123456789',
  'type': type,
  'startAt': Timestamp.fromDate(start ?? DateTime.utc(2030, 10, 12, 8)),
  'slotKey': 'slot',
  'notes':
      'Package: $package\nSelection: $selectionId\nPlease prepare an ivory gown.',
  'dressName': '',
  'response': 'We look forward to your visit.',
  'status': status,
  'revision': 1,
});

Future<void> scrollTo(WidgetTester t, Finder target) async {
  await t.scrollUntilVisible(
    target,
    250,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await t.pumpAndSettle();
}

Finder appointmentCard(String id) => find.byKey(ValueKey('appointment-$id'));

Finder inCard(String id, Finder matching) =>
    find.descendant(of: appointmentCard(id), matching: matching);

Widget customerWorkspace(
  List<BookingRequest> rows, {
  ValueChanged<BookingRequest>? onPay,
  ValueChanged<String>? onPackage,
  void Function(BookingRequest, String)? onUpdate,
}) => Scaffold(
  appBar: AppBar(title: const Text('My appointments')),
  body: AppointmentWorkspace(
    rows: rows,
    staff: false,
    manager: false,
    onUpdate: onUpdate ?? (_, _) {},
    onRefresh: () {},
    onPackage: onPackage ?? (_) {},
    onPayments: () {},
    onBook: () {},
    onFittingPayment: onPay,
  ),
);

class _CountingBookings extends MemoryBookings {
  int subscriptions = 0;
  bool fail = false;

  @override
  Stream<List<BookingRequest>> watch({
    String? uid,
    String? staffUid,
    bool manager = false,
  }) {
    subscriptions++;
    if (fail) return Stream.error(StateError('Internal booking error'));
    return super.watch(uid: uid, staffUid: staffUid, manager: manager);
  }
}

void main() {
  testWidgets('package menu fits a small screen with reduced motion', (
    t,
  ) async {
    viewport(t, const Size(320, 720));
    const systemInsets = EdgeInsets.fromLTRB(0, 28, 0, 20);
    String? openedPackage;
    await t.pumpWidget(
      MaterialApp(
        theme: luvlyTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
            padding: systemInsets,
            viewPadding: systemInsets,
          ),
          child: child!,
        ),
        home: customerWorkspace([
          sample('narrow', 'Confirmed'),
        ], onPackage: (id) => openedPackage = id),
      ),
    );

    final trigger = find.byTooltip('More appointment actions');
    await scrollTo(t, trigger);
    final control = find.byWidgetPredicate(
      (w) => w is PopupMenuButton && w.tooltip == 'More appointment actions',
    );
    expect(
      t.widget<PopupMenuButton<dynamic>>(control).popUpAnimationStyle,
      AnimationStyle.noAnimation,
    );
    await t.tap(trigger);
    await t.pumpAndSettle();

    final label = find.text('View my package');
    final menu = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Material &&
            w.shape ==
                const RoundedRectangleBorder(
                  borderRadius: CustomerUi.cardRadius,
                ),
      ),
    );
    expect(menu, findsOneWidget);
    final bounds = t.getRect(menu);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.top, greaterThanOrEqualTo(systemInsets.top));
    expect(bounds.bottom, lessThanOrEqualTo(720 - systemInsets.bottom));
    final item = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
    );
    expect(t.getSize(item).height, greaterThanOrEqualTo(48));
    await t.tap(label);
    await t.pumpAndSettle();
    expect(openedPackage, selectionId);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'compact visits show scheduled time, saved status and the recorded fitting deadline',
    (t) async {
      viewport(t, const Size(390, 970));
      final clock = DateTime.now().toUtc();
      final expiration = clock.add(const Duration(minutes: 14));
      final waiting = BookingRequest('waiting', {
        ...sample(
          'waiting',
          'AwaitingPayment',
          start: clock.add(const Duration(days: 2)),
        ).data,
        'paymentExpiresAt': expiration.millisecondsSinceEpoch,
        'fittingInvoiceId': 'f' * 32,
      });
      final past = sample(
        'past',
        'Confirmed',
        start: clock.subtract(const Duration(days: 2)),
      );
      final complete = BookingRequest('complete', {
        ...sample(
          'complete',
          'Completed',
          start: clock.subtract(const Duration(days: 3)),
        ).data,
        'actualAttendedAt': Timestamp.fromDate(
          clock.subtract(const Duration(days: 1)),
        ),
      });
      final writes = <String>[];
      String? paidVisit, openedPackage;
      await host(
        t,
        home: customerWorkspace(
          [past, complete, waiting],
          onPay: (visit) => paidVisit = visit.id,
          onPackage: (id) => openedPackage = id,
          onUpdate: (b, state) => writes.add(state),
        ),
      );
      expect(find.text('Your appointments'), findsNothing);
      expect(find.text('3 appointments'), findsOneWidget);
      expect(find.textContaining('Pay the RM50 fitting fee'), findsNothing);
      expect(
        t.getTopLeft(appointmentCard('waiting')).dy,
        lessThan(t.getTopLeft(appointmentCard('past')).dy),
      );
      expect(
        inCard(
          'waiting',
          find.text('Payment deadline · ${appointmentLabel(expiration)}'),
        ),
        findsOneWidget,
      );
      await t.tap(inCard('waiting', find.text('Pay fitting fee')));
      expect(paidVisit, 'waiting');
      expect(inCard('past', find.text('Confirmed')), findsOneWidget);
      expect(inCard('past', find.text('Past appointment')), findsOneWidget);
      await scrollTo(t, inCard('complete', find.text('View details')));
      expect(
        inCard(
          'complete',
          find.text(appointmentLabel(complete.scheduledStart)),
        ),
        findsOneWidget,
      );
      await t.tap(inCard('complete', find.text('View details')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(appointmentLabel(complete.start)), findsOneWidget);
      await t.tap(find.text('View package'));
      await t.pumpAndSettle();
      expect(openedPackage, selectionId);
      expect(writes, isEmpty);
    },
  );

  testWidgets(
    'upcoming and all nine status options keep legacy filtering semantics',
    (t) async {
      viewport(t, const Size(390, 920));
      const statuses = [
        'Requested',
        'AwaitingPayment',
        'Expired',
        'Confirmed',
        'Completed',
        'Cancelled',
        'NoShow',
        'Declined',
      ];
      final now = DateTime.now().toUtc();
      final rows = [
        for (final value in statuses)
          sample(value, value, start: now.add(const Duration(days: 4))),
        sample(
          'past',
          'Confirmed',
          start: now.subtract(const Duration(days: 1)),
        ),
      ];
      await host(t, home: customerWorkspace(rows));
      await t.tap(find.widgetWithText(ChoiceChip, 'Upcoming'));
      await t.pumpAndSettle();
      expect(find.text('3 appointments'), findsOneWidget);
      expect(appointmentCard('past'), findsNothing);
      await t.tap(find.widgetWithText(ChoiceChip, 'All appointments'));
      await t.pumpAndSettle();
      for (final value in [...statuses, 'All']) {
        final chip = find.byKey(ValueKey('appointment-status-$value'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(
          find.text(switch (value) {
            'Confirmed' => '2 appointments',
            'All' => '9 appointments',
            _ => '1 appointment',
          }),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'search and advanced MYT date and type filters combine and can be cleared',
    (t) async {
      viewport(t, const Size(390, 940));
      final rows = [
        sample(
          'from-evening',
          'Confirmed',
          start: DateTime.utc(2030, 10, 11, 16),
          type: 'Bridal Consultation',
        ),
        sample(
          'before',
          'Confirmed',
          start: DateTime.utc(2030, 10, 11, 15),
          type: 'Bridal Consultation',
        ),
        sample(
          'other-package',
          'Confirmed',
          type: 'Bridal Consultation',
          package: 'Luxe Bridal',
        ),
        sample('dress-trial', 'Confirmed'),
      ];
      await host(t, home: customerWorkspace(rows));
      await t.enterText(find.byType(TextField), 'SIGNATURE bridal');
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Filter appointments'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Visit type: All visits'));
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(
          const ValueKey('list-option-Visit type-Bridal Consultation'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Visit dates'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Switch to input'));
      await t.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField),
      );
      await t.enterText(inputs.first, '10/12/2030');
      await t.enterText(inputs.last, '10/12/2030');
      await t.tap(find.text('Apply dates'));
      await t.pumpAndSettle();
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(appointmentCard('from-evening'), findsOneWidget);
      expect(appointmentCard('before'), findsNothing);
      expect(appointmentCard('other-package'), findsNothing);
      expect(appointmentCard('dress-trial'), findsNothing);
      expect(find.text('1 appointment'), findsOneWidget);
      await t.tap(find.byTooltip('Clear search'));
      await t.pumpAndSettle();
      expect(appointmentCard('other-package'), findsOneWidget);
      expect(find.text('2 appointments'), findsOneWidget);
      await t.tap(find.text('Reset filters'));
      await t.pumpAndSettle();
      expect(find.text('4 appointments'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'loading, retry and the collapsed booking guide retain state during refresh',
    (t) async {
      viewport(t, const Size(390, 900));
      final repo = _CountingBookings()..fail = true;
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        BookingScope(
          repository: repo,
          child: const MaterialApp(
            home: Scaffold(
              body: LiveAppointments(uid: 'bride', name: 'Jane'),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No appointments yet'), findsNothing);
      await t.pumpAndSettle();
      expect(
        find.text(
          'Could not load appointments. Check your connection and retry.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Internal booking error'), findsNothing);
      repo.fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('No appointments yet'), findsOneWidget);
      await t.tap(find.text('How package fittings work'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Pay the RM50 fitting fee within 15 minutes'),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('Refresh appointments'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Pay the RM50 fitting fee within 15 minutes'),
        findsOneWidget,
      );
      expect(repo.subscriptions, 3);
      repo.rows.add(
        sample(
          'past',
          'Completed',
          start: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );
      repo.changes.add(null);
      await t.pumpAndSettle();
      await t.tap(find.text('How package fittings work'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Upcoming'));
      await t.pumpAndSettle();
      expect(find.text('No upcoming appointments'), findsOneWidget);
      expect(repo.subscriptions, 3);
      await t.tap(find.widgetWithText(ChoiceChip, 'All appointments'));
      await t.pumpAndSettle();
      expect(find.text('1 appointment'), findsOneWidget);
    },
  );

  testWidgets(
    'Bookings tab opens real routes and keeps the assistant above the list',
    (t) async {
      viewport(t, const Size(390, 880));
      final model = AppModel()..accountId = 'bride';
      final repo = _CountingBookings()
        ..rows.add(
          BookingRequest('wait', {
            ...sample('wait', 'AwaitingPayment').data,
            'fittingInvoiceId': 'a' * 32,
          }),
        );
      final catalogue = FakeCatalogue();
      addTearDown(model.dispose);
      addTearDown(repo.changes.close);
      addTearDown(catalogue.changes.close);
      await host(
        t,
        home: AppScope(
          model: model,
          child: CatalogueScope(
            repository: catalogue,
            child: BookingScope(
              repository: repo,
              availableHours: (_) async => appointmentHours,
              child: const HomeShell(),
            ),
          ),
        ),
      );
      await t.tap(find.widgetWithText(NavigationDestination, 'Bookings'));
      await t.pumpAndSettle();
      expect(find.text('My appointments'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('Open Luvly assistant'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('Open Luvly assistant'));
      await t.pumpAndSettle();
      expect(find.byType(SupportAssistantScreen), findsOneWidget);
      await t.tap(find.byTooltip('Close assistant'));
      await t.pumpAndSettle();
      await t.tap(find.text('Book an appointment'));
      await t.pumpAndSettle();
      expect(find.byType(BookingRequestForm), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Payments & receipts'));
      await t.pumpAndSettle();
      expect(find.byType(LivePaymentsScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Pay fitting fee'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<LivePaymentsScreen>(find.byType(LivePaymentsScreen))
            .initialInvoiceId,
        'a' * 32,
      );
      expect(repo.subscriptions, 1);
    },
  );

  testWidgets(
    '320px double text lists visits lazily and scrolls to the last card',
    (t) async {
      viewport(t, const Size(320, 720));
      final now = DateTime.now().toUtc();
      final rows = [
        for (var index = 1; index <= 24; index++)
          sample(
            'visit-$index',
            'Confirmed',
            start: now.add(Duration(days: index)),
            package: 'A long bridal collection name that needs space to wrap',
          ),
      ];
      await host(t, scale: 2, home: customerWorkspace(rows));
      expect(appointmentCard('visit-24'), findsNothing);
      final last = inCard('visit-24', find.text('View details'));
      for (
        var step = 0;
        step < 45 && last.hitTestable().evaluate().isEmpty;
        step++
      ) {
        await t.dragFrom(const Offset(142, 640), const Offset(0, -445));
        await t.pumpAndSettle();
      }
      expect(last.hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'customer reschedule targets the existing future visit; staff and unpaid visits have no self-service move action',
    (t) async {
      String? moved;
      Widget app(bool staff, String status) => MaterialApp(
        theme: portalTheme,
        home: Scaffold(
          body: AppointmentWorkspace(
            rows: [sample('existing-visit', status)],
            staff: staff,
            manager: false,
            onUpdate: (_, _) {},
            onRefresh: () {},
            onPackage: (_) {},
            onPayments: () {},
            onBook: () {},
            onReschedule: (b) => moved = b.id,
          ),
        ),
      );
      await t.pumpWidget(app(false, 'Confirmed'));
      await t.pumpAndSettle();
      await scrollTo(t, find.byTooltip('More appointment actions'));
      await t.tap(find.byTooltip('More appointment actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reschedule'));
      await t.pumpAndSettle();
      expect(moved, 'existing-visit');
      await t.pumpWidget(app(false, 'AwaitingPayment'));
      await t.pumpAndSettle();
      expect(find.text('Reschedule'), findsNothing);
      await t.pumpWidget(app(true, 'Confirmed'));
      await t.pumpAndSettle();
      expect(find.text('Reschedule'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'linked appointment opens exact record and reset restores the authorized list',
    (t) async {
      t.view.physicalSize = const Size(1400, 1050);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: portalTheme,
          home: Scaffold(
            body: AppointmentWorkspace(
              initialAppointmentId: 'b',
              rows: [
                sample('a', 'Confirmed'),
                sample('b', 'Confirmed', name: 'Maya Lee'),
              ],
              staff: true,
              manager: false,
              onUpdate: (_, _) {},
              onRefresh: () {},
              onPackage: (_) {},
              onPayments: () {},
              onBook: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Maya Lee'), findsOneWidget);
      expect(find.text('Alyssa Tan'), findsNothing);
      await t.tap(
        find
            .widgetWithText(InputChip, 'Linked appointment')
            .hitTestable()
            .first,
      );
      // The chip itself does not remove the scope; only its explicit delete/reset does.
      await t.tap(find.text('Reset filters'));
      await t.pumpAndSettle();
      expect(find.text('Alyssa Tan'), findsOneWidget);
      expect(find.text('Maya Lee'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'presentation separates generated package metadata from real customer notes',
    () {
      final note = AppointmentPackageNote.parse(
        sample('a', 'Confirmed').notes,
      )!;
      expect(note.name, 'Signature Bridal');
      expect(note.selectionId, selectionId);
      expect(note.customerNotes, 'Please prepare an ivory gown.');
      expect(
        AppointmentPackageNote.parse('Please discuss a package with me.'),
        isNull,
      );
      expect(
        AppointmentPackageNote.parse('Package: Bridal\nSelection: invalid'),
        isNull,
      );
    },
  );

  testWidgets(
    'search and status filters work; review opens exact package without displaying its raw ID',
    (t) async {
      t.view.physicalSize = const Size(1400, 1050);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      String? opened;
      await t.pumpWidget(
        MaterialApp(
          theme: portalTheme,
          home: Scaffold(
            body: AppointmentWorkspace(
              rows: [
                sample('a', 'Requested'),
                sample('b', 'Confirmed', name: 'Maya Lee'),
              ],
              staff: true,
              manager: false,
              onUpdate: (_, _) {},
              onRefresh: () {},
              onPackage: (id) => opened = id,
              onPayments: () {},
              onBook: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining(selectionId), findsNothing);
      await t.enterText(find.byType(TextField), 'Maya');
      await t.pumpAndSettle();
      expect(find.text('Alyssa Tan'), findsNothing);
      expect(find.text('Maya Lee'), findsOneWidget);
      await scrollTo(t, find.text('View details'));
      await t.tap(find.text('View details'));
      await t.pumpAndSettle();
      await scrollTo(t, find.text('Review package'));
      await t.tap(find.text('Review package'));
      expect(opened, selectionId);
      expect(find.text('Please prepare an ivory gown.'), findsOneWidget);
      expect(find.textContaining(selectionId), findsNothing);
      await scrollTo(t, find.text('Back to appointments'));
      await t.tap(find.text('Back to appointments'));
      await t.pumpAndSettle();
      final status = find.byWidgetPredicate(
        (w) => w is ListFilterSelect && w.label == 'Status',
      );
      await t.ensureVisible(status);
      await t.tap(status);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('list-option-Status-Cancelled')));
      await t.pumpAndSettle();
      expect(find.text('No appointments match this view.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  for (final scene in ['desktop', 'phone']) {
    testWidgets('appointment workspace layout $scene', (t) async {
      t.view.physicalSize = Size(
        scene == 'desktop' ? 1400 : 390,
        scene == 'desktop' ? 1100 : 1000,
      );
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        for (final entry in {
          'LuvlySans': 'assets/fonts/roboto-regular.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            entry.key,
          )..addFont(rootBundle.load(entry.value))).load();
        }
      });
      const capture = ValueKey('appointment-preview');
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: scene == 'desktop' ? portalTheme : luvlyTheme,
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              appBar: scene == 'phone'
                  ? AppBar(title: const Text('My appointments'))
                  : null,
              body: AppointmentWorkspace(
                rows: [
                  sample('a', 'Requested'),
                  sample('b', 'Confirmed', name: 'Maya Lee'),
                  sample('c', 'Cancelled', name: 'Claire Lim'),
                ],
                staff: scene == 'desktop',
                manager: false,
                onUpdate: (_, _) {},
                onRefresh: () {},
                onPackage: (_) {},
                onPayments: () {},
                onBook: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile('previews/appointments-$scene.png'),
      );
    });
  }
}
