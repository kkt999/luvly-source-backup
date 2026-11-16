import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'account.dart';
import 'dresses.dart';
import 'commerce.dart';
import 'appointments.dart';
import 'support.dart';
import 'ar_preview.dart';
import 'home_boutique.dart';
import '../promotions/promotion_screen.dart';
import '../promotions/promotion_api.dart';
import '../planning/planning_api.dart';
import '../planning/planning_screen.dart';
import '../workspace/notifications.dart';
import '../reviews/review_screen.dart';
import '../support/assistant_launcher.dart' show AssistantAppBarAction;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(
        [
          'Luvly',
          'Wedding dresses',
          'My appointments',
          'Support',
          'My profile',
        ][index],
        style: index == 0
            ? const TextStyle(
                fontFamily: 'LuvlySerif',
                fontStyle: FontStyle.italic,
                fontSize: 26,
                color: rose,
              )
            : null,
      ),
      actions: [
        if (index == 2 && AppScope.of(c).accountId != null)
          const AssistantAppBarAction(),
        if (index == 0 && AppScope.of(c).accountId != null)
          NotificationBell(
            uid: AppScope.of(c).accountId!,
            name: AppScope.of(c).name,
          )
        else if (index == 0)
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => go(c, const NotificationsScreen()),
            icon: const Icon(Icons.notifications_none),
          ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: IndexedStack(
        index: index,
        children: [
          HomeScreen(
            active: index == 0,
            onTab: (i) => setState(() => index = i),
          ),
          const CatalogueScreen(),
          const AppointmentsScreen(assistantInAppBar: true),
          SupportScreen(active: index == 3),
          const ProfileScreen(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (v) => setState(() => index = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
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
          icon: Icon(Icons.support_agent),
          label: 'Support',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onTab,
    this.promotionApi,
    this.planningApi,
    this.active = true,
  });
  final ValueChanged<int> onTab;
  final PromotionApi? promotionApi;
  final PlanningApi? planningApi;
  final bool active;
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    final name = m.name.trim().split(RegExp(r'\s+')).first;
    return ListView(
      key: const PageStorageKey('customer-home'),
      padding: const EdgeInsets.fromLTRB(
        CustomerUi.pageInset,
        12,
        CustomerUi.pageInset,
        CustomerUi.sectionSpacing,
      ),
      children: [
        Text(
          name.isEmpty ? 'Welcome to Luvly' : 'Hello, $name.',
          style: Theme.of(c).textTheme.headlineLarge,
        ),
        gap(20),
        if (m.accountId != null) ...[
          CustomerPlanningView(
            key: ValueKey('planning-${m.accountId}'),
            uid: m.accountId!,
            api: planningApi,
            compact: true,
            active: active,
            onAppointments: () => onTab(2),
            onSupport: () => onTab(3),
          ),
        ],
        HomeBoutiqueSections(
          onCollection: () => onTab(1),
          onPackages: () => go(c, const PackagesScreen()),
          onBookings: () => onTab(2),
          onPayments: () => go(c, const PaymentsScreen()),
          onShortlist: () => go(c, const ShortlistScreen()),
          onTryOn: () => go(c, const ArDressLibraryScreen()),
          onSupport: () => onTab(3),
          onReviews: () => go(c, ReviewsScreen(preview: m.accountId == null)),
          offers: m.accountId == null
              ? null
              : HomeOfferBanner(
                  key: ValueKey('offers-${m.accountId}'),
                  api: promotionApi,
                  active: active,
                ),
        ),
      ],
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext c) => AppScope.of(c).accountId != null
      ? InboxScreen(uid: AppScope.of(c).accountId!, name: AppScope.of(c).name)
      : PageFrame(
          title: 'Notifications',
          child: PageList(
            children: [
              MenuTile(
                Icons.calendar_today_outlined,
                'Your fitting is coming up',
                'Check your appointment details before you visit.',
                () => go(
                  c,
                  BookingDetailScreen(booking: AppScope.of(c).bookings.first),
                ),
              ),
              MenuTile(
                Icons.auto_awesome,
                'Offers for your day',
                'Explore package promotions and boutique news.',
                () => go(c, const OffersScreen(preview: true)),
              ),
              const DemoNote(
                text:
                    'Sample notifications. Push notifications will be connected in the backend stage.',
              ),
            ],
          ),
        );
}
