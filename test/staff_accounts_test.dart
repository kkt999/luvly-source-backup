import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/admin/staff_accounts.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'availability_calendar_test.dart' show tapVisible;

Map<String, dynamic> employee({
  String id = 'mary',
  String name = 'Mary Tan',
  bool active = true,
  String role = 'staff',
}) => {
  'id': id,
  'name': name,
  'email': '$id@example.com',
  'phone': '0123456789',
  'role': role,
  'active': active,
  'revision': 3,
  'profileRevision': 2,
  'jobRole': 'FittingSpecialist',
  'serviceTypes': ['Dress Trial'],
  'invitationState': 'Sent',
  'syncRequired': false,
  'sessionReviewRequired': false,
  'history': [],
};

class AccountsFixture implements StaffAccountsApi {
  final rows = [
    employee(id: 'manager', name: 'Manager', role: 'manager'),
    employee(),
    employee(id: 'new', name: 'New Employee', active: false)
      ..['pendingActivation'] = true,
  ];
  final posts = <({String path, Map<String, dynamic> body})>[];
  bool fail = false,
      failCreate = false,
      duplicateEmail = false,
      partialSync = false,
      mailUncertain = false,
      canMail = true;
  int appointments = 0;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body != null) {
      posts.add((path: path, body: jsonDecode(jsonEncode(body))));
      if (path.isEmpty) {
        if (failCreate) {
          throw const PaymentFailure('Account response is uncertain.');
        }
        if (duplicateEmail && body['email'] == 'new.person@example.com') {
          throw const PaymentFailure(
            'This email is already in use.',
            code: 'STAFF_EMAIL_IN_USE',
          );
        }
        rows.add({
          ...employee(id: 'created', name: body['name'], active: false),
          'email': body['email'],
          'phone': body['phone'],
          'role': body['role'],
          'jobRole': body['jobRole'],
          'serviceTypes': body['serviceTypes'],
          'invitationState': 'NotSent',
          'pendingActivation': true,
        });
        return {'id': 'created', 'created': true};
      }
      final row = rows.firstWhere((r) => r['id'] == path.split('/')[1]);
      if (path.endsWith('/status')) {
        row['active'] = partialSync ? false : body['active'];
        row['syncRequired'] = partialSync;
        row['revision'] += 1;
        return {'saved': !partialSync, 'syncRequired': partialSync};
      }
      if (path.endsWith('/sync')) {
        row['syncRequired'] = false;
        return {'saved': true};
      }
      if (path.endsWith('/invite')) {
        if (!mailUncertain) row['invitationState'] = 'Sent';
        return mailUncertain
            ? {'sent': false, 'reviewRequired': true}
            : {'sent': true};
      }
      if (path.endsWith('/sessions')) return {'saved': true};
      row.addAll(body);
      return {'saved': true};
    }
    if (fail) throw const PaymentFailure('Manager access required.');
    if (path.isEmpty) {
      return {
        'records': rows,
        'actorUid': 'manager',
        'canSendSetupEmail': canMail,
        'limited': false,
      };
    }
    final row = rows.firstWhere((r) => r['id'] == path.substring(1));
    return {
      'record': row,
      'authAvailable': true,
      'authDisabled': false,
      'workload': {'appointments': appointments, 'tasks': 0, 'tickets': 0},
    };
  }

  @override
  void close() {}
}

Finder field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);
Future<void> mount(
  WidgetTester t,
  AccountsFixture f, {
  Widget? child,
  double width = 1440,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1100));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: portalTheme,
      debugShowCheckedModeBanner: false,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(body: child ?? StaffAccountsPage(api: f)),
    ),
  );
  await t.pumpAndSettle();
}

Widget details(AccountsFixture f, {String id = 'mary'}) => StaffAccountDetails(
  api: f,
  id: id,
  actorUid: 'manager',
  canMail: f.canMail,
);
Future<void> fill(WidgetTester t) async {
  await t.enterText(field('Full name'), 'New Person');
  await t.enterText(field('Login email'), 'new.person@example.com');
  await t.enterText(field('Phone'), '0123456789');
  await tapVisible(t, find.byType(DropdownButtonFormField<String>).last);
  await t.tap(find.text('Front desk').last);
  await t.pumpAndSettle();
}

void main() {
  test(
    'API uses authenticated manager endpoints and keeps mutations explicit',
    () async {
      final requests = <http.Request>[];
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'signed-token',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(jsonEncode({'saved': true}), 200);
        }),
      );
      final api = HttpStaffAccountsApi(transport: transport);
      await api.request('');
      await api.request(
        '/employee/status',
        body: {
          'active': false,
          'revision': 2,
          'requestId': 'a',
          'note': 'Left company',
        },
      );
      expect(requests.map((r) => r.method), ['GET', 'POST']);
      expect(requests.last.url.path, '/v1/staff-accounts/employee/status');
      expect(
        requests.every(
          (r) => r.headers['authorization'] == 'Bearer signed-token',
        ),
        isTrue,
      );
      expect(requests.last.url.hasQuery, isFalse);
      expect(jsonDecode(requests.last.body)['revision'], 2);
      transport.close();
    },
  );
  testWidgets(
    'manager list has real management actions and combines search with status',
    (t) async {
      final f = AccountsFixture();
      await mount(t, f);
      expect(find.text('Add staff account'), findsOneWidget);
      expect(find.text('Mary Tan'), findsOneWidget);
      expect(f.posts, isEmpty);
      await t.enterText(find.byType(TextField).first, 'mary');
      await t.pumpAndSettle();
      expect(find.text('Mary Tan'), findsOneWidget);
      expect(find.text('New Employee'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'failed authentication hides management buttons instead of presenting a fake empty list',
    (t) async {
      final f = AccountsFixture()..fail = true;
      await mount(t, f);
      expect(find.text('Manager access required.'), findsOneWidget);
      expect(find.text('Add staff account'), findsNothing);
      expect(find.text('Manage account'), findsNothing);
    },
  );
  testWidgets(
    'creation validates work role and sends an inactive account request without password or active override',
    (t) async {
      final f = AccountsFixture();
      await mount(t, f);
      await tapVisible(t, find.text('Add staff account'));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Work role'), findsOneWidget);
      await tapVisible(t, find.text('Create staff account'));
      expect(f.posts, isEmpty);
      await fill(t);
      await tapVisible(t, find.text('Create staff account'));
      expect(f.posts.single.path, '');
      final body = f.posts.single.body;
      expect(body['name'], 'New Person');
      expect(body['phone'], '+60123456789');
      expect(body['role'], 'staff');
      expect(body['jobRole'], 'FrontDesk');
      expect(body['serviceTypes'], isEmpty);
      expect(body.containsKey('password'), isFalse);
      expect(body.containsKey('active'), isFalse);
      expect(body['requestId'], isNotEmpty);
      expect(find.text('Manage staff account'), findsOneWidget);
      expect(find.text('Activate access'), findsOneWidget);
      final activate = find.ancestor(
        of: find.text('Activate access'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(t.widget<FilledButton>(activate).onPressed, isNull);
      expect(f.posts.length, 1);
      await tapVisible(t, find.text('Send setup email'));
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(f.posts.last.path, '/created/invite');
      expect(t.widget<FilledButton>(activate).onPressed, isNotNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('custom work role requires a job title and keeps Staff access', (
    t,
  ) async {
    final f = AccountsFixture();
    await mount(t, f);
    await tapVisible(t, find.text('Add staff account'));
    await fill(t);
    await tapVisible(t, find.byType(DropdownButtonFormField<String>).last);
    await t.tap(find.text('Other role').last);
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Create staff account'));
    expect(f.posts, isEmpty);
    await t.ensureVisible(field('Job title'));
    await t.enterText(field('Job title'), 'Seamstress');
    await tapVisible(t, find.text('Create staff account'));
    expect(f.posts.single.body['jobRole'], 'Other');
    expect(f.posts.single.body['jobTitle'], 'Seamstress');
    expect(f.posts.single.body['role'], 'staff');
  });
  testWidgets('known duplicate email lets the manager correct the form', (
    t,
  ) async {
    final f = AccountsFixture()..duplicateEmail = true;
    await mount(t, f);
    await tapVisible(t, find.text('Add staff account'));
    await fill(t);
    await tapVisible(t, find.text('Create staff account'));
    expect(find.text('This email is already in use.'), findsOneWidget);
    expect(t.widget<TextFormField>(field('Login email')).enabled, isTrue);
    await t.enterText(field('Login email'), 'other.work@example.com');
    await tapVisible(t, find.text('Create staff account'));
    expect(f.posts.last.body['email'], 'other.work@example.com');
    expect(f.posts.last.body['name'], f.posts.first.body['name']);
    expect(
      f.posts.last.body['requestId'],
      isNot(f.posts.first.body['requestId']),
    );
  });
  testWidgets('invalid staff contact fields stop submission', (t) async {
    final f = AccountsFixture();
    await mount(t, f);
    await tapVisible(t, find.text('Add staff account'));
    await fill(t);
    await t.enterText(field('Full name'), '**--');
    await t.enterText(field('Phone'), 'abcdefghi');
    await tapVisible(t, find.text('Create staff account'));
    expect(find.textContaining('Use letters'), findsOneWidget);
    expect(
      find.textContaining('Enter a valid Malaysian phone number'),
      findsOneWidget,
    );
    expect(f.posts, isEmpty);
  });
  testWidgets(
    'uncertain creation retries the same request and locks the submitted draft',
    (t) async {
      final f = AccountsFixture()..failCreate = true;
      await mount(t, f);
      await tapVisible(t, find.text('Add staff account'));
      await fill(t);
      await tapVisible(t, find.text('Create staff account'));
      expect(
        find.textContaining('Account response is uncertain.'),
        findsOneWidget,
      );
      expect(t.widget<TextFormField>(field('Full name')).enabled, isFalse);
      await tapVisible(t, find.text('Retry same request'));
      expect(f.posts.length, 2);
      expect(f.posts.first.body, f.posts.last.body);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'editor preserves exact account/profile revisions and does not change login email or activation',
    (t) async {
      final f = AccountsFixture();
      await mount(t, f, child: details(f));
      await tapVisible(t, find.text('Edit details & responsibilities'));
      expect(t.widget<TextFormField>(field('Login email')).enabled, isFalse);
      await t.enterText(field('Full name'), 'Mary Updated');
      await tapVisible(t, find.text('Save changes'));
      final body = f.posts.single.body;
      expect(f.posts.single.path, '/mary');
      expect(body['revision'], 3);
      expect(body['profileRevision'], 2);
      expect(body['name'], 'Mary Updated');
      expect(body.containsKey('email'), isFalse);
      expect(body.containsKey('active'), isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('makeup artist can be created with Staff access', (t) async {
    final f = AccountsFixture();
    await mount(t, f);
    await tapVisible(t, find.text('Add staff account'));
    await fill(t);
    final dialog = find.byType(StaffAccountEditor);
    final workRole = find.descendant(
      of: dialog,
      matching: find.byType(DropdownButtonFormField<String>),
    );
    expect(workRole, findsOneWidget);
    await tapVisible(t, workRole);
    await t.tap(find.text('Makeup artist').last);
    await t.pumpAndSettle();
    await tapVisible(t, find.widgetWithText(CheckboxListTile, 'Bridal Makeup'));
    await tapVisible(t, find.text('Create staff account'));
    final body = f.posts.single.body;
    expect(body['role'], 'staff');
    expect(body['jobRole'], 'MakeupArtist');
    expect(body['serviceTypes'], ['Bridal Makeup']);
  });
  testWidgets(
    'deactivation requires a reason, retains history, and does not send before confirmation',
    (t) async {
      final f = AccountsFixture();
      await mount(t, f, child: details(f));
      await tapVisible(t, find.text('Deactivate access'));
      expect(f.posts, isEmpty);
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(f.posts, isEmpty);
      await t.enterText(
        field('Reason (recorded in history)'),
        'Employee has left',
      );
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(f.posts.single.path, '/mary/status');
      expect(f.posts.single.body['active'], false);
      expect(f.posts.single.body['revision'], 3);
      expect(f.posts.single.body['note'], 'Employee has left');
      expect(find.text('Activate access'), findsOneWidget);
      expect(find.textContaining('Access deactivated.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('self deactivation and own role change are disabled in UI', (
    t,
  ) async {
    final f = AccountsFixture();
    f.rows.first['name'] = 'Boutique owner';
    await mount(t, f, child: details(f, id: 'manager'));
    expect(
      t
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Deactivate access'),
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tapVisible(t, find.text('Edit details & responsibilities'));
    final dialog = find.byType(StaffAccountEditor);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Manager')),
      findsOneWidget,
    );
    expect(f.posts, isEmpty);
    await tapVisible(t, find.text('Save changes'));
    expect(f.posts.single.body['role'], 'manager');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'partial Auth sync remains inactive and requires explicit retry, not a success banner',
    (t) async {
      final f = AccountsFixture()..partialSync = true;
      await mount(t, f, child: details(f));
      await tapVisible(t, find.text('Deactivate access'));
      await t.enterText(
        field('Reason (recorded in history)'),
        'Employee has left',
      );
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Authentication sync did not complete.'),
        findsOneWidget,
      );
      expect(find.text('Retry access sync'), findsOneWidget);
      expect(
        find.text('Access deactivated. History has been retained.'),
        findsNothing,
      );
      await tapVisible(t, find.text('Retry access sync'));
      expect(f.posts.last.path, '/mary/sync');
      expect(f.posts.last.body, isEmpty);
      expect(find.text('Access synchronised.'), findsOneWidget);
    },
  );
  testWidgets(
    'setup email needs explicit confirmation and uncertain SMTP result is not labelled sent',
    (t) async {
      final f = AccountsFixture()..mailUncertain = true;
      await mount(t, f, child: details(f));
      await tapVisible(t, find.text('Send setup email'));
      expect(f.posts, isEmpty);
      expect(find.textContaining('mary@example.com?'), findsOneWidget);
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(f.posts.single.path, '/mary/invite');
      expect(f.posts.single.body['revision'], 3);
      expect(f.posts.single.body.containsKey('to'), isFalse);
      expect(find.textContaining('email outcome is uncertain'), findsOneWidget);
      expect(find.textContaining('mail server accepted'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('failed refresh removes stale account controls', (t) async {
    final f = AccountsFixture();
    await mount(t, f, child: details(f));
    f.fail = true;
    await t.tap(find.byTooltip('Refresh account'));
    await t.pumpAndSettle();
    expect(find.text('Manager access required.'), findsOneWidget);
    expect(find.text('Deactivate access'), findsNothing);
    expect(find.text('Edit details & responsibilities'), findsNothing);
  });
  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('staff account management fits $width at enlarged text', (
      t,
    ) async {
      final f = AccountsFixture();
      await mount(t, f, width: width, scale: 1.8);
      expect(t.takeException(), isNull);
      await mount(t, f, child: details(f), width: width, scale: 1.8);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'creation dialog remains usable on a narrow screen with enlarged text',
    (t) async {
      final f = AccountsFixture();
      await mount(t, f, width: 320, scale: 1.8);
      await tapVisible(t, find.text('Add staff account'));
      await fill(t);
      await tapVisible(t, find.text('Create staff account'));
      expect(f.posts.single.body['jobRole'], 'FrontDesk');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('staff accounts desktop visual with synthetic data', (t) async {
    final f = AccountsFixture();
    await mount(t, f);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/staff-accounts-2071.png'),
    );
  });
  testWidgets('staff account detail desktop visual with synthetic data', (
    t,
  ) async {
    final f = AccountsFixture();
    await mount(t, f, child: details(f));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/staff-account-details-2071.png'),
    );
  });
}
