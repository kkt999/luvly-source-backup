import 'dart:async';
import 'package:flutter/material.dart';
import '../bookings/booking_screens.dart';
import '../payments/payment_screen.dart';
import '../payments/payment_api.dart' show PaymentFailure;
import '../packages/package_screen.dart';
import 'analytics_api.dart';
import 'analytics_detail.dart';
import 'design.dart';
import 'export.dart';
import 'model.dart';
import 'people.dart' show AccessDenied;

const _sage = Color(0xFF46665B), _gold = Color(0xFFAE7835);

enum ManagerReport {
  packages(
    'packages',
    'Package Popularity Report',
    'Compare recorded selections and paid bookings by package.',
    Icons.workspace_premium_outlined,
  ),
  conversion(
    'conversion',
    'Appointment Conversion Report',
    'Track completed fittings that led to a verified package payment.',
    Icons.event_available_outlined,
  ),
  collections(
    'collections',
    'Revenue Summary Report',
    'Review verified service collections and refundable security.',
    Icons.bar_chart_outlined,
  ),
  bodyTypes(
    'body-types',
    'Body Type Distribution Report',
    'View counts and percentages for shared body profiles.',
    Icons.pie_chart_outline,
  );

  const ManagerReport(this.id, this.title, this.description, this.icon);

  final String id, title, description;
  String get breadcrumb => title.substring(0, title.length - ' Report'.length);
  final IconData icon;
}

class BusinessAnalyticsPage extends StatefulWidget {
  const BusinessAnalyticsPage({
    super.key,
    this.dashboard = false,
    this.api,
    this.onNavigate,
    this.exportCsv,
    this.today,
    this.selectedReport,
    this.onSelectReport,
  });
  final bool dashboard;
  final AnalyticsApi? api;
  final ValueChanged<PortalPage>? onNavigate;
  final bool Function(String, String)? exportCsv;
  final DateTime? today;
  final ManagerReport? selectedReport;
  final ValueChanged<ManagerReport>? onSelectReport;
  @override
  State<BusinessAnalyticsPage> createState() => _BusinessAnalyticsState();
}

class _BusinessAnalyticsState extends State<BusinessAnalyticsPage>
    with WidgetsBindingObserver {
  AnalyticsApi? api;
  String? actorKey;
  bool ownsApi = false, dirty = false, methodologyOpen = false;
  Future<AnalyticsSnapshot>? future;
  final sourceRevision = ValueNotifier<int>(0);
  StreamSubscription<String>? liveSubscription;
  Timer? reconnect, debounce, clockRefresh;
  String liveStatus = 'Manual updates';
  bool loading = false, refreshQueued = false, visible = true;
  int requestEpoch = 0, liveEpoch = 0, retrySeconds = 2;
  DateTime? lastRequest;
  DateTime get today =>
      widget.today ?? AnalyticsScope.todayOf(context) ?? analyticsToday();
  late DateTime from = today.subtract(const Duration(days: 29)), to = today;
  late DateTime appliedFrom = from, appliedTo = to;
  String preset = 'Last 30 days';
  ManagerReport? get selectedReport => widget.selectedReport;
  String? get reportId => selectedReport?.id;
  bool get canLoad => widget.dashboard || (selectedReport != null && manager);
  bool get manager => PortalScope.of(context).isManager;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final member = PortalScope.of(context).current!;
    final key = '${member.id}:${member.role}';
    final changedActor = actorKey != null && actorKey != key;
    actorKey = key;
    if (api == null) {
      final injected = widget.api ?? AnalyticsScope.maybeOf(context);
      api = injected ?? HttpAnalyticsApi();
      ownsApi = injected == null;
      WidgetsBinding.instance.addObserver(this);
      load();
      connectLive();
    } else if (changedActor) {
      stopLive();
      requestEpoch++;
      load();
      connectLive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopLive();
    sourceRevision.dispose();
    if (ownsApi) api?.close();
    super.dispose();
  }

  void load({bool applyDraft = true}) {
    if (!canLoad) return;
    final snapshotOnly = !widget.dashboard && reportId == 'body-types';
    if (!applyDraft &&
        manager &&
        !dirty &&
        preset != 'Custom dates' &&
        to != today) {
      to = today;
      from = to.subtract(
        Duration(
          days: preset == 'Last 7 days'
              ? 6
              : preset == 'Last 90 days'
              ? 89
              : 29,
        ),
      );
      appliedFrom = from;
      appliedTo = to;
    }
    if (manager &&
        !snapshotOnly &&
        validateReportDates(
              applyDraft ? from : appliedFrom,
              applyDraft ? to : appliedTo,
              today: today,
            ) !=
            null) {
      return;
    }
    if (!snapshotOnly && applyDraft) {
      appliedFrom = from;
      appliedTo = to;
      dirty = false;
    }
    final request = manager
        ? api!.report(appliedFrom, appliedTo)
        : api!.dashboard();
    final epoch = ++requestEpoch;
    loading = true;
    lastRequest = DateTime.now();
    future = request.whenComplete(() {
      if (!mounted || epoch != requestEpoch) return;
      setState(() => loading = false);
      if (refreshQueued) {
        refreshQueued = false;
        scheduleRefresh();
      }
    });
    future!.ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    if (!visible) {
      stopLive();
      if (mounted && api is LiveAnalyticsApi) {
        setState(
          () => liveStatus = widget.dashboard
              ? 'Updates paused'
              : 'Auto-refresh paused',
        );
      }
    } else if (mounted) {
      setState(() => load(applyDraft: false));
      connectLive();
    }
  }

  void stopLive() {
    liveEpoch++;
    liveSubscription?.cancel();
    liveSubscription = null;
    reconnect?.cancel();
    debounce?.cancel();
    clockRefresh?.cancel();
    reconnect = null;
    debounce = null;
    clockRefresh = null;
    refreshQueued = false;
  }

  void scheduleRefresh() {
    if (!mounted || !visible) return;
    if (loading) {
      refreshQueued = true;
      return;
    }
    if (debounce?.isActive == true) return;
    final elapsed = lastRequest == null
        ? 5000
        : DateTime.now().difference(lastRequest!).inMilliseconds;
    debounce = Timer(
      Duration(milliseconds: elapsed < 5000 ? 5000 - elapsed : 350),
      () {
        if (mounted && visible) setState(() => load(applyDraft: false));
      },
    );
  }

  void connectLive() {
    if (api is! LiveAnalyticsApi || !canLoad || !visible) {
      return;
    }
    stopLive();
    final epoch = liveEpoch;
    liveStatus = widget.dashboard
        ? 'Connecting live updates'
        : 'Connecting auto-refresh';
    void disconnected() {
      if (!mounted || epoch != liveEpoch || !visible) return;
      liveEpoch++;
      liveSubscription?.cancel();
      liveSubscription = null;
      clockRefresh?.cancel();
      setState(
        () => liveStatus = widget.dashboard
            ? 'Live disconnected · reconnecting'
            : 'Auto-refresh disconnected · reconnecting',
      );
      reconnect = Timer(Duration(seconds: retrySeconds), () {
        if (mounted && visible) setState(connectLive);
      });
      retrySeconds = (retrySeconds * 2).clamp(2, 30);
    }

    liveSubscription = (api as LiveAnalyticsApi).changes().listen(
      (event) {
        if (!mounted || epoch != liveEpoch) return;
        if (event == 'ready') {
          retrySeconds = 2;
          setState(() => liveStatus = 'Live updates connected');
          // Covers writes between the initial report read and listener readiness.
          scheduleRefresh();
          clockRefresh?.cancel();
          clockRefresh = Timer.periodic(
            const Duration(minutes: 1),
            (_) => scheduleRefresh(),
          );
        } else if (event == 'changed') {
          sourceRevision.value++;
          scheduleRefresh();
        } else if (event == 'access-denied') {
          stopLive();
          setState(() {
            liveStatus = widget.dashboard
                ? 'Live access unavailable'
                : 'Auto-refresh unavailable';
            future = Future<AnalyticsSnapshot>.error(
              const PaymentFailure(
                'Your access changed. Please sign in again.',
              ),
            );
            future!.ignore();
          });
        } else if (event == 'unavailable') {
          disconnected();
        }
      },
      onError: (_) => disconnected(),
      onDone: disconnected,
    );
  }

  void showDetails(String kind, AnalyticsSnapshot snapshot) {
    if (!manager) return;
    final range = snapshot.data['range'];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyticsDetailPage(
          snapshot: snapshot,
          kind: kind,
          revision: sourceRevision,
          reload: () => api!.report(
            DateTime.parse(range['from']),
            DateTime.parse(range['to']),
          ),
          onRecord: (type, id) {
            final member = PortalScope.of(context).current!;
            final page = type == 'service' || type == 'security'
                ? LivePaymentsScreen(
                    staff: true,
                    manager: true,
                    initialInvoiceId: id,
                    focusInitialInvoice: true,
                  )
                : type == 'selections'
                ? LivePackageScreen(
                    staff: true,
                    manager: true,
                    initialSelections: true,
                    initialSelectionId: id,
                  )
                : LiveAppointments(
                    uid: member.id,
                    name: member.name,
                    staff: true,
                    manager: true,
                    initialAppointmentId: id,
                  );
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Source record')),
                  body: page,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> pick(bool start) async {
    final value = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          from = value;
        } else {
          to = value;
        }
        preset = 'Custom dates';
        dirty = true;
      });
    }
  }

  @override
  void didUpdateWidget(BusinessAnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedReport == selectedReport) return;
    stopLive();
    requestEpoch++;
    future = null;
    loading = false;
    methodologyOpen = false;
    liveStatus = 'Manual updates';
    load(applyDraft: false);
    connectLive();
  }

  @override
  Widget build(BuildContext c) {
    final model = PortalScope.of(c);
    if (!widget.dashboard && !model.isManager) return const AccessDenied();
    final selected = selectedReport;
    if (!widget.dashboard && selected == null) {
      return PageBody(
        key: const ValueKey('report-picker'),
        children: [
          const Heading(
            'Analytics Dashboard',
            'Choose a business report to view.',
          ),
          ResponsiveGrid(
            minWidth: 340,
            children: [
              for (final report in ManagerReport.values)
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    leading: Icon(report.icon, color: rose),
                    title: Text(report.title),
                    subtitle: Text(report.description),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onSelectReport?.call(report),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    return PageBody(
      key: ValueKey(selected?.id ?? 'dashboard'),
      children: [
        Heading(
          widget.dashboard
              ? 'Welcome back, ${model.current!.name}'
              : selected!.title,
          widget.dashboard
              ? 'A clear view of your boutique, with the next actions in reach.'
              : selected!.description,
          bottomSpacing: selected == null ? 22 : 12,
          action: OutlinedButton.icon(
            onPressed: () => setState(() => load(applyDraft: widget.dashboard)),
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Refresh data'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.dashboard || api is LiveAnalyticsApi) ...[
              Icon(
                liveStatus == 'Live updates connected'
                    ? Icons.sensors
                    : Icons.sync_disabled,
                size: 16,
                color: liveStatus == 'Live updates connected' ? _sage : muted,
              ),
              Text(
                liveStatus == 'Live updates connected' && !widget.dashboard
                    ? 'Auto-refresh active'
                    : liveStatus,
                style: const TextStyle(color: muted, fontSize: 12),
                semanticsLabel: liveStatus == 'Auto-refresh paused'
                    ? 'Auto-refresh paused while this page is inactive'
                    : null,
              ),
            ],
            if (loading)
              const Text(
                'Checking latest data…',
                style: TextStyle(color: muted, fontSize: 12),
              ),
          ],
        ),
        gap(selected == null ? 16 : 10),
        if (manager && (widget.dashboard || reportId != 'body-types')) ...[
          Panel(
            padding: selected == null
                ? const EdgeInsets.all(20)
                : const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 175,
                      child: DropdownButtonFormField<String>(
                        initialValue: preset,
                        key: ValueKey(preset),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Reporting period',
                        ),
                        items:
                            [
                                  'Last 7 days',
                                  'Last 30 days',
                                  'Last 90 days',
                                  'Custom dates',
                                ]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            preset = v;
                            if (v != 'Custom dates') {
                              to = today;
                              from = to.subtract(
                                Duration(
                                  days: v == 'Last 7 days'
                                      ? 6
                                      : v == 'Last 90 days'
                                      ? 89
                                      : 29,
                                ),
                              );
                              load();
                            }
                          });
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => pick(true),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('From: ${analyticsDate(from)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => pick(false),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('To: ${analyticsDate(to)}'),
                    ),
                    FilledButton(
                      onPressed:
                          validateReportDates(from, to, today: today) == null
                          ? () => setState(load)
                          : null,
                      child: const Text('Apply filters'),
                    ),
                  ],
                ),
                if (validateReportDates(from, to, today: today)
                    case final String error)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (dirty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Dates changed. Apply filters to update results and enable export.',
                      style: TextStyle(color: _gold),
                    ),
                  ),
              ],
            ),
          ),
          gap(22),
        ],
        FutureBuilder<AnalyticsSnapshot>(
          future: future,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done && !s.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (s.hasError || !s.hasData) {
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dashboard
                          ? 'Could not load dashboard data.'
                          : 'Could not load this report.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    gap(8),
                    Text(
                      s.hasError
                          ? analyticsError(s.error!)
                          : 'No verified response was received. No totals are being estimated.',
                    ),
                    gap(14),
                    FilledButton.icon(
                      onPressed: () =>
                          setState(() => load(applyDraft: widget.dashboard)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    if (widget.dashboard)
                      TextButton.icon(
                        onPressed: () =>
                            widget.onNavigate?.call(PortalPage.appointments),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Manage appointments'),
                      ),
                  ],
                ),
              );
            }
            final data = s.data!;
            final generated = DateTime.fromMillisecondsSinceEpoch(
              data.data['generatedAt'],
              isUtc: true,
            ).add(const Duration(hours: 8));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (manager) _tag('Test transactions', rose, blush),
                    if (manager && reportId != 'body-types')
                      Text(
                        'Applied period: ${data.data['range']['from']} to ${data.data['range']['to']}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    Text(
                      '${widget.dashboard ? 'Updated' : 'Last updated'} ${analyticsDate(generated)} · ${generated.hour.toString().padLeft(2, '0')}:${generated.minute.toString().padLeft(2, '0')} MYT',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    if (!manager)
                      const Text(
                        'Team operations · financial reports are manager-only',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                  ],
                ),
                gap(18),
                if (widget.dashboard) ...[
                  if (manager) ...[
                    _BusinessMetrics(
                      data: data,
                      onDetails: (kind) => showDetails(kind, data),
                    ),
                    gap(22),
                    ResponsiveGrid(
                      minWidth: 440,
                      children: [
                        _CollectionsChart(data: data),
                        _PackageChart(data: data),
                      ],
                    ),
                    gap(24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () =>
                            widget.onNavigate?.call(PortalPage.reports),
                        icon: const Icon(Icons.arrow_forward, size: 17),
                        label: const Text('Explore business reports'),
                      ),
                    ),
                  ],
                  _Operations(data: data, onNavigate: widget.onNavigate),
                ] else ...[
                  if (reportId == 'collections') _CollectionsChart(data: data),
                  if (reportId == 'packages') _PackageChart(data: data),
                  if (reportId == 'conversion') _ConversionChart(data: data),
                  if (reportId == 'body-types') _BodyChart(data: data),
                  gap(22),
                  for (final report in data.reports.where(
                    (r) => r.id == reportId,
                  )) ...[
                    Heading(
                      'Report Results',
                      report.summary,
                      titleStyle: Theme.of(c).textTheme.titleLarge,
                      bottomSpacing: 6,
                      action: FilledButton.icon(
                        key: const Key('export-report-csv'),
                        onPressed: dirty && report.id != 'body-types'
                            ? null
                            : () {
                                final filename = report.id == 'body-types'
                                    ? 'Luvly-test-report-body-types-snapshot-${analyticsDate(generated)}.csv'
                                    : 'Luvly-test-report-${report.id}-${data.data['range']['from']}-${data.data['range']['to']}.csv';
                                final success =
                                    (widget.exportCsv ?? downloadCsv)(
                                      filename,
                                      safeReportCsv(report, data),
                                    );
                                notice(
                                  c,
                                  success
                                      ? 'Report CSV downloaded.'
                                      : 'CSV downloads are available in the browser.',
                                );
                              },
                        icon: const Icon(Icons.download_outlined, size: 17),
                        label: const Text('Export full CSV'),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        MergeSemantics(
                          child: Semantics(
                            expanded: methodologyOpen,
                            hint: methodologyOpen
                                ? 'Collapse calculation details'
                                : 'Expand calculation details',
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => methodologyOpen = !methodologyOpen,
                              ),
                              icon: Icon(
                                methodologyOpen
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 17,
                              ),
                              label: const Text(
                                'How this report is calculated',
                              ),
                            ),
                          ),
                        ),
                        if (reportId == 'packages')
                          TextButton(
                            onPressed: () => showDetails('selections', data),
                            child: const Text('View package selection records'),
                          ),
                        if (reportId == 'conversion')
                          TextButton(
                            onPressed: () => showDetails('conversion', data),
                            child: const Text('View fitting records'),
                          ),
                        if (reportId == 'collections') ...[
                          TextButton(
                            onPressed: () => showDetails('service', data),
                            child: const Text('View service receipts'),
                          ),
                          TextButton(
                            onPressed: () => showDetails('security', data),
                            child: const Text('View security receipts'),
                          ),
                        ],
                      ],
                    ),
                    if (methodologyOpen)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                        child: Text(
                          report.basis,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ),
                    gap(8),
                    _ReportTable(
                      key: ValueKey(
                        '${reportId}_${data.data['range']['from']}_${data.data['range']['to']}',
                      ),
                      report: report,
                    ),
                  ],
                ],
                if (manager &&
                    (widget.dashboard || reportId == 'collections')) ...[
                  gap(20),
                  const Text(
                    'Collections show verified test payments. Refundable security and refund records are tracked separately. Dates use Malaysia time.',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.6),
                  ),
                  if (data.quality.entries
                      .where(
                        (e) =>
                            e.key != 'unclassifiedProfiles' &&
                            e.value is num &&
                            (e.value as num) > 0,
                      )
                      .isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Current source data quality: ${data.quality['paidMissingMetadata']} paid records missing verification metadata; ${data.quality['selectionsMissingDate']} selections and ${data.quality['appointmentsMissingDate']} appointments missing dates. These cannot be included in the corresponding dated totals.',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 11,
                          height: 1.6,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

Widget _tag(String text, Color color, Color fill) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  decoration: BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: .8,
    ),
  ),
);

class _Stat extends StatelessWidget {
  const _Stat(
    this.title,
    this.value,
    this.note,
    this.icon, {
    this.color = rose,
    this.onDetails,
  });
  final String title, value, note;
  final IconData icon;
  final Color color;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: color, size: 21),
          ],
        ),
        gap(18),
        InkWell(
          onTap: onDetails,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -.6,
              decoration: onDetails == null ? null : TextDecoration.underline,
              decorationThickness: 1,
            ),
          ),
        ),
        gap(6),
        Text(
          note,
          style: const TextStyle(color: muted, fontSize: 11, height: 1.5),
        ),
        if (onDetails != null) ...[
          gap(12),
          TextButton.icon(
            key: ValueKey('details-$title'),
            onPressed: onDetails,
            icon: const Icon(Icons.arrow_outward, size: 16),
            label: const Text('View details'),
          ),
        ],
      ],
    ),
  );
}

class _BusinessMetrics extends StatelessWidget {
  const _BusinessMetrics({required this.data, required this.onDetails});
  final AnalyticsSnapshot data;
  final ValueChanged<String> onDetails;
  @override
  Widget build(BuildContext c) => ResponsiveGrid(
    minWidth: 225,
    children: [
      _Stat(
        'Service collections',
        analyticsMoney(data.total('serviceCents')),
        'Verified receipts · security excluded',
        Icons.payments_outlined,
        onDetails: () => onDetails('service'),
      ),
      _Stat(
        'Refundable security collected',
        analyticsMoney(data.total('securityCents')),
        'Shown separately · not service income',
        Icons.shield_outlined,
        color: _sage,
        onDetails: () => onDetails('security'),
      ),
      _Stat(
        'Package selections',
        '${data.total('packageSelections')}',
        '${data.total('paidPackageBookings')} with a verified package deposit',
        Icons.checkroom_outlined,
        color: _gold,
        onDetails: () => onDetails('selections'),
      ),
      _Stat(
        'Fitting conversion',
        '${data.totals['conversionPercent']}%',
        '${data.total('convertedFittings')} of ${data.total('completedFittings')} completed fittings',
        Icons.trending_up,
        color: _sage,
        onDetails: () => onDetails('conversion'),
      ),
    ],
  );
}

class _ChartHeading extends StatelessWidget {
  const _ChartHeading(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      gap(5),
      Text(
        subtitle,
        style: const TextStyle(color: muted, fontSize: 11, height: 1.5),
      ),
      gap(22),
    ],
  );
}

class _CollectionsChart extends StatelessWidget {
  const _CollectionsChart({required this.data});
  final AnalyticsSnapshot data;
  @override
  Widget build(BuildContext c) {
    final rows = data.series('trend');
    final peak = rows.fold<int>(0, (max, row) {
      final n =
          (row['serviceCents'] + row['securityCents'] + row['otherCents'])
              as int;
      return n > max ? n : max;
    });
    final axisText = TextPainter(
      text: TextSpan(
        text: analyticsMoney(peak),
        style: DefaultTextStyle.of(c).style.copyWith(fontSize: 9),
      ),
      textDirection: Directionality.of(c),
      textScaler: MediaQuery.textScalerOf(c),
    )..layout();
    final axisWidth = axisText.width + 12 < 74 ? 74.0 : axisText.width + 12;
    axisText.dispose();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ChartHeading(
            'Collections over time',
            'Verified paid date · daily / weekly MYT groups',
          ),
          if (peak == 0)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  'No verified collections in this period.',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            SizedBox(
              height: 205 + MediaQuery.textScalerOf(c).scale(9) * 1.6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: axisWidth,
                    height: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          analyticsMoney(peak),
                          maxLines: 1,
                          style: const TextStyle(fontSize: 9, color: muted),
                        ),
                        Text(
                          analyticsMoney(peak ~/ 2),
                          maxLines: 1,
                          style: const TextStyle(fontSize: 9, color: muted),
                        ),
                        const Text(
                          'RM 0',
                          style: TextStyle(fontSize: 9, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 180,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final row in rows)
                                Expanded(
                                  child: Tooltip(
                                    message:
                                        '${row['from']}\nServices ${analyticsMoney(row['serviceCents'])}\nSecurity ${analyticsMoney(row['securityCents'])}\nOther ${analyticsMoney(row['otherCents'])}',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 1.5,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          for (final item in [
                                            ('otherCents', _gold),
                                            ('securityCents', _sage),
                                            ('serviceCents', rose),
                                          ])
                                            if (row[item.$1] > 0)
                                              Container(
                                                height:
                                                    174 *
                                                    (row[item.$1] as int) /
                                                    peak,
                                                decoration: BoxDecoration(
                                                  color: item.$2,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        gap(9),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              (rows.first['from'] as String).substring(5),
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                            Text(
                              (rows.last['from'] as String).substring(5),
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          gap(16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legend('Service collections', rose),
              _legend('Refundable security', _sage),
              _legend('Review / unclassified', _gold),
            ],
          ),
          if (data.total('otherCents') > 0)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '${analyticsMoney(data.total('otherCents'))} requires classification / review; excluded from service collections.',
                style: const TextStyle(color: _gold, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _legend(String text, Color color) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    const SizedBox(width: 6),
    Text(text, style: const TextStyle(fontSize: 10, color: muted)),
  ],
);

class _PackageChart extends StatelessWidget {
  const _PackageChart({required this.data});
  final AnalyticsSnapshot data;
  @override
  Widget build(BuildContext c) {
    final rows = data.series('packages'),
        max = rows.fold<int>(
          1,
          (n, p) => p['selections'] > n ? p['selections'] : n,
        );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ChartHeading(
            'Most considered packages',
            'Selections created in period · not stock reservations',
          ),
          if (rows.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  'No package selections in this period.',
                  style: TextStyle(color: muted),
                ),
              ),
            ),
          for (final p in rows.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${p['selections']}',
                        style: const TextStyle(
                          color: _sage,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  gap(8),
                  LinearProgressIndicator(
                    value: p['selections'] / max,
                    minHeight: 7,
                    color: _sage,
                    backgroundColor: const Color(0xFFEDF2EE),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  gap(6),
                  Text(
                    '${p['paidBookings']} verified paid bookings',
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          if (rows.length > 5)
            const Text(
              'Top five shown · the table / CSV includes all packages.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _ConversionChart extends StatelessWidget {
  const _ConversionChart({required this.data});
  final AnalyticsSnapshot data;
  @override
  Widget build(BuildContext c) {
    final total = data.total('completedFittings'),
        converted = data.total('convertedFittings');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ChartHeading(
            'From fitting to bridal booking',
            'Completed Dress Trial visits only · verified linked package deposits',
          ),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _tag('$converted CONVERTED', _sage, const Color(0xFFEDF2EE)),
              _tag(
                '${total - converted} NOT YET CONVERTED',
                _gold,
                const Color(0xFFFAF1E4),
              ),
            ],
          ),
          gap(22),
          LinearProgressIndicator(
            value: total == 0 ? 0 : converted / total,
            minHeight: 12,
            color: _sage,
            backgroundColor: const Color(0xFFFAF1E4),
            borderRadius: BorderRadius.circular(7),
          ),
          gap(14),
          Text(
            total == 0
                ? 'No completed fittings in this cohort.'
                : '${data.totals['conversionPercent']}% of $total completed fittings converted as of this snapshot.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BodyChart extends StatelessWidget {
  const _BodyChart({required this.data});
  final AnalyticsSnapshot data;
  @override
  Widget build(BuildContext c) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ChartHeading(
          'Recorded body profiles',
          'Current snapshot · shared recommendation guides only',
        ),
        Text(
          '${data.total('classifiedProfiles')} classified · ${data.quality['unclassifiedProfiles']} not classified',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        gap(20),
        for (final row in data.series('bodyTypes'))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    row['label'],
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: data.total('classifiedProfiles') == 0
                        ? 0
                        : row['count'] / data.total('classifiedProfiles'),
                    minHeight: 8,
                    color: _sage,
                    backgroundColor: blush,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${row['count']}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Operations extends StatelessWidget {
  const _Operations({required this.data, this.onNavigate});
  final AnalyticsSnapshot data;
  final ValueChanged<PortalPage>? onNavigate;
  @override
  Widget build(BuildContext c) {
    final upcoming = (data.operations['upcoming'] as List).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today in the boutique',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        gap(6),
        const Text(
          'Current operations · separate from the reporting date filter',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        gap(16),
        ResponsiveGrid(
          minWidth: 210,
          children: [
            _Stat(
              'Confirmed visits today',
              '${data.operation('todayConfirmed')}',
              data.operations['today'],
              Icons.event_available_outlined,
            ),
            _Stat(
              'Open conversations',
              '${data.operation('openConversations')}',
              'Shared team inbox',
              Icons.support_agent,
              color: _sage,
            ),
            _Stat(
              'Active rental holds',
              '${data.operation('activeHolds')}',
              'Expired 15-minute holds excluded',
              Icons.hourglass_bottom_outlined,
              color: _gold,
            ),
            _Stat(
              'Overdue returns',
              '${data.operation('overdueReturns')}',
              'Collected gowns not yet returned',
              Icons.assignment_late_outlined,
              color: data.operation('overdueReturns') > 0
                  ? Colors.red.shade700
                  : _sage,
            ),
          ],
        ),
        gap(22),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ChartHeading(
                'Next appointments',
                'Confirmed upcoming visits · next seven days',
              ),
              if (upcoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    'No confirmed upcoming visits in the next seven days.',
                    style: TextStyle(color: muted),
                  ),
                ),
              for (final row in upcoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        backgroundColor: blush,
                        child: Icon(
                          Icons.calendar_month_outlined,
                          color: rose,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              row['type'],
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _visitTime(row['startAt']),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => onNavigate?.call(PortalPage.appointments),
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: const Text('Manage appointments'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onNavigate?.call(PortalPage.support),
                    icon: const Icon(Icons.support_agent, size: 16),
                    label: const Text('Customer support'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _visitTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(
    ms,
    isUtc: true,
  ).add(const Duration(hours: 8));
  return '${analyticsDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} MYT';
}

class _ReportTable extends StatefulWidget {
  const _ReportTable({super.key, required this.report});
  final BusinessReport report;
  @override
  State<_ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<_ReportTable> {
  String query = '';
  int page = 0;
  @override
  Widget build(BuildContext c) {
    final rows = widget.report.rows
        .where((r) => r.join(' ').toLowerCase().contains(query.toLowerCase()))
        .toList();
    const size = 20;
    final max = rows.isEmpty ? 0 : (rows.length - 1) ~/ size;
    final current = page.clamp(0, max);
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search report rows',
          ),
          onChanged: (v) => setState(() {
            query = v;
            page = 0;
          }),
        ),
        gap(8),
        RecordTable(
          columns: widget.report.headers,
          numericColumns: switch (widget.report.id) {
            'packages' => const {1, 2, 3},
            'collections' => const {3},
            'body-types' => const {1, 2},
            _ => const {},
          },
          connected: true,
          minWidth: 650,
          rows: rows
              .skip(current * size)
              .take(size)
              .map((r) => r.map((v) => cell(v)).toList())
              .toList(),
          empty: 'No records match these filters.',
        ),
        gap(12),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              rows.isEmpty
                  ? '0 matching rows'
                  : '${current * size + 1}–${(current + 1) * size > rows.length ? rows.length : (current + 1) * size} of ${rows.length} matching rows',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const Text(
              'CSV exports all rows in the dated report.',
              style: TextStyle(color: muted, fontSize: 10),
            ),
            IconButton(
              tooltip: 'Previous report page',
              onPressed: current > 0
                  ? () => setState(() => page = current - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next report page',
              onPressed: current < max
                  ? () => setState(() => page = current + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
