import 'package:flutter_test/flutter_test.dart';
import 'availability_calendar_test.dart'
    show CalendarFixture, renderCalendar, tapVisible, selectDay;

void main() {
  testWidgets(
    'employee requests time off and sees assigned visit time on a mobile calendar',
    (tester) async {
      final f = CalendarFixture();
      addTearDown(f.api.close);
      await renderCalendar(tester, f, width: 390);
      await selectDay(tester, '2026-10-20');
      expect(find.text('10:00–11:00'), findsOneWidget);
      await tapVisible(tester, find.text('Request time off'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.posts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
