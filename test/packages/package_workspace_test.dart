import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/admin/model.dart';
import 'package_test.dart' show FakePackages, bridal, tapVisible;

class WorkspacePackages extends FakePackages implements PackageDeletionApi {
  int catalogueReads = 0, selectionReads = 0, deleted = 0;
  bool failCatalogue = false, failSelections = false;
  @override
  Future<List<BridalPackage>> catalogue() async {
    catalogueReads++;
    if (failCatalogue) throw StateError('catalogue unavailable');
    return [bridal];
  }

  @override
  Future<List<PackageSelection>> selections() async {
    selectionReads++;
    if (failSelections) throw StateError('orders unavailable');
    return rows;
  }

  @override
  Future<void> remove(BridalPackage package) async {
    deleted++;
  }
}

void main() {
  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test(
    'preview package mutations are manager only; both roles can open rentals',
    () {
      final model = PortalModel()..login(PortalRole.staff);
      expect(model.canOpen(PortalPage.rentals), isTrue);
      expect(() => model.savePackage(model.packages.first), throwsStateError);
      expect(
        () => model.deactivatePackage(model.packages.first),
        throwsStateError,
      );
      model.login(PortalRole.manager);
      expect(
        () => model.deactivatePackage(model.packages.first),
        returnsNormally,
      );
    },
  );

  testWidgets(
    'staff catalogue is read-only and independent of customer rentals',
    (tester) async {
      desktop(tester);
      final api = WorkspacePackages()..failSelections = true;
      await tester.pumpWidget(
        MaterialApp(home: LivePackageScreen(staff: true, api: api)),
      );
      await tester.pumpAndSettle();
      expect(api.selectionReads, 0);
      expect(find.text('Package catalogue'), findsOneWidget);
      expect(find.text('Customer selections'), findsNothing);
      expect(find.text('Create package'), findsNothing);
      await tapVisible(tester, find.text('Essential Bridal'));
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
      expect(api.packagesSaved, 0);
    },
  );

  testWidgets(
    'manager catalogue shows management actions but no customer tab',
    (tester) async {
      desktop(tester);
      final api = WorkspacePackages();
      await tester.pumpWidget(
        MaterialApp(
          home: LivePackageScreen(staff: true, manager: true, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create package'), findsOneWidget);
      expect(find.text('Customer selections'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      await tester.tap(find.byTooltip('More actions for Essential Bridal'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Delete'));
      expect(find.text('Delete package?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.deleted, 1);
    },
  );

  testWidgets(
    'customer rental workspace loads only orders and combines search with stage filter',
    (tester) async {
      desktop(tester);
      final api = WorkspacePackages()..failCatalogue = true;
      for (final row in [
        {
          'id': 'one',
          'name': 'First package',
          'customerName': 'Jane',
          'rental': {'state': 'Locked'},
        },
        {'id': 'two', 'name': 'Second package', 'customerName': 'Amy'},
      ]) {
        api.rows.add(
          PackageSelection({
            ...row,
            'totalCents': 89900,
            'services': [],
            'appointments': [],
          }),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: LivePackageScreen(
            staff: true,
            manager: true,
            initialSelections: true,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.catalogueReads, 0);
      expect(find.text('Create package'), findsNothing);
      expect(find.text('Packages'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Jane');
      await tester.pumpAndSettle();
      expect(find.text('First package'), findsOneWidget);
      expect(find.text('Second package'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Not reserved'));
      await tester.pumpAndSettle();
      expect(
        find.text('No customer rentals match your search and filters.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'Amy');
      await tester.pumpAndSettle();
      expect(find.text('Second package'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('rental labels distinguish draft, expiry, collection and returns', () {
    String stage(Map<String, dynamic>? rental) => customerRentalStage(
      PackageSelection({'rental': rental}),
      now: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(stage(null), 'Not reserved');
    expect(stage({'state': 'Held', 'expiresAt': 999}), 'Expired');
    expect(stage({'state': 'Held', 'expiresAt': 1001}), 'Awaiting deposit');
    expect(stage({'state': 'Locked', 'fulfilment': 'Collected'}), 'Collected');
    expect(stage({'state': 'Locked', 'fulfilment': 'Returned'}), 'Returned');
    expect(stage({'state': 'PaymentReview'}), 'Needs review');
  });
}
