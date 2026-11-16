import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/live_inventory.dart';
import 'package:luvly_app/catalogue/ar_models.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/src/ar_preview.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/dresses.dart';
import 'package:luvly_app/src/home.dart';
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/src/model.dart';
import 'fake_catalogue.dart';

CatalogueDress linked(String id) => CatalogueDress.fromFields('dress-1', {
  ...sampleDress().toFields(),
  'revision': 1,
  'arModelId': id,
});

void main() {
  test('Private model metadata stays editable without enabling desktop AR', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() => debugDefaultTargetPlatformOverride = previous);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(linked('elegant-local-review').validationError, isNull);
    expect(resolveCatalogueArDress('elegant-local-review'), elegantLocalReview);
    expect(resolveArDress('elegant-local-review'), isNull);
    expect(browseArDresses, isNot(contains(elegantLocalReview)));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(resolveArDress('elegant-local-review'), elegantLocalReview);
  });
  test(
    'Prepared model IDs and files match the native allowlist; no name fallback',
    () {
      final native = File(
        'android/app/src/main/kotlin/com/luvly/luvly_app/ar/ArDressCatalogue.kt',
      ).readAsStringSync();
      expect(preparedArDresses.length, 2);
      for (final d in preparedArDresses) {
        expect(File(d.arAsset!).existsSync(), isTrue);
        expect(File('assets/images/${d.asset}.jpg').existsSync(), isTrue);
        expect(native, contains('"${d.id}"'));
        expect(native, contains('"${d.arAsset}"'));
        expect(resolveArDress(d.id), same(d));
      }
      expect(resolveArDress('Princess Wedding Dress'), isNull);
      expect(resolveArDress('../unrelated.glb'), isNull);
      expect(resolveArDress(null), isNull);
      expect(linked('unknown').validationError, contains('supported AR model'));
      expect(linked('princess-wedding').validationError, isNull);
      expect(sampleDress().arModelId, isEmpty);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    Widget child,
    FakeCatalogue repo, {
    double height = 1200,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(repo.changes.close);
    final app = AppModel.live()..accountId = 'bride';
    addTearDown(app.dispose);
    await tester.pumpWidget(
      AppScope(
        model: app,
        child: CatalogueScope(
          repository: repo,
          child: MaterialApp(
            theme: luvlyTheme,
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final failing in [false, true]) {
    testWidgets(
      'Signed-in catalogue exposes AR with empty/error feed: $failing',
      (tester) async {
        final repo = FakeCatalogue()..readError = failing;
        await mount(tester, const CatalogueScreen(), repo, height: 1800);
        expect(find.text('Explore AR try-on'), findsNothing);
        expect(find.text('Princess Wedding Dress'), findsOneWidget);
        expect(find.text('Francine Gown'), findsOneWidget);
        expect(find.text('The Golden Gown'), findsNothing);
        expect(find.text('Virtual try-on'), findsNWidgets(3));
        expect(find.text('Elegant Bridal Gown'), findsOneWidget);
        expect(repo.records, isEmpty);
        expect(repo.saves, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Published rental gowns suppress all corresponding preview cards',
    (tester) async {
      final repo = FakeCatalogue();
      for (final model in catalogueArModels) {
        final id = 'rental-${model.id}';
        repo.records[id] = CatalogueDress.fromFields(id, {
          ...sampleDress().toFields(),
          'name': 'Rental ${model.name}',
          'arModelId': model.id,
          'published': true,
          'revision': 1,
        });
      }
      await mount(tester, const CatalogueScreen(), repo, height: 2200);
      expect(
        find.textContaining('previews · Explore digital gowns'),
        findsNothing,
      );
      expect(find.text('Virtual try-on'), findsNothing);
      expect(find.text('AR try-on'), findsNothing);
      expect(find.text('AR available'), findsNWidgets(3));
      expect(
        find.text('3 gowns · Confirm availability for your rental dates'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unified catalogue filters references and deduplicates published model links',
    (tester) async {
      final repo = FakeCatalogue()
        ..records['dress-1'] = linked('princess-wedding');
      await mount(tester, const CatalogueScreen(), repo, height: 1600);
      expect(
        find.text('1 gown · Confirm availability for your rental dates'),
        findsOneWidget,
      );
      expect(find.text('2 previews · Explore digital gowns'), findsOneWidget);
      expect(find.text('Princess Wedding Dress'), findsNothing);
      expect(find.text('Francine Gown'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'francine');
      await tester.pumpAndSettle();
      expect(find.text('1 preview · Explore digital gowns'), findsOneWidget);
      await tester.tap(find.text('AR try-on'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ArTryOnGuideScreen>(find.byType(ArTryOnGuideScreen))
            .dress
            .id,
        'francine-reference',
      );
      Navigator.of(tester.element(find.byType(ArTryOnGuideScreen))).pop();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byKey(const Key('open-catalogue-filters')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('filter-available-now')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-available-now')));
      await tester.tap(find.byKey(const Key('apply-gown-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Francine Gown'), findsNothing);
      expect(
        find.text('1 gown · Confirm availability for your rental dates'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Private draft link does not suppress public reference; style filter works',
    (tester) async {
      final repo = FakeCatalogue()
        ..records['draft'] = CatalogueDress.fromFields('draft', {
          ...linked('princess-wedding').toFields(),
          'revision': 1,
          'published': false,
        });
      await mount(tester, const CatalogueScreen(), repo);
      expect(find.text('Princess Wedding Dress'), findsOneWidget);
      await tester.tap(find.text('Ball Gown'));
      await tester.pumpAndSettle();
      expect(find.text('Princess Wedding Dress'), findsOneWidget);
      expect(find.text('Francine Gown'), findsNothing);
      expect(find.text('1 preview · Explore digital gowns'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home AR shortcut opens the prepared library, not the live catalogue',
    (tester) async {
      await mount(
        tester,
        HomeScreen(onTab: (_) {}),
        FakeCatalogue(),
        height: 1800,
      );
      await tester.ensureVisible(find.text('Explore AR try-on'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore AR try-on'));
      await tester.pumpAndSettle();
      expect(find.byType(ArDressLibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Linked private gown routes the exact asset only in Android debug preview',
    (tester) async {
      expect(resolveArDress(elegantLocalReview.id), elegantLocalReview);
      expect(linked(elegantLocalReview.id!).validationError, isNull);
      await mount(
        tester,
        ArTryOnGuideScreen(dress: elegantLocalReview),
        FakeCatalogue(),
      );
      MethodCall? call;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('luvly/ar'),
        (value) async {
          call = value;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('luvly/ar'),
          null,
        ),
      );
      await tester.tap(find.text('Start live try-on'));
      await tester.pump();
      expect(call?.arguments, {
        'dressId': 'elegant-local-review',
        'modelAsset': 'local_review/elegant_bridal.glb',
      });
    },
  );

  for (final dress in catalogueArModels) {
    testWidgets('Linked catalogue opens exact native model ${dress.id}', (
      tester,
    ) async {
      MethodCall? call;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('luvly/ar'),
        (value) async {
          call = value;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('luvly/ar'),
          null,
        ),
      );
      final repo = FakeCatalogue()..records['dress-1'] = linked(dress.id!);
      await mount(
        tester,
        const LiveDressDetailScreen(id: 'dress-1'),
        repo,
        height: 1600,
      );
      expect(
        find.ancestor(
          of: find.text('AR try-on'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
        findsNothing,
      );
      expect(find.widgetWithText(OutlinedButton, 'AR try-on'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Book a fitting'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('Book a fitting'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('AR try-on'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('AR try-on')).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const ValueKey('zoom-dress-1'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('AR try-on')).dy,
        lessThan(tester.getTopLeft(find.text('Select a size')).dy),
      );
      expect(find.text('Model: ${dress.name}'), findsNothing);
      await tester.ensureVisible(find.text('About preview'));
      await tester.tap(find.text('About preview'));
      await tester.pumpAndSettle();
      expect(find.text('Model: ${dress.name}'), findsOneWidget);
      await tester.tap(find.text('About preview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('360° view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('360° view'));
      await tester.pump();
      expect(call?.method, 'openGownViewer');
      expect(call?.arguments, {
        'dressId': dress.id,
        'modelAsset': dress.arAsset,
      });
      await tester.ensureVisible(find.text('AR try-on'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AR try-on'));
      await tester.pumpAndSettle();
      expect(find.text('Linked model: ${dress.name}'), findsOneWidget);
      await tester.tap(find.text('Start live try-on'));
      await tester.pump();
      expect(call?.method, 'openTryOn');
      expect(call?.arguments, {
        'dressId': dress.id,
        'modelAsset': dress.arAsset,
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Unsupported model never shows an AR action', (tester) async {
    final repo = FakeCatalogue()..records['dress-1'] = linked('unknown-model');
    await mount(
      tester,
      const LiveDressDetailScreen(id: 'dress-1'),
      repo,
      height: 1600,
    );
    expect(find.text('AR try-on'), findsNothing);
    expect(find.text('360° view'), findsNothing);
    expect(find.text('About preview'), findsNothing);
    expect(find.text('Book a fitting'), findsOneWidget);
  });

  testWidgets(
    'Android gown details open makeup even without a 3D model',
    (tester) async {
      const channel = MethodChannel('luvly/makeup');
      final messenger = tester.binding.defaultBinaryMessenger;
      MethodCall? call;
      messenger.setMockMethodCallHandler(channel, (request) async {
        call = request;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await mount(
        tester,
        const LiveDressDetailScreen(id: 'dress-1'),
        FakeCatalogue()..records['dress-1'] = sampleDress(),
        height: 1600,
      );
      final preview = find.text('Preview bridal makeup');
      expect(find.text('AR try-on'), findsNothing);
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pump();
      expect(call?.method, 'open');
      expect(call?.arguments, isNull);
      await tester.scrollUntilVisible(
        find.text('Book a fitting'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.ancestor(
          of: find.text('Book a fitting'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('Guide disables camera action on non-Android platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mount(
      tester,
      ArTryOnGuideScreen(dress: resolveArDress('princess-wedding')!),
      FakeCatalogue(),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use the Android app for AR'),
          )
          .onPressed,
      isNull,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Manager must check chosen model, can save it and clear the optional link',
    (tester) async {
      final repo = FakeCatalogue()..records['dress-1'] = sampleDress();
      await mount(
        tester,
        DressEditor(
          repository: repo,
          actorUid: 'manager',
          dress: sampleDress(),
        ),
        repo,
        height: 2300,
      );
      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'AR model (optional)',
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Princess Wedding Dress').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Dress'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(
        find.text('Check that the selected model represents this dress'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Save Dress'));
      await tester.pumpAndSettle();
      expect(repo.records['dress-1']!.arModelId, 'princess-wedding');
      final cleared = CatalogueDress.fromFields('dress-1', {
        ...repo.records['dress-1']!.toFields(),
        'revision': 2,
        'arModelId': '',
      });
      await repo.save(cleared, actorUid: 'manager');
      expect(repo.records['dress-1']!.arModelId, isEmpty);
    },
  );
}
