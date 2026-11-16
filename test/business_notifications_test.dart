import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/workspace/notifications.dart';
import 'package:luvly_app/workspace/workspace_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/payments/payment_api.dart' show PaymentFailure;
import 'package:luvly_app/bookings/booking_screens.dart';
import 'package:luvly_app/support/assistant_screen.dart';
import 'package:luvly_app/support/support_screens.dart';

import 'assistant_launcher_test.dart' show host;
import 'checkout_redesign_test.dart' show viewport;

class BusinessInbox extends WorkspaceApi {
  BusinessInbox(
    this.type, {
    this.uid = 'bride',
    this.kind,
    this.title = 'Your next step is ready',
  });
  final String type;
  final String uid, title;
  final String? kind;
  final source = 'b' * 32;
  int unread = 1;
  final calls = <String>[];
  Completer<Map<String, dynamic>>? readResult;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    calls.add(path);
    if (path.endsWith('/read')) {
      final result = await readResult?.future ?? {'read': true};
      if (result['read'] == true) unread = 0;
      return result;
    }
    return {
      'uid': uid,
      'unread': unread,
      'nextCursor': null,
      'records': [
        {
          'id': 'a' * 32,
          'kind': kind,
          'title': title,
          'sourceType': type,
          'sourceId': source,
          'createdAt': 1900000000000,
          'readAt': unread == 0 ? 1900000000001 : null,
        },
      ],
    };
  }
}

Map<String, dynamic> notice(
  int number,
  String title,
  String type, {
  bool read = false,
  String? sourceId = 'booking-id',
}) => {
  'id': number.toRadixString(16).padLeft(32, '0'),
  'title': title,
  'sourceType': type,
  'sourceId': sourceId,
  'createdAt': DateTime.now()
      .subtract(Duration(minutes: number))
      .millisecondsSinceEpoch,
  'readAt': read ? 1900000000001 : null,
};

class PagedInbox extends WorkspaceApi {
  PagedInbox(this.records, {this.older = const []});

  final List<Map<String, dynamic>> records, older;
  final calls = <String>[];
  Completer<void>? pending;
  Completer<void>? pendingRead;
  final failReads = <String>{};
  bool fail = false, failOlder = false;
  bool readOlder = false;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    calls.add(path);
    if (path.endsWith('/read')) {
      expect(body, isEmpty);
      final id = path.split('/')[3];
      await pendingRead?.future;
      if (failReads.contains(id)) throw StateError('Write failed');
      final row = [
        ...records,
        ...older,
      ].where((row) => row['id'] == id).firstOrNull;
      if (row == null) {
        throw const PaymentFailure(
          'Unavailable',
          code: 'NOTIFICATION_NOT_FOUND',
        );
      }
      row['readAt'] = DateTime.now().millisecondsSinceEpoch;
      return {'read': true};
    }
    expect(body, isNull);
    await pending?.future;
    final more = path.contains('?cursor=');
    if (fail || (more && failOlder)) throw StateError('private debug text');
    if (more) readOlder = true;
    return {
      'uid': 'bride',
      'records': [
        for (final row in more ? older : records) {...row},
      ],
      'unread': [
        ...records,
        ...older,
      ].where((row) => row['readAt'] == null).length,
      'nextCursor': older.isNotEmpty && !more ? records.last['id'] : null,
    };
  }
}

final inboxOption = find.byTooltip('Notification inbox options');
final selectAll = find.byTooltip('Select all loaded unread');

Future<void> chooseInboxOption(WidgetTester t, String label) async {
  await t.tap(inboxOption);
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

Future<void> tapFilter(WidgetTester t, String filter) async {
  final chip = find.byKey(ValueKey('notification-filter-$filter'));
  await t.ensureVisible(chip);
  await t.tap(chip);
  await t.pumpAndSettle();
}

Future<void> showInbox(WidgetTester t, PagedInbox api) async {
  addTearDown(api.close);
  await host(
    t,
    home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
  );
}

List<String> readIds(PagedInbox api) => api.calls
    .where((path) => path.endsWith('/read'))
    .map((path) => path.split('/')[3])
    .toList();

Future<void> markRead(WidgetTester t) async {
  await t.tap(find.byTooltip('Notification options'));
  await t.pumpAndSettle();
  await t.tap(find.text('Mark as read'));
}

void main() {
  testWidgets(
    'selection from long press and menu stays inside the active filter',
    (t) async {
      final api = PagedInbox([
        notice(1, 'First payment', 'Payment'),
        notice(2, 'Second payment', 'Payment'),
        notice(3, 'Already read', 'Payment', read: true),
        notice(4, 'A booking', 'Appointment'),
      ]);
      await showInbox(t, api);
      await tapFilter(t, 'payments');
      await t.longPress(find.text('Already read'));
      await t.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      await t.longPress(find.text('First payment'));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byTooltip('Open Luvly assistant'), findsNothing);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      expect(find.byTooltip('Notification options'), findsNothing);
      await t.tap(find.text('Already read'));
      await t.tap(find.text('Second payment'));
      await t.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await t.tap(find.text('Second payment'));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(selectAll);
      await t.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await t.tap(find.byTooltip('Selection options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Deselect all'));
      await t.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      FilledButton bulkButton() =>
          t.widget(find.widgetWithText(FilledButton, 'Mark 0 as read'));
      expect(bulkButton().onPressed, isNull);
      await t.tap(find.text('First payment'));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('First payment'), findsOneWidget);
      expect(find.text('A booking'), findsNothing);
      expect(find.byTooltip('Open Luvly assistant'), findsOneWidget);
      await chooseInboxOption(t, 'Select notifications');
      expect(find.text('0 selected'), findsOneWidget);
      await t.tap(find.byTooltip('Cancel selection'));
      await t.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(readIds(api), isEmpty);
    },
  );

  testWidgets(
    'bulk awaits writes, updates the count and retries only failed notifications',
    (t) async {
      final first = notice(1, 'New payment', 'Payment');
      final second = notice(2, 'Payment receipt', 'Payment');
      final other = notice(3, 'Appointment confirmed', 'Appointment');
      final older = notice(4, 'Older payment', 'Payment');
      final api = PagedInbox([first, second, other], older: [older]);
      await showInbox(t, api);
      await tapFilter(t, 'payments');
      await chooseInboxOption(t, 'Select notifications');
      await t.tap(selectAll);
      await t.pumpAndSettle();
      final bulk = find.widgetWithText(FilledButton, 'Mark 2 as read');
      api.failReads.add(second['id'] as String);
      api.pendingRead = Completer<void>();
      await t.tap(bulk);
      await t.pump();
      expect(find.text('4 unread updates'), findsOneWidget);
      final busy = find.widgetWithText(FilledButton, 'Marking as read…');
      expect(t.widget<FilledButton>(busy).onPressed, isNull);
      await t.tap(busy);
      await t.binding.handlePopRoute();
      expect(readIds(api), [first['id'], second['id']]);
      api.pendingRead!.complete();
      await t.pumpAndSettle();
      expect(find.text('3 unread updates'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        find.text('Could not confirm 1 as read. Try again.'),
        findsOneWidget,
      );
      final rejected = find.byKey(ValueKey("notification-${second['id']}"));
      expect(
        find.descendant(of: rejected, matching: find.byIcon(Icons.check_box)),
        findsOneWidget,
      );
      expect(first['readAt'], isNotNull);
      expect(second['readAt'], isNull);
      api.failReads.clear();
      await t.tap(find.text('Mark 1 as read'));
      await t.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('2 unread updates'), findsOneWidget);
      expect(readIds(api), [first['id'], second['id'], second['id']]);
      expect(other['readAt'], isNull);
      expect(older['readAt'], isNull);
      expect(api.readOlder, isFalse);
      expect(find.text('Appointment confirmed'), findsNothing);
    },
  );

  testWidgets('Mark visible uses the current filter on loaded pages only', (
    t,
  ) async {
    final appointment = notice(1, 'Appointment moved', 'Appointment');
    final payment = notice(2, 'Payment verified', 'Payment');
    final rental = notice(3, 'Rental reserved', 'Package');
    final support = notice(4, 'Team replied', 'Support');
    final api = PagedInbox([appointment, payment], older: [rental, support]);
    await showInbox(t, api);
    await t.tap(find.text('Load older notifications'));
    await t.pumpAndSettle();
    await tapFilter(t, 'bookings');
    await chooseInboxOption(t, 'Mark visible as read');
    expect(find.text('2 unread updates'), findsOneWidget);
    expect(readIds(api), [appointment['id'], rental['id']]);
    expect(find.text('Rental reserved'), findsOneWidget);
    expect(payment['readAt'], isNull);
    expect(support['readAt'], isNull);
    await t.tap(inboxOption);
    await t.pumpAndSettle();
    final item = find.widgetWithText(
      PopupMenuItem<void>,
      'Mark visible as read',
    );
    expect(t.widget<PopupMenuItem<void>>(item).enabled, isFalse);
  });

  testWidgets(
    'refresh reconciles selected IDs that were read or removed elsewhere',
    (t) async {
      final first = notice(1, 'First notification', 'Support');
      final removed = notice(2, 'Removed notification', 'Support');
      final third = notice(3, 'Another notification', 'Support');
      final api = PagedInbox([first, removed, third]);
      await showInbox(t, api);
      await chooseInboxOption(t, 'Select notifications');
      await t.tap(selectAll);
      await t.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      first['readAt'] = DateTime.now().millisecondsSinceEpoch;
      api.records.remove(removed);
      await t.pump(const Duration(seconds: 20));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Removed notification'), findsNothing);
      await t.tap(find.text('Mark 1 as read'));
      await t.pumpAndSettle();
      expect(readIds(api), [third['id']]);
      expect(find.text('0 unread updates'), findsOneWidget);
    },
  );

  testWidgets(
    'deleted notifications from older loaded pages are removed from selection',
    (t) async {
      final older = notice(2, 'An older notification', 'Support');
      final api = PagedInbox(
        [notice(1, 'Current update', 'Support', read: true)],
        older: [older],
      );
      await showInbox(t, api);
      await t.tap(find.text('Load older notifications'));
      await t.pumpAndSettle();
      await t.longPress(find.text('An older notification'));
      await t.pumpAndSettle();
      api.older.clear();
      await t.tap(find.text('Mark 1 as read'));
      await t.pumpAndSettle();
      expect(find.text('An older notification'), findsNothing);
      expect(
        find.text('Some notifications are no longer available.'),
        findsOneWidget,
      );
      expect(find.text('0 unread updates'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    },
  );

  testWidgets(
    'selection bottom action respects system insets at double text size',
    (t) async {
      viewport(t, const Size(320, 700));
      t.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(t.view.resetPadding);
      final api = PagedInbox([
        for (var index = 1; index <= 20; index++)
          notice(index, 'Fitting notification $index', 'Appointment'),
      ]);
      addTearDown(api.close);
      await host(
        t,
        scale: 2,
        home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
      );
      await t.longPress(find.text('Fitting notification 1'));
      await t.pumpAndSettle();
      final last = find.text('Fitting notification 20');
      await t.scrollUntilVisible(
        last,
        370,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await t.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Mark 1 as read');
      expect(last.hitTestable(), findsOneWidget);
      expect(t.getBottomLeft(last).dy, lessThan(t.getTopLeft(button).dy));
      expect(t.getBottomLeft(button).dy, lessThanOrEqualTo(676));
      expect(t.takeException(), isNull);
      expect(readIds(api), isEmpty);
    },
  );

  testWidgets('staff sees operational wording for older rental notices', (
    t,
  ) async {
    final api = BusinessInbox(
      'Package',
      uid: 'staff',
      kind: 'RentalReserved',
      title: 'Your rental booking is confirmed',
    );
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: InboxScreen(uid: 'staff', name: 'John', staff: true, api: api),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Staff notifications'), findsOneWidget);
    expect(find.text('Customer rental booking confirmed'), findsOneWidget);
    expect(find.text(api.title), findsNothing);
    await t.tap(find.text('View rental record'));
    await t.pumpAndSettle();
    final page = t.widget<LivePackageScreen>(find.byType(LivePackageScreen));
    expect(page.staff, isTrue);
    expect(page.initialSelectionId, api.source);
    expect(page.openInitialSelection, isTrue);
    expect(api.unread, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('payment review points staff to the exact invoice', (t) async {
    final api = BusinessInbox(
      'Payment',
      uid: 'staff',
      kind: 'PaymentReview',
      title: 'A payment needs review',
    );
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: InboxScreen(uid: 'staff', name: 'John', staff: true, api: api),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Customer payment needs review'), findsOneWidget);
    await t.tap(find.text('Review payment'));
    await t.pumpAndSettle();
    final page = t.widget<LivePaymentsScreen>(find.byType(LivePaymentsScreen));
    expect(page.staff, isTrue);
    expect(page.initialInvoiceId, api.source);
    expect(page.focusInitialInvoice, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  for (final type in ['Package', 'Payment', 'Appointment']) {
    testWidgets(
      '$type updates appear and can be marked read without opening a business action',
      (t) async {
        final api = BusinessInbox(
          type,
          kind: type == 'Package' ? 'RentalReserved' : null,
          title: type == 'Package'
              ? 'Your rental booking is confirmed'
              : 'Your next step is ready',
        );
        addTearDown(api.close);
        await t.pumpWidget(
          MaterialApp(
            home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('1 unread update'), findsOneWidget);
        expect(
          find.text(type == 'Package' ? 'Your rental is reserved' : api.title),
          findsOneWidget,
        );
        await markRead(t);
        await t.pumpAndSettle();
        expect(find.text('0 unread updates'), findsOneWidget);
        expect(api.calls.where((p) => p.endsWith('/read')).length, 1);
        expect(find.byType(LivePackageScreen), findsNothing);
        expect(find.byType(LivePaymentsScreen), findsNothing);
        expect(find.byType(LiveAppointments), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final type in ['Package', 'Payment', 'Appointment', 'Support']) {
    testWidgets(
      '$type action opens the exact record and retains the customer role',
      (t) async {
        final api = BusinessInbox(type);
        addTearDown(api.close);
        await t.pumpWidget(
          MaterialApp(
            home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text(api.title));
        await t.pumpAndSettle();
        if (type == 'Package') {
          final page = t.widget<LivePackageScreen>(
            find.byType(LivePackageScreen),
          );
          expect(page.initialSelectionId, api.source);
          expect(page.openInitialSelection, isTrue);
          expect(page.staff, isFalse);
        } else if (type == 'Payment') {
          final page = t.widget<LivePaymentsScreen>(
            find.byType(LivePaymentsScreen),
          );
          expect(page.initialInvoiceId, api.source);
          expect(page.focusInitialInvoice, isTrue);
          expect(page.staff, isFalse);
        } else if (type == 'Appointment') {
          final page = t.widget<LiveAppointments>(
            find.byType(LiveAppointments),
          );
          expect(page.initialAppointmentId, api.source);
          expect(page.staff, isFalse);
        } else {
          final page = t.widget<SupportConversation>(
            find.byType(SupportConversation),
          );
          expect(page.id, api.source);
          expect(page.staff, isFalse);
        }
        expect(api.unread, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('read state waits for a successful write and can be retried', (
    t,
  ) async {
    final api = BusinessInbox('Payment')..readResult = Completer();
    addTearDown(api.close);
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Unread notification')),
      findsOneWidget,
    );
    await markRead(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('1 unread update'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Marking as read')), findsOneWidget);
    expect(find.byTooltip('Notification options'), findsNothing);
    await t.tap(find.text(api.title));
    expect(api.calls.where((p) => p.endsWith('/read')).length, 1);
    api.readResult!.complete({'read': false});
    await t.pumpAndSettle();
    expect(
      find.text('Could not mark this update as read. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('1 unread update'), findsOneWidget);
    api.readResult = null;
    await markRead(t);
    await t.pumpAndSettle();
    expect(find.text('0 unread updates'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Read notification')), findsOneWidget);
    expect(find.byType(LivePaymentsScreen), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'filters preserve chronology, server unread count and older pages',
    (t) async {
      final api = PagedInbox(
        [
          notice(1, 'Payment verified', 'Payment', read: true),
          notice(2, 'Fitting scheduled', 'Appointment', read: true),
          notice(3, 'Rental reserved', 'Package', read: true),
          notice(4, 'General boutique update', 'General', read: true),
        ],
        older: [notice(5, 'Our team replied', 'Support')],
      );
      addTearDown(api.close);
      await host(
        t,
        enabled: false,
        home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
      );
      expect(find.text('1 unread update'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Payment verified')).dy,
        lessThan(t.getTopLeft(find.text('Fitting scheduled')).dy),
      );
      expect(
        t.getTopLeft(find.text('Fitting scheduled')).dy,
        lessThan(t.getTopLeft(find.text('Rental reserved')).dy),
      );
      expect(find.textContaining('MYT'), findsNothing);
      final received = find.textContaining(' · ').first;
      final locale = MaterialLocalizations.of(t.element(received));
      final date = DateTime.fromMillisecondsSinceEpoch(
        api.records.first['createdAt'],
      );
      final now = DateTime.now();
      final day = DateUtils.isSameDay(date, now) ? 'Today' : 'Yesterday';
      expect(
        t.widget<Text>(received).data,
        '$day · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
      );

      Future<void> filter(String name) async {
        final chip = find.byKey(ValueKey('notification-filter-$name'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
      }

      await filter('bookings');
      expect(find.text('Fitting scheduled'), findsOneWidget);
      expect(find.text('Rental reserved'), findsOneWidget);
      expect(find.text('Payment verified'), findsNothing);
      await filter('payments');
      expect(find.text('Payment verified'), findsOneWidget);
      expect(find.text('Fitting scheduled'), findsNothing);
      await filter('support');
      expect(find.text('No matching notifications'), findsOneWidget);
      await t.tap(find.text('View all notifications'));
      await t.pumpAndSettle();
      expect(find.text('Payment verified'), findsOneWidget);
      await filter('unread');
      expect(find.text('No unread notifications here'), findsOneWidget);
      expect(api.readOlder, isFalse);
      api.failOlder = true;
      await t.tap(find.text('Load older notifications'));
      await t.pumpAndSettle();
      expect(find.text('Could not load older notifications'), findsOneWidget);
      expect(find.text('1 unread update'), findsOneWidget);
      api.failOlder = false;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Our team replied'), findsOneWidget);
      await markRead(t);
      await t.pumpAndSettle();
      expect(find.text('No unread notifications'), findsOneWidget);
      expect(find.text("You're all caught up"), findsNothing);
      expect(api.calls.where((path) => path.contains('?cursor=')).length, 2);
    },
  );

  testWidgets('loading, load error, refresh and empty are distinct', (t) async {
    final api = PagedInbox([])..pending = Completer<void>();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: InboxScreen(uid: 'bride', name: 'Customer', api: api),
      ),
    );
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text("You're all caught up"), findsNothing);
    api.fail = true;
    api.pending!.complete();
    await t.pumpAndSettle();
    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(find.textContaining('private debug'), findsNothing);
    api.fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text("You're all caught up"), findsOneWidget);
    api.records.add(notice(1, 'Boutique update', 'General', sourceId: null));
    await t.tap(find.byTooltip('Refresh notifications'));
    await t.pumpAndSettle();
    expect(find.text('Boutique update'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await t.tap(find.byTooltip('Mark as read'));
    await t.pumpAndSettle();
    expect(find.text('0 unread updates'), findsOneWidget);
    expect(find.byTooltip('Mark as read'), findsNothing);
  });

  testWidgets(
    'the assistant stays in the toolbar and a long list builds lazily at 2×',
    (t) async {
      viewport(t, const Size(320, 720));
      final longTitle = List.filled(
        3,
        'Your fitting appointment has been confirmed',
      ).join(' ');
      final api = PagedInbox([
        notice(1, longTitle, 'Appointment'),
        for (var index = 2; index <= 50; index++)
          notice(index, 'Notification $index', 'Payment', read: true),
      ]);
      addTearDown(api.close);
      await host(
        t,
        scale: 2,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      InboxScreen(uid: 'bride', name: 'Customer', api: api),
                ),
              ),
              child: const Text('Open inbox'),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      await t.tap(find.text('Open inbox'));
      await t.pumpAndSettle();
      expect(find.text(longTitle), findsOneWidget);
      expect(find.text('Notification 50'), findsNothing);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      expect(find.byTooltip('Open Luvly assistant'), findsOneWidget);
      await t.tap(find.byTooltip('Open Luvly assistant'));
      await t.pumpAndSettle();
      expect(find.byType(SupportAssistantScreen), findsOneWidget);
      await t.tap(find.byTooltip('Close assistant'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Notification 50'),
        420,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Notification 50').hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(api.calls, ['/v1/notifications']);
    },
  );
}
