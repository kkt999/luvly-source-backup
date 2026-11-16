import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/planning/home_plan_card.dart';
import 'package:luvly_app/planning/planning_api.dart';
import 'package:luvly_app/src/design.dart';
import 'planning_fixture.dart';

void main() {
  for (final scenario in ['matching', 'paid', 'different invoice']) {
    testWidgets('Homepage payment amount is authoritative: $scenario', (
      tester,
    ) async {
      final body = planningFixture();
      final data = body['plans'][0] as Map<String, dynamic>;
      if (scenario == 'paid') data['balance']['state'] = 'Paid';
      if (scenario == 'different invoice') {
        data['nextAction']['targetId'] = 'unrelated-invoice';
      }
      final snapshot = PlanningSnapshot(body, uid: 'bride');
      final plan = snapshot.plans.single;
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomePlanCard(
                plan: plan,
                next: plan.next,
                visit: snapshot.nextVisit,
                planCount: 1,
                onNext: () => opened = plan.next.targetId,
                onJourney: () {},
                onVisit: () {},
                onSwitch: () {},
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('RM 449.50'),
        scenario == 'matching' ? findsOneWidget : findsNothing,
      );
      expect(find.text('Event · 21 Oct 2026'), findsOneWidget);
      await tester.tap(find.text('Settle your package balance'));
      expect(opened, plan.next.targetId);
      expect(tester.takeException(), isNull);
    });
  }
}
