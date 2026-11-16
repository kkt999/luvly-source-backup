import 'dart:math';
import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import '../src/contact_validation.dart';
import '../shared/list_controls.dart';
import '../src/malaysia_phone_field.dart';
import '../workspace/staff_roles.dart';
import 'design.dart';

String staffRequestId() => List.generate(
  24,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String staffAccountError(Object e) => e is PaymentFailure
    ? e.message
    : 'Could not complete this request. Refresh the account before trying again.';

class StaffAccount {
  StaffAccount(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String? ?? '';
  String get email => data['email'] as String? ?? '';
  String get phone => data['phone'] as String? ?? '';
  String get role => data['role'] as String? ?? '';
  String get jobRole => data['jobRole'] as String? ?? '';
  String? get jobTitle => data['jobTitle'] as String?;
  String get workLabel => staffWorkRoleLabel(jobRole, jobTitle);
  String get displayPhone => formatContactPhone(phone);
  String get roleLabel => role == 'manager'
      ? 'Manager'
      : role == 'staff'
      ? 'Staff'
      : 'Unassigned';
  bool get active => data['active'] == true;
  bool get pendingSetup => !active && data['pendingActivation'] == true;
  bool get needsSetupEmail => pendingSetup && data['invitationState'] != 'Sent';
  bool get syncing => data['syncRequired'] == true;
  int get revision => data['revision'] as int? ?? 0;
  int get profileRevision => data['profileRevision'] as int? ?? 0;
  List<String> get services => List<String>.from(data['serviceTypes'] ?? []);
  String get invitation => switch (data['invitationState']) {
    'Sent' => 'Email sent to mail server',
    'Sending' => 'Email delivery needs review',
    'ReviewRequired' => 'Email delivery needs review',
    _ => 'Setup email not sent',
  };
  String get status => syncing
      ? 'Sync required'
      : active
      ? 'Active'
      : pendingSetup
      ? (needsSetupEmail ? 'Pending setup' : 'Ready to activate')
      : 'Inactive';
}

abstract class StaffAccountsApi {
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  });
  void close();
}

class HttpStaffAccountsApi implements StaffAccountsApi {
  HttpStaffAccountsApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi(),
      owns = transport == null;
  final HttpPaymentApi transport;
  final bool owns;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async => Map<String, dynamic>.from(
    await transport.businessRequest('/v1/staff-accounts$path', body: body),
  );
  @override
  void close() {
    if (owns) transport.close();
  }
}

class StaffAccountsPage extends StatefulWidget {
  const StaffAccountsPage({super.key, this.api});
  final StaffAccountsApi? api;
  @override
  State<StaffAccountsPage> createState() => _StaffAccountsPageState();
}

class _StaffAccountsPageState extends State<StaffAccountsPage> {
  late final api = widget.api ?? HttpStaffAccountsApi();
  late Future<Map<String, dynamic>> feed = load();
  String query = '', status = 'All accounts', role = 'All roles';
  int page = 0;
  Future<Map<String, dynamic>> load() async {
    final data = await api.request('');
    if (data['limited'] != false ||
        data['records'] is! List ||
        data['actorUid'] is! String) {
      throw const PaymentFailure(
        'Could not verify the complete staff list. Refresh before making changes.',
      );
    }
    return data;
  }

  void refresh() => setState(() {
    feed = load();
    feed.ignore();
  });
  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> open(String id, Map<String, dynamic> contextData) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffAccountDetails(
          api: api,
          id: id,
          actorUid: contextData['actorUid'],
          canMail: contextData['canSendSetupEmail'] == true,
        ),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> create(Map<String, dynamic> data) async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffAccountEditor(api: api),
    );
    if (!mounted) return;
    refresh();
    if (id != null) {
      notice(
        context,
        'Staff account created. Send the setup email, then activate portal access.',
      );
      await open(id, data);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: feed,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData) {
        return PageBody(
          children: [
            const Heading(
              'Staff accounts',
              'Manage team access and responsibilities.',
            ),
            if (snapshot.hasError)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(staffAccountError(snapshot.error!)),
                    TextButton(onPressed: refresh, child: const Text('Retry')),
                  ],
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
        );
      }
      final data = snapshot.data!,
          all = (data['records'] as List)
              .map((r) => StaffAccount(Map<String, dynamic>.from(r)))
              .toList();
      final rows = all
          .where(
            (r) =>
                matchesListSearch(query, [
                  r.name,
                  r.email,
                  r.phone,
                  r.displayPhone,
                  r.workLabel,
                ]) &&
                (status == 'All accounts' || r.status == status) &&
                (role == 'All roles' || r.roleLabel == role),
          )
          .toList();
      final last = rows.isEmpty ? 0 : (rows.length - 1) ~/ 20,
          current = page.clamp(0, last);
      return PageBody(
        children: [
          Heading(
            'Staff accounts',
            'The right access for every member of your team.',
            action: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                FilledButton.icon(
                  onPressed: () => create(data),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add staff account'),
                ),
              ],
            ),
          ),
          ResponsiveGrid(
            children: [
              Metric(
                'Active accounts',
                '${all.where((r) => r.active).length}',
                'Can access the portal',
                Icons.verified_user_outlined,
                connected: true,
              ),
              Metric(
                'Awaiting activation',
                '${all.where((r) => r.pendingSetup && !r.syncing).length}',
                'New accounts awaiting activation',
                Icons.person_off_outlined,
                connected: true,
              ),
              Metric(
                'Needs review',
                '${all.where((r) => r.syncing || r.data['sessionReviewRequired'] == true).length}',
                'Access synchronisation',
                Icons.sync_problem_outlined,
                connected: true,
              ),
            ],
          ),
          gap(20),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListSearchField(
                  value: query,
                  hint: 'Search name, email or work role',
                  onChanged: (v) => setState(() {
                    query = v;
                    page = 0;
                  }),
                ),
                gap(12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ListFilterSelect(
                      label: 'Access',
                      value: status,
                      options: const [
                        'All accounts',
                        'Active',
                        'Pending setup',
                        'Ready to activate',
                        'Inactive',
                        'Sync required',
                      ],
                      onChanged: (v) => setState(() {
                        status = v;
                        page = 0;
                      }),
                    ),
                    ListFilterSelect(
                      label: 'System role',
                      value: role,
                      options: const [
                        'All roles',
                        'Staff',
                        'Manager',
                        'Unassigned',
                      ],
                      onChanged: (v) => setState(() {
                        role = v;
                        page = 0;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
          gap(20),
          Text(
            '${rows.length} matching accounts',
            style: const TextStyle(color: muted),
          ),
          gap(10),
          RecordTable(
            connected: true,
            minWidth: 920,
            columns: const [
              'Team member',
              'Contact',
              'Responsibilities',
              'Access',
              'Action',
            ],
            empty: 'No staff accounts match these filters.',
            rows: rows
                .skip(current * 20)
                .take(20)
                .map(
                  (r) => [
                    cell(
                      r.name.isEmpty ? 'Name not recorded' : r.name,
                      sub: r.id == data['actorUid']
                          ? '${r.roleLabel} · You'
                          : r.roleLabel,
                    ),
                    cell(
                      r.email.isEmpty
                          ? 'Open details to check login email'
                          : r.email,
                      sub: r.displayPhone,
                    ),
                    cell(
                      r.workLabel,
                      sub: r.services.isEmpty
                          ? 'No customer services assigned'
                          : r.services.join(' · '),
                    ),
                    Pill(r.status),
                    TextButton(
                      onPressed: () => open(r.id, data),
                      child: const Text('Manage account'),
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
          gap(),
          const Text(
            'Deactivate access rather than delete accounts. Existing appointments, payments and service history are kept.',
            style: TextStyle(color: muted),
          ),
        ],
      );
    },
  );
}

class StaffAccountDetails extends StatefulWidget {
  const StaffAccountDetails({
    super.key,
    required this.api,
    required this.id,
    required this.actorUid,
    required this.canMail,
  });
  final StaffAccountsApi api;
  final String id, actorUid;
  final bool canMail;
  @override
  State<StaffAccountDetails> createState() => _StaffAccountDetailsState();
}

class _StaffAccountDetailsState extends State<StaffAccountDetails> {
  late Future<Map<String, dynamic>> feed = widget.api.request('/${widget.id}');
  bool busy = false;
  String? message;
  void refresh() => setState(() {
    feed = widget.api.request('/${widget.id}');
    feed.ignore();
  });
  Future<void> action(
    String path,
    Map<String, dynamic> body,
    String success,
  ) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await widget.api.request(
        '/${widget.id}/$path',
        body: body,
      );
      if (mounted) {
        message = result['syncRequired'] == true
            ? 'Access remains inactive. Authentication sync did not complete. Use Retry access sync.'
            : result['reviewRequired'] == true
            ? 'The email outcome is uncertain. Check with the employee before sending a new email.'
            : result['sessionReviewRequired'] == true
            ? 'Could not finish ending sessions. Please retry.'
            : success;
      }
    } catch (e) {
      if (mounted) message = staffAccountError(e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        refresh();
      }
    }
  }

  Future<void> edit(StaffAccount r) async {
    final saved = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffAccountEditor(api: widget.api, record: r),
    );
    if (mounted && saved != null) {
      message = 'Account details saved.';
      refresh();
    }
  }

  Future<void> status(StaffAccount r) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => StaffStatusDialog(name: r.name, active: !r.active),
    );
    if (note != null && mounted) {
      await action(
        'status',
        {
          'active': !r.active,
          'revision': r.revision,
          'requestId': staffRequestId(),
          'note': note,
        },
        r.active
            ? 'Access deactivated. History has been retained.'
            : 'Staff access activated.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Manage staff account'),
      actions: [
        IconButton(
          tooltip: 'Refresh account',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: feed,
      builder: (context, s) {
        if (s.hasError ||
            s.connectionState != ConnectionState.done ||
            !s.hasData) {
          return Center(
            child: s.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(staffAccountError(s.error!)),
                        TextButton(
                          onPressed: refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          );
        }
        final r = StaffAccount(Map<String, dynamic>.from(s.data!['record'])),
            workload = Map<String, dynamic>.from(s.data!['workload']);
        final self = r.id == widget.actorUid;
        final authReady = s.data!['authAvailable'] == true;
        return PageBody(
          children: [
            Heading(
              r.name.isEmpty ? 'Staff account' : r.name,
              '${r.roleLabel} · ${r.workLabel}',
              action: Pill(r.status),
            ),
            if (message != null) ...[
              Panel(
                color: blush,
                child: Text(message!, key: const ValueKey('account-message')),
              ),
              gap(),
            ],
            if (!authReady) ...[
              const Panel(
                child: Text(
                  'The login account could not be verified. Editing contact details does not repair authentication. Check the backend connection before activation or password setup.',
                ),
              ),
              gap(),
            ],
            if (r.syncing) ...[
              Panel(
                color: blush,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Access is paused until authentication sync completes.',
                    ),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => action('sync', {}, 'Access synchronised.'),
                      icon: const Icon(Icons.sync),
                      label: const Text('Retry access sync'),
                    ),
                  ],
                ),
              ),
              gap(),
            ],
            ResponsiveGrid(
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account & contact',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      gap(),
                      Info(
                        'Login email',
                        r.email.isEmpty ? 'Not available' : r.email,
                      ),
                      Info(
                        'Phone',
                        r.phone.isEmpty ? 'Not recorded' : r.displayPhone,
                      ),
                      Info('System role', r.roleLabel),
                      Info('Work role', r.workLabel),
                      Info(
                        'Eligible services',
                        r.services.isEmpty
                            ? 'None configured'
                            : r.services.join('\n'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy || r.syncing ? null : () => edit(r),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit details & responsibilities'),
                      ),
                    ],
                  ),
                ),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Access & password',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      gap(),
                      Text(r.invitation),
                      gap(8),
                      const Text(
                        'The employee sets their own password through a secure email link. Managers never see or store the password.',
                        style: TextStyle(color: muted),
                      ),
                      gap(),
                      OutlinedButton.icon(
                        onPressed:
                            busy ||
                                r.syncing ||
                                !authReady ||
                                s.data!['authDisabled'] == true ||
                                !widget.canMail
                            ? null
                            : () async {
                                if (await confirm(
                                  context,
                                  'Send password setup email?',
                                  'Send a secure password setup/reset link to ${r.email}? Only the employee receives the link. This does not activate portal access.',
                                )) {
                                  if (mounted) {
                                    await action(
                                      'invite',
                                      {
                                        'requestId': staffRequestId(),
                                        'revision': r.revision,
                                      },
                                      'The mail server accepted the setup email. Ask the employee to check their inbox and spam folder.',
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.mail_outline),
                        label: const Text('Send setup email'),
                      ),
                      if (!widget.canMail)
                        const Text(
                          'Email service is not configured. Contact the system administrator.',
                        ),
                      if (s.data!['authDisabled'] == true)
                        const Text(
                          'Activate the account before sending a new password email.',
                        ),
                      const Divider(),
                      Text(
                        r.active
                            ? 'Deactivation removes portal access and ends login sessions. History is retained.'
                            : r.needsSetupEmail
                            ? 'Send the setup email before activating access.'
                            : 'Confirm the employee’s details and responsibilities before granting access.',
                      ),
                      gap(10),
                      FilledButton.icon(
                        onPressed:
                            busy ||
                                r.syncing ||
                                !authReady ||
                                self ||
                                r.needsSetupEmail
                            ? null
                            : () => status(r),
                        icon: Icon(
                          r.active
                              ? Icons.person_off_outlined
                              : Icons.verified_user_outlined,
                        ),
                        label: Text(
                          r.active ? 'Deactivate access' : 'Activate access',
                        ),
                      ),
                      if (self)
                        const Text('You cannot deactivate your own account.'),
                      if (r.data['sessionReviewRequired'] == true) ...[
                        gap(),
                        const Text(
                          'Session revocation needs review. Role permissions are already checked against the current staff record.',
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => action(
                                  'sessions',
                                  {},
                                  'Existing login sessions ended.',
                                ),
                          child: const Text('Retry ending sessions'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            gap(20),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Work to hand over',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  gap(8),
                  Text(
                    '${workload['appointments']} unfinished appointments · ${workload['tasks']} assigned tasks · ${workload['tickets']} assigned support tickets',
                  ),
                  const Text(
                    'Deactivation is blocked while assigned work remains, or when required staffing cover would be lost. Reassign or properly complete the work first.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            gap(16),
            Panel(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Account change history'),
                children: [
                  for (final h
                      in ((r.data['history'] as List?) ?? []).reversed.take(40))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(switch (h['action']) {
                        'Created inactive account' => 'Created staff account',
                        final String action => action,
                        _ => 'Account updated',
                      }),
                      subtitle: Text(
                        '${h['at'] is int ? paymentDateLabel(h['at']) : 'Time not recorded'}${h['note'] == null ? '' : '\n${h['note']}'}',
                      ),
                    ),
                  if (((r.data['history'] as List?) ?? []).isEmpty)
                    const Text('No account-management changes recorded yet.'),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class StaffAccountEditor extends StatefulWidget {
  const StaffAccountEditor({super.key, required this.api, this.record});
  final StaffAccountsApi api;
  final StaffAccount? record;
  @override
  State<StaffAccountEditor> createState() => _StaffAccountEditorState();
}

class _StaffAccountEditorState extends State<StaffAccountEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.record?.name ?? ''),
      email = TextEditingController(text: widget.record?.email ?? ''),
      phone = TextEditingController(
        text: malaysiaNationalInput(widget.record?.phone ?? ''),
      ),
      title = TextEditingController(text: widget.record?.jobTitle ?? '');
  late String job = widget.record?.jobRole ?? '';
  late final services = {...?widget.record?.services};
  String requestId = staffRequestId();
  bool busy = false;
  String? error;
  Map<String, dynamic>? submitted;
  bool get creating => widget.record == null;
  bool get locked => busy || creating && submitted != null;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    title.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final body =
        submitted ??
        {
          'name': name.text.trim(),
          'phone': formatContactPhone(phone.text),
          'role': widget.record?.role ?? 'staff',
          'jobRole': job,
          if (job == otherStaffRole) 'jobTitle': title.text.trim(),
          'serviceTypes': services.toList(),
          if (creating) ...{
            'email': email.text.trim(),
            'requestId': requestId,
          } else ...{
            'revision': widget.record!.revision,
            'profileRevision': widget.record!.profileRevision,
          },
        };
    setState(() {
      busy = true;
      error = null;
      if (creating) submitted = body;
    });
    try {
      final result = await widget.api.request(
        creating ? '' : '/${widget.record!.id}',
        body: body,
      );
      if (mounted) {
        Navigator.pop(
          context,
          creating ? result['id'] as String : widget.record!.id,
        );
      }
    } catch (e) {
      if (mounted) {
        final canCorrect =
            e is PaymentFailure &&
            (e.code == 'STAFF_EMAIL_IN_USE' ||
                e.code == 'INVALID_STAFF_ACCOUNT');
        setState(() {
          if (creating && canCorrect) {
            submitted = null;
            requestId = staffRequestId();
          }
          error = staffAccountError(e);
          if (creating && !canCorrect) {
            error =
                '$error\nRetry sends the same request to avoid creating a duplicate account.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(creating ? 'Add staff account' : 'Edit staff account'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  creating
                      ? 'Create the account, send a password setup email, then activate portal access.'
                      : 'System access and day-to-day responsibilities are separate.',
                ),
                gap(18),
                TextFormField(
                  controller: name,
                  enabled: !locked,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: validateName,
                ),
                gap(12),
                TextFormField(
                  controller: email,
                  enabled: creating && !locked,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254,
                  decoration: InputDecoration(
                    labelText: 'Login email',
                    helperText: creating
                        ? 'Use an email belonging to this employee.'
                        : 'Login email is read-only to protect the authentication identity.',
                  ),
                  validator: creating
                      ? (v) =>
                            !RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(v?.trim() ?? '')
                            ? 'Enter a valid employee email.'
                            : null
                      : null,
                ),
                gap(12),
                MalaysiaPhoneField(
                  controller: phone,
                  enabled: !locked,
                  existingPhone: widget.record?.phone,
                ),
                gap(12),
                Info('System role', widget.record?.roleLabel ?? 'Staff'),
                gap(16),
                DropdownButtonFormField<String>(
                  initialValue: staffWorkRoles.containsKey(job) ? job : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Work role'),
                  items: staffWorkRoles.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: locked ? null : (v) => setState(() => job = v!),
                  validator: (v) => v == null
                      ? 'Choose the employee’s actual work role.'
                      : null,
                ),
                if (job == otherStaffRole) ...[
                  gap(12),
                  TextFormField(
                    controller: title,
                    enabled: !locked,
                    decoration: const InputDecoration(
                      labelText: 'Job title',
                      hintText: 'e.g. Seamstress',
                    ),
                    validator: validateStaffJobTitle,
                  ),
                ],
                gap(16),
                Text(
                  'Services this employee can perform',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Select the services this employee can perform. Bridal Makeup qualifies them for Makeup Trial appointments. Front desk can leave all services unchecked.',
                  style: TextStyle(color: muted),
                ),
                for (final service in staffServices)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(service),
                    value: services.contains(service),
                    onChanged: locked
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              services.add(service);
                            } else {
                              services.remove(service);
                            }
                          }),
                  ),
                if (creating)
                  const Text(
                    'No password is shown or shared with the manager. New accounts cannot access the portal until activated.',
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(error!, style: const TextStyle(color: rose)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(
            busy
                ? 'Saving…'
                : creating
                ? submitted == null
                      ? 'Create staff account'
                      : 'Retry same request'
                : 'Save changes',
          ),
        ),
      ],
    ),
  );
}

class StaffStatusDialog extends StatefulWidget {
  const StaffStatusDialog({
    super.key,
    required this.name,
    required this.active,
  });
  final String name;
  final bool active;
  @override
  State<StaffStatusDialog> createState() => _StaffStatusDialogState();
}

class _StaffStatusDialogState extends State<StaffStatusDialog> {
  final note = TextEditingController(), form = GlobalKey<FormState>();
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.active ? 'Activate staff access?' : 'Deactivate staff access?',
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.active
                    ? 'Allow ${widget.name} to use the portal with the configured role and responsibilities.'
                    : 'Remove ${widget.name}’s portal access and end their login sessions. Assigned work and minimum staffing cover will be checked. Nothing is permanently deleted.',
              ),
              gap(),
              TextFormField(
                controller: note,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason (recorded in history)',
                ),
                validator: (v) => (v?.trim().length ?? 0) < 5
                    ? 'Enter a reason of at least five characters.'
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, note.text.trim());
          }
        },
        child: const Text('Confirm'),
      ),
    ],
  );
}
