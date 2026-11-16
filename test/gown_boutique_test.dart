import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/catalogue/gown_size_help.dart';
import 'package:luvly_app/packages/package_gowns.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart';
import 'fake_catalogue.dart';
import 'packages/package_gowns_test.dart' show GownPackages, testGown;
import 'packages/package_test.dart' show phone;

const measurements = {
  'bustMin': 80,
  'bustMax': 90,
  'waistMin': 60,
  'waistMax': 70,
  'hipMin': 90,
  'hipMax': 100,
};
CatalogueDress gown(String id) => CatalogueDress.fromFields(id, {
  ...testGown.toFields(),
  'revision': 2,
  'photoRevision': 1,
  'name': id == 'gown1' ? 'Ivory satin gown' : 'Pearl bridal gown',
});

class CollectionApi extends GownPackages {
  @override
  Future<List<CatalogueDress>> gowns() async => [gown('gown1'), gown('gown2')];
}

HttpPaymentApi sizeApi({bool failure = false, List<String>? calls}) =>
    HttpPaymentApi(
      baseUrl: 'https://example.com',
      token: () async => 'test-token',
      client: MockClient((r) async {
        calls?.add('${r.method} ${r.url.path}');
        return http.Response(
          jsonEncode(
            failure
                ? {'error': 'UNAVAILABLE'}
                : {
                    'variants': [
                      {'size': 'M', 'measurements': measurements},
                      {'size': 'S', 'measurements': null},
                      {'size': 'XL', 'measurements': measurements},
                    ],
                  },
          ),
          failure ? 503 : 200,
        );
      }),
    );

Future<void> visible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  test('units use real conversion and reject invalid body measurements', () {
    expect(bodyMeasurementCm('33.46', inches: true), closeTo(84.9884, .001));
    expect(bodyMeasurementCm('85', inches: false), 85);
    for (final invalid in ['NaN', 'Infinity', '-20', '0', '300.1', '25.555']) {
      expect(bodyMeasurementCm(invalid, inches: false), isNull);
    }
    expect(bodyMeasurementCm('120', inches: true), isNull);
  });
  testWidgets(
    'browsing and cancelling details does not choose a gown; limit and removal remain enforced',
    (t) async {
      phone(t);
      final repo = FakeCatalogue();
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: PackageGownPicker(
            api: CollectionApi(),
            eligibleIds: {'gown1', 'gown2'},
            allowance: 1,
            repository: repo,
          ),
        ),
      );
      await t.pumpAndSettle();
      Future<void> choose(String id) async {
        final view = find.descendant(
          of: find.byKey(ValueKey('gown-$id')),
          matching: find.text('View gown'),
        );
        await visible(t, view);
        await t.tap(view);
        await t.pumpAndSettle();
        await visible(t, find.byKey(ValueKey('size-$id-M')));
        await t.tap(find.byKey(ValueKey('size-$id-M')));
        await t.pumpAndSettle();
      }

      await choose('gown1');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('0 of 1 selected'), findsOneWidget);
      await choose('gown1');
      await t.tap(find.text('Select this gown'));
      await t.pumpAndSettle();
      expect(find.text('1 of 1 selected'), findsOneWidget);
      await choose('gown2');
      await t.tap(find.text('Select this gown'));
      await t.pumpAndSettle();
      expect(find.textContaining('Deselect a gown first.'), findsOneWidget);
      expect(find.text('Selected · M'), findsOneWidget);
      await visible(t, find.text('Remove'));
      await t.tap(find.text('Remove'));
      await t.pumpAndSettle();
      expect(find.text('0 of 1 selected'), findsOneWidget);
      expect(repo.saves, 0);
    },
  );
  testWidgets(
    'size guide units, local inputs, measuring instructions and eligible recommendations',
    (t) async {
      phone(t);
      final calls = <String>[];
      final api = sizeApi(calls: calls);
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: Scaffold(
            body: GownSizeHelp(
              dressId: 'gown1',
              dressName: 'Ivory gown',
              api: api,
              selectableSizes: const ['S', 'M'],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('XL'), findsNothing);
      expect(find.text('80–90'), findsOneWidget);
      await t.tap(find.text('inches'));
      await t.pumpAndSettle();
      expect(find.text('31.5–35.4'), findsOneWidget);
      await t.tap(find.text('How to measure'));
      await t.pumpAndSettle();
      expect(find.text('Bust'), findsOneWidget);
      expect(find.textContaining('natural waist'), findsOneWidget);
      await t.tap(find.widgetWithText(ChoiceChip, 'Find my size'));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.enterText(
          find.byType(TextFormField).at(i),
          ['33.46', '25.59', '37.40'][i],
        );
      }
      await visible(t, find.widgetWithText(FilledButton, 'Find my size'));
      await t.tap(find.widgetWithText(FilledButton, 'Find my size'));
      await t.pumpAndSettle();
      expect(find.text('Reference size: M'), findsOneWidget);
      expect(calls, ['GET /v1/rental-variants']);
    },
  );
  testWidgets('help instructions remain usable when size API is unavailable', (
    t,
  ) async {
    phone(t);
    final api = sizeApi(failure: true);
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GownSizeHelp(dressId: 'gown1', dressName: 'Ivory', api: api),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Size information could not be loaded.'), findsOneWidget);
    await t.tap(find.text('How to measure'));
    await t.pumpAndSettle();
    expect(find.textContaining('natural waist'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('photo enlarges without modifying selection', (t) async {
    phone(t);
    await t.pumpWidget(
      MaterialApp(
        theme: luvlyTheme,
        home: PackageGownPicker(
          api: GownPackages(),
          eligibleIds: {'gown1'},
          allowance: 1,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('gown-gown1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('zoom-gown1')));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await t.tap(find.byTooltip('Close photograph'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Select this gown'),
          )
          .onPressed,
      isNull,
    );
  });

  for (final scene in [
    'collection',
    'details',
    'chart',
    'measure',
    'narrow-large-text',
  ]) {
    testWidgets('Boutique visual $scene', (t) async {
      t.view.physicalSize = Size(scene == 'narrow-large-text' ? 320 : 390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        for (final entry in {
          'LuvlySans': 'assets/fonts/roboto-regular.ttf',
          'LuvlySerif': 'assets/fonts/CormorantGaramond.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            entry.key,
          )..addFont(rootBundle.load(entry.value))).load();
        }
      });
      final repo = FakeCatalogue();
      addTearDown(repo.changes.close);
      final data = compressDressPhoto(
        File('assets/images/elegant_bridal.jpg').readAsBytesSync(),
      );
      repo.photos.addAll({'gown1': data, 'gown2': data});
      final api = sizeApi();
      addTearDown(api.close);
      const capture = ValueKey('boutique-capture');
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  scene == 'narrow-large-text' ? 1.5 : 1,
                ),
              ),
              child: child!,
            ),
            home: scene == 'chart' || scene == 'measure'
                ? Scaffold(
                    body: SafeArea(
                      child: GownSizeHelp(
                        dressId: 'gown1',
                        dressName: 'Ivory satin gown',
                        api: api,
                        selectableSizes: const ['S', 'M'],
                      ),
                    ),
                  )
                : PackageGownPicker(
                    api: CollectionApi(),
                    eligibleIds: {'gown1', 'gown2'},
                    allowance: 1,
                    repository: repo,
                  ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await precacheImage(
          MemoryImage(data.imageBytes),
          t.element(find.byType(Scaffold).first),
        );
      });
      await t.pumpAndSettle();
      if (scene == 'details') {
        await t.tap(find.byKey(const ValueKey('gown-gown1')));
        await t.pumpAndSettle();
      }
      if (scene == 'measure') {
        await t.tap(find.text('How to measure'));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile('previews/gown-boutique-$scene.png'),
      );
    });
  }
}
