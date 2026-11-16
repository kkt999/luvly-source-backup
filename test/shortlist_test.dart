import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/shortlist/shortlist_controller.dart';
import 'package:luvly_app/shortlist/shortlist_repository.dart';
import 'package:luvly_app/shortlist/shortlist_screen.dart';
import 'package:luvly_app/shortlist/shortlist_widgets.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/bride_app.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'package:luvly_app/src/home.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'fake_catalogue.dart';
import 'fake_accounts.dart';

class MemoryShortlist implements ShortlistRepository {
  final records = <String, List<String>>{};
  final events = <String, StreamController<ShortlistSnapshot>>{};
  Completer<void>? wait;
  bool failWrite = false, failRead = false;
  int writes = 0;
  @override
  Stream<ShortlistSnapshot> watch(String uid) async* {
    if (failRead) throw StateError('Synthetic read error');
    yield ShortlistSnapshot(List.of(records[uid] ?? []));
    yield* events.putIfAbsent(uid, () => StreamController.broadcast()).stream;
  }

  @override
  Future<void> setSaved(String uid, String id, bool saved) async {
    writes++;
    if (wait != null) await wait!.future;
    if (failWrite) throw StateError('Synthetic write error');
    final ids = records.putIfAbsent(uid, () => []);
    ids.remove(id);
    if (saved) ids.insert(0, id);
    events[uid]?.add(ShortlistSnapshot(List.of(ids)));
  }

  Future<void> close() async {
    for (final event in events.values) {
      await event.close();
    }
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('favourites survive a new controller and do not mix accounts', () async {
    final repo = MemoryShortlist();
    addTearDown(repo.close);
    final a = ShortlistController(repo)..bind('a');
    await tick();
    await a.setSaved('gown-stable-id', true);
    await a.setSaved('gown-stable-id', true);
    expect(a.ids, ['gown-stable-id']);
    a.dispose();
    final b = ShortlistController(repo)..bind('a');
    addTearDown(b.dispose);
    await tick();
    expect(b.ids, ['gown-stable-id']);
    b.bind('b');
    expect(b.ids, isEmpty);
    await tick();
    expect(b.ids, isEmpty);
    b.bind('a');
    await tick();
    expect(b.ids, ['gown-stable-id']);
    await b.setSaved('gown-stable-id', false);
    expect(b.ids, isEmpty);
    expect(repo.records['a'], isEmpty);
    b.bind(null);
    await expectLater(b.setSaved('gown', true), throwsStateError);
  });
  test(
    'failed writes never show saved, duplicate taps are blocked and retry works',
    () async {
      final repo = MemoryShortlist();
      addTearDown(repo.close);
      final state = ShortlistController(repo)..bind('a');
      addTearDown(state.dispose);
      await tick();
      repo.wait = Completer<void>();
      repo.failWrite = true;
      final pending = state.setSaved('gown', true);
      expect(state.pending('gown'), isTrue);
      expect(state.contains('gown'), isFalse);
      await expectLater(state.setSaved('gown', true), throwsStateError);
      expect(repo.writes, 1);
      final result = expectLater(pending, throwsStateError);
      repo.wait!.complete();
      await result;
      expect(state.pending('gown'), isFalse);
      expect(state.ids, isEmpty);
      repo.wait = null;
      repo.failWrite = false;
      await state.setSaved('gown', true);
      repo.failWrite = true;
      await expectLater(state.setSaved('gown', false), throwsStateError);
      expect(state.ids, ['gown']);
    },
  );
  test('late old-account completion cannot modify a new account', () async {
    final repo = MemoryShortlist()..wait = Completer<void>();
    addTearDown(repo.close);
    final state = ShortlistController(repo)..bind('a');
    addTearDown(state.dispose);
    await tick();
    final write = state.setSaved('a-gown', true);
    state.bind('b');
    await tick();
    repo.wait!.complete();
    await write;
    await tick();
    expect(state.uid, 'b');
    expect(state.ids, isEmpty);
    expect(state.pending('a-gown'), isFalse);
  });
  test(
    'read errors can be retried, cached lists are marked and live events sync',
    () async {
      final repo = MemoryShortlist()..failRead = true;
      addTearDown(repo.close);
      final state = ShortlistController(repo)..bind('a');
      addTearDown(state.dispose);
      await tick();
      expect(state.error, isNotNull);
      repo.failRead = false;
      state.retry();
      await tick();
      expect(state.error, isNull);
      repo.events['a']!.add(const ShortlistSnapshot(['gown'], fromCache: true));
      await tick();
      expect(state.fromCache, isTrue);
      repo.events['a']!.add(const ShortlistSnapshot(['remote-gown']));
      await tick();
      expect(state.ids, ['remote-gown']);
      expect(state.fromCache, isFalse);
    },
  );

  Future<void> mount(
    WidgetTester t,
    Widget home,
    ShortlistController state,
    FakeCatalogue catalogue, {
    bool large = false,
  }) async {
    viewport(t, Size(large ? 320 : 390, 844));
    await fonts();
    await t.pumpWidget(
      ShortlistScope(
        controller: state,
        child: CatalogueScope(
          repository: catalogue,
          child: MaterialApp(
            theme: luvlyTheme,
            debugShowCheckedModeBanner: false,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const Key('saved-artifact'),
              child: home,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final large in [false, true]) {
    testWidgets(
      'saved list shows current product, removal and unavailable gown ($large)',
      (t) async {
        final repo = MemoryShortlist()
          ..records['a'] = ['dress-1', 'removed-gown'];
        addTearDown(repo.close);
        final state = ShortlistController(repo)..bind('a');
        addTearDown(state.dispose);
        final cat = FakeCatalogue();
        addTearDown(cat.changes.close);
        cat.records['dress-1'] = CatalogueDress.fromFields('dress-1', {
          ...sampleDress(name: 'Princess Wedding Dress').toFields(),
          'revision': 1,
          'imageUrl': '',
          'photoRevision': 1,
        });
        final image = await rootBundle.load(
          'assets/images/princess_wedding.jpg',
        );
        cat.photos['dress-1'] = compressDressPhoto(image.buffer.asUint8List());
        await mount(t, const LiveShortlistScreen(), state, cat, large: large);
        expect(find.text('Princess Wedding Dress'), findsOneWidget);
        expect(find.text('2 saved gowns'), findsOneWidget);
        expect(find.text('Shortlist coming soon'), findsNothing);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('saved-artifact')),
          );
          final img = await boundary.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          Directory('work/shortlist-2127').createSync(recursive: true);
          File(
            'work/shortlist-2127/shortlist-${large ? 'large' : 'normal'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
        final remove = find.byKey(const ValueKey('save-gown-dress-1'));
        await t.ensureVisible(remove);
        await t.pumpAndSettle();
        await t.tap(remove);
        await t.pumpAndSettle();
        expect(find.text('Princess Wedding Dress'), findsNothing);
        expect(find.text('Gown no longer listed'), findsOneWidget);
        final unavailable = find.byKey(
          const ValueKey('save-gown-removed-gown'),
        );
        await t.ensureVisible(unavailable);
        await t.pumpAndSettle();
        await t.tap(unavailable);
        await t.pumpAndSettle();
        expect(find.text('Find a gown to fall for'), findsOneWidget);
        expect(state.ids, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('catalogue heart saves and detail heart stays in sync', (
    t,
  ) async {
    final repo = MemoryShortlist();
    addTearDown(repo.close);
    final state = ShortlistController(repo)..bind('a');
    addTearDown(state.dispose);
    final cat = FakeCatalogue()..records['dress-1'] = sampleDress();
    addTearDown(cat.changes.close);
    await mount(t, const Scaffold(body: LiveCatalogueScreen()), state, cat);
    final heart = find.byKey(const ValueKey('save-gown-dress-1'));
    await t.ensureVisible(heart);
    await t.pumpAndSettle();
    await t.tap(heart);
    await t.pumpAndSettle();
    expect(state.contains('dress-1'), isTrue);
    expect(t.widget<IconButton>(heart).isSelected, isTrue);
    await t.ensureVisible(find.text('Test Lace Dress'));
    await t.pumpAndSettle();
    await t.tap(find.text('Test Lace Dress'));
    await t.pumpAndSettle();
    expect(find.text('Gown details'), findsOneWidget);
    final detail = find.byKey(const ValueKey('save-gown-dress-1')).last;
    expect(t.widget<IconButton>(detail).isSelected, isTrue);
    await t.tap(detail);
    await t.pumpAndSettle();
    expect(state.ids, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('read failure shows retry rather than an empty shortlist', (
    t,
  ) async {
    final repo = MemoryShortlist()..failRead = true;
    addTearDown(repo.close);
    final state = ShortlistController(repo)..bind('a');
    addTearDown(state.dispose);
    final cat = FakeCatalogue();
    addTearDown(cat.changes.close);
    await mount(t, const LiveShortlistScreen(), state, cat);
    expect(find.text('Retry shortlist'), findsOneWidget);
    expect(find.text('Find a gown to fall for'), findsNothing);
    repo.failRead = false;
    await t.tap(find.text('Retry shortlist'));
    await t.pumpAndSettle();
    expect(find.text('Find a gown to fall for'), findsOneWidget);
    await t.tap(find.text('Explore gowns'));
    await t.pumpAndSettle();
    expect(find.text('Wedding dresses'), findsOneWidget);
  });

  testWidgets('app authentication binds and clears the real shortlist scope', (
    t,
  ) async {
    final repo = MemoryShortlist()..records['bride-a'] = ['private-gown'];
    addTearDown(repo.close);
    final gateway = FakeAccounts()
      ..saved = const BrideProfile(name: 'Jane Lim', phone: '+60123456789')
      ..user = AccountIdentity('bride-a', 'jane@example.test');
    final session = AccountSession(gateway);
    addTearDown(() async {
      session.dispose();
      await gateway.events.close();
    });
    final cat = FakeCatalogue();
    addTearDown(cat.changes.close);
    await t.pumpWidget(
      LuvlyApp(session: session, catalogue: cat, shortlistRepository: repo),
    );
    await t.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    final controller = ShortlistScope.maybeOf(
      t.element(find.byType(HomeShell)),
    )!;
    expect(controller.ids, ['private-gown']);
    gateway.emit(null);
    await t.pumpAndSettle();
    expect(controller.ids, isEmpty);
    expect(controller.uid, isNull);
    gateway.emit(AccountIdentity('bride-b', 'other@example.test'));
    await t.pumpAndSettle();
    expect(controller.uid, 'bride-b');
    expect(controller.ids, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
