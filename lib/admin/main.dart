import 'package:flutter/material.dart';
import '../src/auth_service.dart';
import 'design.dart';
import 'portal_auth.dart';
import 'portal_login.dart';
import '../catalogue/catalogue_repository.dart';
import '../bookings/booking_repository.dart';
import '../bookings/booking_api.dart';
import '../support/support_repository.dart';
import 'analytics_api.dart';

class PortalApp extends StatefulWidget {
  const PortalApp({
    super.key,
    this.session,
    this.catalogue,
    this.analytics,
    this.bookings,
  });
  final PortalSession? session;
  final CatalogueRepository? catalogue;
  final AnalyticsApi? analytics;
  final BookingRepository? bookings;

  @override
  State<PortalApp> createState() => _PortalAppState();
}

class _PortalAppState extends State<PortalApp> {
  late final PortalSession session;
  late final CatalogueRepository catalogue;
  late final AnalyticsApi analytics;
  late final BookingRepository bookings;
  @override
  void initState() {
    super.initState();
    catalogue = widget.catalogue ?? FirebaseCatalogueRepository();
    analytics = widget.analytics ?? HttpAnalyticsApi();
    bookings = widget.bookings ?? FirebaseBookingRepository();
    session =
        widget.session ??
        PortalSession(FirebaseAccountGateway(), FirebaseStaffAccessGateway());
    session.start();
  }

  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    if (widget.analytics == null) analytics.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnalyticsScope(
      api: analytics,
      child: CatalogueScope(
        repository: catalogue,
        child: SupportScope(
          repository: FirebaseSupportRepository(),
          child: BookingScope(
            repository: bookings,
            availableHours: loadBookingHours,
            availableHoursForType: loadBookingHoursForType,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => MaterialApp(
                // Clear protected routes/dialogs whenever identity or access changes.
                key: ValueKey(
                  '${session.phase}:${session.identity?.uid}:${session.access?.role}:${session.access?.boutiqueOperations}',
                ),
                title: 'Luvly Portal | Staff & Manager',
                debugShowCheckedModeBanner: false,
                theme: portalTheme,
                home: PortalEntry(session: session),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
