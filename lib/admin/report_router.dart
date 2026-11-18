import 'package:flutter/material.dart';

/// Browser locations for Reports. Other portal destinations keep their
/// existing in-shell navigation.
class ReportRouter extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  ReportRouter(this.buildEntry, this.entryKey);

  final Widget Function(BuildContext) buildEntry;
  final LocalKey Function() entryKey;
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Uri _location = Uri(path: '/');

  static ReportRouter? of(BuildContext context) {
    final delegate = Router.maybeOf(context)?.routerDelegate;
    return delegate is ReportRouter ? delegate : null;
  }

  @override
  Uri get currentConfiguration => _location;

  void open(BuildContext context, String path) {
    final next = Uri(path: path);
    if (_location == next) return;
    Router.navigate(context, () {
      _location = next;
      notifyListeners();
    });
  }

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    if (_location != configuration) {
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      _location = configuration;
    }
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      MaterialPage<void>(
        key: entryKey(),
        canPop: false,
        child: buildEntry(context),
      ),
    ],
    onDidRemovePage: (_) {},
  );
}

class ReportRouteParser extends RouteInformationParser<Uri> {
  const ReportRouteParser();

  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) async =>
      routeInformation.uri;

  @override
  RouteInformation restoreRouteInformation(Uri configuration) =>
      RouteInformation(uri: configuration);
}
