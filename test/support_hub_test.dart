import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart'
    show CatalogueScope;
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/src/home.dart' show HomeShell;
import 'package:luvly_app/src/model.dart' show AppModel, AppScope;
import 'package:luvly_app/support/support_hub.dart';
import 'package:luvly_app/support/support_repository.dart';
import 'package:luvly_app/support/support_screens.dart';
import 'support_flow_test.dart' show MemorySupport;
import 'assistant_launcher_test.dart' show host;
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'fake_catalogue.dart' show FakeCatalogue;

final conversations = [
  SupportCase('fitting', {
    'uid': 'bride',
    'name': 'Jane',
    'subject': 'A question about my fitting',
    'category': 'Appointments',
    'status': 'In Progress',
    'revision': 1,
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1, 6, 20)),
  }),
  SupportCase('gown', {
    'uid': 'bride',
    'name': 'Jane',
    'subject': 'Choosing my gown size',
    'category': 'Dresses & AR',
    'status': 'Closed',
    'revision': 1,
  }),
];
Future<void> mount(
  WidgetTester t, {
  bool large = false,
  Stream<List<SupportCase>>? feed,
  VoidCallback? retry,
  VoidCallback? assistant,
  VoidCallback? message,
  ValueChanged<SupportCase>? open,
  Future<String?> Function(SupportCase)? preview,
  bool settle = true,
}) async {
  viewport(t, Size(large ? 320 : 390, 844));
  await fonts();
  await t.pumpWidget(
    RepaintBoundary(
      key: const Key('support-artifact'),
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
          appBar: AppBar(title: const Text('Support')),
          body: CustomerSupportHub(
            feed: feed ?? Stream.value(conversations),
            onRetry: retry ?? () {},
            onAssistant: assistant ?? () {},
            onMessage: message ?? () {},
            onOpen: open ?? (_) {},
            loadPreview: preview,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 3,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.checkroom_outlined),
                label: 'Dresses',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                label: 'Bookings',
              ),
              NavigationDestination(
                icon: Icon(Icons.support_agent_outlined),
                label: 'Support',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (settle) await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('support-artifact')),
    );
    final i = await b.toImage();
    final bytes = await i.toByteData(format: ui.ImageByteFormat.png);
    Directory('work/support-2113').createSync(recursive: true);
    File(
      'work/support-2113/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    i.dispose();
  });
}

Future<void> tapVisible(WidgetTester t, Finder f) async {
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

void main() {
  testWidgets(
    'support entries and exact conversation preserve their own actions',
    (t) async {
      var assistant = 0, message = 0;
      String? opened;
      await mount(
        t,
        assistant: () => assistant++,
        message: () => message++,
        open: (r) => opened = r.id,
      );
      await t.tap(find.byKey(const Key('support-assistant-entry')));
      await t.tap(find.byKey(const Key('support-team-entry')));
      expect(assistant, 1);
      expect(message, 1);
      await tapVisible(
        t,
        find.byKey(const ValueKey('support-conversation-fitting')),
      );
      expect(opened, 'fitting');
      final updated = find.textContaining('Updated ');
      final context = t.element(updated);
      final local = DateTime.utc(2026, 11, 1, 6, 20).toLocal();
      final locale = MaterialLocalizations.of(context);
      expect(updated, findsOneWidget);
      expect(
        t.widget<Text>(updated).data,
        'Updated ${locale.formatShortDate(local)} · '
        '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
      );
    },
  );
  testWidgets(
    'topic status and search combine; clearing restores original records without writes',
    (t) async {
      await mount(t);
      await tapVisible(t, find.byKey(const Key('support-topic-filter')));
      await t.tap(find.byKey(const ValueKey('support-topic-Dresses & AR')));
      await t.pumpAndSettle();
      expect(find.text('No matching conversations'), findsOneWidget);
      await tapVisible(t, find.byKey(const ValueKey('support-status-Closed')));
      expect(find.text('Choosing my gown size'), findsOneWidget);
      expect(find.text('A question about my fitting'), findsNothing);
      await t.enterText(find.byType(TextField), 'missing gown');
      await t.pumpAndSettle();
      expect(find.text('No matching conversations'), findsOneWidget);
      await tapVisible(t, find.byTooltip('Clear search'));
      expect(find.text('Choosing my gown size'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'missing gown');
      await t.pumpAndSettle();
      await tapVisible(t, find.text('Reset filters'));
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
      expect(find.text('A question about my fitting'), findsOneWidget);
      await tapVisible(t, find.byKey(const ValueKey('support-status-All')));
      expect(find.text('Choosing my gown size'), findsOneWidget);
    },
  );
  testWidgets('empty and failed feeds have distinct states and retry action', (
    t,
  ) async {
    await mount(t, feed: Stream.value([]));
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await capture(t, 'empty');
    var retries = 0;
    await mount(
      t,
      feed: Stream.error(StateError('offline')),
      retry: () => retries++,
    );
    expect(find.text('Could not load conversations.'), findsOneWidget);
    expect(find.text('No conversations yet'), findsNothing);
    expect(find.byKey(const Key('support-assistant-entry')), findsOneWidget);
    expect(find.byKey(const Key('support-team-entry')), findsOneWidget);
    await tapVisible(t, find.text('Retry'));
    expect(retries, 1);
    await capture(t, 'error');
  });
  testWidgets('loading and closed-only history keep support available', (
    t,
  ) async {
    final feed = StreamController<List<SupportCase>>();
    addTearDown(feed.close);
    await mount(t, feed: feed.stream, settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('No conversations yet'), findsNothing);
    expect(find.byKey(const Key('support-team-entry')), findsOneWidget);
    feed.add([conversations.last]);
    await t.pumpAndSettle();
    expect(find.text('No matching conversations'), findsOneWidget);
    await tapVisible(t, find.text('Show all conversations'));
    expect(find.text('Choosing my gown size'), findsOneWidget);
  });
  testWidgets(
    'latest preview is refreshed by ID, stays out of search and is optional',
    (t) async {
      const firstMessage = 'Your fitting is confirmed.';
      const secondMessage = 'Please bring your wedding shoes to the fitting.';
      final subject = List.filled(
        5,
        'A question about the gown for my fitting',
      ).join(' ');
      final feed = StreamController<List<SupportCase>>();
      addTearDown(feed.close);
      final requested = <(String, String?)>[];
      final second = Completer<String?>();
      SupportCase ticket(String id, {String? messageId}) => SupportCase(id, {
        ...conversations.first.data,
        'subject': id == 'fitting' ? subject : 'Legacy conversation',
        'lastMessageId': messageId,
      });
      await mount(
        t,
        large: true,
        feed: feed.stream,
        settle: false,
        preview: (row) async {
          requested.add((row.id, row.lastMessageId));
          return switch (row.lastMessageId) {
            'first' => firstMessage,
            'second' => second.future,
            _ => throw StateError('private data'),
          };
        },
      );
      feed.add([ticket('fitting', messageId: 'first'), ticket('legacy')]);
      await t.pumpAndSettle();
      await tapVisible(
        t,
        find.byKey(const ValueKey('support-conversation-fitting')),
      );
      expect(t.widget<Text>(find.text(subject)).maxLines, 2);
      expect(t.widget<Text>(find.text(firstMessage)).maxLines, 2);
      await capture(t, 'preview-large');
      expect(requested, [('fitting', 'first')]);
      await t.enterText(find.byType(TextField), 'confirmed');
      await t.pumpAndSettle();
      expect(find.text(firstMessage), findsNothing);
      await tapVisible(t, find.byTooltip('Clear search'));
      await tapVisible(
        t,
        find.byKey(const ValueKey('support-conversation-fitting')),
      );
      expect(requested, [('fitting', 'first')]);
      feed.add([ticket('fitting', messageId: 'second')]);
      await t.pumpAndSettle();
      expect(find.text(firstMessage), findsNothing);
      second.complete(secondMessage);
      await t.pumpAndSettle();
      expect(find.text(secondMessage), findsOneWidget);
      feed.add([ticket('fitting', messageId: 'denied')]);
      await t.pumpAndSettle();
      expect(find.text(secondMessage), findsNothing);
      expect(find.textContaining('private data'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('team and conversation cards open their existing routes', (
    t,
  ) async {
    final repo = MemorySupport()..ticket = conversations.first;
    addTearDown(repo.changes.close);
    await host(
      t,
      home: SupportScope(
        repository: repo,
        child: const Scaffold(
          body: LiveSupportScreen(uid: 'bride', name: 'Jane'),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('support-team-entry')));
    await t.pumpAndSettle();
    expect(find.byType(NewSupportTicket), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapVisible(
      t,
      find.byKey(const ValueKey('support-conversation-fitting')),
    );
    expect(
      t.widget<SupportConversation>(find.byType(SupportConversation)).id,
      'fitting',
    );
  });
  testWidgets(
    'signed-in HomeShell selects Support and the other four destinations',
    (t) async {
      final model = AppModel()..accountId = 'bride';
      final support = MemorySupport()..ticket = conversations.first;
      final catalogue = FakeCatalogue();
      addTearDown(model.dispose);
      addTearDown(support.changes.close);
      addTearDown(catalogue.changes.close);
      await host(
        t,
        home: AppScope(
          model: model,
          child: CatalogueScope(
            repository: catalogue,
            child: SupportScope(repository: support, child: const HomeShell()),
          ),
        ),
      );
      final destinations = [
        'Home',
        'Dresses',
        'Bookings',
        'Support',
        'Profile',
      ];
      for (final index in [3, 1, 2, 4, 0, 3]) {
        await t.tap(
          find.widgetWithText(NavigationDestination, destinations[index]),
        );
        await t.pumpAndSettle();
        expect(
          t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
          index,
        );
        expect(
          find.byKey(const Key('support-team-entry')).hitTestable(),
          index == 3 ? findsOneWidget : findsNothing,
        );
      }
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'active support suppresses duplicate floating assistant and switching away restores it',
    (t) async {
      final repo = MemorySupport();
      addTearDown(repo.changes.close);
      var active = false;
      await host(
        t,
        home: SupportScope(
          repository: repo,
          child: StatefulBuilder(
            builder: (c, set) => Scaffold(
              body: LiveSupportScreen(
                uid: 'bride',
                name: 'Jane',
                active: active,
              ),
              bottomNavigationBar: TextButton(
                onPressed: () => set(() => active = !active),
                child: const Text('Switch tab'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.text('Switch tab'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
        await t.tap(find.text('Switch tab'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('luvly-assistant-launcher')),
          findsOneWidget,
        );
      }
      expect(t.takeException(), isNull);
    },
  );
  for (final large in [false, true]) {
    testWidgets('support hub responsive ${large ? 'double text' : 'phone'}', (
      t,
    ) async {
      await mount(t, large: large);
      await capture(t, large ? 'large-top' : 'phone');
      expect(t.takeException(), isNull);
      await tapVisible(t, find.byKey(const Key('support-topic-filter')));
      await capture(t, large ? 'large-topics' : 'topics');
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('support-topic-All categories')));
      await t.pumpAndSettle();
      await tapVisible(
        t,
        find.byKey(const ValueKey('support-conversation-fitting')),
      );
      await capture(t, large ? 'large-conversation' : 'conversation');
      expect(t.takeException(), isNull);
    });
  }
}
