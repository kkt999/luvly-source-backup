import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/support/support_repository.dart';
import 'package:luvly_app/workspace/workspace_api.dart';
import 'package:luvly_app/workspace/task_screen.dart';
import 'package:luvly_app/workspace/staff_profile.dart';
import 'package:luvly_app/workspace/notifications.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;

class FakeWorkspace extends WorkspaceApi {
  FakeWorkspace({this.uid = 'john', this.manager = false, this.fixed = false});
  final String uid;
  final bool fixed;
  bool manager, fail = false;
  int unread = 1;
  List<(String, Map<String, dynamic>?)> calls = [];
  Map<String, dynamic> profile = {
    'uid': 'john',
    'name': 'John',
    'phone': '0123456789',
    'email': 'john@example.com',
    'revision': 1,
    'role': 'staff',
  };
  late List<Map<String, dynamic>> tasks = [
    {
      'id': 'task1',
      'workspaceVersion': 1,
      'title': 'Prepare the bridal fitting room',
      'description':
          'Check the selected accessories and prepare the fitting area.',
      'type': 'Fitting preparation',
      'assignedStaffId': uid,
      'staffName': 'John',
      'day': fixed
          ? '2026-10-24'
          : workDay(workToday().add(const Duration(days: 1))),
      'startHour': 10,
      'endHour': 12,
      'startAt': fixed
          ? 1792807200000
          : DateTime.now().millisecondsSinceEpoch + 86400000,
      'endAt': fixed
          ? 1792814400000
          : DateTime.now().millisecondsSinceEpoch + 93600000,
      'status': 'Scheduled',
      'revision': 3,
    },
  ];
  late final String noticeId = 'a' * 32;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    calls.add((path, body == null ? null : Map.of(body)));
    if (fail) throw const PaymentFailure('Connection unavailable. Retry.');
    if (path == '/v1/my-profile-photo') {
      return {'uid': uid, 'revision': 0, 'photo': null};
    }
    if (path == '/v1/my-staff-profile') {
      if (body != null) {
        profile = {
          ...profile,
          ...body,
          'revision': (body['revision'] as int) + 1,
        };
      }
      return Map.of(profile);
    }
    if (path == '/v1/staff-tasks') {
      return {
        'uid': uid,
        'manager': manager,
        'staff': manager
            ? [
                {'id': uid, 'name': 'John'},
              ]
            : [],
        'records': tasks.map((r) => Map.of(r)).toList(),
      };
    }
    if (path == '/v1/notifications') {
      return {
        'uid': uid,
        'unread': unread,
        'nextCursor': null,
        'records': [
          {
            'id': noticeId,
            'kind': 'SupportReply',
            'title': 'You have a support reply',
            'sourceType': 'Support',
            'sourceId': 'ticket1',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'readAt': unread == 0 ? 1 : null,
          },
        ],
      };
    }
    if (path.endsWith('/read')) {
      unread = 0;
      return {'read': true};
    }
    if (path.startsWith('/v1/support-messages')) {
      return {'saved': true, 'id': 'ticket1'};
    }
    return {'saved': true};
  }
}

Future<void> show(
  WidgetTester t,
  Widget page, {
  double width = 1100,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1000));
  await t.pumpWidget(
    MaterialApp(
      theme: portalTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: page,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(fonts);
  testWidgets(
    'failed task assignment retains form and safely reuses request ID',
    (t) async {
      final api = FakeWorkspace(manager: true);
      addTearDown(api.close);
      await show(t, StaffTasksScreen(uid: 'john', api: api));
      await t.tap(find.text('Assign task'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Task title'),
        'Prepare accessories',
      );
      await t.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Assign to'),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('John').last);
      await t.pumpAndSettle();
      api.fail = true;
      await t.ensureVisible(find.text('Save task'));
      await t.tap(find.text('Save task'));
      await t.pumpAndSettle();
      expect(find.text('Prepare accessories'), findsOneWidget);
      expect(find.text('Connection unavailable. Retry.'), findsOneWidget);
      final first = api.calls.last.$2!;
      expect(first['revision'], 0);
      expect(first.containsKey('uid'), false);
      api.fail = false;
      await t.tap(find.text('Save task'));
      await t.pumpAndSettle();
      final posted = api.calls
          .where((r) => r.$1 == '/v1/staff-tasks' && r.$2 != null)
          .last
          .$2!;
      expect(posted['requestId'], first['requestId']);
      expect(find.text('Assign a work task'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'notification badge checks updates and clears on account change',
    (t) async {
      final api = FakeWorkspace();
      addTearDown(api.close);
      await show(
        t,
        Scaffold(
          body: NotificationBell(uid: 'john', name: 'John', api: api),
        ),
      );
      expect(find.byTooltip('Notifications (1 unread)'), findsOneWidget);
      api.unread = 0;
      await t.pump(const Duration(seconds: 20));
      await t.pumpAndSettle();
      expect(find.byTooltip('Notifications'), findsOneWidget);
      await show(
        t,
        Scaffold(
          body: NotificationBell(uid: 'other', name: 'Other', api: api),
        ),
      );
      expect(
        find.byTooltip('Notifications unavailable — open to retry'),
        findsOneWidget,
      );
      expect(find.byTooltip('Notifications (1 unread)'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'staff saves only own permitted fields with the loaded revision',
    (t) async {
      final api = FakeWorkspace();
      addTearDown(api.close);
      await show(t, StaffProfileScreen(uid: 'john', api: api));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'John Updated',
      );
      await t.tap(find.text('Save profile'));
      await t.pumpAndSettle();
      final body = api.calls.last.$2!;
      expect(body.keys.toSet(), {'name', 'phone', 'revision'});
      expect(body['revision'], 1);
      expect(body['name'], 'John Updated');
      expect(body['phone'], '+60123456789');
      expect(find.text('Your profile has been saved.'), findsOneWidget);
      expect(find.text('Access role: staff · read only'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'invalid phone is not posted; server failure retains edited profile',
    (t) async {
      final api = FakeWorkspace();
      addTearDown(api.close);
      await show(t, StaffProfileScreen(uid: 'john', api: api));
      await t.enterText(find.widgetWithText(TextFormField, 'Phone'), 'abc');
      await t.tap(find.text('Save profile'));
      await t.pumpAndSettle();
      expect(api.calls.where((r) => r.$2 != null), isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Phone'),
        '0123456789',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Keep my changes',
      );
      api.fail = true;
      await t.tap(find.text('Save profile'));
      await t.pumpAndSettle();
      expect(find.text('Keep my changes'), findsOneWidget);
      expect(find.text('Connection unavailable. Retry.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'email uses verification flow rather than writing an email or role',
    (t) async {
      final api = FakeWorkspace();
      addTearDown(api.close);
      String? sent;
      await show(
        t,
        StaffProfileScreen(
          uid: 'john',
          api: api,
          verifyEmail: (email) async {
            sent = email;
          },
        ),
      );
      await t.enterText(
        find.widgetWithText(TextField, 'New email address'),
        'new@example.com',
      );
      await t.ensureVisible(find.text('Verify new email'));
      await t.tap(find.text('Verify new email'));
      await t.pumpAndSettle();
      expect(sent, 'new@example.com');
      expect(api.calls.where((r) => r.$2 != null), isEmpty);
      expect(find.textContaining('Verification email sent.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('staff sees own task details but no assignment controls', (
    t,
  ) async {
    final api = FakeWorkspace();
    addTearDown(api.close);
    await show(t, StaffTasksScreen(uid: 'john', api: api));
    expect(find.text('Assign task'), findsNothing);
    await t.tap(find.text('View task'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Check the selected accessories'),
      findsOneWidget,
    );
    expect(find.text('Edit assignment'), findsNothing);
    expect(find.text('Cancel task'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('manager has workload and can open the task assignment form', (
    t,
  ) async {
    final api = FakeWorkspace(manager: true);
    addTearDown(api.close);
    await show(t, StaffTasksScreen(uid: 'john', api: api));
    expect(find.textContaining('John: 1 active'), findsOneWidget);
    await t.tap(find.text('Assign task'));
    await t.pumpAndSettle();
    expect(find.text('Assign a work task'), findsOneWidget);
    expect(find.text('Assign to'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'exact notification task target never falls back to another task',
    (t) async {
      final api = FakeWorkspace();
      addTearDown(api.close);
      await show(
        t,
        StaffTasksScreen(uid: 'john', api: api, initialId: 'removed-task'),
      );
      expect(
        find.text('This task is no longer available to your account.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('task list checks changes automatically and retains search', (
    t,
  ) async {
    final api = FakeWorkspace();
    addTearDown(api.close);
    await show(t, StaffTasksScreen(uid: 'john', api: api));
    await t.enterText(
      find.widgetWithText(TextField, 'Search task, staff or date'),
      'accessory',
    );
    await t.pumpAndSettle();
    api.tasks = [
      {...api.tasks.first, 'title': 'Accessory preparation'},
    ];
    await t.pump(const Duration(seconds: 20));
    await t.pumpAndSettle();
    expect(find.text('Accessory preparation'), findsOneWidget);
    expect(find.text('accessory'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('inbox read status is saved by the owner-bound endpoint', (
    t,
  ) async {
    final api = FakeWorkspace();
    addTearDown(api.close);
    await show(
      t,
      InboxScreen(uid: 'john', name: 'John', staff: true, api: api),
    );
    expect(find.text('1 unread'), findsOneWidget);
    await t.tap(find.text('Mark as read'));
    await t.pumpAndSettle();
    expect(find.text('0 unread'), findsOneWidget);
    expect(api.calls.last.$1, '/v1/notifications/${api.noticeId}/read');
    expect(api.calls.last.$2, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('failed inbox does not pretend there are no notifications', (
    t,
  ) async {
    final api = FakeWorkspace()..fail = true;
    addTearDown(api.close);
    await show(t, InboxScreen(uid: 'john', name: 'John', api: api));
    expect(find.text('Connection unavailable. Retry.'), findsOneWidget);
    expect(find.textContaining('You are all caught up.'), findsNothing);
    api.fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('You have a support reply'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'support create/reply/close use atomic server notification endpoints',
    (t) async {
      final api = FakeWorkspace();
      addTearDown(api.close);
      final repo = FirebaseSupportRepository(api: api);
      expect(
        await repo.create(
          uid: 'john',
          name: 'Forged client name',
          subject: 'Fitting question',
          category: 'Appointments',
          body: 'Hello',
        ),
        'ticket1',
      );
      await repo.reply(
        'ticket1',
        actor: 'john',
        name: 'Forged',
        staff: false,
        body: 'A reply',
      );
      await repo.close(SupportCase('ticket1', {'revision': 2}), 'john');
      expect(api.calls.map((r) => r.$2!['action']), [
        'Create',
        'Reply',
        'Close',
      ]);
      for (final call in api.calls) {
        expect(call.$2!.containsKey('senderRole'), false);
        expect(call.$2!.containsKey('name'), false);
        expect(call.$2!.containsKey('uid'), false);
        expect(call.$2!['requestId'], isA<String>());
      }
    },
  );
  testWidgets('uncertain support response reuses its request identity', (
    t,
  ) async {
    final api = FakeWorkspace()..fail = true;
    addTearDown(api.close);
    final repo = FirebaseSupportRepository(api: api);
    await expectLater(
      repo.reply(
        'ticket1',
        actor: 'john',
        name: 'John',
        staff: true,
        body: 'Retry this safely',
      ),
      throwsA(isA<PaymentFailure>()),
    );
    final first = api.calls.last.$2!['requestId'];
    api.fail = false;
    await repo.reply(
      'ticket1',
      actor: 'john',
      name: 'John',
      staff: true,
      body: 'Retry this safely',
    );
    expect(api.calls.last.$2!['requestId'], first);
  });
  for (final width in [320.0, 1100.0]) {
    testWidgets('task and inbox fit $width at double text size', (t) async {
      final api = FakeWorkspace(manager: true);
      addTearDown(api.close);
      await show(
        t,
        StaffTasksScreen(uid: 'john', api: api),
        width: width,
        scale: 2,
      );
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView).first, const Offset(0, -650));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await show(
        t,
        InboxScreen(uid: 'john', name: 'John', staff: true, api: api),
        width: width,
        scale: 2,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('task and profile new visual previews', (t) async {
    final api = FakeWorkspace(manager: true, fixed: true);
    addTearDown(api.close);
    await show(t, StaffTasksScreen(uid: 'john', api: api));
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('previews/work-tasks-2075.png'),
    );
    await show(t, StaffProfileScreen(uid: 'john', api: api));
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('previews/staff-profile-2076.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
}
