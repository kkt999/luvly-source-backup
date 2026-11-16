import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/fitting_gown_change.dart';
import 'package:luvly_app/packages/fitting_result_screen.dart';
import 'package:luvly_app/packages/fitting_workbench.dart';
import 'package:luvly_app/packages/fitting_proposal_screen.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_rental_test.dart' show selection;

Map<String, dynamic> options({int count = 1}) => {
  'selectionRevision': 0,
  'planRevision': 2,
  'packageRevision': 1,
  'includedGownCount': count,
  'reserved': false,
  'gowns': [
    {
      'dressId': 'gown',
      'name': 'Ivory gown',
      'colour': 'Ivory',
      'category': 'Ball Gown',
      'revision': 1,
      'sizes': [
        {'size': 'M', 'status': 'Available'},
      ],
    },
    {
      'dressId': 'new',
      'name': 'Pearl A-Line',
      'colour': 'White',
      'category': 'A-Line',
      'revision': 2,
      'sizes': [
        {'size': 'S', 'status': 'Available'},
        {'size': 'M', 'status': 'Unavailable'},
        {'size': 'L', 'status': 'Unconfirmed'},
      ],
    },
  ],
};
HttpPackageApi api(
  List<http.Request> calls, {
  bool failOptions = false,
  bool stale = false,
  bool stockChanged = false,
}) => HttpPackageApi(
  transport: HttpPaymentApi(
    baseUrl: 'https://example.com',
    token: () async => 'token',
    client: MockClient((r) async {
      calls.add(r);
      if (r.url.path.endsWith('/fitting-gown-options')) {
        return http.Response(
          jsonEncode(
            failOptions
                ? {'error': 'RENTAL_PLAN_CHANGED'}
                : {...options(), if (stale) 'selectionRevision': 1},
          ),
          failOptions ? 409 : 200,
        );
      }
      return http.Response(
        jsonEncode(
          stockChanged
              ? {'error': 'RENTAL_STOCK_UNAVAILABLE'}
              : {'saved': true},
        ),
        stockChanged ? 409 : 200,
      );
    }),
  ),
);
Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1000));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      debugShowCheckedModeBanner: false,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: child,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> scroll(WidgetTester t, String text) async {
  final form = find.byKey(const ValueKey('fitting-form-scroll'));
  await t.scrollUntilVisible(
    find.text(text),
    180,
    scrollable: form.evaluate().isNotEmpty
        ? find.descendant(of: form, matching: find.byType(Scrollable)).first
        : find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

Future<void> decision(WidgetTester t, String text) async {
  if (find.byType(FittingOptions).evaluate().isEmpty) {
    await tap(t, find.byKey(const ValueKey('fitting-decision')));
  }
  await tap(t, find.text(text).last);
}

Future<void> chooseNew(WidgetTester t) async {
  await scroll(t, 'Select replacement gown & size');
  await tap(t, find.text('Select replacement gown & size'));
  await tap(t, find.byKey(const ValueKey('replacement-size-new')));
  await tap(t, find.text('S').last);
  await tap(t, find.text('Use these gowns (1/1)'));
}

void main() {
  testWidgets(
    'replacement draft is not submitted after returning to keep-current selection',
    (t) async {
      final calls = <http.Request>[], a = api(calls);
      addTearDown(a.close);
      await mount(t, FittingResultScreen(selection: selection(), api: a));
      await decision(t, 'Chosen a different gown');
      await chooseNew(t);
      await decision(t, 'Keep current gown selection');
      await tap(t, find.byKey(const ValueKey('fitting-visit')));
      await tap(t, find.textContaining('2026').last);
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer decided to keep the original ivory gown after discussion.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await scroll(t, 'Save fitting outcome');
      await tap(t, find.text('Save fitting outcome'));
      final body = jsonDecode(calls.last.body);
      expect(body.containsKey('gownChange'), false);
      expect(body['assessment']['gowns'].single['dressId'], 'gown');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'stock changing after the picker never shows a saved fitting result',
    (t) async {
      final calls = <http.Request>[], a = api(calls, stockChanged: true);
      addTearDown(a.close);
      await mount(t, FittingResultScreen(selection: selection(), api: a));
      await tap(t, find.byKey(const ValueKey('fitting-visit')));
      await tap(t, find.textContaining('2026').last);
      await decision(t, 'Chosen a different gown');
      await chooseNew(t);
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer attended and chose the Pearl A-Line in size S.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await scroll(t, 'Save fitting outcome');
      await tap(t, find.text('Save fitting outcome'));
      expect(find.byType(FittingResultScreen), findsOneWidget);
      expect(
        find.textContaining(
          'A selected item is unavailable for your rental and cleaning dates',
        ),
        findsOneWidget,
      );
      expect(calls.length, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'different gown requires an explicit gown and size; does not save attendance or a deposit on selection',
    (t) async {
      final calls = <http.Request>[], a = api(calls);
      addTearDown(a.close);
      await mount(t, FittingResultScreen(selection: selection(), api: a));
      await decision(t, 'Chosen a different gown');
      await scroll(t, 'Save fitting outcome');
      await tap(t, find.text('Save fitting outcome'));
      expect(calls, isEmpty);
      expect(
        find.textContaining('Select the replacement gown and size'),
        findsOneWidget,
      );
      await chooseNew(t);
      expect(calls.length, 1);
      expect(calls.single.url.path, endsWith('/fitting-gown-options'));
      expect(find.text('Previously: Ivory gown · M'), findsOneWidget);
      expect(find.text('Pearl A-Line · S\nWhite'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'submitted replacement and assessment use exact new gown while keeping attendance checks',
    (t) async {
      final calls = <http.Request>[], a = api(calls);
      addTearDown(a.close);
      await mount(t, FittingResultScreen(selection: selection(), api: a));
      await tap(t, find.byKey(const ValueKey('fitting-visit')));
      await tap(t, find.textContaining('2026').last);
      await decision(t, 'Chosen a different gown');
      await chooseNew(t);
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer attended and selected the Pearl A-Line in size S.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await scroll(t, 'Save fitting outcome');
      await tap(t, find.text('Save fitting outcome'));
      final result = calls.last;
      expect(result.url.path, endsWith('/fitting-result'));
      final body = jsonDecode(result.body);
      expect(body['outcome'], 'Selected');
      expect(body['appointmentId'], 'appointment');
      expect(body['confirmed'], true);
      expect(body['gownChange'], {
        'selectionRevision': 0,
        'planRevision': 2,
        'packageRevision': 1,
        'gowns': [
          {'dressId': 'new', 'size': 'S', 'revision': 2},
        ],
      });
      expect(body['assessment']['gowns'].single['dressId'], 'new');
      expect(body['assessment']['gowns'].single['size'], 'S');
      expect(calls.length, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'not chosen yet records reselection without replacement or implying a deposit',
    (t) async {
      final calls = <http.Request>[], a = api(calls);
      addTearDown(a.close);
      await mount(t, FittingResultScreen(selection: selection(), api: a));
      await decision(t, 'Needs another gown · not chosen yet');
      expect(find.text('Select replacement gown & size'), findsNothing);
      expect(find.textContaining('No new gown is agreed yet.'), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('fitting-visit')));
      await tap(t, find.textContaining('2026').last);
      await t.enterText(
        find.byKey(const ValueKey('fitting-notes')),
        'Customer attended but needs time to choose another gown.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await scroll(t, 'Save fitting outcome');
      await tap(t, find.text('Save fitting outcome'));
      final body = jsonDecode(calls.single.body);
      expect(body['outcome'], 'Reselect');
      expect(body.containsKey('gownChange'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unavailable and unconfirmed sizes stay disabled; removing selection resets the dropdown',
    (t) async {
      await mount(
        t,
        FittingGownChangePicker(
          options: options(),
          original: selection().selectedGowns,
        ),
      );
      await tap(t, find.byKey(const ValueKey('replacement-size-new')));
      for (final value in ['M', 'L']) {
        final item = find.byWidgetPredicate(
          (w) =>
              w is DropdownMenuItem<String> && w.value == value && !w.enabled,
        );
        expect(item, findsWidgets);
      }
      await tap(t, find.text('S').last);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tap(t, find.text('Remove selection'));
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('replacement-size-new')),
            )
            .initialValue,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('original unchanged gown cannot be submitted as a replacement', (
    t,
  ) async {
    await mount(
      t,
      FittingGownChangePicker(
        options: options(),
        original: selection().selectedGowns,
      ),
    );
    await tap(t, find.byKey(const ValueKey('replacement-size-gown')));
    await tap(t, find.text('M').last);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'multi gown entitlement needs a complete selection, not only the changed item',
    (t) async {
      await mount(
        t,
        FittingGownChangePicker(
          options: options(count: 2),
          original: selection().selectedGowns,
        ),
      );
      await tap(t, find.byKey(const ValueKey('replacement-size-new')));
      await tap(t, find.text('S').last);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tap(t, find.byKey(const ValueKey('replacement-size-gown')));
      await tap(t, find.text('M').last);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final stale in [false, true]) {
    testWidgets(
      'replacement lookup failure/stale=$stale never opens an unchecked picker',
      (t) async {
        final calls = <http.Request>[],
            a = api(calls, failOptions: !stale, stale: stale);
        addTearDown(a.close);
        await mount(t, FittingResultScreen(selection: selection(), api: a));
        await decision(t, 'Chosen a different gown');
        await scroll(t, 'Select replacement gown & size');
        await tap(t, find.text('Select replacement gown & size'));
        expect(find.byType(FittingGownChangePicker), findsNothing);
        expect(calls.length, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'customer and staff both see the exact replacement in the proposal, before any acceptance',
    (t) async {
      for (final staff in [false, true]) {
        final calls = <http.Request>[], a = api(calls);
        addTearDown(a.close);
        final s = selection();
        s.data.addAll({
          'fittingWorkflowVersion': 2,
          'fittingDecision': {
            'state': 'QuoteNeeded',
            'outcome': 'Selected',
            'adjustment': 'None',
            'gownChange': {
              'from': s.selectedGowns,
              'to': [
                {
                  'dressId': 'new',
                  'name': 'Pearl A-Line',
                  'size': 'S',
                  'colour': 'White',
                },
              ],
            },
          },
        });
        await mount(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: FittingProposalPanel(
                selection: s,
                api: a,
                staff: staff,
                manager: false,
                reload: () {},
              ),
            ),
          ),
        );
        expect(find.text('Gown selection updated at fitting'), findsOneWidget);
        expect(find.text('Pearl A-Line · S\nWhite'), findsOneWidget);
        expect(calls, isEmpty);
        expect(t.takeException(), isNull);
      }
    },
  );
  for (final width in [320.0, 1100.0]) {
    testWidgets('replacement picker fits $width at large text', (t) async {
      await mount(
        t,
        FittingGownChangePicker(
          options: options(),
          original: selection().selectedGowns,
        ),
        width: width,
        scale: 1.4,
      );
      await tap(t, find.byKey(const ValueKey('replacement-size-new')));
      await tap(t, find.text('S').last);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('replacement picker visual preview', (t) async {
    await mount(
      t,
      RepaintBoundary(
        key: const ValueKey('preview'),
        child: FittingGownChangePicker(
          options: options(),
          original: selection().selectedGowns,
        ),
      ),
      width: 1100,
    );
    await tap(t, find.byKey(const ValueKey('replacement-size-new')));
    await tap(t, find.text('S').last);
    await expectLater(
      find.byKey(const ValueKey('preview')),
      matchesGoldenFile('goldens/fitting-replacement-2067.png'),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('replacement outcome visual preview', (t) async {
    final calls = <http.Request>[], a = api(calls);
    addTearDown(a.close);
    await mount(
      t,
      RepaintBoundary(
        key: const ValueKey('form-preview'),
        child: FittingResultScreen(selection: selection(), api: a),
      ),
      width: 1100,
    );
    await decision(t, 'Chosen a different gown');
    await chooseNew(t);
    await t.scrollUntilVisible(
      find.text('Replacement selection'),
      -180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('fitting-form-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('form-preview')),
      matchesGoldenFile('goldens/fitting-replacement-form-2067.png'),
    );
    expect(t.takeException(), isNull);
  });
}
