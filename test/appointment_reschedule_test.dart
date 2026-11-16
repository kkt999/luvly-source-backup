import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/bookings/reschedule_api.dart';
import 'package:luvly_app/bookings/reschedule_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;

final oldStart = DateTime.utc(2026, 11, 3, 2);
RescheduleContext context({bool eligible = true, String? reason}) =>
    RescheduleContext(
      id: 'visit',
      type: 'Dress Trial',
      start: oldStart,
      revision: 2,
      serverNow: DateTime.utc(2026, 11, 2),
      lastDay: DateTime(2026, 11, 10),
      eligible: eligible,
      feePreserved: true,
      reason: reason,
    );

class FakeMoveApi extends RescheduleApi {
  RescheduleContext current = context();
  int loads = 0, slotReads = 0, idCount = 0;
  bool failLoad = false, failSave = false;
  List<int> available = [11, 12, 14];
  final saved =
      <({String id, int revision, DateTime start, String requestId})>[];
  Completer<RescheduleResult>? pending;
  @override
  String requestId() => 'request-${++idCount}';
  @override
  Future<RescheduleContext> load(String id) async {
    loads++;
    if (failLoad) throw const PaymentFailure('Connection unavailable');
    return current;
  }

  @override
  Future<List<int>> hours(DateTime day, String type) async {
    slotReads++;
    return available;
  }

  @override
  Future<RescheduleResult> save(
    RescheduleContext c,
    DateTime start,
    String requestId,
  ) async {
    saved.add((
      id: c.id,
      revision: c.revision,
      start: start,
      requestId: requestId,
    ));
    if (pending != null) return pending!.future;
    if (failSave) {
      throw const PaymentFailure(
        'This time has been booked. Please choose another time.',
      );
    }
    return RescheduleResult(start, 'Confirmed');
  }
}

Future<void> mount(
  WidgetTester t,
  FakeMoveApi api, {
  bool large = false,
  ValueChanged<RescheduleResult?>? result,
}) async {
  viewport(t, Size(large ? 320 : 390, 844));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
        child: w!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (c) => FilledButton(
            onPressed: () async {
              final value = await Navigator.of(c).push<RescheduleResult>(
                MaterialPageRoute(
                  builder: (_) => RepaintBoundary(
                    key: const Key('move-capture'),
                    child: RescheduleAppointmentScreen(
                      appointmentId: 'visit',
                      api: api,
                    ),
                  ),
                ),
              );
              result?.call(value);
            },
            child: const Text('Open visit'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open visit'));
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, int hour) async {
  final f = find.byKey(ValueKey('reschedule-hour-$hour'));
  await t.scrollUntilVisible(
    f,
    180,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last,
  );
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> confirm(WidgetTester t) async {
  await t.tap(find.widgetWithText(FilledButton, 'Confirm new time'));
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton, 'Confirm reschedule'));
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('move-capture')),
        ),
        im = await boundary.toImage(),
        bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    Directory('work/reschedule-2116').createSync(recursive: true);
    File(
      'work/reschedule-2116/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    im.dispose();
  });
}

void main() {
  test(
    'API keeps the same visit, sends no owner/type/fee override and handles conflicts',
    () async {
      final requests = <http.Request>[];
      final transport = HttpPaymentApi(
        baseUrl: 'https://fixture.example',
        token: () async => 'fixture',
        client: MockClient((r) async {
          requests.add(r);
          if (r.method == 'POST') {
            return http.Response(
              jsonEncode({
                'appointmentId': 'visit',
                'revision': 3,
                'startAt': oldStart
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
                'status': 'Confirmed',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'appointmentId': 'visit',
              'type': 'Dress Trial',
              'startAt': oldStart.millisecondsSinceEpoch,
              'revision': 2,
              'serverNow': DateTime.utc(2026, 11, 2).millisecondsSinceEpoch,
              'latestDay': '2026-11-10',
              'eligible': true,
              'reason': null,
              'feePreserved': true,
            }),
            200,
          );
        }),
      );
      final api = RescheduleApi(transport: transport),
          c = await api.load('visit');
      await api.save(c, oldStart.add(const Duration(hours: 1)), 'retry-id');
      expect(
        requests.every(
          (r) => r.url.path == '/v1/appointments/visit/reschedule',
        ),
        isTrue,
      );
      final data = jsonDecode(requests.last.body) as Map;
      expect(data.keys.toSet(), {'revision', 'startAt', 'requestId'});
      expect(data['revision'], 2);
      transport.close();
      expect(
        () => RescheduleContext.parse({'eligible': true}, 'visit'),
        throwsA(isA<PaymentFailure>()),
      );
    },
  );
  testWidgets(
    'reschedule retains current visit and fee; keeping current time never submits',
    (t) async {
      final api = FakeMoveApi();
      RescheduleResult? result;
      await mount(t, api, result: (r) => result = r);
      expect(find.textContaining('Current appointment:'), findsOneWidget);
      expect(find.textContaining('verified fitting fee stays'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm new time'),
            )
            .onPressed,
        isNull,
      );
      await choose(t, 11);
      await t.tap(find.widgetWithText(FilledButton, 'Confirm new time'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep current time'));
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      await confirm(t);
      expect(api.saved.single.id, 'visit');
      expect(api.saved.single.revision, 2);
      expect(result!.start, oldStart.add(const Duration(hours: 1)));
    },
  );
  testWidgets(
    'conflict retains form; retries keep request ID and changing target uses a new one',
    (t) async {
      final api = FakeMoveApi()..failSave = true;
      await mount(t, api);
      await choose(t, 11);
      await confirm(t);
      await confirm(t);
      expect(api.saved[0].requestId, api.saved[1].requestId);
      expect(api.loads, 1);
      await choose(t, 12);
      await confirm(t);
      expect(api.saved[2].requestId, isNot(api.saved[1].requestId));
      expect(find.textContaining('Current appointment:'), findsOneWidget);
      expect(find.byType(RescheduleAppointmentScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unpaid or ineligible visits do not offer available-time or save controls',
    (t) async {
      final api = FakeMoveApi()
        ..current = context(
          eligible: false,
          reason: 'RESCHEDULE_PAYMENT_REQUIRED',
        );
      await mount(t, api);
      expect(
        find.textContaining('Complete the fitting payment'),
        findsOneWidget,
      );
      expect(find.text('Confirm new time'), findsNothing);
      expect(api.slotReads, 0);
      expect(api.saved, isEmpty);
    },
  );
  testWidgets(
    'an in-flight save prevents repeated submission and accidental navigation away',
    (t) async {
      final api = FakeMoveApi()..pending = Completer<RescheduleResult>();
      await mount(t, api);
      await choose(t, 11);
      await confirm(t);
      expect(api.saved.length, 1);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(RescheduleAppointmentScreen), findsOneWidget);
      api.pending!.complete(
        RescheduleResult(oldStart.add(const Duration(hours: 1)), 'Confirmed'),
      );
      await t.pumpAndSettle();
      expect(find.byType(RescheduleAppointmentScreen), findsNothing);
      expect(api.saved.length, 1);
    },
  );
  testWidgets('a failed context load cannot submit and can be retried', (
    t,
  ) async {
    final api = FakeMoveApi()..failLoad = true;
    await mount(t, api);
    expect(find.text('Connection unavailable'), findsOneWidget);
    expect(find.text('Confirm new time'), findsNothing);
    api.failLoad = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(api.loads, 2);
    expect(find.text('Available times'), findsOneWidget);
  });
  testWidgets(
    'unavailable day preserves existing booking and choosing another day loads new times',
    (t) async {
      final api = FakeMoveApi()..available = [];
      await mount(t, api);
      expect(
        find.textContaining('No other times are available'),
        findsOneWidget,
      );
      expect(api.saved, isEmpty);
      await t.tap(find.text('New date'));
      await t.pumpAndSettle();
      await t.tap(find.text('4').last);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(api.slotReads, 2);
      expect(api.saved, isEmpty);
      expect(find.textContaining('4/11/2026'), findsOneWidget);
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'rescheduling form and confirmation fit ${large ? 'large' : 'normal'} text',
      (t) async {
        final api = FakeMoveApi();
        await mount(t, api, large: large);
        await capture(t, large ? 'form-large' : 'form');
        expect(t.takeException(), isNull);
        await choose(t, 11);
        await t.tap(find.widgetWithText(FilledButton, 'Confirm new time'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.text('Keep current time'));
        await t.pumpAndSettle();
        expect(api.saved, isEmpty);
      },
    );
  }
}
