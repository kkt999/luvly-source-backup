import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/catalogue_widgets.dart';
import 'package:luvly_app/admin/live_inventory.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'fake_catalogue.dart';

void main() {
  test(
    'Structured dress validation rejects placeholder fields and malformed sizes',
    () {
      final sample = sampleDress();
      for (final mutation in <Map<String, dynamic>>[
        {'colour': 'sdsdsds'},
        {'sizes': 'sdsd'},
        {'sizes': 'S, S'},
        {'sizes': 'S, Made to measure'},
        {'sizes': ''},
        {'priceCents': 0},
        {'priceCents': -1},
        {'name': '  '},
        {'name': '12345'},
        {'name': 'Dress\u0000Name'},
        {'description': 'ewqeqwe'},
        {'description': '123456789012345678901'},
        {'description': '  A long description with unwanted padding.  '},
      ]) {
        expect(
          CatalogueDress.fromFields(sample.id, {
            ...sample.toFields(),
            'revision': 1,
            ...mutation,
          }).validationError,
          isNotNull,
          reason: mutation.toString(),
        );
      }
      expect(
        CatalogueDress.fromFields(sample.id, {
          ...sample.toFields(),
          'revision': 1,
          'name': '象牙白婚纱',
          'sizes': 'Made to measure',
        }).validationError,
        isNull,
      );
      expect(
        validDressSizes(
          dressSizes.where((s) => s != 'Made to measure').join(', '),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'High prices need confirmation; changes reset it and sizing is exclusive',
    (tester) async {
      final repo = FakeCatalogue();
      addTearDown(repo.changes.close);
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DressEditor(
            repository: repo,
            actorUid: 'manager',
            dress: sampleDress(),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price (RM)'),
        '100000',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Dress'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(
        find.text('Confirm this unusually high price before saving'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price (RM)'),
        '200000',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Made to measure'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'S'))
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'M'))
            .selected,
        isFalse,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'L'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, 'Made to measure'),
            )
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'L'))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Empty form shows required colour and sizes and never saves', (
    tester,
  ) async {
    final repo = FakeCatalogue();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: DressEditor(repository: repo, actorUid: 'manager'),
      ),
    );
    await tester.tap(find.text('Save Dress'));
    await tester.pumpAndSettle();
    expect(find.text('Select the actual dress colour'), findsOneWidget);
    expect(find.text('Select at least one available size'), findsOneWidget);
    expect(repo.saves, 0);
    expect(tester.takeException(), isNull);
  });

  test('Price is stored as exact cents and rejects malformed values', () {
    expect(parsePriceCents('1250.50'), 125050);
    expect(parsePriceCents('1.2'), 120);
    expect(parsePriceCents('0.01'), 1);
    for (final invalid in [
      '-1',
      '0',
      '0.00',
      'NaN',
      'Infinity',
      '1e3',
      '2.345',
      '',
      '1000000.01',
    ]) {
      expect(parsePriceCents(invalid), isNull, reason: invalid);
    }
  });
  test('Photo links and published dress requirements are validated', () {
    expect(validPhotoUrl('https://example.com/a.jpg'), isTrue);
    for (final invalid in [
      'http://example.com/a.jpg',
      'data:image/png;base64,aa',
      'javascript:alert(1)',
      'https://user:password@example.com/a',
      'https://example.com/with space',
    ]) {
      expect(validPhotoUrl(invalid), isFalse);
    }
    final d = sampleDress();
    expect(d.validationError, isNull);
    expect(
      CatalogueDress.fromFields(d.id, {
        ...d.toFields(),
        'revision': 1,
        'imageUrl': '',
      }).validationError,
      contains('photo'),
    );
    expect(
      CatalogueDress.fromFields(d.id, {
        ...d.toFields(),
        'revision': 1,
        'imageUrl': '',
        'published': false,
      }).validationError,
      isNull,
    );
  });

  for (final role in PortalRole.values) {
    testWidgets('${role.name} inventory has the correct editing access', (
      tester,
    ) async {
      final repo = FakeCatalogue()
        ..records['dress-1'] = sampleDress(published: false);
      final model = PortalModel.live(
        member: TeamMember('uid', 'John', 'john@example.com', role),
      );
      addTearDown(model.dispose);
      addTearDown(repo.changes.close);
      await tester.pumpWidget(
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
      await tester.pumpAndSettle();
      expect(find.text('Test Lace Dress'), findsOneWidget);
      expect(
        find.text('Add Dress'),
        role == PortalRole.manager ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Visible to staff only'), findsOneWidget);
      expect(
        find.text('Edit Dress'),
        role == PortalRole.manager ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Manager saves a draft, publishes, and bride sees exact details',
    (tester) async {
      final repo = FakeCatalogue();
      addTearDown(repo.changes.close);
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: portalTheme,
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: c,
                  builder: (_) =>
                      DressEditor(repository: repo, actorUid: 'manager'),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      for (final entry in {
        'Dress name': 'Real Boutique Gown',
        'Price (RM)': '899.90',
        'Description': 'Shop supplied dress details.',
      }.entries) {
        await tester.enterText(
          find.widgetWithText(TextFormField, entry.key),
          entry.value,
        );
      }
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Champagne').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'M'));
      await tester.tap(find.widgetWithText(FilterChip, 'L'));
      await tester.tap(find.text('Save Dress'));
      await tester.pumpAndSettle();
      expect(repo.records.values.single.published, isFalse);
      expect(repo.records.values.single.priceCents, 89990);
      final draft = repo.records.values.single;
      final published = CatalogueDress.fromFields(draft.id, {
        ...draft.toFields(),
        'revision': draft.revision,
        'published': true,
        'imageUrl': 'https://example.com/dress.jpg',
      });
      await repo.save(published, actorUid: 'manager');
      await tester.pumpWidget(
        CatalogueScope(
          repository: repo,
          child: MaterialApp(
            theme: luvlyTheme,
            home: const Scaffold(body: LiveCatalogueScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Real Boutique Gown'), findsOneWidget);
      await tester.tap(find.text('Real Boutique Gown'));
      await tester.pumpAndSettle();
      expect(find.text('Colour · Champagne'), findsOneWidget);
      expect(find.text('RM 899.90'), findsOneWidget);
      expect(find.byKey(const ValueKey('size-dress-1-M')), findsOneWidget);
      expect(find.byKey(const ValueKey('size-dress-1-L')), findsOneWidget);
      expect(find.text('AR try-on'), findsNothing);
      expect(find.text('360° view'), findsNothing);
      expect(find.text('About preview'), findsNothing);
      final current = repo.records.values.single;
      await repo.save(
        CatalogueDress.fromFields(current.id, {
          ...current.toFields(),
          'published': false,
          'revision': current.revision,
        }),
        actorUid: 'manager',
      );
      await tester.pumpAndSettle();
      expect(find.text('Dress no longer listed'), findsOneWidget);
      expect(find.text('Real Boutique Gown'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Failed save retains input and blocks duplicate submits', (
    tester,
  ) async {
    final repo = FakeCatalogue()
      ..saveWait = Completer<void>()
      ..saveError = StateError('This dress changed elsewhere.');
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: DressEditor(
          repository: repo,
          actorUid: 'manager',
          dress: sampleDress(),
        ),
      ),
    );
    await tester.tap(find.text('Save Dress'));
    await tester.pump();
    expect(repo.saves, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
          .onPressed,
      isNull,
    );
    repo.saveWait!.complete();
    await tester.pumpAndSettle();
    expect(find.text('This dress changed elsewhere.'), findsOneWidget);
    expect(find.text('Test Lace Dress'), findsOneWidget);
  });

  testWidgets('Bride sees no drafts; empty and retry states are explicit', (
    tester,
  ) async {
    final repo = FakeCatalogue()..readError = true;
    addTearDown(repo.changes.close);
    repo.records['draft'] = sampleDress(published: false);
    await tester.pumpWidget(
      CatalogueScope(
        repository: repo,
        child: MaterialApp(
          theme: luvlyTheme,
          home: const Scaffold(body: LiveCatalogueScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    repo.readError = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('0 gowns · Confirm availability for your rental dates'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('The AR studio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3 previews · Explore digital gowns'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Princess Wedding Dress'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Princess Wedding Dress'), findsOneWidget);
    expect(find.text('Test Lace Dress'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Missing photo does not substitute another dress', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DressPhoto(url: '')),
      ),
    );
    expect(find.text('Photo not added'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
