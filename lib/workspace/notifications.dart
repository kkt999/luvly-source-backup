import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../payments/payment_api.dart' show PaymentFailure, paymentDateLabel;
import '../src/design.dart' show CustomerUi, blush, ink, ivory, line, rose;
import '../support/assistant_launcher.dart'
    show AssistantAppBarAction, AssistantExclusion;
import '../support/support_screens.dart';
import 'task_screen.dart';
import 'workspace_api.dart';
import '../packages/package_screen.dart';
import '../payments/payment_screen.dart';
import '../bookings/booking_screens.dart';

String notificationAction(String type) => switch (type) {
  'Support' => 'View conversation',
  'Task' => 'View task',
  'Package' => 'View package',
  'Payment' => 'View payment',
  'Appointment' => 'View appointment',
  _ => 'View details',
};

String _customerNotificationTitle(Map<String, dynamic> row) => switch ((
  row['sourceType'],
  row['kind'],
)) {
  ('Appointment', 'AppointmentConfirmed') => 'Your appointment is confirmed',
  ('Package', 'RentalReserved') => 'Your rental is reserved',
  ('Package', 'RefundRecorded') => 'A security refund was recorded',
  _ => row['title'] as String,
};

// Older inbox entries can contain customer-facing wording for shared events.
// Use the event kind to present those same records in the staff workspace.
String _staffNotificationTitle(Map<String, dynamic> row) =>
    switch (row['kind']) {
      'PaymentVerified' => 'Customer payment verified',
      'PaymentReview' => 'Customer payment needs review',
      'RentalReserved' => 'Customer rental booking confirmed',
      'RentalExpired' => 'Customer rental hold expired',
      'RentalCancelled' => 'Customer rental booking cancelled',
      'AppointmentRequested' => 'New customer appointment request',
      'AppointmentConfirmed' => 'Customer appointment confirmed',
      'AppointmentChanged' => 'Customer appointment updated',
      'AppointmentCancelled' => 'Customer appointment cancelled',
      'AppointmentExpired' => 'Unpaid customer appointment expired',
      'SupportReply' => 'Customer replied to a support ticket',
      'SupportClosed' => 'Customer closed a support ticket',
      _ => row['title'] as String,
    };

String _staffNotificationAction(Map<String, dynamic> row) =>
    switch (row['sourceType']) {
      'Payment' =>
        row['kind'] == 'PaymentReview'
            ? 'Review payment'
            : 'View payment record',
      'Package' => 'View rental record',
      'Appointment' => 'View appointment record',
      'Support' => 'Open support ticket',
      _ => notificationAction(row['sourceType']),
    };

IconData notificationIcon(String type) => switch (type) {
  'Support' => Icons.chat_bubble_outline,
  'Task' => Icons.task_alt,
  'Package' => Icons.checkroom_outlined,
  'Payment' => Icons.receipt_long_outlined,
  'Appointment' => Icons.event_outlined,
  _ => Icons.notifications_outlined,
};

class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.uid,
    required this.name,
    this.staff = false,
    this.manager = false,
    this.boutiqueOperations = true,
    this.api,
  });
  final String uid, name;
  final bool staff, manager, boutiqueOperations;
  final WorkspaceApi? api;
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  late final api = widget.api ?? WorkspaceApi();
  Timer? timer;
  int unread = 0, epoch = 0;
  bool active = true, loading = false, unavailable = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.api == null && Firebase.apps.isEmpty) {
      unavailable = true;
      return;
    }
    load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (active) load();
    });
  }

  @override
  void didUpdateWidget(NotificationBell old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) {
      epoch++;
      unread = 0;
      loading = false;
      unavailable = false;
      load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) load();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    final request = ++epoch;
    try {
      final data = await api.request('/v1/notifications');
      if (data['uid'] != widget.uid ||
          data['unread'] is! int ||
          data['unread'] < 0) {
        throw StateError('Invalid inbox');
      }
      if (mounted && request == epoch) {
        setState(() {
          unread = data['unread'];
          unavailable = false;
        });
      }
    } catch (_) {
      if (mounted && request == epoch) {
        setState(() {
          unavailable = true;
          unread = 0;
        });
      }
    } finally {
      if (request == epoch) loading = false;
    }
  }

  @override
  void dispose() {
    epoch++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: unavailable
        ? 'Notifications unavailable — open to retry'
        : 'Notifications${unread > 0 ? ' ($unread unread)' : ''}',
    onPressed: () async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InboxScreen(
            uid: widget.uid,
            name: widget.name,
            staff: widget.staff,
            manager: widget.manager,
            boutiqueOperations: widget.boutiqueOperations,
            api: api,
          ),
        ),
      );
      if (mounted) load();
    },
    icon: Badge(
      isLabelVisible: unread > 0 || unavailable,
      label: Text(
        unavailable
            ? '!'
            : unread > 99
            ? '99+'
            : '$unread',
      ),
      child: const Icon(Icons.notifications_none),
    ),
  );
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.uid,
    required this.name,
    this.staff = false,
    this.manager = false,
    this.boutiqueOperations = true,
    this.api,
  });
  final String uid, name;
  final bool staff, manager, boutiqueOperations;
  final WorkspaceApi? api;
  @override
  State<InboxScreen> createState() => _InboxState();
}

typedef _InboxPage = ({
  List<Map<String, dynamic>> rows,
  int unread,
  String? cursor,
});

class _InboxState extends State<InboxScreen> with WidgetsBindingObserver {
  late final api = widget.api ?? WorkspaceApi();
  static final _notificationId = RegExp(r'^[a-f0-9]{32}$');
  static final _sourceId = RegExp(r'^[A-Za-z0-9_-]{1,150}$');
  List<Map<String, dynamic>> records = [];
  String? next, error, busyId;
  bool loading = false, active = true;
  int unread = 0, generation = 0;
  _InboxFilter filter = _InboxFilter.all;
  final selectedIds = <String>{};
  bool selecting = false, bulkUpdating = false, loadedOlder = false;
  String? bulkError;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (active && busyId == null && records.length <= 50) load();
    });
  }

  @override
  void didUpdateWidget(InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid == widget.uid) return;
    generation++;
    records = [];
    next = error = busyId = null;
    unread = 0;
    loading = false;
    bulkUpdating = loadedOlder = false;
    _clearSelection();
    filter = _InboxFilter.all;
    load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    active = s == AppLifecycleState.resumed;
    if (active && records.length <= 50) load();
  }

  Future<_InboxPage> _fetchPage(String uid, {String? cursor}) async {
    final query = cursor == null
        ? ''
        : '?cursor=${Uri.encodeComponent(cursor)}';
    final value = await api.request('/v1/notifications$query');
    final count = value['unread'];
    final nextCursor = value['nextCursor'];
    if (value['uid'] != uid ||
        value['records'] is! List ||
        count is! int ||
        count < 0 ||
        (nextCursor != null && nextCursor is! String)) {
      throw StateError('Invalid inbox');
    }
    final rows = (value['records'] as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    for (final r in rows) {
      if (r['id'] is! String ||
          !_notificationId.hasMatch(r['id']) ||
          r['title'] is! String ||
          r['createdAt'] is! int ||
          (r['readAt'] != null && r['readAt'] is! int) ||
          (widget.staff && !_hasSource(r, staff: true))) {
        throw StateError('Invalid notification');
      }
    }
    return (rows: rows, unread: count, cursor: nextCursor as String?);
  }

  Future<void> load({bool more = false}) async {
    if (loading || busyId != null || bulkUpdating || (more && next == null)) {
      return;
    }
    final request = generation;
    setState(() => loading = true);
    try {
      final page = await _fetchPage(widget.uid, cursor: more ? next : null);
      if (!mounted || request != generation) return;
      setState(() {
        records = more
            ? {
                for (final r in [...records, ...page.rows]) r['id']: r,
              }.values.toList()
            : page.rows;
        loadedOlder = more;
        next = page.cursor;
        unread = page.unread;
        error = null;
        _reconcileSelection();
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          error = workspaceError(e);
          if (!more || widget.staff) {
            records = [];
            next = null;
            unread = 0;
            loadedOlder = false;
            _reconcileSelection();
          }
        });
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  bool _hasSource(Map<String, dynamic> row, {bool staff = false}) {
    final id = row['sourceId'];
    return id is String &&
        _sourceId.hasMatch(id) &&
        switch (row['sourceType']) {
          'Support' || 'Package' || 'Payment' || 'Appointment' => true,
          'Task' => staff,
          _ => false,
        };
  }

  bool _canOpen(Map<String, dynamic> row) =>
      _hasSource(row, staff: widget.staff) &&
      (!widget.staff ||
          widget.boutiqueOperations ||
          !['Payment', 'Package'].contains(row['sourceType']));

  Set<String> get _loadedUnreadIds => {
    for (final row in records)
      if (row['readAt'] == null && filter.matches(row)) row['id'] as String,
  };

  void _clearSelection() {
    selecting = false;
    selectedIds.clear();
    bulkError = null;
  }

  void _reconcileSelection() {
    if (selectedIds.isEmpty) return;
    selectedIds.retainAll(_loadedUnreadIds);
  }

  void _startSelection([String? id]) {
    if (widget.staff ||
        selecting ||
        loading ||
        busyId != null ||
        bulkUpdating) {
      return;
    }
    final eligible = _loadedUnreadIds;
    if (eligible.isEmpty || (id != null && !eligible.contains(id))) return;
    setState(() {
      selecting = true;
      if (id != null) selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    if (!selecting ||
        bulkUpdating ||
        loading ||
        !_loadedUnreadIds.contains(id)) {
      return;
    }
    setState(() {
      if (!selectedIds.remove(id)) selectedIds.add(id);
      bulkError = null;
    });
  }

  Future<void> _requestRead(String id) async {
    final result = await api.request('/v1/notifications/$id/read', body: {});
    if (result['read'] != true) throw StateError('Unconfirmed read');
  }

  void _applyRead(Map<String, dynamic> row, int timestamp) {
    if (row['readAt'] == null && unread > 0) unread--;
    row['readAt'] = timestamp;
  }

  Future<void> _markBulk({bool allLoaded = false}) async {
    if (widget.staff || bulkUpdating || loading || busyId != null) return;
    final eligible = _loadedUnreadIds;
    final ids = (allLoaded ? eligible : selectedIds.intersection(eligible))
        .toList();
    if (ids.isEmpty) return;

    final request = generation;
    final uid = widget.uid;
    setState(() {
      selecting = bulkUpdating = true;
      selectedIds
        ..clear()
        ..addAll(ids);
      bulkError = null;
    });

    final confirmed = <String>{};
    final unavailable = <String>{};
    // The existing endpoint owns each write. Keep requests bounded and do not
    // send more if this inbox has been replaced by another account.
    const concurrency = 4;
    for (var offset = 0; offset < ids.length; offset += concurrency) {
      if (!mounted || request != generation) return;
      await Future.wait(
        ids.skip(offset).take(concurrency).map((id) async {
          try {
            await _requestRead(id);
            confirmed.add(id);
          } on PaymentFailure catch (failure) {
            if (failure.code == 'NOTIFICATION_NOT_FOUND') unavailable.add(id);
          } catch (_) {
            // Failed items are reconciled against the inbox and offered for retry.
          }
        }),
      );
    }
    if (!mounted || request != generation) return;

    // A separate device may have already read some items. The server count
    // is authoritative, while acknowledgements let the UI recover offline.
    final page = await _fetchPage(uid).then<_InboxPage?>(
      (value) => value,
      onError: (Object _, StackTrace _) => null,
    );
    if (!mounted || request != generation) return;
    final failed = ids.toSet()
      ..removeAll(confirmed)
      ..removeAll(unavailable);
    setState(() {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      for (final row in records) {
        if (confirmed.contains(row['id'])) {
          _applyRead(row, timestamp);
        } else if (unavailable.contains(row['id']) &&
            row['readAt'] == null &&
            unread > 0) {
          unread--;
        }
      }
      records.removeWhere((row) => unavailable.contains(row['id']));
      if (page != null) {
        if (loadedOlder) {
          // Retain loaded older pages and their cursor so failed items can be retried.
          final latest = {for (final row in page.rows) row['id']: row};
          records = [for (final row in records) latest[row['id']] ?? row];
        } else {
          records = page.rows;
          next = page.cursor;
        }
        unread = page.unread;
        error = null;
        for (final row in page.rows) {
          if (row['readAt'] != null) failed.remove(row['id']);
        }
      }
      selectedIds.retainAll(failed);
      _reconcileSelection();
      bulkUpdating = false;
      if (selectedIds.isEmpty) {
        _clearSelection();
      } else {
        bulkError = 'Could not confirm ${failed.length} as read. Try again.';
      }
    });
    if (failed.isNotEmpty && selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some notifications could not be confirmed as read.'),
        ),
      );
    } else if (unavailable.isNotEmpty && selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some notifications are no longer available.'),
        ),
      );
    }
  }

  Future<void> open(Map<String, dynamic> row, {bool navigate = true}) async {
    if (selecting ||
        busyId != null ||
        loading ||
        (navigate && !_canOpen(row))) {
      return;
    }
    final request = generation;
    var returnedFromDetails = false;
    setState(() => busyId = row['id']);
    try {
      if (row['readAt'] == null || widget.staff) {
        await _requestRead(row['id']);
        if (!mounted || request != generation) return;
        setState(() {
          _applyRead(row, DateTime.now().millisecondsSinceEpoch);
          if (widget.staff) error = null;
        });
      }
      if (navigate) {
        final Widget page = switch (row['sourceType']) {
          'Support' => SupportConversation(
            id: row['sourceId'],
            uid: widget.uid,
            name: widget.name,
            staff: widget.staff,
          ),
          'Task' => StaffTasksScreen(
            uid: widget.uid,
            initialId: row['sourceId'],
          ),
          'Package' => LivePackageScreen(
            staff: widget.staff,
            manager: widget.manager,
            initialSelections: true,
            initialSelectionId: row['sourceId'],
            openInitialSelection: true,
          ),
          'Payment' => LivePaymentsScreen(
            staff: widget.staff,
            manager: widget.manager,
            initialInvoiceId: row['sourceId'],
            focusInitialInvoice: true,
          ),
          'Appointment' => LiveAppointments(
            uid: widget.uid,
            name: widget.name,
            staff: widget.staff,
            manager: widget.manager,
            boutiqueOperations: widget.boutiqueOperations,
            initialAppointmentId: row['sourceId'],
          ),
          _ => throw StateError('Unknown notification source'),
        };
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => page));
        returnedFromDetails = true;
      }
    } catch (e) {
      if (mounted && request == generation) {
        if (widget.staff) {
          setState(() => error = workspaceError(e));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                navigate
                    ? 'Could not open this update. Please try again.'
                    : 'Could not mark this update as read. Please try again.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => busyId = null);
        if (returnedFromDetails) await load();
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = widget.staff ? const <String>{} : _loadedUnreadIds;
    final canAct = !loading && busyId == null && !bulkUpdating;
    return PopScope<void>(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting && !bulkUpdating) setState(_clearSelection);
      },
      child: AssistantExclusion(
        enabled: selecting && (ModalRoute.isCurrentOf(context) ?? true),
        child: Scaffold(
          appBar: selecting
              ? AppBar(
                  leading: IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: bulkUpdating
                        ? null
                        : () => setState(_clearSelection),
                    icon: const Icon(Icons.close),
                  ),
                  title: Semantics(
                    liveRegion: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${selectedIds.length} selected'),
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Select all loaded unread',
                      onPressed: canAct && eligible.length > selectedIds.length
                          ? () => setState(() {
                              selectedIds.addAll(eligible);
                              bulkError = null;
                            })
                          : null,
                      icon: const Icon(Icons.select_all),
                    ),
                    PopupMenuButton<void>(
                      tooltip: 'Selection options',
                      popUpAnimationStyle: CustomerUi.popupMotion(context),
                      enabled: canAct && selectedIds.isNotEmpty,
                      itemBuilder: (_) => [
                        PopupMenuItem<void>(
                          onTap: () => setState(() {
                            selectedIds.clear();
                            bulkError = null;
                          }),
                          child: const Text('Deselect all'),
                        ),
                      ],
                    ),
                  ],
                )
              : AppBar(
                  title: widget.staff
                      ? const Text('Staff notifications')
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Notifications'),
                        ),
                  actions: [
                    if (!widget.staff) const AssistantAppBarAction(),
                    IconButton(
                      tooltip: 'Refresh notifications',
                      onPressed: canAct ? () => load() : null,
                      icon: const Icon(Icons.refresh),
                    ),
                    if (!widget.staff)
                      PopupMenuButton<void>(
                        tooltip: 'Notification inbox options',
                        popUpAnimationStyle: CustomerUi.popupMotion(context),
                        enabled: canAct,
                        itemBuilder: (_) => [
                          PopupMenuItem<void>(
                            enabled: eligible.isNotEmpty,
                            onTap: _startSelection,
                            child: const Text('Select notifications'),
                          ),
                          PopupMenuItem<void>(
                            enabled: eligible.isNotEmpty,
                            onTap: () => _markBulk(allLoaded: true),
                            child: const Text('Mark visible as read'),
                          ),
                        ],
                      ),
                  ],
                ),
          body: widget.staff ? staffInbox(context) : customerInbox(context),
          bottomNavigationBar: selecting
              ? _bulkActionBar(context, canAct)
              : null,
        ),
      ),
    );
  }

  Widget _bulkActionBar(BuildContext context, bool canAct) {
    final count = selectedIds.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ivory,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 728),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bulkError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        bulkError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (bulkUpdating)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      semanticsLabel: 'Marking selected notifications as read',
                    ),
                  ),
                FilledButton(
                  onPressed: canAct && count > 0 ? () => _markBulk() : null,
                  child: Text(
                    bulkUpdating ? 'Marking as read…' : 'Mark $count as read',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget customerInbox(BuildContext context) {
    final theme = Theme.of(context);
    final rows = filter == _InboxFilter.all
        ? records
        : records.where(filter.matches).toList();
    final enabled = !loading && busyId == null && !bulkUpdating;
    final receivedToday = DateTime.now();
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            key: const Key('notification-inbox-list'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (error == null || records.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!loading || records.isNotEmpty)
                                Semantics(
                                  header: true,
                                  liveRegion: true,
                                  child: Text(
                                    '$unread unread update${unread == 1 ? '' : 's'}',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              if (records.isNotEmpty)
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final option in _InboxFilter.values)
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                end: 6,
                                              ),
                                          child: ChoiceChip(
                                            key: ValueKey(
                                              'notification-filter-${option.name}',
                                            ),
                                            label: Text(option.label),
                                            showCheckmark: false,
                                            selected: filter == option,
                                            onSelected: selecting
                                                ? null
                                                : (_) => setState(
                                                    () => filter = option,
                                                  ),
                                            selectedColor: blush,
                                            backgroundColor: ivory,
                                            disabledColor: filter == option
                                                ? blush
                                                : ivory,
                                            shape: const StadiumBorder(),
                                            side: const BorderSide(color: line),
                                            labelStyle: const TextStyle(
                                              color: ink,
                                            ),
                                            visualDensity:
                                                VisualDensity.standard,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.padded,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (loading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            semanticsLabel: 'Loading notifications',
                          ),
                        ),
                      ),
                    if (error != null)
                      SliverToBoxAdapter(
                        child: _InboxNotice(
                          icon: Icons.cloud_off_outlined,
                          title: records.isEmpty
                              ? 'Could not load notifications'
                              : 'Could not load older notifications',
                          detail: error!,
                          actionLabel: 'Try again',
                          onAction: enabled
                              ? () => load(more: records.isNotEmpty)
                              : null,
                        ),
                      ),
                    if (rows.isNotEmpty)
                      SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          final id = row['id'] as String;
                          final isUnread = row['readAt'] == null;
                          return _InboxRow(
                            key: ValueKey('notification-$id'),
                            row: row,
                            today: receivedToday,
                            enabled: enabled,
                            marking: busyId == id,
                            selecting: selecting,
                            selected: selectedIds.contains(id),
                            onStartSelection: isUnread
                                ? () => _startSelection(id)
                                : null,
                            onToggle: isUnread
                                ? () => _toggleSelection(id)
                                : null,
                            onOpen: _canOpen(row) ? () => open(row) : null,
                            onMarkRead: () => open(row, navigate: false),
                          );
                        },
                      )
                    else if (!loading && error == null)
                      SliverToBoxAdapter(
                        child: _InboxNotice(
                          icon: records.isEmpty
                              ? Icons.notifications_none
                              : Icons.inbox_outlined,
                          title: records.isEmpty
                              ? "You're all caught up"
                              : filter == _InboxFilter.unread && unread == 0
                              ? 'No unread notifications'
                              : filter == _InboxFilter.unread
                              ? 'No unread notifications here'
                              : 'No matching notifications',
                          detail: records.isEmpty
                              ? 'Your booking, fitting and payment updates will appear here.'
                              : next != null &&
                                    (filter != _InboxFilter.unread ||
                                        unread > 0)
                              ? 'Load older notifications to check for more updates.'
                              : 'View all notifications to see your history.',
                          actionLabel: records.isEmpty || selecting
                              ? null
                              : 'View all notifications',
                          onAction: () =>
                              setState(() => filter = _InboxFilter.all),
                        ),
                      ),
                    if (next != null && error == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            child: TextButton(
                              onPressed: enabled
                                  ? () => load(more: true)
                                  : null,
                              child: const Text('Load older notifications'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget staffInbox(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            error != null
                ? 'Inbox unavailable'
                : loading && records.isEmpty
                ? 'Checking notifications…'
                : '$unread unread',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            records.length > 50
                ? 'Viewing older updates. Refresh to see the latest.'
                : 'Follow customer bookings, payments and support tickets, and see updates to your assigned work.',
          ),
          const SizedBox(height: 20),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: loading ? null : () => load(),
              child: const Text('Try again'),
            ),
          ],
          if (records.isEmpty && !loading && error == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'You are all caught up. New notifications will appear here.',
              ),
            ),
          for (final r in records)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          notificationIcon(r['sourceType']),
                          color: const Color(0xFFA70C3B),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _staffNotificationTitle(r),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: r['readAt'] == null
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(paymentDateLabel(r['createdAt'])),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (_canOpen(r))
                          TextButton(
                            onPressed: busyId != null ? null : () => open(r),
                            child: Text(_staffNotificationAction(r)),
                          ),
                        if (r['readAt'] == null)
                          TextButton(
                            onPressed: busyId != null
                                ? null
                                : () => open(r, navigate: false),
                            child: const Text('Mark as read'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (next != null)
            OutlinedButton(
              onPressed: loading ? null : () => load(more: true),
              child: const Text('Load older notifications'),
            ),
        ],
      ),
    ),
  );
}

enum _InboxFilter {
  all('All'),
  unread('Unread'),
  payments('Payments'),
  bookings('Bookings'),
  support('Support');

  const _InboxFilter(this.label);
  final String label;

  bool matches(Map<String, dynamic> row) => switch (this) {
    all => true,
    unread => row['readAt'] == null,
    payments => row['sourceType'] == 'Payment',
    bookings => const ['Package', 'Appointment'].contains(row['sourceType']),
    support => row['sourceType'] == 'Support',
  };
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    super.key,
    required this.row,
    required this.today,
    required this.enabled,
    required this.marking,
    required this.selecting,
    required this.selected,
    required this.onStartSelection,
    required this.onToggle,
    required this.onOpen,
    required this.onMarkRead,
  });

  final Map<String, dynamic> row;
  final DateTime today;
  final bool enabled, marking, selecting, selected;
  final VoidCallback? onOpen, onStartSelection, onToggle;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.6;
    final unread = row['readAt'] == null;
    final showChevron = !selecting && onOpen != null;
    final sourceType = row['sourceType'];
    final type = sourceType is String ? sourceType : '';
    final date = DateTime.fromMillisecondsSinceEpoch(row['createdAt']);
    final locale = MaterialLocalizations.of(context);
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final day = DateUtils.isSameDay(date, today)
        ? 'Today'
        : DateUtils.isSameDay(date, yesterday)
        ? 'Yesterday'
        : date.year == today.year
        ? locale.formatShortMonthDay(date)
        : locale.formatShortDate(date);

    final dateLabel = Semantics(
      label: '${locale.formatFullDate(date)} · $time',
      excludeSemantics: true,
      child: Text(
        '$day · $time',
        style: theme.textTheme.bodySmall?.copyWith(color: secondary),
      ),
    );
    final chevron = Icon(Icons.chevron_right, size: 18, color: secondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: CustomerUi.motion(context, CustomerUi.selection),
        curve: Curves.easeOut,
        decoration: ShapeDecoration(
          color: selected
              ? blush
              : unread
              ? CustomerUi.linen
              : CustomerUi.paper,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? rose : Colors.transparent,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            borderRadius: CustomerUi.buttonRadius,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: showChevron,
                  checked: selecting && unread ? selected : null,
                  enabled: selecting ? unread && enabled : null,
                  label: unread ? 'Unread notification' : 'Read notification',
                  hint: selecting
                      ? null
                      : showChevron
                      ? notificationAction(type)
                      : null,
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    // A held read row stays in the inbox even though a tap opens it.
                    onLongPress: enabled && showChevron && !unread
                        ? () {}
                        : null,
                    child: InkWell(
                      onTap: enabled ? (selecting ? onToggle : onOpen) : null,
                      onLongPress: enabled && !selecting
                          ? onStartSelection
                          : null,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          12,
                          10,
                          12,
                        ),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: largeText ? 32 : 36,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: unread ? blush : ivory,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        notificationIcon(type),
                                        size: 20,
                                        color: unread ? rose : secondary,
                                      ),
                                    ),
                                  ),
                                  if (unread)
                                    const PositionedDirectional(
                                      end: 0,
                                      top: 0,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: rose,
                                          shape: BoxShape.circle,
                                          border: Border.fromBorderSide(
                                            BorderSide(color: Colors.white),
                                          ),
                                        ),
                                        child: SizedBox.square(dimension: 9),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: largeText ? 8 : 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _customerNotificationTitle(row),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: ink,
                                      height: 1.3,
                                      fontWeight: unread
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if (largeText && showChevron)
                                    Row(
                                      children: [
                                        Expanded(child: dateLabel),
                                        chevron,
                                      ],
                                    )
                                  else
                                    dateLabel,
                                ],
                              ),
                            ),
                            if (!largeText && showChevron) ...[
                              const SizedBox(width: 4),
                              chevron,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (selecting && unread)
                InkWell(
                  onTap: enabled ? onToggle : null,
                  excludeFromSemantics: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: selected ? rose : secondary,
                      size: 21,
                    ),
                  ),
                )
              else if (unread)
                if (marking)
                  const SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Marking as read',
                        ),
                      ),
                    ),
                  )
                else if (onOpen != null)
                  PopupMenuButton<void>(
                    tooltip: 'Notification options',
                    popUpAnimationStyle: CustomerUi.popupMotion(context),
                    icon: const Icon(Icons.more_vert, size: 20),
                    enabled: enabled,
                    itemBuilder: (_) => [
                      PopupMenuItem<void>(
                        onTap: onMarkRead,
                        child: const Text('Mark as read'),
                      ),
                    ],
                  )
                else
                  IconButton(
                    tooltip: 'Mark as read',
                    icon: const Icon(Icons.done, size: 20),
                    onPressed: enabled ? onMarkRead : null,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxNotice extends StatelessWidget {
  const _InboxNotice({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title, detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        children: [
          Icon(icon, color: rose, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
