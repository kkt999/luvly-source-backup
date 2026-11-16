import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import '../shared/list_controls.dart';
import '../src/contact_validation.dart';
import 'design.dart';

class DirectoryRecord {
  const DirectoryRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.role = '',
    this.active = false,
    this.eventDates = const [],
  });
  final String id, name, email, phone, role;
  final bool active;
  final List<String> eventDates;
  factory DirectoryRecord.fromJson(Map<String, dynamic> data) {
    if (['id', 'name', 'email', 'phone'].any((k) => data[k] is! String) ||
        data['eventDates'] != null &&
            (data['eventDates'] is! List ||
                (data['eventDates'] as List).any(
                  (d) =>
                      d is! String || !RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(d),
                ))) {
      throw const PaymentFailure(
        'Could not verify this directory. Refresh and try again.',
      );
    }
    return DirectoryRecord(
      id: data['id'],
      name: data['name'],
      email: data['email'],
      phone: data['phone'],
      role: data['role'] as String? ?? '',
      active: data['active'] == true,
      eventDates: List<String>.from(data['eventDates'] ?? const []),
    );
  }
  String get displayPhone => formatContactPhone(phone);
  String get displayName => name.isEmpty ? 'Name not recorded' : name;
  String get roleLabel => role == 'manager'
      ? 'Manager'
      : role == 'staff'
      ? 'Staff'
      : 'Unassigned';
}

abstract class DirectoryApi {
  Future<List<DirectoryRecord>> list(bool staffAccounts);
  void close();
}

class HttpDirectoryApi implements DirectoryApi {
  HttpDirectoryApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi(),
      ownsTransport = transport == null;
  final HttpPaymentApi transport;
  final bool ownsTransport;
  @override
  Future<List<DirectoryRecord>> list(bool staffAccounts) async {
    final data = await transport.businessRequest(
      '/v1/directory/${staffAccounts ? 'staff' : 'customers'}',
    );
    if (data['limited'] != false || data['records'] is! List) {
      throw const PaymentFailure(
        'Could not load a complete directory. Refresh or contact the manager.',
      );
    }
    return (data['records'] as List)
        .map((r) => DirectoryRecord.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  void close() {
    if (ownsTransport) transport.close();
  }
}

bool matchesDirectory(
  DirectoryRecord row, {
  required bool staffAccounts,
  String query = '',
  String role = 'All roles',
  String status = 'All accounts',
  String dates = 'All customers',
}) =>
    matchesListSearch(query, [
      row.name,
      row.email,
      row.phone,
      row.displayPhone,
      row.id,
      ...row.eventDates,
    ]) &&
    (!staffAccounts ||
        (role == 'All roles' || role == row.roleLabel) &&
            (status == 'All accounts' || row.active == (status == 'Active'))) &&
    (staffAccounts ||
        dates == 'All customers' ||
        (dates == 'With saved dates'
            ? row.eventDates.isNotEmpty
            : row.eventDates.isEmpty));

class LiveDirectoryPage extends StatefulWidget {
  const LiveDirectoryPage({super.key, required this.staffAccounts, this.api});
  final bool staffAccounts;
  final DirectoryApi? api;
  @override
  State<LiveDirectoryPage> createState() => _LiveDirectoryState();
}

class _LiveDirectoryState extends State<LiveDirectoryPage> {
  late final api = widget.api ?? HttpDirectoryApi();
  late Future<List<DirectoryRecord>> feed = load();
  String query = '',
      role = 'All roles',
      status = 'All accounts',
      dates = 'All customers';
  int page = 0;
  Future<List<DirectoryRecord>> load() {
    final next = api.list(widget.staffAccounts);
    next.ignore();
    return next;
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  void reset() => setState(() {
    query = '';
    role = 'All roles';
    status = 'All accounts';
    dates = 'All customers';
    page = 0;
  });
  void refresh() {
    final next = load();
    setState(() {
      feed = next;
    });
  }

  void view(DirectoryRecord row) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(row.displayName),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Info('Email', row.email.isEmpty ? 'Not recorded' : row.email),
              Info(
                'Phone',
                row.phone.isEmpty ? 'Not recorded' : row.displayPhone,
              ),
              if (widget.staffAccounts) ...[
                Info('Role', row.roleLabel),
                Info('Access status', row.active ? 'Active' : 'Inactive'),
              ] else
                Info(
                  'Saved event dates',
                  row.eventDates.isEmpty
                      ? 'Not set'
                      : row.eventDates.join('\n'),
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
      ],
    ),
  );
  @override
  Widget build(BuildContext c) => PageBody(
    children: [
      Heading(
        widget.staffAccounts ? 'Staff accounts' : 'Customer records',
        widget.staffAccounts
            ? 'View team contacts and access status.'
            : 'View customer contact details and saved event dates.',
        action: OutlinedButton.icon(
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ),
      ListSearchField(
        value: query,
        hint: 'Search name, email or phone',
        onChanged: (v) => setState(() {
          query = v;
          page = 0;
        }),
      ),
      gap(14),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.staffAccounts) ...[
            ListFilterSelect(
              label: 'Role',
              value: role,
              options: const ['All roles', 'Manager', 'Staff', 'Unassigned'],
              onChanged: (v) => setState(() {
                role = v;
                page = 0;
              }),
            ),
            ListFilterSelect(
              label: 'Access status',
              value: status,
              options: const ['All accounts', 'Active', 'Inactive'],
              onChanged: (v) => setState(() {
                status = v;
                page = 0;
              }),
            ),
          ] else
            ListFilterSelect(
              label: 'Event dates',
              value: dates,
              options: const [
                'All customers',
                'With saved dates',
                'No saved dates',
              ],
              onChanged: (v) => setState(() {
                dates = v;
                page = 0;
              }),
            ),
          if (query.isNotEmpty ||
              role != 'All roles' ||
              status != 'All accounts' ||
              dates != 'All customers')
            ResetListFilters(onReset: reset),
        ],
      ),
      gap(20),
      FutureBuilder<List<DirectoryRecord>>(
        future: feed,
        builder: (c, s) {
          if (s.hasError) {
            return Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.error is PaymentFailure
                        ? (s.error as PaymentFailure).message
                        : 'Could not load directory records.',
                  ),
                  TextButton(onPressed: refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = s.data!
              .where(
                (r) => matchesDirectory(
                  r,
                  staffAccounts: widget.staffAccounts,
                  query: query,
                  role: role,
                  status: status,
                  dates: dates,
                ),
              )
              .toList();
          final last = rows.isEmpty ? 0 : (rows.length - 1) ~/ 20,
              current = page.clamp(0, last);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${rows.length} matching ${widget.staffAccounts ? 'accounts' : 'customers'}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              gap(12),
              RecordTable(
                connected: true,
                columns: [
                  'Name',
                  'Contact',
                  widget.staffAccounts ? 'Role / access' : 'Saved event dates',
                  'Action',
                ],
                minWidth: 760,
                empty: s.data!.isEmpty
                    ? widget.staffAccounts
                          ? 'No staff accounts are available.'
                          : 'No customer records are available in your scope.'
                    : 'No records match your search and filters.',
                rows: rows
                    .skip(current * 20)
                    .take(20)
                    .map(
                      (r) => [
                        cell(r.displayName),
                        cell(
                          r.email.isEmpty ? 'Email not recorded' : r.email,
                          sub: r.phone.isEmpty
                              ? 'Phone not recorded'
                              : r.displayPhone,
                        ),
                        widget.staffAccounts
                            ? cell(
                                r.roleLabel,
                                sub: r.active ? 'Active' : 'Inactive',
                              )
                            : cell(
                                r.eventDates.isEmpty
                                    ? 'Not set'
                                    : r.eventDates.join('\n'),
                              ),
                        TextButton(
                          onPressed: () => view(r),
                          child: const Text('View details'),
                        ),
                      ],
                    )
                    .toList(),
              ),
              gap(12),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    rows.isEmpty
                        ? '0 records'
                        : 'Page ${current + 1} of ${last + 1}',
                  ),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: current > 0
                        ? () => setState(() => page = current - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: current < last
                        ? () => setState(() => page = current + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}
