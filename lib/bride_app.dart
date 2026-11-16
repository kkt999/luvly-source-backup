import 'package:flutter/material.dart';
import 'src/design.dart';
import 'src/model.dart';
import 'src/account.dart';
import 'src/auth_service.dart';
import 'src/home.dart';
import 'catalogue/catalogue_repository.dart';
import 'bookings/booking_repository.dart';
import 'bookings/booking_api.dart';
import 'support/support_repository.dart';
import 'support/assistant_launcher.dart';
import 'support/support_screens.dart' show NewSupportTicket;
import 'planning/planning_api.dart';
import 'shortlist/shortlist_repository.dart';
import 'shortlist/shortlist_controller.dart';
import 'shortlist/shortlist_widgets.dart';

class LuvlyApp extends StatefulWidget {
  const LuvlyApp({
    super.key,
    this.model,
    this.session,
    this.catalogue,
    this.shortlistRepository,
  });
  final AppModel? model;
  final AccountSession? session;
  final CatalogueRepository? catalogue;
  final ShortlistRepository? shortlistRepository;
  @override
  State<LuvlyApp> createState() => _LuvlyAppState();
}

class _LuvlyAppState extends State<LuvlyApp> {
  late final AppModel model;
  late final AccountSession session;
  late final CatalogueRepository catalogue;
  late final ShortlistController shortlist;
  BrideProfile? appliedProfile;
  var navigator = GlobalKey<NavigatorState>();
  var assistantRoutes = AssistantRouteObserver();
  var planningRoutes = RouteObserver<PageRoute<dynamic>>();
  String? routeIdentity;
  @override
  void initState() {
    super.initState();
    catalogue = widget.catalogue ?? FirebaseCatalogueRepository();
    shortlist = ShortlistController(
      widget.shortlistRepository ?? FirebaseShortlistRepository(),
    );
    model = widget.model ?? AppModel.live();
    session = widget.session ?? AccountSession(FirebaseAccountGateway());
    session.addListener(_syncAccount);
    session.start();
  }

  @override
  void dispose() {
    assistantRoutes.dispose();
    shortlist.dispose();
    session.removeListener(_syncAccount);
    if (widget.session == null) session.dispose();
    if (widget.model == null) model.dispose();
    super.dispose();
  }

  void _syncAccount() {
    final nextRouteIdentity =
        '${session.phase.name}:${session.identity?.uid ?? "signed-out"}';
    if (routeIdentity != nextRouteIdentity) {
      // A global launcher must not preserve a navigator across auth boundaries.
      routeIdentity = nextRouteIdentity;
      navigator = GlobalKey<NavigatorState>();
      assistantRoutes.dispose();
      assistantRoutes = AssistantRouteObserver();
      planningRoutes = RouteObserver<PageRoute<dynamic>>();
    }
    final uid = session.phase == AccountPhase.ready
        ? session.identity?.uid
        : null;
    if (model.accountId != uid) {
      model.clearAccount();
      model.accountId = uid;
      appliedProfile = null;
    }
    final profile = session.profile;
    shortlist.bind(uid);
    if (profile != null && profile != appliedProfile) {
      model.name = profile.name;
      model.email = session.identity!.email;
      model.phone = profile.phone;
      model.contact = profile.contact;
      model.notes = profile.notes;
      model.membership = profile.membership;
      model.points = profile.points;
      appliedProfile = profile;
    }
    model.changed();
  }

  @override
  Widget build(BuildContext context) => ShortlistScope(
    controller: shortlist,
    child: CatalogueScope(
      repository: catalogue,
      child: SupportScope(
        repository: FirebaseSupportRepository(),
        child: BookingScope(
          repository: FirebaseBookingRepository(),
          availableHours: loadBookingHours,
          availableHoursForType: loadBookingHoursForType,
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              final Widget home = switch (session.phase) {
                AccountPhase.signedOut => const WelcomeScreen(),
                AccountPhase.ready => const HomeShell(),
                AccountPhase.completeProfile => const CompleteProfileScreen(),
                AccountPhase.blocked => const AccountRecoveryScreen(),
                AccountPhase.loading => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              };
              return PlanningNavigationScope(
                observer: planningRoutes,
                child: AccountScope(
                  session: session,
                  child: AppScope(
                    model: model,
                    // Discard protected routes whenever the account or authentication phase changes.
                    child: MaterialApp(
                      key: ValueKey(
                        '${session.phase.name}:${session.identity?.uid ?? "signed-out"}',
                      ),
                      title: 'Luvly • Your bridal journey',
                      debugShowCheckedModeBanner: false,
                      theme: luvlyTheme,
                      navigatorKey: navigator,
                      navigatorObservers: [assistantRoutes, planningRoutes],
                      home: home,
                      builder: (context, child) => ColoredBox(
                        color: const Color(0xFFEDE7E3),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: ClipRect(
                              child: AssistantHost(
                                navigatorKey: navigator,
                                observer: assistantRoutes,
                                enabled: session.phase == AccountPhase.ready,
                                onContact: (draft) async {
                                  final uid = session.identity?.uid;
                                  if (session.phase != AccountPhase.ready ||
                                      uid == null) {
                                    return;
                                  }
                                  await navigator.currentState?.push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => NewSupportTicket(
                                        uid: uid,
                                        name: model.name,
                                        initialSubject: 'Assistant follow-up',
                                        initialBody: draft,
                                        initialCategory: 'Other',
                                      ),
                                    ),
                                  );
                                },
                                child: child!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
