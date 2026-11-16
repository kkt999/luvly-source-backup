import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/rental_service_progress.dart';
import 'package:luvly_app/packages/staff_rental_details.dart';
import 'package:luvly_app/payments/payment_api.dart';
import '../checkout_redesign_test.dart' show viewport;
import 'staff_rental_workspace_test.dart' show staffSelection, showWorkspace;

void main() {
  test(
    'staff and manager expose one rental menu, with legacy tasks preserved',
    () {
      for (final role in PortalRole.values) {
        final model = PortalModel()..login(role);
        expect(model.pages, contains(PortalPage.rentals));
        expect(model.pages, isNot(contains(PortalPage.progress)));
        expect(model.tasks, isNotEmpty);
        model.dispose();
      }
    },
  );
  test(
    'redundant Workflow page is removed while direct operational pages remain',
    () {
      expect(PortalPage.values.map((p) => p.name), isNot(contains('workflow')));
      for (final role in PortalRole.values) {
        final model = PortalModel()..login(role);
        expect(
          model.pages,
          containsAll([
            PortalPage.appointments,
            PortalPage.rentals,
            PortalPage.schedule,
          ]),
        );
        expect(model.pages.map((p) => p.label), isNot(contains('Workflow')));
        model.dispose();
      }
    },
  );
  testWidgets(
    'preparation panel derives fitting and opens the exact linked appointment',
    (t) async {
      final selection = staffSelection();
      selection.data['serviceProgress'] = {
        'alteration': 'InProgress',
        'preparation': 'Preparing',
        'note': 'Adjust waist seam.',
        'byName': 'John',
      };
      selection.data['appointments'] = [
        {'id': 'visit-one', 'type': 'Dress Trial'},
      ];
      String? visit;
      await showWorkspace(
        t,
        RentalServiceProgressPanel(
          selection: selection,
          onAppointment: (id) => visit = id,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Fitting completed · satisfied'), findsOneWidget);
      expect(find.text('Alteration in progress'), findsOneWidget);
      expect(find.text('Adjust waist seam.'), findsOneWidget);
      await t.tap(find.text('Open Dress Trial'));
      expect(visit, 'visit-one');
      expect(find.text('Update preparation'), findsNothing);
    },
  );
  testWidgets(
    'preparation editor validates note and sends revision without payment fields',
    (t) async {
      final selection = staffSelection();
      selection.data['serviceProgress'] = {
        'revision': 4,
        'alteration': 'InProgress',
        'preparation': 'Preparing',
      };
      final calls = <Map<String, dynamic>>[];
      final gate = Completer<void>();
      await showWorkspace(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => editRentalServiceProgress(
              context,
              selection: selection,
              save: (body) async {
                calls.add(body);
                await gate.future;
              },
            ),
            child: const Text('Edit'),
          ),
        ),
      );
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save preparation'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      await t.enterText(
        find.byType(TextFormField),
        '  Waist adjustment started.  ',
      );
      await t.tap(find.text('Save preparation'));
      await t.pump();
      expect(calls.single.keys.toSet(), {
        'requestId',
        'revision',
        'alteration',
        'preparation',
        'note',
      });
      expect(calls.single['revision'], 4);
      expect(calls.single['note'], 'Waist adjustment started.');
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      gate.complete();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'failed preparation save stays visible and requires closing to refresh',
    (t) async {
      await showWorkspace(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => editRentalServiceProgress(
              context,
              selection: staffSelection(),
              save: (_) async =>
                  throw const PaymentFailure('This record changed.'),
            ),
            child: const Text('Edit'),
          ),
        ),
      );
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Preparation note');
      await t.tap(find.text('Save preparation'));
      await t.pumpAndSettle();
      expect(find.textContaining('This record changed.'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save preparation'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );
  testWidgets(
    'rental details persist progress through real transport then refresh',
    (t) async {
      viewport(t, const Size(660, 1200));
      final selection = staffSelection();
      final calls = <http.Request>[];
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'fixture-token',
          client: MockClient((r) async {
            calls.add(r);
            if (r.method == 'POST') {
              expect(
                r.url.path,
                '/v1/package-selections/${selection.id}/service-progress',
              );
              expect(r.headers['authorization'], 'Bearer fixture-token');
              selection.data['serviceProgress'] = {
                ...jsonDecode(r.body),
                'revision': 1,
                'byName': 'John',
              };
              return http.Response('{}', 200);
            }
            return http.Response(
              jsonEncode({
                'selections': [selection.data],
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(api.close);
      await showWorkspace(
        t,
        StaffRentalDetails(
          selection: selection,
          workspace: true,
          api: api,
          manager: false,
          onChanged: () {},
          onIssueInvoice: (_) async {},
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('rental-tab-1')));
      await t.tap(find.byKey(const ValueKey('rental-tab-1')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Update preparation'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Update preparation'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextFormField),
        'Steam gown before pickup.',
      );
      await t.tap(find.text('Save preparation'));
      await t.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST').length, 1);
      expect(find.text('Steam gown before pickup.'), findsOneWidget);
      expect(selection.data['rental']['paymentState'], 'DepositPaid');
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('service panel and editor fit 320px at text $scale', (t) async {
      viewport(t, const Size(320, 1000));
      final s = staffSelection();
      s.data['serviceProgress'] = {
        'alteration': 'InProgress',
        'preparation': 'Preparing',
      };
      await showWorkspace(
        t,
        Builder(
          builder: (context) => SingleChildScrollView(
            child: RentalServiceProgressPanel(
              selection: s,
              onEdit: () => editRentalServiceProgress(
                context,
                selection: s,
                save: (_) async {},
              ),
            ),
          ),
        ),
        scale: scale,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Update preparation'));
      await t.tap(find.text('Update preparation'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
