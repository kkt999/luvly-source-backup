import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:luvly_app/packages/fitting_assessment.dart';
import 'package:luvly_app/packages/fitting_result_screen.dart';
import 'package:luvly_app/packages/fitting_proposal_screen.dart';
import 'package:luvly_app/planning/planning_api.dart';
import 'package:luvly_app/src/design.dart';
import 'packages/package_rental_test.dart' show selection;
import 'fitting_workflow_test.dart' show apiFor;
import 'fitting_proposal_test.dart' show proposed;
import 'checkout_redesign_test.dart' show fonts, viewport;

const gowns = [
  {'dressId': 'gown', 'name': 'Ivory satin gown', 'size': 'M'},
  {'dressId': 'second', 'name': 'Lace wedding gown', 'size': 'S'},
];
Future<void> visible(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 180);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await visible(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> field(WidgetTester t, String key, String value) async {
  final f = find.byKey(ValueKey(key));
  await visible(t, f);
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> app(
  WidgetTester t,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1100));
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

void main() {
  test(
    'canonical cm survives repeated switches; blanks and unknown fit are not fabricated',
    () {
      final d = FittingAssessmentDraft(gowns);
      addTearDown(d.dispose);
      expect(d.toJson(adjustments: false)['bodyCm'], isEmpty);
      expect(
        d.gowns.every((g) => g.fit.values.every((v) => v == 'NotAssessed')),
        true,
      );
      d.body['bust']!.text = '85';
      d.changed('bust');
      for (var i = 0; i < 40; i++) {
        expect(d.switchUnit(true), true);
        expect(d.body['bust']!.text, '33.46');
        expect(d.switchUnit(false), true);
      }
      expect(d.bodyCm['bust'], 85);
      expect(d.body['waist']!.text, isEmpty);
      d.switchUnit(true);
      d.body['bust']!.text = '33.46';
      d.changed('bust');
      expect(d.bodyCm['bust'], 84.9884);
      d.switchUnit(false);
      expect(d.body['bust']!.text, '84.99');
      d.switchUnit(true);
      expect(d.bodyCm['bust'], 84.9884);
      for (final invalid in [
        '0',
        '-20',
        'NaN',
        'Infinity',
        '120',
        '1.234',
        'abc',
      ]) {
        d.body['bust']!.text = invalid;
        d.changed('bust');
        expect(d.measurementError, isNotNull);
        expect(d.switchUnit(false), false);
      }
      d.body['bust']!.clear();
      d.changed('bust');
      expect(d.measurementError, isNull);
    },
  );
  test(
    'adjustment details are conditional and do not leak into an unchanged outcome',
    () {
      final d = FittingAssessmentDraft(gowns);
      addTearDown(d.dispose);
      expect(d.validate(adjustments: true, pickup: '2030-01-01'), isNotNull);
      d.gowns.first.notes.text = 'Take in waist by 2 cm';
      d.followUp = 'Required';
      d.targetDate = fittingToday();
      expect(
        d.validate(adjustments: true, pickup: fittingDay(fittingToday())),
        isNull,
      );
      final hidden = d.toJson(adjustments: false);
      expect(hidden['followUp'], 'NotDecided');
      expect(hidden['targetDate'], isNull);
      expect(
        (hidden['gowns'] as List).every((g) => g['adjustmentNotes'] == ''),
        true,
      );
      d.targetDate = fittingToday().subtract(const Duration(days: 1));
      expect(d.validate(adjustments: true, pickup: '2030-01-01'), isNotNull);
    },
  );
  testWidgets(
    'staff submits optional measurements, per-gown fit and follow-up without charging or booking',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      final s = selection();
      s.data['rentalPlan']['pickupDate'] = fittingDay(
        fittingToday().add(const Duration(days: 10)),
      );
      await app(t, FittingResultScreen(selection: s, api: api));
      await tap(t, find.byType(DropdownButtonFormField<String>).first);
      await t.tap(find.text(planningTime(1792116000000)).last);
      await t.pumpAndSettle();
      await tap(
        t,
        find.widgetWithText(DropdownButtonFormField<String>, 'No adjustment'),
      );
      await t.tap(find.text('Basic fit adjustments').last);
      await t.pumpAndSettle();
      await field(t, 'body-bust', '85');
      await field(t, 'body-waist', '68');
      await tap(t, find.byKey(const ValueKey('fit-gown-waist')));
      await t.tap(find.text('Too loose').last);
      await t.pumpAndSettle();
      await field(t, 'adjustment-gown', 'Take in waist by 2 cm');
      await tap(t, find.byKey(const ValueKey('fitting-follow-up')));
      await t.tap(find.text('Another fitting needed').last);
      await t.pumpAndSettle();
      await tap(t, find.text('Set completion target (optional)'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await field(
        t,
        'fitting-notes',
        'Customer likes the gown and requests a waist adjustment.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await tap(t, find.text('Save fitting outcome'));
      expect(calls.length, 1);
      expect(calls.single.url.path, endsWith('/fitting-result'));
      final a = jsonDecode(calls.single.body)['assessment'];
      expect(a['bodyCm'], {'bust': 85.0, 'waist': 68.0});
      expect(a['gowns'][0]['fit']['waist'], 'Loose');
      expect(a['gowns'][0]['fit']['hips'], 'NotAssessed');
      expect(a['followUp'], 'Required');
      expect(a['targetDate'], fittingDay(fittingToday()));
      expect(
        calls.any(
          (c) =>
              c.url.path.contains('checkout') || c.url.path.endsWith('/book'),
        ),
        false,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'no-fitting approval cannot invent a body or garment assessment',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      final s = selection();
      s.data['fittingChoice'] = {'mode': 'SkipFitting', 'accepted': true};
      await app(t, FittingResultScreen(selection: s, api: api));
      expect(find.text('Measurements & fit assessment'), findsNothing);
      await field(
        t,
        'fitting-notes',
        'Reviewed the customer request and agreed selected items.',
      );
      await tap(t, find.byKey(const ValueKey('fitting-attendance')));
      await tap(t, find.text('Approve no-fitting request'));
      expect(calls.length, 1);
      expect(jsonDecode(calls.single.body).containsKey('assessment'), false);
    },
  );
  testWidgets(
    'customer proposal shows instructions but no raw body measurements',
    (t) async {
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      final s = proposed();
      s.data['fittingDecision'] = <String, dynamic>{
        ...s.data['fittingDecision'],
        'assessment': {
          'bodyCm': {'bust': 85},
          'gowns': [],
        },
      };
      s.data['fittingQuote']['adjustmentPlan'] = {
        'gowns': [
          {
            'name': 'Ivory satin gown',
            'size': 'M',
            'instructions': 'Take in waist by 2 cm',
          },
        ],
        'followUp': 'Required',
        'targetDate': '2026-10-24',
      };
      await app(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: FittingProposalPanel(
              selection: s,
              api: api,
              staff: false,
              manager: false,
              reload: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Take in waist by 2 cm'), findsOneWidget);
      expect(find.text('Measurements & fit record'), findsNothing);
      expect(find.textContaining('85 cm'), findsNothing);
      expect(calls, isEmpty);
      await tap(t, find.text('Review & accept proposal'));
      await tap(t, find.byType(CheckboxListTile));
      await tap(t, find.text('Agree to proposal'));
      expect(jsonDecode(calls.single.body), {
        'revision': 1,
        'response': 'Accept',
        'adjustmentPlanVersion': 1,
      });
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('expanded metrics fit $width at $scale', (t) async {
        final d = FittingAssessmentDraft(gowns);
        addTearDown(d.dispose);
        await app(
          t,
          RepaintBoundary(
            key: const ValueKey('metrics-capture'),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Measurements & fit assessment'),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: FittingAssessmentEditor(
                      draft: d,
                      adjustments: true,
                      enabled: true,
                      pickup: '2030-01-01',
                    ),
                  ),
                ),
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(find.byKey(const ValueKey('body-bust')), findsOneWidget);
        expect(t.takeException(), isNull);
        if (scale == 1 && width != 320) {
          await expectLater(
            find.byKey(const ValueKey('metrics-capture')),
            matchesGoldenFile(
              'previews/fitting-metrics-${width == 390 ? 'mobile' : 'desktop'}.png',
            ),
          );
        }
        await visible(t, find.byKey(const ValueKey('adjustment-second')));
        expect(t.takeException(), isNull);
        await visible(t, find.text('Set completion target (optional)'));
        expect(t.takeException(), isNull);
      });
    }
  }
}
