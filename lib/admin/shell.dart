import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'overview.dart';
import 'operations.dart';
import 'catalogue.dart';
import 'people.dart';
import 'support.dart';
import '../support/support_screens.dart';
import 'chapter4.dart';
import 'reports.dart';
import 'analytics_screen.dart' show ManagerReport;
import 'report_router.dart';
import '../bookings/booking_screens.dart';
import '../bookings/availability_screen.dart';
import '../promotions/promotion_admin.dart';
import '../workspace/staff_profile.dart';
import '../workspace/task_screen.dart';
import '../workspace/notifications.dart';
import '../profile/profile_photo.dart';
import '../reviews/review_screen.dart';

const pageIcons = [
  Icons.dashboard_outlined,
  Icons.calendar_month_outlined,
  Icons.checkroom_outlined,
  Icons.inventory_2_outlined,
  Icons.shopping_bag_outlined,
  Icons.timeline,
  Icons.receipt_long_outlined,
  Icons.support_agent,
  Icons.folder_open_outlined,
  Icons.badge_outlined,
  Icons.bar_chart_outlined,
  Icons.event_available_outlined,
  Icons.campaign_outlined,
  Icons.task_alt,
  Icons.rate_review_outlined,
];

class PortalRoot extends StatelessWidget {
  const PortalRoot({super.key});
  @override
  Widget build(BuildContext c) =>
      PortalScope.of(c).signedIn ? const PortalShell() : const LoginScreen();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  PortalRole role = PortalRole.staff;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: Panel(
            padding: EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (c, b) {
                final form = Padding(
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Pill('UI preview'),
                      gap(22),
                      Text(
                        'Welcome to your workspace',
                        style: Theme.of(c).textTheme.headlineMedium,
                      ),
                      gap(10),
                      const Text(
                        'One portal. The right tools for your role.',
                        style: TextStyle(color: muted),
                      ),
                      gap(28),
                      const Text(
                        'Choose a demo role',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      gap(12),
                      for (final r in PortalRole.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => setState(() => role = r),
                            borderRadius: BorderRadius.circular(10),
                            child: Panel(
                              color: role == r ? blush : Colors.white,
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    role == r
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: rose,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r == PortalRole.staff
                                              ? 'Staff'
                                              : 'Manager',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          r == PortalRole.staff
                                              ? 'My appointments, tasks and assigned tickets'
                                              : 'All operations, staff assignment and reports',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      gap(12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => PortalScope.of(c).login(role),
                          child: Text(
                            role == PortalRole.staff
                                ? 'Enter staff workspace'
                                : 'Enter manager workspace',
                          ),
                        ),
                      ),
                      gap(18),
                      const Text(
                        'Demo access only — this is not a secure login. Authentication and server-side permissions will be connected later.',
                        style: TextStyle(
                          fontSize: 11,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                );
                final brand = Container(
                  padding: const EdgeInsets.all(38),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6F5655),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.spa_outlined,
                        color: Color(0xFFE7CAC9),
                        size: 34,
                      ),
                      gap(24),
                      const Text(
                        'Luvly Portal',
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      gap(8),
                      const Text(
                        'MANAGEMENT CONSOLE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: Color(0xFFE7CAC9),
                        ),
                      ),
                      gap(80),
                      const Text(
                        'Behind every beautiful\nbridal journey.',
                        style: TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                      gap(20),
                      const Text(
                        'A thoughtful space to organise appointments, care for your brides, and keep every detail on track.',
                        style: TextStyle(color: Color(0xFFE7DAD4), height: 1.7),
                      ),
                      gap(65),
                      const Text(
                        'STAFF & MANAGER WEBSITE',
                        style: TextStyle(
                          color: Color(0xFFE7CAC9),
                          letterSpacing: 1.5,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
                return b.maxWidth >= 800
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: brand),
                            Expanded(flex: 1, child: form),
                          ],
                        ),
                      )
                    : form;
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class PortalShell extends StatefulWidget {
  const PortalShell({super.key, this.onSignOut});
  final VoidCallback? onSignOut;
  @override
  State<PortalShell> createState() => _ShellState();
}

class _ShellState extends State<PortalShell> {
  PortalPage basePage = PortalPage.dashboard;
  String localReportPath = '/';

  String get reportPath =>
      ReportRouter.of(context)?.currentConfiguration.path ?? localReportPath;

  PortalPage get page {
    final model = PortalScope.of(context);
    if (model.isLive &&
        model.canOpen(PortalPage.reports) &&
        (reportPath == '/reports' || reportPath.startsWith('/reports/'))) {
      return PortalPage.reports;
    }
    if (!model.canOpen(basePage)) return PortalPage.dashboard;
    return basePage;
  }

  ManagerReport? get selectedReport {
    for (final report in ManagerReport.values) {
      if (reportPath == '/reports/${report.id}') return report;
    }
    return null;
  }

  void openReport(ManagerReport? report) {
    final path = report == null ? '/reports' : '/reports/${report.id}';
    updateReportPath(path);
  }

  void updateReportPath(String path) {
    final router = ReportRouter.of(context);
    if (router == null) {
      setState(() => localReportPath = path);
    } else {
      router.open(context, path);
    }
  }

  void navigate(PortalPage p) {
    if (p == PortalPage.progress) p = PortalPage.rentals;
    final model = PortalScope.of(context);
    if (!model.canOpen(p)) return;
    if (p == PortalPage.reports && model.isLive) {
      openReport(null);
      return;
    }
    final leavingReports = page == PortalPage.reports && model.isLive;
    setState(() => basePage = p);
    if (leavingReports) updateReportPath('/');
  }

  Widget reportBreadcrumb(ManagerReport report) {
    const style = TextStyle(color: muted, fontSize: 12);
    const separator = Text('/', style: style, semanticsLabel: ' ');
    return Wrap(
      spacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Luvly Portal', style: style),
        separator,
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () => openReport(null),
          child: const Text('Reports', style: TextStyle(fontSize: 12)),
        ),
        separator,
        Text(report.breadcrumb, style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (!m.canOpen(basePage)) basePage = PortalPage.dashboard;
    final report = page == PortalPage.reports ? selectedReport : null;
    final narrow = MediaQuery.sizeOf(c).width < 1050;
    return Scaffold(
      drawer: narrow ? Drawer(child: _sidebar(c, true)) : null,
      body: Row(
        children: [
          if (!narrow) SizedBox(width: 224, child: _sidebar(c, false)),
          Expanded(
            child: Column(
              children: [
                Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: EdgeInsets.symmetric(
                    horizontal: narrow ? 12 : 26,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Row(
                    children: [
                      if (narrow)
                        Builder(
                          builder: (c) => IconButton(
                            tooltip: 'Open navigation',
                            onPressed: () => Scaffold.of(c).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                        ),
                      Expanded(
                        child: report != null
                            ? reportBreadcrumb(report)
                            : Text(
                                narrow
                                    ? m.pageLabel(page)
                                    : 'Luvly Portal   /   ${m.pageLabel(page)}',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      if (!narrow && MediaQuery.textScalerOf(c).scale(12) < 18)
                        Text(
                          dateText(m.today),
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      SizedBox(width: narrow ? 6 : 18),
                      if (m.isLive)
                        NotificationBell(
                          uid: m.current!.id,
                          name: m.current!.name,
                          staff: true,
                          manager: m.isManager,
                          boutiqueOperations: m.boutiqueOperations,
                        )
                      else
                        IconButton(
                          tooltip: 'Recent activity',
                          onPressed: () => showDialog<void>(
                            context: c,
                            builder: (d) => AlertDialog(
                              title: const Text('Recent activity'),
                              content: SizedBox(
                                width: 450,
                                child: ListView(
                                  shrinkWrap: true,
                                  children: m.isLive
                                      ? const [
                                          ListTile(
                                            title: Text(
                                              'Activity history is not connected yet.',
                                            ),
                                          ),
                                        ]
                                      : m.visibleActivity
                                            .take(12)
                                            .map(
                                              (a) => ListTile(
                                                leading: const Icon(
                                                  Icons.history,
                                                  color: rose,
                                                  size: 18,
                                                ),
                                                title: Text(
                                                  a,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.notifications_none, size: 21),
                        ),
                      const SizedBox(width: 8),
                      if (m.isLive)
                        ProfilePhotoAvatar(
                          uid: m.current!.id,
                          radius: 16,
                          backgroundColor: blush,
                          fallbackInitial: m.current!.name.trim().isEmpty
                              ? '?'
                              : m.current!.name.characters.first.toUpperCase(),
                        )
                      else
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: blush,
                          child: Text(
                            m.current!.name.trim().isEmpty
                                ? '?'
                                : m.current!.name.characters.first
                                      .toUpperCase(),
                            style: const TextStyle(color: rose),
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (!narrow)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 154),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tooltip(
                                message: m.current!.name,
                                child: Text(
                                  m.current!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                m.isManager ? 'Manager' : 'Staff',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Account menu',
                        onSelected: (v) {
                          if (v == 'logout') (widget.onSignOut ?? m.logout)();
                          if (v == 'profile') {
                            Navigator.of(c).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    StaffProfileScreen(uid: m.current!.id),
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            enabled: false,
                            child: Text(
                              '${m.isManager ? 'Manager' : 'Staff'} ${m.isLive ? 'account' : 'demo session'}',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Text('Sign out'),
                          ),
                          if (m.isLive)
                            const PopupMenuItem(
                              value: 'profile',
                              child: Text('My profile'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!m.isLive) const DemoBanner(),
                Expanded(
                  child: KeyedSubtree(key: ValueKey(page), child: _content()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() => switch (page) {
    PortalPage.dashboard => DashboardPage(onNavigate: navigate),
    PortalPage.appointments =>
      PortalScope.of(context).isLive
          ? LiveAppointments(
              uid: PortalScope.of(context).current!.id,
              name: PortalScope.of(context).current!.name,
              staff: true,
              manager: PortalScope.of(context).isManager,
              boutiqueOperations: PortalScope.of(context).boutiqueOperations,
            )
          : const AppointmentsPage(),
    PortalPage.inventory => const InventoryPage(),
    PortalPage.packages => const PackagesPage(),
    PortalPage.rentals => const CustomerRentalsPage(),
    PortalPage.progress => const CustomerRentalsPage(),
    PortalPage.payments => const PaymentsPage(),
    PortalPage.support =>
      PortalScope.of(context).isLive
          ? LiveSupportScreen(
              uid: PortalScope.of(context).current!.id,
              name: PortalScope.of(context).current!.name,
              staff: true,
            )
          : const SupportPage(),
    PortalPage.records => const RecordsPage(),
    PortalPage.staff => const StaffPage(),
    PortalPage.reports => ChapterReportsPage(
      selectedReport: selectedReport,
      onSelectReport: openReport,
    ),
    PortalPage.schedule =>
      PortalScope.of(context).isLive
          ? LiveAvailabilityScreen(
              manager: PortalScope.of(context).isManager,
              onAppointments: () => navigate(PortalPage.appointments),
            )
          : const SchedulePage(),
    PortalPage.promotions => PromotionManagementScreen(
      canManage: PortalScope.of(context).isManager,
      preview: !PortalScope.of(context).isLive,
    ),
    PortalPage.tasks =>
      PortalScope.of(context).isLive
          ? StaffTasksScreen(uid: PortalScope.of(context).current!.id)
          : const Center(child: Text('Sign in to view real work tasks.')),
    PortalPage.reviews => const ReviewsScreen(manage: true),
  };
  Widget _sidebar(BuildContext c, bool drawer) {
    final m = PortalScope.of(c);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 25, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LUVLY',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: rose,
                      letterSpacing: 1.2,
                    ),
                  ),
                  gap(4),
                  const Text(
                    'BRIDAL BOUTIQUE',
                    style: TextStyle(
                      fontSize: 10,
                      color: muted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('portal-navigation-list'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 0, 12),
                    child: Text(
                      'WORKSPACE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.7,
                        color: muted,
                      ),
                    ),
                  ),
                  for (final p in m.pages) ...[
                    if (p == PortalPage.support || p == PortalPage.schedule)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 20, 0, 10),
                        child: Text(
                          p == PortalPage.support
                              ? 'CUSTOMER CARE'
                              : 'SCHEDULE & TOOLS',
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.3,
                            color: muted,
                          ),
                        ),
                      ),
                    if (p == PortalPage.staff)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 24, 0, 12),
                        child: Text(
                          'MANAGEMENT',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.7,
                            color: muted,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: p == page ? rose : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        child: ListTile(
                          key: ValueKey('nav-${p.name}'),
                          dense: true,
                          minTileHeight: 44,
                          horizontalTitleGap: 12,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                          leading: Icon(
                            pageIcons[p.index],
                            color: p == page ? Colors.white : muted,
                            size: 18,
                          ),
                          title: Text(
                            m.pageLabel(p),
                            style: TextStyle(
                              fontSize: 12,
                              color: p == page ? Colors.white : ink,
                              fontWeight: p == page
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          onTap: () {
                            navigate(p);
                            if (drawer) Navigator.pop(c);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12),
                  TextButton.icon(
                    onPressed: widget.onSignOut ?? m.logout,
                    icon: const Icon(Icons.logout, size: 17),
                    label: const Text(
                      'Sign out',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
