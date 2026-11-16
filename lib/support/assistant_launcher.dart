import 'package:flutter/material.dart';
import '../src/design.dart' show CustomerUi;
import 'assistant_api.dart';
import 'assistant_screen.dart';

/// Tracks the root navigator, including dialogs/sheets, without covering them.
class AssistantRouteObserver extends NavigatorObserver with ChangeNotifier {
  Route<dynamic>? current;
  bool disposed = false;
  bool get visible => current is PageRoute;
  void update(Route<dynamic>? route) {
    current = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!disposed) notifyListeners();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      update(newRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(current, route)) update(previousRoute);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class AssistantVisibility extends ChangeNotifier {
  int exclusions = 0;
  bool disposed = false;
  void change(int delta) {
    exclusions += delta;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _AssistantScope extends InheritedWidget {
  const _AssistantScope({
    required this.visibility,
    required this.onOpen,
    required super.child,
  });
  final AssistantVisibility visibility;
  final VoidCallback? onOpen;
  @override
  bool updateShouldNotify(_AssistantScope oldWidget) =>
      visibility != oldWidget.visibility || onOpen != oldWidget.onOpen;
}

/// Moves the launcher into a screen's toolbar while that route is active.
class AssistantAppBarAction extends StatelessWidget {
  const AssistantAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AssistantScope>();
    if (scope?.onOpen == null) return const SizedBox.shrink();
    return AssistantExclusion(
      enabled: ModalRoute.isCurrentOf(context) ?? true,
      child: IconButton(
        tooltip: 'Open Luvly assistant',
        icon: const Icon(Icons.smart_toy_outlined),
        color: Theme.of(context).colorScheme.primary,
        onPressed: scope!.onOpen,
      ),
    );
  }
}

/// Used by focused checkout/forms; not an authorization boundary.
class AssistantExclusion extends StatefulWidget {
  const AssistantExclusion({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;
  @override
  State<AssistantExclusion> createState() => _AssistantExclusionState();
}

class _AssistantExclusionState extends State<AssistantExclusion> {
  AssistantVisibility? visibility;
  AssistantVisibility? hostVisibility;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    hostVisibility = context
        .dependOnInheritedWidgetOfExactType<_AssistantScope>()
        ?.visibility;
    sync();
  }

  @override
  void didUpdateWidget(AssistantExclusion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) sync();
  }

  void sync() {
    final next = widget.enabled ? hostVisibility : null;
    if (identical(next, visibility)) return;
    visibility?.change(-1);
    visibility = next;
    visibility?.change(1);
  }

  @override
  void dispose() {
    visibility?.change(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> openLuvlyAssistant(
  BuildContext context, {
  AssistantApi? api,
  Future<void> Function(String draft)? onContact,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: CustomerUi.canvas,
  clipBehavior: Clip.antiAlias,
  shape: const RoundedRectangleBorder(borderRadius: CustomerUi.sheetRadius),
  sheetAnimationStyle: CustomerUi.expansionMotion(context),
  builder: (sheetContext) => FractionallySizedBox(
    heightFactor: .94,
    child: SupportAssistantScreen(
      api: api,
      onContact: onContact,
      onClose: () => Navigator.pop(sheetContext),
    ),
  ),
);

class AssistantHost extends StatefulWidget {
  const AssistantHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.observer,
    required this.enabled,
    this.onContact,
    this.api,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final AssistantRouteObserver observer;
  final bool enabled;
  final AssistantApi? api;
  final Future<void> Function(String draft)? onContact;
  @override
  State<AssistantHost> createState() => _AssistantHostState();
}

class _AssistantHostState extends State<AssistantHost> {
  final visibility = AssistantVisibility();
  bool opening = false;
  @override
  void dispose() {
    visibility.dispose();
    super.dispose();
  }

  Future<void> open() async {
    if (opening) return;
    final context = widget.navigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    setState(() => opening = true);
    try {
      await openLuvlyAssistant(
        context,
        api: widget.api,
        onContact: widget.onContact,
      );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AssistantScope(
    visibility: visibility,
    onOpen: widget.enabled ? open : null,
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.observer, visibility]),
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final shown =
            widget.enabled &&
            widget.observer.visible &&
            !opening &&
            visibility.exclusions == 0 &&
            media.viewInsets.bottom == 0;
        return Stack(
          children: [
            widget.child,
            if (shown)
              Positioned(
                right: 18,
                bottom: 112 + media.padding.bottom,
                child: Semantics(
                  label: 'Open Luvly assistant',
                  button: true,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26382E31),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: CustomerUi.activeText,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const Key('luvly-assistant-launcher'),
                        onTap: open,
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(
                            Icons.smart_toy_outlined,
                            color: Colors.white,
                            size: 27,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
