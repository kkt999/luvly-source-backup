import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'live_directory.dart';
import 'staff_accounts.dart';

class AccessDenied extends StatelessWidget {
  const AccessDenied({super.key});
  @override
  Widget build(BuildContext c) => const Center(
    child: Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, color: rose, size: 32),
          SizedBox(height: 16),
          Text('Manager access required'),
          Text(
            'This page is not available for your role.',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );
}

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});
  @override
  State<RecordsPage> createState() => _RecordsState();
}

class _RecordsState extends State<RecordsPage> {
  String query = '';
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (m.isLive) return const LiveDirectoryPage(staffAccounts: false);
    final brides = m.visibleBrides
        .where(
          (b) => '${b.name} ${b.id} ${b.email}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return PageBody(
      children: [
        Heading(
          'Customer records',
          m.isManager
              ? 'A thoughtful overview of every bride and bridal journey.'
              : 'Read-only profiles for brides linked to your assigned work.',
        ),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search name, ID or email',
        ),
        RecordTable(
          columns: const ['Bride', 'Contact', 'Wedding date', 'Actions'],
          minWidth: 800,
          rows: brides
              .map(
                (b) => [
                  cell(b.name, sub: b.id),
                  cell(b.email, sub: b.phone),
                  cell(dateText(b.wedding)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: Text(b.name),
                            content: SizedBox(
                              width: 480,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Info('Customer ID', b.id),
                                    Info('Email', b.email),
                                    Info('Phone', b.phone),
                                    Info('Wedding', dateText(b.wedding)),
                                    Info(
                                      'Notes',
                                      b.notes.isEmpty
                                          ? 'No additional notes.'
                                          : b.notes,
                                    ),
                                    const Divider(),
                                    Info(
                                      'Appointments',
                                      '${m.visibleAppointments.where((a) => a.brideId == b.id).length} visible',
                                    ),
                                    Info(
                                      'Service tasks',
                                      '${m.visibleTasks.where((t) => t.brideId == b.id).length} visible',
                                    ),
                                    Info(
                                      'Payments received',
                                      money(
                                        m.visiblePayments
                                            .where(
                                              (p) =>
                                                  p.brideId == b.id &&
                                                  p.status == 'Paid',
                                            )
                                            .fold(0.0, (s, p) => s + p.amount),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('View profile'),
                      ),
                      if (m.isManager)
                        IconButton(
                          tooltip: 'Edit ${b.name}',
                          onPressed: () => editForm(
                            c,
                            'Update customer record',
                            [
                              FieldSpec(
                                'notes',
                                'Internal notes',
                                b.notes,
                                multiline: true,
                                optional: true,
                              ),
                            ],
                            (v) => m.saveBride(b, b.membership, v['notes']!),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                    ],
                  ),
                ],
              )
              .toList(),
        ),
        gap(16),
        const Text(
          'Sample personal information only. Access to real customer data must be enforced by the backend.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

void staffForm(BuildContext c, {TeamMember? staff}) {
  final m = PortalScope.of(c);
  if (!m.isManager) return;
  editForm(
    c,
    staff == null ? 'Create demo staff account' : 'Edit staff account',
    [
      FieldSpec('name', 'Full name', staff?.name ?? ''),
      FieldSpec('email', 'Work email', staff?.email ?? ''),
      FieldSpec('phone', 'Phone number', staff?.phone ?? '', optional: true),
      FieldSpec('position', 'Position', staff?.position ?? 'Bridal consultant'),
      FieldSpec(
        'experience',
        'Years of experience',
        '${staff?.experience ?? 0}',
        number: true,
      ),
      FieldSpec(
        'role',
        'Role',
        staff?.role.name ?? 'staff',
        options: const {'staff': 'Staff', 'manager': 'Manager'},
      ),
      FieldSpec(
        'status',
        'Account status',
        staff?.active == false ? 'Inactive' : 'Active',
        options: choices(['Active', 'Inactive']),
      ),
    ],
    (v) => m.saveStaff(
      TeamMember(
        staff?.id ?? 'S${100 + m.team.length}',
        v['name']!,
        v['email']!,
        v['role'] == 'manager' ? PortalRole.manager : PortalRole.staff,
        active: v['status'] == 'Active',
        phone: v['phone']!,
        position: v['position']!,
        experience: int.parse(v['experience']!),
        joined: staff?.joined ?? m.today,
      ),
      existing: staff,
    ),
    submitLabel: staff == null ? 'Create demo account' : 'Save changes',
  );
}

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffState();
}

class _StaffState extends State<StaffPage> {
  String query = '', status = 'Active';
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (!m.canOpen(PortalPage.staff)) return const AccessDenied();
    if (m.isLive) return const StaffAccountsPage();
    final list = m.team
        .where(
          (s) =>
              (status == 'All accounts' ||
                  (s.active ? 'Active' : 'Inactive') == status) &&
              '${s.name} ${s.email}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return PageBody(
      children: [
        Heading(
          'Staff accounts',
          'Manage your team, roles and workload.',
          action: FilledButton.icon(
            onPressed: m.isLive ? null : () => staffForm(c),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add staff account'),
          ),
        ),
        ResponsiveGrid(
          children: [
            Metric(
              'Team members',
              '${m.team.length}',
              'Staff and managers',
              Icons.groups_outlined,
            ),
            Metric(
              'Active accounts',
              '${m.team.where((s) => s.active).length}',
              'Available for assignment',
              Icons.verified_user_outlined,
            ),
            Metric(
              'Unassigned tasks',
              '${m.tasks.where((t) => t.staffId == null).length}',
              'Review in Customer rentals',
              Icons.assignment_ind_outlined,
            ),
          ],
        ),
        gap(26),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search team member',
          filters: [
            filterSelect(status, [
              'Active',
              'Inactive',
              'All accounts',
            ], (v) => setState(() => status = v)),
          ],
        ),
        RecordTable(
          columns: const [
            'Team member',
            'Role',
            'Status',
            'Active tasks',
            'Appointments',
            'Action',
          ],
          rows: list
              .map(
                (s) => [
                  cell(s.name, sub: s.email),
                  Pill(s.role == PortalRole.manager ? 'Manager' : 'Staff'),
                  Pill(s.active ? 'Active' : 'Inactive'),
                  cell(
                    '${m.tasks.where((t) => t.staffId == s.id && !['Completed', 'Cancelled'].contains(t.status)).length}',
                  ),
                  cell(
                    '${m.appointments.where((a) => a.staffId == s.id && a.status == 'Confirmed').length}',
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: c,
                      builder: (d) => AlertDialog(
                        title: Text(s.name),
                        content: SizedBox(
                          width: 420,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Pill(s.active ? 'Active' : 'Inactive'),
                                gap(),
                                Info('Employee ID', s.id),
                                Info('Email', s.email),
                                Info(
                                  'Phone',
                                  s.phone.isEmpty ? 'Not recorded' : s.phone,
                                ),
                                Info('Position', s.position),
                                Info('Role', s.role.name),
                                Info('Joined', dateText(s.joined)),
                                Info('Experience', '${s.experience} years'),
                                const Text(
                                  'Use My availability for workload and schedule management.',
                                  style: TextStyle(color: muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('Close'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(d);
                              staffForm(c, staff: s);
                            },
                            child: const Text('Edit staff'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('View details'),
                  ),
                ],
              )
              .toList(),
        ),
        gap(16),
        Text(
          m.isLive
              ? 'Staff directory management is not connected yet. Your verified account remains active; this is not a list of all registered accounts.'
              : 'Creating an account only adds a demo team record. No invitation, credentials or authentication account is created. Reassign active work before deactivating an account.',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}
