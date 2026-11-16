import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/main.dart';
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/home.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/dresses.dart';
import 'package:luvly_app/src/appointments.dart';
import 'package:luvly_app/src/commerce.dart';
import 'package:luvly_app/src/support.dart';
import 'package:luvly_app/src/auth_service.dart';
import 'fake_accounts.dart';

Future<void> screen(
  WidgetTester tester,
  Widget child, {
  AppModel? model,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    AppScope(
      model: model ?? AppModel(),
      child: RepaintBoundary(
        key: const Key('preview'),
        child: MaterialApp(theme: luvlyTheme, home: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all screen layouts render at mobile widths without overflow', (
    tester,
  ) async {
    const channel = MethodChannel('luvly/ar');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => [],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final m = AppModel();
    final screens = <Widget>[
      const WelcomeScreen(),
      const AuthScreen(),
      const AuthScreen(register: true),
      const ResetPasswordScreen(),
      const HomeShell(),
      const PageFrame(title: 'Profile', child: ProfileScreen()),
      const EditProfileScreen(),
      const MeasurementsScreen(),
      const BodyScanScreen(),
      const MembershipScreen(),
      const LoyaltyScreen(),
      const PageFrame(title: 'Dresses', child: CatalogueScreen()),
      const DressDetailScreen(index: 0),
      DressDetailScreen(index: dresses.length - 1),
      TryOnGuideScreen(index: dresses.length - 1),
      const ShortlistScreen(),
      const RecommendationsScreen(),
      const TryOnGuideScreen(index: 0),
      const TryOnHistoryScreen(),
      const PageFrame(title: 'Bookings', child: AppointmentsScreen()),
      const BookAppointmentScreen(),
      BookingDetailScreen(booking: m.bookings.first),
      const TimelineScreen(),
      const PackagesScreen(),
      const PackageDetailScreen(index: 0),
      const CustomizePackageScreen(index: 0),
      const SelectedPackageScreen(),
      const PaymentsScreen(),
      const PaymentFormScreen(),
      ReceiptScreen(payment: m.payments.first),
      const PageFrame(title: 'Support', child: SupportScreen()),
      const AssistantScreen(),
      const CreateTicketScreen(),
      const TicketsScreen(),
      TicketDetailScreen(ticket: m.tickets.first),
      TicketDetailScreen(ticket: m.tickets.last),
    ];
    for (final width in [390.0, 320.0]) {
      for (final s in screens) {
        await screen(tester, s, model: m, width: width);
        expect(
          tester.takeException(),
          isNull,
          reason: '${s.runtimeType} at $width',
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
  testWidgets('authenticated bride can use all five navigation tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final backend = FakeAccounts()
      ..user = const AccountIdentity('test-bride', 'jane@example.com')
      ..saved = const BrideProfile(name: 'Jane Lim', phone: '0123456789');
    final session = AccountSession(backend);
    addTearDown(session.dispose);
    await tester.pumpWidget(LuvlyApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Jane.'), findsOneWidget);
    for (final label in ['Dresses', 'Bookings', 'Support', 'Profile', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('login rejects invalid input', (tester) async {
    await screen(tester, const AuthScreen());
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });
  testWidgets('catalogue search filters results', (tester) async {
    await screen(
      tester,
      const PageFrame(title: 'Dresses', child: CatalogueScreen()),
    );
    await tester.enterText(find.byType(TextField), 'Eden');
    await tester.pumpAndSettle();
    expect(find.text('Eden Lace'), findsOneWidget);
    expect(find.text('The Golden Gown'), findsNothing);
    await tester.enterText(find.byType(TextField), 'unmatched');
    await tester.pumpAndSettle();
    expect(find.text('No dresses found'), findsOneWidget);
  });
  testWidgets('shortlist changes app state', (tester) async {
    final m = AppModel();
    await screen(tester, const DressDetailScreen(index: 2), model: m);
    await tester.tap(find.byTooltip('Toggle shortlist'));
    await tester.pumpAndSettle();
    expect(m.shortlist.contains(2), isTrue);
    await tester.tap(find.byTooltip('Toggle shortlist'));
    await tester.pumpAndSettle();
    expect(m.shortlist.contains(2), isFalse);
  });
  testWidgets('package customization computes extras', (tester) async {
    await screen(tester, const CustomizePackageScreen(index: 0));
    await tester.ensureVisible(find.text('Makeup trial'));
    await tester.tap(find.text('Makeup trial'));
    await tester.pumpAndSettle();
    expect(find.text('RM 5150.00'), findsOneWidget);
    await tester.tap(find.text('Review selection'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm package'), findsOneWidget);
  });
  testWidgets('booking requires a slot and confirms selection', (tester) async {
    final m = AppModel();
    await screen(tester, const BookAppointmentScreen(), model: m);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an available time slot.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('10:00 AM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00 AM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm demo booking'));
    await tester.pumpAndSettle();
    expect(m.bookings.length, 2);
    expect(find.text('You’re all set!'), findsOneWidget);
  });
  testWidgets(
    'offline demo has one success action and review does not change balance',
    (tester) async {
      final m = AppModel();
      await screen(tester, const PaymentFormScreen(), model: m);
      await tester.enterText(find.byType(TextFormField).first, '300');
      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      expect(find.text('Preview failed-payment state'), findsNothing);
      expect(m.balance, 3800);
      await tester.tap(find.text('Simulate successful payment'));
      await tester.pumpAndSettle();
      expect(m.balance, 3500);
      expect(find.text('DEMO • NOT A VALID PAYMENT RECEIPT'), findsOneWidget);
    },
  );
  testWidgets('closed tickets do not allow replies', (tester) async {
    final m = AppModel();
    await screen(tester, TicketDetailScreen(ticket: m.tickets.last), model: m);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('ticket submission and reply are retained in session', (
    tester,
  ) async {
    final m = AppModel();
    await screen(tester, const CreateTicketScreen(), model: m);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Change my appointment',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Please help me choose another appointment date.',
    );
    await tester.tap(find.text('Submit demo ticket'));
    await tester.pumpAndSettle();
    expect(m.tickets.length, 3);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Thank you for your help.');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(m.tickets.first.messages.length, 2);
  });
}
