import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/packages/accessory_draft_screen.dart';
import 'package:luvly_app/packages/package_presentation.dart';
import 'package_test.dart' show bridal;

void main() {
  testWidgets('draft search and shortlist never imply a booking or price', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AccessoryDraftScreen()));
    await tester.pumpAndSettle();
    expect(find.text('DRAFT · NOT AVAILABLE TO RENT'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'dress ring');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Shortlist concept'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shortlist concept'));
    await tester.pumpAndSettle();
    expect(find.text('Your concept shortlist (1)'), findsOneWidget);
    expect(find.text('Shortlisted · draft'), findsOneWidget);
    await tester.ensureVisible(find.text('View item details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View item details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not a wedding band'), findsOneWidget);
    expect(find.textContaining('No stock is reserved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('package card fits $width without invented inclusion claims', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PackageCollectionCard(
                package: bridal,
                onExplore: () {},
                index: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RM 2,500.00'), findsOneWidget);
      expect(find.text('Dress rental'), findsOneWidget);
      expect(find.textContaining('priced separately'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
