import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/recommendations/recommendation_api.dart';
import 'package:luvly_app/recommendations/recommendation_engine.dart';
import 'package:luvly_app/recommendations/recommendation_screen.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/model.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'fake_catalogue.dart';
import 'recommendation_engine_test.dart' show gown;

class PreferenceApi extends RecommendationApi {
  PreferenceRecord row = const PreferenceRecord(0, BridalPreferences());
  final saved = <BridalPreferences>[], ids = <String>[];
  bool failLoad = false, failSave = false;
  Completer<PreferenceRecord>? pendingLoad;
  @override
  Future<PreferenceRecord> load() async {
    if (pendingLoad != null) return pendingLoad!.future;
    if (failLoad) throw const PaymentFailure('Connection unavailable');
    return row;
  }

  @override
  Future<PreferenceRecord> save(
    PreferenceRecord old,
    BridalPreferences next,
    String requestId,
  ) async {
    saved.add(next);
    ids.add(requestId);
    if (failSave) throw const PaymentFailure('Please retry');
    return row = PreferenceRecord(old.revision + 1, next);
  }
}

Future<void> mount(
  WidgetTester t,
  PreferenceApi api, {
  bool editor = false,
  bool measurementsOnly = false,
  bool large = false,
  BridalPreferences? initial,
  ValueChanged<String>? open,
}) async {
  viewport(t, Size(large ? 320 : 390, 844));
  await fonts();
  if (initial != null) api.row = PreferenceRecord(1, initial);
  final repo = FakeCatalogue();
  addTearDown(repo.changes.close);
  final bytes = await rootBundle.load('assets/images/francine_reference.jpg');
  repo.records['first'] = CatalogueDress.fromFields('first', {
    ...gown('first', 'Sheath', colour: 'Ivory', price: 49900).toFields(),
    'name': 'Francine Gown',
    'revision': 1,
    'photoRevision': 1,
  });
  repo.photos['first'] = compressDressPhoto(bytes.buffer.asUint8List());
  repo.records['second'] = gown('second', 'A-Line', price: 54900);
  final model = AppModel.live()..accountId = 'bride';
  addTearDown(model.dispose);
  await t.pumpWidget(
    AppScope(
      model: model,
      child: CatalogueScope(
        repository: repo,
        child: RepaintBoundary(
          key: const Key('recommendation-artifact'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => FilledButton(
                  onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute<void>(
                      builder: (_) => editor
                          ? BridalPreferencesEditor(
                              api: api,
                              measurementsOnly: measurementsOnly,
                            )
                          : PersonalizedGownsScreen(
                              api: api,
                              onOpenDress: open,
                            ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
  await t.runAsync(() async {
    for (final photo in repo.photos.values) {
      await precacheImage(
        MemoryImage(photo.imageBytes),
        t.element(find.byType(MaterialApp)),
      );
    }
  });
  await t.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    250,
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

Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('recommendation-artifact')),
    );
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('work/recommendations-2111').createSync(recursive: true);
    File(
      'work/recommendations-2111/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  testWidgets(
    'sharing is separate from personal guidance and can be withdrawn without clearing measurements',
    (t) async {
      final api = PreferenceApi();
      await mount(
        t,
        api,
        editor: true,
        initial: const BridalPreferences(
          measurements: {'Bust': 90, 'Waist': 65, 'Hips': 92},
          useProportions: true,
        ),
      );
      final share = find.widgetWithText(
        SwitchListTile,
        'Include my guide in boutique statistics',
      );
      await t.scrollUntilVisible(
        share,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await t.pumpAndSettle();
      expect((t.widget<SwitchListTile>(share)).value, isFalse);
      await tapVisible(t, share);
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      expect(api.saved.last.shareProportionStats, isTrue);
      await mount(t, api, editor: true);
      await tapVisible(t, share);
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      expect(api.saved.last.shareProportionStats, isFalse);
      expect(api.saved.last.useProportions, isTrue);
      expect(api.saved.last.measurements['Bust'], 90);
    },
  );
  testWidgets('late profile response cannot leak across account switches', (
    t,
  ) async {
    final api = PreferenceApi()..pendingLoad = Completer<PreferenceRecord>();
    final old = api.pendingLoad!;
    viewport(t, const Size(390, 844));
    final model = AppModel.live()..accountId = 'bride';
    addTearDown(model.dispose);
    final repo = FakeCatalogue();
    addTearDown(repo.changes.close);
    await t.pumpWidget(
      AppScope(
        model: model,
        child: CatalogueScope(
          repository: repo,
          child: MaterialApp(
            theme: luvlyTheme,
            home: PersonalizedGownsScreen(api: api),
          ),
        ),
      ),
    );
    await t.pump();
    api.pendingLoad = null;
    model.accountId = 'other';
    model.changed();
    await t.pumpAndSettle();
    old.complete(
      const PreferenceRecord(1, BridalPreferences(styles: ['Mermaid'])),
    );
    await t.pumpAndSettle();
    expect(find.text('Styles · Mermaid'), findsNothing);
    expect(find.text('Let’s find what feels like you'), findsOneWidget);
  });
  testWidgets(
    'live catalogue changes remove unpublished or unavailable suggestions',
    (t) async {
      final api = PreferenceApi()
        ..row = const PreferenceRecord(
          1,
          BridalPreferences(styles: ['A-Line']),
        );
      viewport(t, const Size(390, 844));
      final model = AppModel.live()..accountId = 'bride';
      addTearDown(model.dispose);
      final repo = FakeCatalogue();
      addTearDown(repo.changes.close);
      repo.records['first'] = gown('first', 'A-Line');
      await t.pumpWidget(
        AppScope(
          model: model,
          child: CatalogueScope(
            repository: repo,
            child: MaterialApp(
              theme: luvlyTheme,
              home: PersonalizedGownsScreen(api: api),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('1 gown to explore'), findsOneWidget);
      repo.records['first'] = gown(
        'first',
        'A-Line',
        availability: 'Unavailable',
      );
      repo.changes.add(null);
      await t.pumpAndSettle();
      expect(find.text('0 gowns to explore'), findsOneWidget);
      expect(find.byKey(const ValueKey('recommendation-first')), findsNothing);
    },
  );
  testWidgets(
    'no profile shows available catalogue without invented scores; preferences open then cancel without saving',
    (t) async {
      final api = PreferenceApi();
      await mount(t, api);
      expect(find.text('Let’s find what feels like you'), findsOneWidget);
      expect(find.textContaining('Style match '), findsNothing);
      await t.tap(find.byKey(const Key('edit-bridal-preferences')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('prefer-style-Mermaid')));
      await t.pageBack();
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      expect(find.text('Let’s find what feels like you'), findsOneWidget);
    },
  );
  testWidgets(
    'real saved preferences order gowns, explain score, and open exact product',
    (t) async {
      final api = PreferenceApi();
      String? opened;
      await mount(
        t,
        api,
        initial: const BridalPreferences(
          styles: ['Sheath'],
          colours: ['Ivory'],
          maxPriceCents: 50000,
        ),
        open: (id) => opened = id,
      );
      await tapVisible(t, find.text('Explore gown').first);
      await capture(t, 'gown-card');
      expect(opened, 'first');
      expect(find.byKey(const ValueKey('recommendation-second')), findsNothing);
      await tapVisible(t, find.text('Why this gown?').first);
      expect(find.textContaining('Your style · 100/100'), findsOneWidget);
      expect(find.textContaining('Your colour · 100/100'), findsOneWidget);
    },
  );
  testWidgets(
    'save works without measurements and body information shares persisted values',
    (t) async {
      final api = PreferenceApi();
      await mount(t, api, editor: true);
      await t.tap(find.byKey(const ValueKey('prefer-style-Sheath')));
      await t.tap(find.byKey(const ValueKey('prefer-colour-Ivory')));
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      expect(api.saved.single.styles, ['Sheath']);
      expect(api.saved.single.measurements, isEmpty);
      expect(api.saved.single.useProportions, isFalse);
      await mount(t, api, editor: true, measurementsOnly: true);
      await tapVisible(t, find.byKey(const ValueKey('body-Bust')));
      await t.enterText(find.byKey(const ValueKey('body-Bust')), '90.5');
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      expect(api.saved.last.measurements['Bust'], 90.5);
      expect(api.saved.last.styles, ['Sheath']);
    },
  );
  testWidgets(
    'failed saves retain form and request ID; incomplete body guide cannot save',
    (t) async {
      final api = PreferenceApi()..failSave = true;
      await mount(t, api, editor: true);
      await t.tap(find.byKey(const ValueKey('prefer-style-A-Line')));
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      expect(api.ids[0], api.ids[1]);
      expect(api.saved.last.styles, ['A-Line']);
      await tapVisible(t, find.byType(SwitchListTile));
      await t.tap(find.byKey(const Key('save-bridal-preferences')));
      await t.pumpAndSettle();
      expect(api.saved.length, 2);
      expect(find.textContaining('Add bust, waist and hips'), findsOneWidget);
    },
  );
  testWidgets(
    'load failure does not replace private profile with sample measurements or allow save',
    (t) async {
      final api = PreferenceApi()..failLoad = true;
      await mount(t, api, editor: true);
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.byKey(const Key('save-bridal-preferences')), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      api.failLoad = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('save-bridal-preferences')), findsOneWidget);
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'recommendation phone and editor fit ${large ? 'large text' : 'normal'}',
      (t) async {
        final api = PreferenceApi();
        await mount(
          t,
          api,
          large: large,
          initial: const BridalPreferences(
            styles: ['Sheath'],
            colours: ['Ivory'],
            maxPriceCents: 60000,
          ),
        );
        await capture(t, large ? 'results-large' : 'results');
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('edit-bridal-preferences')));
        await t.pumpAndSettle();
        await capture(t, large ? 'editor-large' : 'editor');
        expect(t.takeException(), isNull);
        expect(
          t.getBottomRight(find.byKey(const Key('save-bridal-preferences'))).dy,
          lessThanOrEqualTo(844),
        );
        await tapVisible(t, find.byType(SwitchListTile));
        await tapVisible(t, find.byKey(const ValueKey('body-Hips')));
        await t.enterText(find.byKey(const ValueKey('body-Hips')), 'Infinity');
        await t.tap(find.byKey(const Key('save-bridal-preferences')));
        await t.pumpAndSettle();
        expect(find.text('Enter 30–300 cm.'), findsOneWidget);
        expect(api.saved, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
