import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/admin/inventory_workspace.dart';
import 'package:luvly_app/admin/live_inventory.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/bookings/staff_appointment_workspace.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'availability_calendar_test.dart' show tapVisible;
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'module_search_test.dart' show choose;
import 'fake_catalogue.dart';

final clock = DateTime.utc(2026, 10, 23, 4);
BookingRequest visit(
  String id, {
  String status = 'Confirmed',
  DateTime? start,
  int revision = 1,
}) => BookingRequest(id, {
  'uid': 'bride',
  'name': 'Customer $id',
  'phone': '0123456789',
  'type': 'Dress Trial',
  'startAt': Timestamp.fromDate(start ?? DateTime.utc(2026, 10, 23, 2)),
  'status': status,
  'notes': 'Customer notes for $id',
  'dressName': 'Ivory gown',
  'response': '',
  'slotKey': 'slot-$id',
  'revision': revision,
});
Widget appointments(
  List<BookingRequest> rows, {
  String? busy,
  String? error,
  void Function(BookingRequest, String)? onUpdate,
}) => MaterialApp(
  theme: portalTheme,
  home: Scaffold(
    body: StaffAppointmentWorkspace(
      rows: rows,
      now: clock,
      busy: busy,
      error: error,
      onUpdate: onUpdate ?? (_, _) {},
      onRefresh: () {},
      onPayments: () {},
      onPackage: (_) {},
    ),
  ),
);
CatalogueDress gown(
  String id, {
  String sizes = 'S, M',
  bool published = true,
  int price = 89900,
}) => CatalogueDress.fromFields(id, {
  ...sampleDress(id: id, name: 'Gown $id').toFields(),
  'sizes': sizes,
  'published': published,
  'priceCents': price,
  'imageUrl': '',
  'revision': 1,
});
Widget inventory(
  List<CatalogueDress> rows,
  InventoryListState state, {
  bool manager = false,
  bool cached = false,
  double scale = 1,
  ValueChanged<CatalogueDress>? onStock,
}) => CatalogueScope(
  repository: FakeCatalogue(),
  child: MaterialApp(
    theme: portalTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          InventoryWorkspace(
            records: rows,
            state: state,
            onView: (_) {},
            onStock: onStock ?? (_) {},
            onEdit: manager ? (_) {} : null,
            cached: cached,
          ),
        ],
      ),
    ),
  ),
);

void main() {
  test('MYT today crosses UTC midnight without using device timezone', () {
    expect(
      sameMalaysiaDay(
        DateTime.utc(2026, 10, 22, 16),
        DateTime.utc(2026, 10, 23, 15, 59),
      ),
      isTrue,
    );
    expect(
      sameMalaysiaDay(
        DateTime.utc(2026, 10, 22, 15, 59),
        DateTime.utc(2026, 10, 23, 0),
      ),
      isFalse,
    );
  });
  test(
    'size filters are exact, combined with publication, colour and query',
    () {
      final rows = [
        gown('xs', sizes: 'XS'),
        gown('s'),
        gown('draft', published: false),
        gown('custom', sizes: 'Made to measure'),
      ];
      final s = InventoryListState()
        ..size = 'S'
        ..visibility = 'Published'
        ..colour = 'Ivory'
        ..query = 'gown';
      expect(filterInventory(rows, s).map((d) => d.id), ['s']);
      s.size = 'Made to measure';
      expect(filterInventory(rows, s).single.id, 'custom');
      s.category = 'Mermaid';
      expect(filterInventory(rows, s), isEmpty);
      s.reset();
      expect(filterInventory(rows, s), hasLength(4));
    },
  );
  test('inventory sorts deterministically and does not infer quantities', () {
    final s = InventoryListState()..sort = 'Price: low to high';
    expect(
      filterInventory([
        gown('b', price: 100),
        gown('a', price: 100),
        gown('c', price: 200),
      ], s).map((d) => d.id),
      ['a', 'b', 'c'],
    );
    s.sort = 'Price: high to low';
    expect(
      filterInventory([
        gown('a', price: 100),
        gown('c', price: 200),
      ], s).first.id,
      'c',
    );
  });
  testWidgets(
    'view is read-only; same ID refresh updates actions and removal never substitutes another visit',
    (t) async {
      viewport(t, const Size(1450, 1050));
      final updates = <String>[];
      await t.pumpWidget(
        appointments([
          visit('a'),
          visit('b'),
        ], onUpdate: (b, s) => updates.add('${b.id}:${b.revision}:$s')),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('view-visit-a')));
      expect(updates, isEmpty);
      await t.pumpWidget(
        appointments([
          visit('a', revision: 2),
          visit('b'),
        ], onUpdate: (b, s) => updates.add('${b.id}:${b.revision}:$s')),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('visit-action-Completed')));
      expect(updates, ['a:2:Completed']);
      await t.pumpWidget(
        appointments([
          visit('a', status: 'Completed', revision: 3),
          visit('b'),
        ]),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('visit-action-Completed')),
        findsNothing,
      );
      await t.pumpWidget(appointments([visit('b')]));
      await t.pumpAndSettle();
      expect(find.text('Appointment unavailable'), findsOneWidget);
      expect(find.text('Customer b'), findsNothing);
      expect(
        find.byKey(const ValueKey('visit-action-Cancelled')),
        findsNothing,
      );
    },
  );
  for (final status in ['Confirmed', 'AwaitingPayment', 'Requested']) {
    testWidgets('$status future visit keeps transition guards', (t) async {
      viewport(t, const Size(1450, 1050));
      await t.pumpWidget(
        appointments([
          visit(
            'a',
            status: status,
            start: clock.add(const Duration(hours: 1)),
          ),
        ]),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('view-visit-a')));
      await tapVisible(t, find.text('Visit administration'));
      final complete = find.byKey(const ValueKey('visit-action-Completed'));
      if (status == 'Confirmed') {
        expect(t.widget<OutlinedButton>(complete).onPressed, isNull);
        expect(
          t
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('visit-action-NoShow')),
              )
              .onPressed,
          isNull,
        );
      } else {
        expect(complete, findsNothing);
      }
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('visit-action-Cancelled')),
            )
            .onPressed,
        isNotNull,
      );
    });
  }
  testWidgets(
    'no-show opens only after an hour, busy disables changes without showing fake completion',
    (t) async {
      viewport(t, const Size(1450, 1050));
      await t.pumpWidget(
        appointments([
          visit('a', start: clock.subtract(const Duration(minutes: 59))),
        ]),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('view-visit-a')));
      await tapVisible(t, find.text('Visit administration'));
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('visit-action-NoShow')),
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(
        appointments([
          visit('a', start: clock.subtract(const Duration(hours: 1))),
        ], busy: 'a'),
      );
      await t.pump();
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('visit-action-NoShow')),
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(
        appointments([
          visit('a', start: clock.subtract(const Duration(hours: 1))),
        ]),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('visit-action-NoShow')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'today/type/status combine and list filters survive opening and returning',
    (t) async {
      viewport(t, const Size(1450, 1100));
      await t.pumpWidget(
        appointments([
          visit('a'),
          visit('b', start: clock.add(const Duration(days: 1))),
          visit('c', status: 'Completed'),
        ]),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.widgetWithText(ChoiceChip, 'Today'));
      await choose(t, 'Status', 'Confirmed');
      expect(find.text('Customer a'), findsOneWidget);
      expect(find.text('Customer b'), findsNothing);
      expect(find.text('Customer c'), findsNothing);
      await tapVisible(t, find.byKey(const ValueKey('view-visit-a')));
      await tapVisible(t, find.text('Back to appointments'));
      expect(find.text('Customer a'), findsOneWidget);
      expect(find.text('Customer b'), findsNothing);
    },
  );
  testWidgets('appointment page bounds clamp when source shrinks', (t) async {
    viewport(t, const Size(1450, 1100));
    await t.pumpWidget(
      appointments([
        for (var n = 0; n < 21; n++) visit(n.toString().padLeft(2, '0')),
      ]),
    );
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Next'));
    expect(find.text('21–21 of 21'), findsOneWidget);
    await t.pumpWidget(appointments([visit('only')]));
    await t.pumpAndSettle();
    await tapVisible(t, find.byKey(const ValueKey('view-visit-only')));
    expect(find.text('Customer only'), findsWidgets);
    expect(find.text('Back to appointments').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'inventory pagination, read-only staff and direct stock entry retain exact dress',
    (t) async {
      viewport(t, const Size(1450, 1050));
      final state = InventoryListState();
      String? stock;
      final rows = [
        for (var n = 0; n < 21; n++) gown(n.toString().padLeft(2, '0')),
      ];
      await t.pumpWidget(inventory(rows, state, onStock: (d) => stock = d.id));
      await t.pumpAndSettle();
      expect(find.byTooltip('Edit Gown 00'), findsNothing);
      await tapVisible(t, find.text('Next'));
      expect(state.page, 1);
      await tapVisible(t, find.byKey(const ValueKey('inventory-stock-20')));
      expect(stock, '20');
      state.query = 'Gown 00';
      await t.pumpWidget(inventory(rows, state));
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('inventory-view-00')));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'cached manager catalogue disables editing but remains readable',
    (t) async {
      viewport(t, const Size(1450, 1050));
      await t.pumpWidget(
        inventory(
          [gown('a')],
          InventoryListState(),
          manager: true,
          cached: true,
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Edit Gown a',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Cached catalogue'), findsOneWidget);
      expect(find.textContaining('0 available'), findsNothing);
    },
  );
  testWidgets(
    'inventory selected record removal is explicit and filters survive return',
    (t) async {
      viewport(t, const Size(1450, 1100));
      final repo = FakeCatalogue()
        ..records['a'] = gown('alpha')
        ..records['b'] = gown('b');
      final model = PortalModel.live(
        member: TeamMember(
          'john',
          'John',
          'john@example.com',
          PortalRole.staff,
        ),
      );
      addTearDown(model.dispose);
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        CatalogueScope(
          repository: repo,
          child: PortalScope(
            model: model,
            child: MaterialApp(
              theme: portalTheme,
              home: const Scaffold(body: LiveInventoryPage()),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'alpha');
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('inventory-view-alpha')));
      repo.records.remove('a');
      repo.changes.add(null);
      await t.pumpAndSettle();
      expect(
        find.textContaining('no longer in the current catalogue'),
        findsOneWidget,
      );
      expect(find.text('Gown b'), findsNothing);
      await tapVisible(t, find.text('Back to inventory'));
      expect(find.text('Gown b'), findsNothing);
      expect(repo.saves, 0);
    },
  );
  for (final width in [320.0, 1100.0]) {
    testWidgets('operations pages fit $width at double text size', (t) async {
      viewport(t, Size(width, 1000));
      await t.pumpWidget(
        inventory([gown('a')], InventoryListState(), scale: 2),
      );
      await t.pumpAndSettle();
      if (width < 600) {
        await tapVisible(t, find.text('Refine inventory'));
      }
      await tapVisible(t, find.text('Reset filters').first);
      await tapVisible(t, find.byKey(const ValueKey('inventory-view-a')));
      expect(t.takeException(), isNull);
      await t.pumpWidget(
        MaterialApp(
          theme: portalTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: StaffAppointmentWorkspace(
              rows: [visit('a')],
              now: clock,
              onUpdate: (_, _) {},
              onRefresh: () {},
              onPayments: () {},
              onPackage: (_) {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const ValueKey('view-visit-a')));
      await tapVisible(t, find.text('Visit administration'));
      expect(t.takeException(), isNull);
    });
  }
  for (final scene in ['appointments', 'inventory']) {
    testWidgets('operations preview $scene', (t) async {
      viewport(t, const Size(1450, 1100));
      await t.runAsync(fonts);
      const capture = ValueKey('operations-preview');
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: scene == 'appointments'
              ? appointments([
                  visit('Jane Lim'),
                  visit('Mei Wong', start: clock.add(const Duration(hours: 2))),
                  visit('Sarah Lee', status: 'AwaitingPayment'),
                  visit('Nora Tan', status: 'Completed'),
                ])
              : inventory(
                  [
                    gown('Ivory Lace'),
                    gown('Signature Satin'),
                    gown('Rose Bridal', published: false),
                  ],
                  InventoryListState(),
                  manager: true,
                ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile('previews/staff-$scene-2073.png'),
      );
    });
  }
}
