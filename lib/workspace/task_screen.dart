import 'dart:async';
import 'package:flutter/material.dart';
import '../packages/package_api.dart' show packageRequestId;
import '../payments/payment_api.dart' show paymentDateLabel;
import 'workspace_api.dart';
import '../shared/list_controls.dart';

const workTaskTypes = [
  'Fitting preparation',
  'Alteration',
  'Bridal makeup',
  'Front desk',
  'Other',
];
const workTaskStatuses = ['Scheduled', 'In Progress', 'Completed', 'Cancelled'];

class StaffTasksScreen extends StatefulWidget {
  const StaffTasksScreen({
    super.key,
    required this.uid,
    this.api,
    this.initialId,
  });
  final String uid;
  final String? initialId;
  final WorkspaceApi? api;
  @override
  State<StaffTasksScreen> createState() => _StaffTasksState();
}

class _StaffTasksState extends State<StaffTasksScreen>
    with WidgetsBindingObserver {
  late final api = widget.api ?? WorkspaceApi();
  Map<String, dynamic>? data;
  String? error;
  String query = '', status = 'Active', employee = 'All staff';
  bool loading = false, visible = true, opened = false;
  Timer? timer;
  bool get manager => data?['manager'] == true;
  List<Map<String, dynamic>> get records => (data?['records'] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (visible) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    if (visible) load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final value = await api.request('/v1/staff-tasks');
      if (value['uid'] != widget.uid ||
          value['manager'] is! bool ||
          value['staff'] is! List ||
          value['records'] is! List) {
        throw StateError('Invalid task data');
      }
      for (final r in value['records']) {
        if (r is! Map ||
            r['id'] is! String ||
            r['revision'] is! int ||
            r['startAt'] is! int ||
            r['endAt'] is! int ||
            !workTaskStatuses.contains(r['status']) ||
            r['title'] is! String ||
            r['assignedStaffId'] is! String) {
          throw StateError('Invalid task');
        }
      }
      if (!mounted) return;
      setState(() {
        data = value;
        error = null;
        if (employee != 'All staff' &&
            !(value['staff'] as List).any((s) => s['id'] == employee)) {
          employee = 'All staff';
        }
      });
      if (widget.initialId != null && !opened) {
        opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) details(widget.initialId!);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = workspaceError(e);
          data = null;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? old]) async {
    if (!manager) return;
    final staffOptions = List<Map<String, dynamic>>.from(
      (data!['staff'] as List).map((r) => Map<String, dynamic>.from(r)),
    );
    final title = TextEditingController(text: old?['title'] ?? ''),
        description = TextEditingController(text: old?['description'] ?? '');
    final form = GlobalKey<FormState>(), requestId = packageRequestId();
    String? staffUid = old?['assignedStaffId'];
    String type = old?['type'] ?? workTaskTypes.first;
    DateTime day = old == null
        ? workToday().add(const Duration(days: 1))
        : DateTime.parse(old['day']);
    int start = old?['startHour'] ?? 10, end = old?['endHour'] ?? 11;
    bool busy = false;
    String? failure;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => _DialogControllers(
        controllers: [title, description],
        child: StatefulBuilder(
          builder: (c, set) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: Text(
                old == null ? 'Assign a work task' : 'Edit scheduled task',
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MYT · 10:00–13:00 or 14:00–17:00. Assign qualified staff; appointments, other tasks and approved leave are checked again when saving.',
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: title,
                          enabled: !busy,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Task title',
                          ),
                          validator: (v) => (v ?? '').trim().length < 3
                              ? 'Use at least 3 characters.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: type,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Task type',
                          ),
                          items: workTaskTypes
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: busy ? null : (v) => set(() => type = v!),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue:
                              staffOptions.any((r) => r['id'] == staffUid)
                              ? staffUid
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Assign to',
                          ),
                          items: staffOptions
                              .map(
                                (r) => DropdownMenuItem<String>(
                                  value: r['id'],
                                  child: Text(
                                    r['name'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (v) => set(() => staffUid = v),
                          validator: (v) =>
                              v == null ? 'Choose an employee.' : null,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final d = await showDatePicker(
                                    context: c,
                                    initialDate: day.isBefore(workToday())
                                        ? workToday()
                                        : day,
                                    firstDate: workToday(),
                                    lastDate: workToday().add(
                                      const Duration(days: 179),
                                    ),
                                  );
                                  if (d != null) set(() => day = d);
                                },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(workDay(day)),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 160,
                              child: DropdownButtonFormField<int>(
                                initialValue: start,
                                decoration: const InputDecoration(
                                  labelText: 'Start time',
                                ),
                                items: [10, 11, 12, 14, 15, 16]
                                    .map(
                                      (h) => DropdownMenuItem(
                                        value: h,
                                        child: Text('$h:00'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: busy
                                    ? null
                                    : (v) => set(() => start = v!),
                              ),
                            ),
                            SizedBox(
                              width: 160,
                              child: DropdownButtonFormField<int>(
                                initialValue: end,
                                decoration: const InputDecoration(
                                  labelText: 'End time',
                                ),
                                items: [11, 12, 13, 15, 16, 17]
                                    .map(
                                      (h) => DropdownMenuItem(
                                        value: h,
                                        child: Text('$h:00'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: busy
                                    ? null
                                    : (v) => set(() => end = v!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: description,
                          enabled: !busy,
                          maxLength: 1000,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Instructions (optional)',
                          ),
                        ),
                        if (failure != null)
                          Text(
                            failure!,
                            style: TextStyle(
                              color: Theme.of(c).colorScheme.error,
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
                          if (end <= start ||
                              !((start >= 10 && end <= 13) ||
                                  (start >= 14 && end <= 17))) {
                            set(
                              () => failure =
                                  'Choose a time within one morning or afternoon session.',
                            );
                            return;
                          }
                          set(() {
                            busy = true;
                            failure = null;
                          });
                          try {
                            await api.request(
                              old == null
                                  ? '/v1/staff-tasks'
                                  : '/v1/staff-tasks/${old['id']}',
                              body: {
                                'requestId': requestId,
                                'revision': old?['revision'] ?? 0,
                                'title': title.text.trim(),
                                'description': description.text.trim(),
                                'type': type,
                                'staffUid': staffUid,
                                'day': workDay(day),
                                'startHour': start,
                                'endHour': end,
                              },
                            );
                            if (dialog.mounted) {
                              set(() => busy = false);
                              Navigator.pop(dialog, true);
                            }
                          } catch (e) {
                            if (dialog.mounted) {
                              set(() {
                                busy = false;
                                failure = workspaceError(e);
                              });
                            }
                          }
                        },
                  child: Text(busy ? 'Saving…' : 'Save task'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Controllers are owned by the dialog until its exit animation completes.
    if (saved == true) await load();
  }

  Future<void> details(String id) async {
    final matching = records.where((r) => r['id'] == id);
    if (matching.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This task is no longer available to your account.'),
          ),
        );
      }
      return;
    }
    final row = matching.first;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(row['title']),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['type']} · ${row['status']}'),
                const SizedBox(height: 12),
                Text('Assigned to ${row['staffName']}'),
                Text(paymentDateLabel(row['startAt'])),
                Text('End: ${row['endHour']}:00 MYT'),
                const SizedBox(height: 16),
                Text(
                  row['description'].toString().isEmpty
                      ? 'No additional instructions.'
                      : row['description'],
                ),
                if (row['progressNote'] != null) ...[
                  const SizedBox(height: 12),
                  Text('Latest note: ${row['progressNote']}'),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Task progress does not confirm customer attendance, reserve stock or verify a payment.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
          if (manager &&
              row['status'] == 'Scheduled' &&
              row['startAt'] > DateTime.now().millisecondsSinceEpoch)
            TextButton(
              onPressed: () => Navigator.pop(c, 'Edit'),
              child: const Text('Edit assignment'),
            ),
          if (manager && ['Scheduled', 'In Progress'].contains(row['status']))
            TextButton(
              onPressed: () => Navigator.pop(c, 'Cancelled'),
              child: const Text('Cancel task'),
            ),
          if (row['status'] == 'Scheduled' &&
              row['startAt'] <= DateTime.now().millisecondsSinceEpoch)
            FilledButton(
              onPressed: () => Navigator.pop(c, 'In Progress'),
              child: const Text('Start task'),
            ),
          if (row['status'] == 'In Progress')
            FilledButton(
              onPressed: () => Navigator.pop(c, 'Completed'),
              child: const Text('Mark completed'),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'Edit') {
      await edit(row);
      return;
    }
    final note = TextEditingController();
    bool busy = false;
    String? failure;
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => _DialogControllers(
        controllers: [note],
        child: StatefulBuilder(
          builder: (c, set) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: Text('$action — ${row['title']}'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Confirm the actual task progress. Existing appointments and payments are unchanged.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: note,
                        enabled: !busy,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Progress note (optional)',
                        ),
                      ),
                      if (failure != null)
                        Text(
                          failure!,
                          style: TextStyle(
                            color: Theme.of(c).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialog, false),
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            await api.request(
                              '/v1/staff-tasks/$id/status',
                              body: {
                                'revision': row['revision'],
                                'status': action,
                                'note': note.text.trim(),
                              },
                            );
                            if (dialog.mounted) {
                              set(() => busy = false);
                              Navigator.pop(dialog, true);
                            }
                          } catch (e) {
                            if (dialog.mounted) {
                              set(() {
                                busy = false;
                                failure = workspaceError(e);
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
      ),
    );
    if (done == true) await load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = records
        .where(
          (r) =>
              (status == 'All' ||
                  status == 'Active' &&
                      ['Scheduled', 'In Progress'].contains(r['status']) ||
                  r['status'] == status) &&
              (employee == 'All staff' || r['assignedStaffId'] == employee) &&
              query
                  .toLowerCase()
                  .split(RegExp(r'\s+'))
                  .every(
                    (q) =>
                        '${r['title']} ${r['type']} ${r['staffName']} ${r['day']} ${r['status']}'
                            .toLowerCase()
                            .contains(q),
                  ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work tasks'),
        actions: [
          IconButton(
            tooltip: 'Refresh tasks',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (c, size) => ListView(
          padding: EdgeInsets.all(size.maxWidth < 600 ? 16 : 24),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 20,
              runSpacing: 16,
              children: [
                const SizedBox(
                  width: 570,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A clear plan for your team',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Separate work tasks from customer visits. Staff see their own tasks; managers assign and review the team’s work. Times are MYT.',
                      ),
                    ],
                  ),
                ),
                if (manager)
                  FilledButton.icon(
                    onPressed: loading ? null : () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Assign task'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (data != null) ...[
              if (manager)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: (data!['staff'] as List).map((s) {
                    final work = records
                        .where(
                          (r) =>
                              r['assignedStaffId'] == s['id'] &&
                              [
                                'Scheduled',
                                'In Progress',
                              ].contains(r['status']),
                        )
                        .toList();
                    final hours =
                        work.fold<int>(
                          0,
                          (n, r) =>
                              n + (r['endAt'] as int) - (r['startAt'] as int),
                        ) /
                        3600000;
                    return Chip(
                      label: Text(
                        '${s['name']}: ${work.length} active · ${hours.toStringAsFixed(0)} planned hrs',
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search task, staff or date',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ListFilterSelect(
                    label: 'Status',
                    value: status,
                    options: ['Active', 'All', ...workTaskStatuses],
                    onChanged: (v) => setState(() => status = v),
                  ),
                  if (manager)
                    ListFilterSelect(
                      label: 'Employee',
                      value: employee,
                      options: [
                        'All staff',
                        for (final s in data!['staff']) s['id'] as String,
                      ],
                      labels: {
                        for (final s in data!['staff'])
                          s['id'] as String: s['name'] as String,
                      },
                      onChanged: (v) => setState(() => employee = v),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '${rows.length} tasks · updates checked every 20 seconds while visible',
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No tasks match this view.'),
                ),
              for (final r in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runSpacing: 12,
                      spacing: 20,
                      children: [
                        SizedBox(
                          width: size.maxWidth < 600
                              ? size.maxWidth - 100
                              : 360,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['title'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('${r['type']} · ${r['staffName']}'),
                              Text(
                                '${r['day']} · ${r['startHour']}:00–${r['endHour']}:00 MYT',
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Chip(label: Text(r['status'])),
                            TextButton(
                              onPressed: () => details(r['id']),
                              child: const Text('View task'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialogControllers extends StatefulWidget {
  const _DialogControllers({required this.controllers, required this.child});
  final List<TextEditingController> controllers;
  final Widget child;
  @override
  State<_DialogControllers> createState() => _DialogControllersState();
}

class _DialogControllersState extends State<_DialogControllers> {
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }
}
