import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/support/assistant_launcher.dart';
import 'package:luvly_app/support/assistant_screen.dart';
import 'package:luvly_app/support/assistant_api.dart';
import 'package:luvly_app/support/support_repository.dart';
import 'package:luvly_app/support/support_screens.dart';
import 'support_assistant_test.dart' show FakeAssistant;
import 'support_assistant_test.dart' show showAssistant, chatOption;
import 'support_flow_test.dart' show MemorySupport;
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_test.dart' show FakePackages;

Future<void> host(
  WidgetTester t, {
  bool enabled = true,
  Widget? home,
  double scale = 1,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  final observer = AssistantRouteObserver();
  addTearDown(observer.dispose);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: luvlyTheme,
      navigatorKey: navigator,
      navigatorObservers: [observer],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: AssistantHost(
          navigatorKey: navigator,
          observer: observer,
          enabled: enabled,
          api: FakeAssistant(),
          child: child!,
        ),
      ),
      home:
          home ??
          Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Wedding dresses')),
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Gown details')),
                        ),
                      ),
                    ),
                    child: const Text('View gown'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const AssistantExclusion(
                              child: Text('Payment'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open payment'),
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('A dialog'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Open dialog'),
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.checkroom_outlined),
                    label: 'Dresses',
                  ),
                ],
              ),
            ),
          ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'AI mode fits a narrow phone with large text; quota fallback is not labelled as AI',
    (t) async {
      viewport(t, const Size(320, 720));
      final api = FakeAssistant()
        ..result = const AssistantReply(
          answer: 'Daily AI allowance reached. You can still browse the guide.',
          mode: 'Guide',
          handoff: false,
          sources: [],
          notice: 'Quota',
        );
      await showAssistant(t, api, scale: 1.5);
      await t.enterText(find.byType(TextField), 'Tell me about fittings');
      await t.tap(find.byTooltip('Send question'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Enable AI'));
      await t.pumpAndSettle();
      expect(find.text('AI chat · powered by Gemini'), findsOneWidget);
      expect(find.textContaining('Daily AI limit reached'), findsOneWidget);
      expect(find.text('Gemini · AI answer'), findsNothing);
      expect(find.text('Help guide answer'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'one robot on home and pushed pages; opens a dismissible sheet without replacing the page',
    (t) async {
      viewport(t, const Size(390, 844));
      await host(t);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      await t.tap(find.text('View gown'));
      await t.pumpAndSettle();
      expect(find.text('Gown details'), findsOneWidget);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      await t.tap(find.byKey(const Key('luvly-assistant-launcher')));
      await t.pumpAndSettle();
      expect(find.byType(SupportAssistantScreen), findsOneWidget);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      await t.tap(find.byTooltip('Close assistant'));
      await t.pumpAndSettle();
      expect(find.text('Gown details'), findsOneWidget);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('package toolbar assistant stays clear of browsing controls', (
    t,
  ) async {
    viewport(t, const Size(320, 720));
    t.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(t.view.resetPadding);
    await host(t, scale: 1.5, home: LivePackageScreen(api: FakePackages()));
    final action = find.byTooltip('Open Luvly assistant');
    final floating = find.byKey(const Key('luvly-assistant-launcher'));
    expect(floating, findsNothing);
    final rect = t.getRect(action);
    expect(rect.top, greaterThanOrEqualTo(24));
    final search = find.byType(TextField);
    final list = find.byType(Scrollable).first;
    await t.scrollUntilVisible(search, 160, scrollable: list);
    expect(t.getRect(search).overlaps(rect), isFalse);
    await t.tap(action);
    await t.pumpAndSettle();
    expect(find.byType(SupportAssistantScreen), findsOneWidget);
    await t.tap(find.byTooltip('Close assistant'));
    await t.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    final myPackages = find.widgetWithText(ChoiceChip, 'My packages');
    await t.scrollUntilVisible(myPackages, -140, scrollable: list);
    await Scrollable.ensureVisible(t.element(myPackages), alignment: .4);
    await t.pumpAndSettle();
    await t.tap(myPackages);
    await t.pumpAndSettle();
    expect(find.text('No packages selected yet'), findsOneWidget);
    expect(floating, findsNothing);
    await t.tap(find.widgetWithText(ChoiceChip, 'Packages'));
    await t.pumpAndSettle();
    final explore = find.text('Explore package');
    await t.scrollUntilVisible(
      explore,
      170,
      scrollable: find.byType(Scrollable).first,
    );
    expect(t.getRect(explore).overlaps(t.getRect(action)), isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'robot hides over payment, dialogs and keyboard; returns on pop; signed out has no robot',
    (t) async {
      viewport(t, const Size(390, 844));
      await host(t);
      await t.tap(find.text('Open payment'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsOneWidget);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await host(t, enabled: false);
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'mode explanation is factual, AI remains opt-in and source labeling reflects real reply mode',
    (t) async {
      await host(t);
      await t.tap(find.byKey(const Key('luvly-assistant-launcher')));
      await t.pumpAndSettle();
      expect(find.text('Here to help'), findsOneWidget);
      await chatOption(t, 'How AI differs from the guide');
      expect(find.text('AI chat · conversational answers'), findsOneWidget);
      expect(find.text('Help guide · finds matching keywords'), findsOneWidget);
      expect(
        find.textContaining('same approved Luvly policies'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets('support hub and floating assistant sheet at scale $scale', (
      t,
    ) async {
      viewport(t, const Size(390, 844));
      await fonts();
      final repo = MemorySupport()
        ..ticket = SupportCase('demo', {
          'uid': 'bride',
          'name': 'Demo Bride',
          'subject': 'A question about my fitting',
          'category': 'Appointments',
          'status': 'In Progress',
          'revision': 1,
        });
      addTearDown(repo.changes.close);
      await host(
        t,
        scale: scale,
        home: SupportScope(
          repository: repo,
          child: Scaffold(
            appBar: AppBar(title: const Text('Support')),
            body: LiveSupportScreen(
              uid: 'bride',
              name: 'Demo Bride',
              assistantApi: FakeAssistant(),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.support_agent_outlined),
                  label: 'Support',
                ),
              ],
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/support-hub-$scale.png'),
      );
      expect(find.byKey(const Key('luvly-assistant-launcher')), findsNothing);
      await t.tap(find.byKey(const Key('support-assistant-entry')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/support-sheet-$scale.png'),
      );
    });
  }
}
