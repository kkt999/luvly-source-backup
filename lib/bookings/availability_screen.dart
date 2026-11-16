import 'package:flutter/material.dart';
import '../admin/design.dart' show Heading, Panel, muted;
import '../payments/payment_api.dart';
import '../shared/list_controls.dart';
import 'booking_api.dart';
import 'booking_repository.dart';
import 'schedule_calendar.dart';
import 'staff_scheduling_screen.dart';

class LiveAvailabilityScreen extends StatefulWidget {
  const LiveAvailabilityScreen({
    super.key,
    this.transport,
    this.onAppointments,
    this.now,
    this.manager = false,
  });
  final HttpPaymentApi? transport;
  final VoidCallback? onAppointments;
  final DateTime Function()? now;
  final bool manager;
  @override
  State<LiveAvailabilityScreen> createState() => _LiveAvailabilityState();
}

class _LiveAvailabilityState extends State<LiveAvailabilityScreen> {
  late final api = widget.transport ?? HttpPaymentApi();
  late DateTime day, month;
  ScheduleMonth? calendar;
  Map<String, dynamic>? data;
  bool monthLoading = false, dayLoading = false, saving = false;
  bool dayPanelBelow = true;
  String? monthError, dayError, notice;
  String query = '', filter = 'All entries';
  String scope = 'default';
  int monthRequest = 0, dayRequest = 0;
  final detailsKey = GlobalKey();
  DateTime get localNow => widget.now?.call() ?? malaysiaNow();
  @override
  void initState() {
    super.initState();
    final n = localNow;
    day = DateTime(n.year, n.month, n.day);
    month = DateTime(n.year, n.month);
    refresh();
  }

  @override
  void dispose() {
    monthRequest++;
    dayRequest++;
    if (widget.transport == null) api.close();
    super.dispose();
  }

  Future<void> loadMonth() async {
    final request = ++monthRequest, requested = scheduleMonth(month);
    setState(() {
      monthLoading = true;
      monthError = null;
      calendar = null;
    });
    try {
      final result = ScheduleMonth.fromJson(
        await api.businessRequest(
          '/v1/appointment-schedule?month=$requested${scope == 'default' ? '' : '&scope=$scope'}',
        ),
        requested,
      );
      if (mounted && request == monthRequest) setState(() => calendar = result);
    } catch (e) {
      if (mounted && request == monthRequest) {
        setState(() => monthError = bookingError(e));
      }
    } finally {
      if (mounted && request == monthRequest) {
        setState(() => monthLoading = false);
      }
    }
  }

  Future<void> loadDay() async {
    final request = ++dayRequest,
        requested = bookingDay(day),
        n = localNow,
        today = DateTime(n.year, n.month, n.day);
    setState(() {
      data = null;
      dayError = null;
      dayLoading = true;
    });
    if (day.isBefore(today) ||
        day.isAfter(today.add(const Duration(days: 179)))) {
      setState(() => dayLoading = false);
      return;
    }
    try {
      final value = await api.businessRequest(
        '/v1/appointment-availability?day=$requested',
      );
      if (value['day'] != requested ||
          value['revision'] is! int ||
          value['revision'] < 0 ||
          value['hours'] is! List ||
          value['assignedHours'] is! List ||
          !value.containsKey('own') ||
          (value['hours'] as List).any((h) => !appointmentHours.contains(h)) ||
          (value['assignedHours'] as List).any(
            (h) => !appointmentHours.contains(h),
          ) ||
          !validScheduleWindow(value['own'])) {
        throw const PaymentFailure(
          'Could not verify this day. Refresh before editing.',
        );
      }
      if (mounted && request == dayRequest) setState(() => data = value);
    } catch (e) {
      if (mounted && request == dayRequest) {
        setState(() => dayError = bookingError(e));
      }
    } finally {
      if (mounted && request == dayRequest) setState(() => dayLoading = false);
    }
  }

  Future<void> refresh() async {
    if (saving) return;
    setState(() => notice = null);
    await Future.wait([loadMonth(), loadDay()]);
  }

  Future<void> select(DateTime next) async {
    if (saving) return;
    setState(() {
      day = next;
      notice = null;
    });
    await loadDay();
    if (mounted && dayPanelBelow && detailsKey.currentContext != null) {
      await Scrollable.ensureVisible(
        detailsKey.currentContext!,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  Future<void> changeMonth(int offset) async {
    if (saving || monthLoading) return;
    final next = DateTime(month.year, month.month + offset),
        n = localNow,
        today = DateTime(n.year, n.month, n.day);
    final selected = next.year == today.year && next.month == today.month
        ? today
        : next;
    setState(() {
      month = next;
      day = selected;
      notice = null;
    });
    await refresh();
  }

  Future<void> today() async {
    final n = localNow;
    setState(() {
      day = DateTime(n.year, n.month, n.day);
      month = DateTime(n.year, n.month);
    });
    await refresh();
  }

  Future<void> edit({bool restore = false}) async {
    if (saving || calendar?.editable(day) != true) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StaffSchedulingScreen(api: api, day: day, requestOnOpen: !restore),
      ),
    );
    if (mounted) await refresh();
  }

  void visitDetails(ScheduleVisit visit) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(visit.name.isEmpty ? 'Assigned visit' : visit.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(visit.type),
          if (visit.assignedStaffName.isNotEmpty)
            Text('Assigned to ${visit.assignedStaffName}'),
          const SizedBox(height: 8),
          Text('${scheduleDate(visit.start)} · ${visit.time} MYT'),
          const SizedBox(height: 8),
          Text(visit.statusLabel),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
        if (widget.onAppointments != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              widget.onAppointments!();
            },
            child: const Text('Open Appointments'),
          ),
        if (widget.manager &&
            visit.revision != null &&
            ['Confirmed', 'AwaitingPayment'].contains(visit.status))
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await reassignScheduleVisit(context, api, visit);
              if (mounted) await refresh();
            },
            child: const Text('Reassign appointment'),
          ),
      ],
    ),
  );
  Widget errorPanel(String message, VoidCallback retry) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton(
          onPressed: saving ? null : retry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
  Widget daily() {
    final entry = calendar?.days[bookingDay(day)],
        editable = calendar?.editable(day) == true;
    final own = data != null ? data!['own'] as Map? : entry?.own;
    final visits = entry?.visits ?? <ScheduleVisit>[];
    final slots = data == null ? <int>[] : List<int>.from(data!['hours']);
    return Panel(
      key: detailsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scheduleDate(day),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Malaysia time (MYT)',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Text(
            own == null
                ? 'Normal business hours'
                : own['available']
                ? 'Custom available window'
                : 'Unavailable window',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            own == null
                ? '10:00–13:00 · 14:00–17:00'
                : '${scheduleTime(own['startHour'])}–${scheduleTime(own['endHour'])}',
          ),
          const SizedBox(height: 14),
          if (editable)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: data == null || dayLoading || saving
                      ? null
                      : () => edit(),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Request time off'),
                ),
                if (own != null)
                  TextButton(
                    onPressed: data == null || dayLoading || saving
                        ? null
                        : () => edit(restore: true),
                    child: const Text('Manage time off'),
                  ),
              ],
            )
          else
            const Text(
              'Read-only date. Availability can be changed from today through the next 179 days.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          if (dayLoading || saving)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (dayError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: saving ? null : loadDay,
                    child: const Text('Refresh this day'),
                  ),
                ],
              ),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                notice!,
                style: const TextStyle(color: Color(0xFF46665B)),
              ),
            ),
          const Divider(height: 36),
          Text(
            calendar?.scope == 'all'
                ? 'Boutique appointments'
                : 'Your assigned visits',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (visits.isEmpty)
            const Text(
              'No appointments in this view on this date.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          for (final visit in visits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => visitDetails(visit),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visit.time,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(visit.name.isEmpty ? visit.type : visit.name),
                        if (visit.assignedStaffName.isNotEmpty)
                          Text('Assigned to ${visit.assignedStaffName}'),
                        Text(
                          '${visit.type} · ${visit.statusLabel}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (editable) ...[
            const Divider(height: 30),
            const Text(
              'Bookable boutique times',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (data == null)
              const Text(
                'Refresh this day to check bookable times.',
                style: TextStyle(color: muted, fontSize: 12),
              )
            else if (slots.isEmpty)
              const Text(
                'No future bookable times on this date.',
                style: TextStyle(color: muted, fontSize: 12),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in slots) Chip(label: Text(scheduleTime(h))),
                ],
              ),
            const SizedBox(height: 10),
            const Text(
              'Boutique times consider all staff and existing bookings, not just your own availability.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = localNow,
        first = DateTime(n.year, n.month),
        last = DateTime(n.year, n.month, n.day).add(const Duration(days: 179));
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: saving || monthLoading || !month.isAfter(first)
              ? null
              : () => changeMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${scheduleMonths[month.month - 1]} ${month.year}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed:
              saving ||
                  monthLoading ||
                  DateTime(
                    month.year,
                    month.month + 1,
                  ).isAfter(DateTime(last.year, last.month))
              ? null
              : () => changeMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
        OutlinedButton(
          onPressed: saving ? null : today,
          child: const Text('Today'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) => ListView(
        padding: EdgeInsets.all(bounds.maxWidth < 700 ? 18 : 26),
        children: [
          Heading(
            'My availability',
            'Appointments, approved time off and team coverage.',
            action: OutlinedButton.icon(
              onPressed: saving || monthLoading ? null : refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh schedule'),
            ),
          ),
          const Text(
            'Normal hours · 10:00–13:00 and 14:00–17:00 MYT. Time off requires manager approval; assigned appointments remain protected.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          controls,
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : () => edit(restore: true),
                icon: const Icon(Icons.people_outline),
                label: Text(
                  widget.manager ? 'Team scheduling' : 'My time-off requests',
                ),
              ),
              if (calendar?.canViewAll == true)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'all',
                      label: Text('All appointments'),
                    ),
                    ButtonSegment(value: 'own', label: Text('My assignments')),
                  ],
                  selected: {calendar!.scope},
                  onSelectionChanged: monthLoading
                      ? null
                      : (values) {
                          setState(
                            () => scope = values.single == 'all'
                                ? 'default'
                                : 'own',
                          );
                          loadMonth();
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: ListSearchField(
                  value: query,
                  hint: 'Search calendar entries',
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              ListFilterSelect(
                label: 'Calendar entries',
                value: filter,
                options: const ['All entries', 'Appointments', 'Unavailable'],
                onChanged: (v) => setState(() => filter = v),
              ),
              if (query.isNotEmpty || filter != 'All entries')
                ResetListFilters(
                  onReset: () => setState(() {
                    query = '';
                    filter = 'All entries';
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (monthLoading) const LinearProgressIndicator(),
          if (monthError != null) errorPanel(monthError!, refresh),
          if (calendar != null) ...[
            if (query.isNotEmpty || filter != 'All entries')
              Builder(
                builder: (context) {
                  final view = ScheduleCalendar(
                    month: month,
                    selected: day,
                    data: calendar!,
                    query: query,
                    filter: filter,
                    onSelect: select,
                  );
                  final count = calendar!.days.values.fold<int>(
                    0,
                    (n, d) =>
                        n +
                        view.visits(d).length +
                        (view.showAbsence(d) ? 1 : 0) +
                        (view.showCustomHours(d) ? 1 : 0),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      count == 0
                          ? 'No matching calendar entries. Select any date to view its full schedule.'
                          : '$count matching calendar entries',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  );
                },
              ),
            LayoutBuilder(
              builder: (context, b) {
                dayPanelBelow =
                    b.maxWidth < 980 ||
                    MediaQuery.textScalerOf(context).scale(12) >= 18;
                final cal = Panel(
                  padding: const EdgeInsets.all(10),
                  child: ScheduleCalendar(
                    month: month,
                    selected: day,
                    data: calendar!,
                    query: query,
                    filter: filter,
                    onSelect: select,
                  ),
                );
                return !dayPanelBelow
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cal),
                          const SizedBox(width: 18),
                          SizedBox(width: 320, child: daily()),
                        ],
                      )
                    : Column(
                        children: [cal, const SizedBox(height: 18), daily()],
                      );
              },
            ),
            const SizedBox(height: 14),
            const Text(
              'Select a date for appointment details. A pending time-off request does not change availability.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
