import 'package:flutter/material.dart';
import '../admin/design.dart' show Panel, Heading, muted;
import '../payments/payment_api.dart';
import '../packages/package_api.dart' show packageRequestId;
import '../workspace/staff_roles.dart';
import 'booking_api.dart';
import 'booking_repository.dart' show makeupTrial;
import 'schedule_calendar.dart';

class StaffSchedulingScreen extends StatefulWidget {
  const StaffSchedulingScreen({
    super.key,
    required this.api,
    required this.day,
    this.requestOnOpen = false,
  });
  final HttpPaymentApi api;
  final DateTime day;
  final bool requestOnOpen;
  @override
  State<StaffSchedulingScreen> createState() => _StaffSchedulingState();
}

class _StaffSchedulingState extends State<StaffSchedulingScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true, opened = false;
  bool get manager => data?['manager'] == true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.api.businessRequest('/v1/staff-scheduling');
      if (value['uid'] is! String ||
          value['manager'] is! bool ||
          value['requests'] is! List ||
          value['policy'] is! Map ||
          value['staff'] is! List) {
        throw const PaymentFailure(
          'Could not verify scheduling access. Refresh before continuing.',
        );
      }
      if (!mounted) return;
      setState(() => data = value);
      if (widget.requestOnOpen && !opened) {
        opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) request();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not load staff scheduling. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit(
    String title,
    List<Widget> Function(StateSetter) fields,
    Future<void> Function() save,
  ) async {
    final form = GlobalKey<FormState>();
    var busy = false;
    String? failure;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (context, set) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...fields(set),
                      if (failure != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            failure!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        set(() {
                          busy = true;
                          failure = null;
                        });
                        try {
                          await save();
                          if (dialog.mounted) {
                            set(() => busy = false);
                            Navigator.pop(dialog, true);
                          }
                        } catch (e) {
                          if (dialog.mounted) {
                            set(() {
                              busy = false;
                              failure = e is PaymentFailure
                                  ? e.message
                                  : 'Could not save. Please retry.';
                            });
                          }
                        }
                      },
                child: Text(busy ? 'Saving…' : 'Confirm'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> request() async {
    if (loading || error != null || data == null) return;
    var start = 10, end = 17, reason = '';
    final id = packageRequestId();
    await edit(
      'Request time off',
      (set) => [
        Text(
          scheduleDate(widget.day),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your hours stay available until a manager approves. Appointment conflicts and team coverage are checked again at approval.',
        ),
        const SizedBox(height: 16),
        for (final isStart in [true, false])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<int>(
              initialValue: isStart ? start : end,
              decoration: InputDecoration(
                labelText: '${isStart ? 'Start' : 'End'} time (MYT)',
              ),
              items: [
                for (var h = isStart ? 9 : 10; h <= (isStart ? 17 : 18); h++)
                  DropdownMenuItem(value: h, child: Text(scheduleTime(h))),
              ],
              onChanged: (v) => set(() {
                if (isStart) {
                  start = v!;
                } else {
                  end = v!;
                }
              }),
              validator: (_) =>
                  start >= end ? 'End time must be after start time.' : null,
            ),
          ),
        TextFormField(
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason'),
          onChanged: (v) => reason = v,
          validator: (v) => (v?.trim().length ?? 0) < 5
              ? 'Enter a brief reason (at least 5 characters).'
              : null,
        ),
      ],
      () async {
        await widget.api.businessRequest(
          '/v1/staff-time-off',
          body: {
            'requestId': id,
            'day': bookingDay(widget.day),
            'startHour': start,
            'endHour': end,
            'reason': reason.trim(),
          },
        );
      },
    );
  }

  Future<void> review(Map r, String action) async {
    var note = '';
    const labels = {
      'Approve': 'Approve time off',
      'Reject': 'Reject time-off request',
      'Withdraw': 'Withdraw time-off request',
      'CancelApproved': 'Cancel approved time off',
    };
    await edit(
      '${labels[action]}?',
      (_) => [
        Text(
          '${r['staffName']} · ${r['day']}\n${scheduleTime(r['startHour'])}–${scheduleTime(r['endHour'])}',
        ),
        const SizedBox(height: 12),
        Text(
          action == 'Approve'
              ? 'Approval checks the latest appointments and minimum staffing before making this employee unavailable.'
              : action == 'CancelApproved'
              ? 'Cancel the approved absence and restore normal hours for this window.'
              : 'This does not change any customer appointment.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Review note (optional)',
          ),
          onChanged: (v) => note = v,
        ),
      ],
      () async {
        await widget.api.businessRequest(
          '/v1/staff-time-off/${r['id']}/review',
          body: {'action': action, 'revision': r['revision'], 'note': note},
        );
      },
    );
  }

  Future<void> profile(Map employee) async {
    final old = employee['profile'] as Map?;
    String? role = old?['jobRole'] as String?;
    String jobTitle = old?['jobTitle'] as String? ?? '';
    final services = Set<String>.from(old?['serviceTypes'] ?? []);
    await edit(
      'Staff scheduling responsibilities',
      (set) => [
        Text(
          '${employee['name']}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Work role'),
          validator: (v) =>
              v == null ? 'Choose this employee’s work role.' : null,
          items: [
            for (final r in staffWorkRoles.entries)
              DropdownMenuItem(value: r.key, child: Text(r.value)),
          ],
          onChanged: (v) => set(() => role = v!),
        ),
        if (role == otherStaffRole) ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: jobTitle,
            decoration: const InputDecoration(labelText: 'Job title'),
            onChanged: (value) => jobTitle = value,
            validator: validateStaffJobTitle,
          ),
        ],
        const SizedBox(height: 16),
        const Text('Services this employee is qualified to deliver'),
        for (final service in staffServices)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(service),
            value: services.contains(service),
            onChanged: (v) => set(() {
              if (v == true) {
                services.add(service);
              } else {
                services.remove(service);
              }
            }),
          ),
        const Text(
          'A front desk role grants the calendar overview, not service qualifications or manager permissions. Existing future assignments must remain supported.',
        ),
      ],
      () async {
        await widget.api.businessRequest(
          '/v1/staff-scheduling/profile',
          body: {
            'uid': employee['uid'],
            'jobRole': role,
            if (role == otherStaffRole) 'jobTitle': jobTitle.trim(),
            'serviceTypes': services.toList(),
            'revision': old?['revision'] ?? 0,
          },
        );
      },
    );
  }

  Future<void> policy() async {
    final p = data!['policy'] as Map, count = (data!['staff'] as List).length;
    var minimum = p['minimumOnDuty'] as int,
        strict = p['requireServiceAssignments'] == true;
    final roles = <String, dynamic>{
          for (final r in schedulingRoles.keys) r: p['minimumByRole']?[r] ?? 0,
        },
        services = <String, dynamic>{
          for (final s in staffServices) s: p['minimumByService']?[s] ?? 0,
        };
    Widget number(String label, int value, int min, ValueChanged<int> change) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            initialValue: value,
            decoration: InputDecoration(labelText: label),
            items: [
              for (var n = min; n <= (count > value ? count : value); n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (v) => change(v!),
          ),
        );
    await edit(
      'Minimum staffing',
      (set) => [
        const Text(
          'The minimum number on duty, including booked employees. Service minimums count qualified employees, not front desk cover.',
        ),
        const SizedBox(height: 16),
        number(
          'Total employees on duty',
          minimum,
          1,
          (v) => set(() => minimum = v),
        ),
        for (final r in schedulingRoles.entries)
          number(
            '${r.value} minimum',
            roles[r.key] as int? ?? 0,
            0,
            (v) => set(() => roles[r.key] = v),
          ),
        for (final s in staffServices)
          number(
            '$s minimum',
            services[s] as int? ?? 0,
            0,
            (v) => set(() => services[s] = v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Require explicit service assignments'),
          subtitle: const Text(
            'Configure every active employee first. Unconfigured new employees will not receive bookings.',
          ),
          value: strict,
          onChanged: (v) => set(() => strict = v),
        ),
        if (!strict)
          const Text(
            'Existing unconfigured accounts retain their previous booking eligibility until this is enabled.',
          ),
      ],
      () async {
        await widget.api.businessRequest(
          '/v1/staff-scheduling/policy',
          body: {
            'revision': p['revision'],
            'minimumOnDuty': minimum,
            'minimumByRole': roles,
            'minimumByService': services,
            'requireServiceAssignments': strict,
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff scheduling')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Heading(
          manager ? 'Team scheduling' : 'My time off',
          'Request time off without disrupting confirmed visits.',
          action: OutlinedButton.icon(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Panel(child: Text(error!)),
        if (!loading && error == null && data != null) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected date · ${scheduleDate(widget.day)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: request,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Request time off'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manager ? 'Time-off requests' : 'My requests',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((data!['requests'] as List).isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Text('No time-off requests yet.'),
                  ),
                for (final r in data!['requests'] as List)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['staffName']} · ${r['state']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${r['day']} · ${scheduleTime(r['startHour'])}–${scheduleTime(r['endHour'])} MYT',
                        ),
                        Text('${r['reason']}'),
                        if ((r['reviewNote'] ?? '').isNotEmpty)
                          Text(
                            'Review: ${r['reviewNote']}',
                            style: const TextStyle(color: muted),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (manager && r['state'] == 'Pending') ...[
                              FilledButton(
                                onPressed: () => review(r, 'Approve'),
                                child: const Text('Approve'),
                              ),
                              OutlinedButton(
                                onPressed: () => review(r, 'Reject'),
                                child: const Text('Reject'),
                              ),
                            ],
                            if (r['uid'] == data!['uid'] &&
                                r['state'] == 'Pending')
                              TextButton(
                                onPressed: () => review(r, 'Withdraw'),
                                child: const Text('Withdraw'),
                              ),
                            if (manager && r['state'] == 'Approved')
                              TextButton(
                                onPressed: () => review(r, 'CancelApproved'),
                                child: const Text('Cancel approved time off'),
                              ),
                          ],
                        ),
                        const Divider(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (manager) ...[
            for (final e in data!['exceptions'] as List? ?? [])
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e['staffName']} · existing schedule exception',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${e['day']} · ${scheduleTime(e['startHour'])}–${scheduleTime(e['endHour'])}',
                      ),
                      TextButton(
                        onPressed: () => edit(
                          'Restore normal hours?',
                          (_) => [
                            const Text(
                              'Remove this existing exception. Customer appointments remain unchanged.',
                            ),
                          ],
                          () async {
                            await widget.api.businessRequest(
                              '/v1/staff-scheduling/restore',
                              body: {
                                'staffUid': e['staffUid'],
                                'day': e['day'],
                                'revision': e['revision'],
                              },
                            );
                          },
                        ),
                        child: const Text('Restore normal hours'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Team responsibilities',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: policy,
                        child: const Text('Minimum staffing'),
                      ),
                    ],
                  ),
                  for (final e in data!['staff'] as List)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${e['name']}'),
                      subtitle: Text(
                        e['profile'] == null
                            ? 'Not configured'
                            : [
                                staffWorkRoleLabel(
                                  e['profile']['jobRole'],
                                  e['profile']['jobTitle'],
                                ),
                                ...(e['profile']['serviceTypes'] as List),
                              ].join(' · '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Configure responsibilities',
                        onPressed: () => profile(e),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    ),
  );
}

Future<void> reassignScheduleVisit(
  BuildContext context,
  HttpPaymentApi api,
  ScheduleVisit visit,
) async {
  try {
    final data = await api.businessRequest('/v1/staff-scheduling');
    if (!context.mounted || data['manager'] != true) return;
    String? chosen;
    final candidates = (data['staff'] as List)
        .where(
          (e) => (e['profile']?['serviceTypes'] as List? ?? []).contains(
            visit.type == makeupTrial ? 'Bridal Makeup' : visit.type,
          ),
        )
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Reassign appointment'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${visit.name} · ${visit.type}\n${scheduleDate(visit.start)} · ${visit.time} MYT',
                ),
                const SizedBox(height: 16),
                if (candidates.isEmpty)
                  const Text(
                    'Configure qualified staff in Team scheduling first.',
                  )
                else
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Qualified employee',
                    ),
                    items: [
                      for (final e in candidates)
                        DropdownMenuItem(
                          value: e['uid'] as String,
                          child: Text(e['name'] as String),
                        ),
                    ],
                    onChanged: (v) => set(() => chosen = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: chosen == null ? null : () => Navigator.pop(c, true),
              child: const Text('Confirm reassignment'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await api.businessRequest(
        '/v1/appointments/${visit.id}/assign',
        body: {'staffUid': chosen, 'revision': visit.revision},
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PaymentFailure
                ? e.message
                : 'Could not reassign this appointment. Refresh and retry.',
          ),
        ),
      );
    }
  }
}
