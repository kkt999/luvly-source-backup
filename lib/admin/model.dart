import 'package:flutter/material.dart';

enum PortalRole { staff, manager }

enum PortalPage {
  dashboard,
  appointments,
  inventory,
  packages,
  rentals,
  progress,
  payments,
  support,
  records,
  staff,
  reports,
  schedule,
  promotions,
  tasks,
  reviews,
}

extension PageNames on PortalPage {
  String get label => [
    'Dashboard',
    'Appointments',
    'Dress inventory',
    'Service packages',
    'Customer rentals',
    'Service progress',
    'Payments & receipts',
    'Customer support',
    'Customer records',
    'Staff accounts',
    'Reports',
    'My availability',
    'Promotions & ads',
    'Work tasks',
    'Customer reviews',
  ][index];
}

class TeamMember {
  TeamMember(
    this.id,
    this.name,
    this.email,
    this.role, {
    this.active = true,
    this.phone = '',
    this.position = 'Bridal consultant',
    this.experience = 0,
    this.frontDesk = false,
    DateTime? joined,
  }) : joined = joined ?? DateTime(2026, 1, 1);
  final String id;
  String name, email;
  PortalRole role;
  bool active;
  final bool frontDesk;
  String phone, position;
  DateTime joined;
  int experience;
}

class BrideRecord {
  BrideRecord(
    this.id,
    this.name,
    this.email,
    this.phone,
    this.wedding,
    this.membership,
  );
  final String id;
  String name, email, phone, membership;
  DateTime wedding;
  String notes = '';
  String bodyShape = 'Not recorded',
      preferredStyle = 'A-Line',
      preferredColour = 'Ivory',
      size = 'M';
}

class Appointment {
  Appointment(
    this.id,
    this.brideId,
    this.type,
    this.date,
    this.hour,
    this.staffId, {
    this.status = 'Confirmed',
    this.notes = '',
  });
  final String id;
  String brideId, type, status, notes;
  DateTime date;
  int hour;
  String? staffId;
  String trialOutcome = '', trialNotes = '';
  bool converted = false;
}

class Gown {
  Gown(
    this.id,
    this.name,
    this.category,
    this.price,
    this.image, {
    this.status = 'Available',
    this.size = 'S–L',
  });
  final String id;
  String name, category, image, status, size;
  double price;
  String description =
      'Elegant wedding dress with a refined silhouette and delicate details.';
}

class ServicePackage {
  ServicePackage(
    this.id,
    this.name,
    this.price,
    this.description,
    this.services, {
    this.active = true,
  });
  final String id;
  String name, description;
  double price;
  List<String> services;
  bool active;
}

class ServiceTask {
  ServiceTask(
    this.id,
    this.brideId,
    this.title,
    this.due,
    this.staffId, {
    this.status = 'Not Started',
    this.note = '',
  });
  final String id, brideId;
  String title, status, note;
  DateTime due;
  String? staffId;
  bool alterationRequired = false;
  String alterationStatus = 'Not Started';
  int startHour = 9, endHour = 10;
  bool scheduled = false;
}

class PaymentRecord {
  PaymentRecord(
    this.id,
    this.brideId,
    this.amount,
    this.date,
    this.method, {
    this.status = 'Paid',
  });
  final String id, brideId, method;
  final double amount;
  final DateTime date;
  String status;
}

class TicketMessage {
  TicketMessage(this.sender, this.text, {this.internal = false});
  final String sender, text;
  final bool internal;
}

class SupportTicket {
  SupportTicket(
    this.id,
    this.brideId,
    this.subject,
    this.category,
    this.staffId,
    this.messages, {
    this.status = 'Open',
    this.priority = 'Normal',
  });
  final String id, brideId, subject, category;
  String? staffId;
  String status, priority;
  final List<TicketMessage> messages;
}

class Availability {
  Availability(
    this.staffId,
    this.date,
    this.startHour,
    this.endHour,
    this.available,
  );
  final String staffId;
  final DateTime date;
  final int startHour, endHour;
  final bool available;
}

class PackageBooking {
  PackageBooking(this.packageId, this.brideId, this.date);
  final String packageId, brideId;
  final DateTime date;
}

class PortalModel extends ChangeNotifier {
  PortalModel({DateTime? today})
    : isLive = false,
      today = DateUtils.dateOnly(today ?? DateTime.now()) {
    brides.addAll([
      BrideRecord(
        'B001',
        'Sophia Loren',
        'sophia@example.com',
        '012 345 6789',
        this.today.add(const Duration(days: 60)),
        'Silver',
      ),
      BrideRecord(
        'B002',
        'Chloe Yap',
        'chloe@example.com',
        '012 888 2367',
        this.today.add(const Duration(days: 35)),
        'Gold',
      ),
      BrideRecord(
        'B003',
        'Sarah Jenkins',
        'sarah@example.com',
        '017 321 4567',
        this.today.add(const Duration(days: 90)),
        'Standard',
      ),
      BrideRecord(
        'B004',
        'Mei Wong',
        'mei@example.com',
        '016 225 8901',
        this.today.add(const Duration(days: 48)),
        'Silver',
      ),
    ]);
    appointments.addAll([
      Appointment('APT-101', 'B001', 'Dress Trial', this.today, 10, 'S001'),
      Appointment(
        'APT-102',
        'B002',
        'Bridal Consultation',
        this.today,
        11,
        'S002',
      ),
      Appointment('APT-103', 'B003', 'Final Fitting', this.today, 14, null),
      Appointment(
        'APT-104',
        'B004',
        'Dress Trial',
        this.today.add(const Duration(days: 1)),
        15,
        'S001',
      ),
      Appointment(
        'APT-100',
        'B001',
        'Bridal Consultation',
        this.today.subtract(const Duration(days: 4)),
        11,
        'S001',
        status: 'Completed',
      ),
    ]);
    tasks.addAll([
      ServiceTask(
        'TSK-201',
        'B001',
        'First dress fitting',
        this.today,
        'S001',
        status: 'In Progress',
        note: 'Bride prefers an A-line silhouette.',
      ),
      ServiceTask(
        'TSK-202',
        'B002',
        'Confirm alterations',
        this.today.add(const Duration(days: 2)),
        'S002',
        status: 'Delayed',
        note: 'Waiting for fabric confirmation.',
      ),
      ServiceTask(
        'TSK-203',
        'B004',
        'Prepare accessories',
        this.today.add(const Duration(days: 3)),
        'S001',
      ),
      ServiceTask(
        'TSK-204',
        'B003',
        'Bridal consultation',
        this.today.add(const Duration(days: 4)),
        null,
      ),
      ServiceTask(
        'TSK-205',
        'B001',
        'Record measurements',
        this.today.subtract(const Duration(days: 2)),
        'S001',
        status: 'Completed',
      ),
    ]);
    payments.addAll([
      PaymentRecord('PAY-301', 'B001', 1000, this.today, 'Online banking'),
      PaymentRecord(
        'PAY-302',
        'B002',
        4800,
        this.today.subtract(const Duration(days: 3)),
        'Card',
      ),
      PaymentRecord(
        'PAY-303',
        'B004',
        1250,
        this.today.subtract(const Duration(days: 9)),
        'E-wallet',
      ),
      PaymentRecord(
        'PAY-304',
        'B003',
        500,
        this.today.subtract(const Duration(days: 16)),
        'Online banking',
        status: 'Pending',
      ),
      PaymentRecord(
        'PAY-305',
        'B002',
        350,
        this.today.subtract(const Duration(days: 35)),
        'Card',
      ),
    ]);
    tickets.addAll([
      SupportTicket(
        'TCK-401',
        'B001',
        'Question about dress alterations',
        'Fitting',
        'S001',
        [
          TicketMessage(
            'Sophia Loren',
            'Can my gown be adjusted before the next fitting?',
          ),
          TicketMessage(
            'Jane Lee',
            'Yes, we will review the measurements during your appointment.',
          ),
        ],
        status: 'In Progress',
      ),
      SupportTicket(
        'TCK-402',
        'B002',
        'Change appointment date',
        'Appointments',
        'S002',
        [
          TicketMessage(
            'Chloe Yap',
            'Could I move my consultation to next week?',
          ),
        ],
      ),
      SupportTicket(
        'TCK-403',
        'B003',
        'Payment receipt enquiry',
        'Payments',
        null,
        [TicketMessage('Sarah Jenkins', 'Where can I find my receipt?')],
        priority: 'High',
      ),
      SupportTicket(
        'TCK-400',
        'B004',
        'Package inclusions',
        'Packages',
        'S001',
        [
          TicketMessage('Mei Wong', 'Are accessories included?'),
          TicketMessage(
            'Jane Lee',
            'Yes, your selected package includes accessories.',
          ),
        ],
        status: 'Closed',
      ),
    ]);
  }

  /// Real identity with no fixture business records. Until repositories are
  /// connected, mutations must not report a successful local-only save.
  PortalModel.live({required TeamMember member, DateTime? today})
    : isLive = true,
      today = DateUtils.dateOnly(today ?? DateTime.now()) {
    team.clear();
    gowns.clear();
    packages.clear();
    activity.clear();
    current = member;
  }

  final bool isLive;
  final DateTime today;
  TeamMember? current;
  final team = [
    TeamMember('M001', 'Amelia Tan', 'manager@luvly.demo', PortalRole.manager),
    TeamMember('S001', 'Jane Lee', 'staff@luvly.demo', PortalRole.staff),
    TeamMember('S002', 'Emma Davis', 'emma@luvly.demo', PortalRole.staff),
  ];
  final List<BrideRecord> brides = [];
  final List<Appointment> appointments = [];
  final List<ServiceTask> tasks = [];
  final List<PaymentRecord> payments = [];
  final List<SupportTicket> tickets = [];
  final List<Availability> availability = [];
  final List<PackageBooking> packageBookings = [];
  final gowns = [
    Gown('DR-001', 'The Golden Gown', 'A-Line', 4500, 'golden'),
    Gown('DR-002', 'Eden Lace', 'A-Line', 3100, 'eden', status: 'Reserved'),
    Gown('DR-003', 'Blush Romance', 'Ball Gown', 3900, 'blush'),
    Gown(
      'DR-004',
      'Luxe Satin',
      'Mermaid',
      4200,
      'satin',
      status: 'In Fitting',
    ),
    Gown(
      'DR-005',
      'Pearl Dreams',
      'Ball Gown',
      3600,
      'pearl',
      status: 'Under Alteration',
    ),
    Gown('DR-006', 'Ivory Bliss', 'Mermaid', 3800, 'ivory'),
  ];
  final packages = [
    ServicePackage(
      'PKG-001',
      'Premium Bridal',
      4800,
      'A complete bridal experience, thoughtfully curated.',
      [
        'Wedding dress rental',
        'Bridal consultation',
        'Stylist guidance',
        'Fitting coordination',
      ],
    ),
    ServicePackage(
      'PKG-002',
      'Essential Elegance',
      2500,
      'The beautiful essentials for an intimate celebration.',
      ['Wedding dress rental', 'Bridal consultation'],
    ),
    ServicePackage(
      'PKG-003',
      'Luxury Bespoke',
      6500,
      'Personal touches for a truly memorable day.',
      [
        'Wedding dress rental',
        'Bridal consultation',
        'Photography',
        'Makeup trial',
      ],
    ),
  ];
  final activity = <String>['Welcome to the Luvly management demo.'];
  List<String> get visibleActivity => activity
      .where(
        (a) =>
            isManager ||
            a.startsWith('${current?.name} ·') ||
            a.startsWith('Welcome to '),
      )
      .toList();
  bool get isManager => current?.role == PortalRole.manager;
  bool get boutiqueOperations =>
      !isLive || isManager || current?.frontDesk == true;
  bool get signedIn => current != null;
  String pageLabel(PortalPage page) =>
      page == PortalPage.appointments && !boutiqueOperations
      ? 'My appointments'
      : page.label;
  List<PortalPage> get pages {
    final result = PortalPage.values.where(canOpen).toList();
    if (result.remove(PortalPage.reviews)) {
      result.insert(result.indexOf(PortalPage.records) + 1, PortalPage.reviews);
    }
    return result;
  }

  bool canOpen(PortalPage p) =>
      signedIn &&
      p != PortalPage.progress &&
      (p != PortalPage.tasks || isLive) &&
      (p != PortalPage.reviews || isLive) &&
      (boutiqueOperations ||
          p != PortalPage.rentals && p != PortalPage.payments) &&
      (!(p == PortalPage.staff || p == PortalPage.reports) || isManager);
  String brideName(String id) => brides.firstWhere((b) => b.id == id).name;
  String staffName(String? id) =>
      id == null ? 'Unassigned' : team.firstWhere((s) => s.id == id).name;
  Set<String> get assignedBrideIds => {
    for (final a in appointments)
      if (a.staffId == current?.id) a.brideId,
    for (final t in tasks)
      if (t.staffId == current?.id) t.brideId,
    for (final t in tickets)
      if (t.staffId == current?.id) t.brideId,
  };
  List<Appointment> get visibleAppointments => appointments
      .where((a) => signedIn && (isManager || a.staffId == current!.id))
      .toList();
  List<ServiceTask> get visibleTasks => tasks
      .where((t) => signedIn && (isManager || t.staffId == current!.id))
      .toList();
  List<SupportTicket> get visibleTickets => tickets
      .where((t) => signedIn && (isManager || t.staffId == current!.id))
      .toList();
  List<BrideRecord> get visibleBrides => brides
      .where((b) => signedIn && (isManager || assignedBrideIds.contains(b.id)))
      .toList();
  List<PaymentRecord> get visiblePayments => payments
      .where(
        (p) => signedIn && (isManager || assignedBrideIds.contains(p.brideId)),
      )
      .toList();
  void login(PortalRole role) {
    requireBusinessData();
    current = team.firstWhere((s) => s.role == role && s.active);
    notifyListeners();
  }

  void logout() {
    requireBusinessData();
    current = null;
    notifyListeners();
  }

  void managerOnly() {
    requireBusinessData();
    if (!isManager) throw StateError('Only managers can perform this action.');
  }

  void owns(String? id) {
    requireBusinessData();
    if (!signedIn || (!isManager && id != current!.id)) {
      throw StateError('This record is not assigned to you.');
    }
  }

  void catalogueAccess() {
    requireBusinessData();
    if (!signedIn || current?.active != true) {
      throw StateError('An active staff or manager session is required.');
    }
  }

  void removeGown(Gown g) {
    catalogueAccess();
    if (['Reserved', 'In Fitting', 'Under Alteration'].contains(g.status)) {
      throw StateError('Release the active dress commitment before removal.');
    }
    g.status = 'Inactive';
    changed('Removed ${g.id} from active inventory; history retained.');
  }

  void deactivatePackage(ServicePackage p) {
    managerOnly();
    p.active = false;
    changed('Deactivated ${p.id}; history retained.');
  }

  void recordTrial(Appointment a, String outcome, String notes) {
    owns(a.staffId);
    if (a.type != 'Dress Trial' || a.status == 'Cancelled') {
      throw StateError('Only eligible dress trials have an outcome.');
    }
    if (outcome.trim().isEmpty || notes.trim().isEmpty) {
      throw StateError('Outcome and notes are required.');
    }
    a.trialOutcome = outcome;
    a.trialNotes = notes;
    changed('Recorded trial outcome for ${a.id}.');
  }

  bool isAvailable(
    String id,
    DateTime date,
    int start,
    int end, {
    Appointment? excludingAppointment,
    ServiceTask? excludingTask,
  }) {
    if (!team.any((s) => s.id == id && s.active)) return false;
    final entries = availability
        .where((x) => x.staffId == id && DateUtils.isSameDay(x.date, date))
        .toList();
    if (entries.any(
      (x) => !x.available && start < x.endHour && end > x.startHour,
    )) {
      return false;
    }
    final windows = entries.where((x) => x.available);
    if (windows.isNotEmpty &&
        !windows.any((x) => start >= x.startHour && end <= x.endHour)) {
      return false;
    }
    if (appointments.any(
      (a) =>
          a != excludingAppointment &&
          a.staffId == id &&
          a.status == 'Confirmed' &&
          DateUtils.isSameDay(a.date, date) &&
          start < a.hour + 1 &&
          end > a.hour,
    )) {
      return false;
    }
    return !tasks.any(
      (t) =>
          t != excludingTask &&
          t.staffId == id &&
          t.scheduled &&
          !['Completed', 'Cancelled'].contains(t.status) &&
          DateUtils.isSameDay(t.due, date) &&
          start < t.endHour &&
          end > t.startHour,
    );
  }

  void saveAvailability(Availability a) {
    owns(a.staffId);
    if (a.startHour >= a.endHour || a.startHour < 0 || a.endHour > 24) {
      throw StateError('End time must be after start time.');
    }
    if (a.date.isBefore(today)) {
      throw StateError('Choose today or a future date.');
    }
    availability.removeWhere(
      (x) => x.staffId == a.staffId && DateUtils.isSameDay(x.date, a.date),
    );
    availability.add(a);
    changed('Updated availability for ${staffName(a.staffId)}.');
  }

  void scheduleTask(
    ServiceTask t,
    String id,
    DateTime date,
    int start,
    int end,
  ) {
    managerOnly();
    if (date.isBefore(today) || start >= end || start < 0 || end > 24) {
      throw StateError('Choose a valid future time range.');
    }
    if (!isAvailable(id, date, start, end, excludingTask: t)) {
      throw StateError(
        'Selected staff member is unavailable or already assigned. Choose another person or time.',
      );
    }
    t.staffId = id;
    t.due = date;
    t.startHour = start;
    t.endHour = end;
    t.scheduled = true;
    changed('Scheduled ${t.id} for ${staffName(id)}.');
  }

  void updateAlteration(ServiceTask t, bool required, String stage) {
    owns(t.staffId);
    if (![
      'Not Started',
      'First Alteration',
      'Second Alteration',
      'Final Fitting',
      'Completed',
    ].contains(stage)) {
      throw StateError('Invalid alteration stage.');
    }
    t.alterationRequired = required;
    t.alterationStatus = required ? stage : 'Not Started';
    changed('Updated alteration information for ${t.id}.');
  }

  void requireBusinessData() {
    if (isLive) {
      throw StateError(
        'This section is not connected yet. No changes were saved.',
      );
    }
  }

  void changed(String message) {
    requireBusinessData();
    activity.insert(0, '${current?.name ?? 'System'} · $message');
    notifyListeners();
  }

  void assignTask(ServiceTask task, String? id) {
    managerOnly();
    _activeStaff(id);
    if (id != null &&
        task.scheduled &&
        !isAvailable(
          id,
          task.due,
          task.startHour,
          task.endHour,
          excludingTask: task,
        )) {
      throw StateError(
        'This staff member has an overlapping appointment or task.',
      );
    }
    task.staffId = id;
    changed('Assigned ${task.id} to ${staffName(id)}.');
  }

  void _activeStaff(String? id) {
    if (id != null && !team.any((s) => s.id == id && s.active)) {
      throw StateError('Select an active team member.');
    }
  }

  void updateTask(ServiceTask t, String status, String note) {
    owns(t.staffId);
    if (!taskStatuses.contains(status)) throw StateError('Invalid status.');
    t.status = status;
    t.note = note;
    changed('Updated ${t.id} to $status.');
  }

  void saveAppointment(Appointment a, {Appointment? existing}) {
    managerOnly();
    _activeStaff(a.staffId);
    if (a.staffId != null &&
        a.status == 'Confirmed' &&
        !isAvailable(
          a.staffId!,
          a.date,
          a.hour,
          a.hour + 1,
          excludingAppointment: existing,
        )) {
      throw StateError(
        'Selected staff member is unavailable or already assigned at this time.',
      );
    }
    if (a.staffId != null &&
        a.status == 'Confirmed' &&
        appointments.any(
          (x) =>
              x != existing &&
              x.status == 'Confirmed' &&
              x.staffId == a.staffId &&
              DateUtils.isSameDay(x.date, a.date) &&
              x.hour == a.hour,
        )) {
      throw StateError(
        'This team member already has an appointment at this time.',
      );
    }
    if (existing == null) {
      appointments.add(a);
    } else {
      existing.brideId = a.brideId;
      existing.type = a.type;
      existing.date = a.date;
      existing.hour = a.hour;
      existing.staffId = a.staffId;
      existing.status = a.status;
      existing.notes = a.notes;
    }
    changed('Saved appointment ${a.id}.');
  }

  void appointmentStatus(Appointment a, String status) {
    owns(a.staffId);
    if (!['Confirmed', 'Completed', 'Cancelled'].contains(status)) {
      throw StateError('Invalid status.');
    }
    if (!isManager && status != 'Completed') {
      throw StateError('Staff can only mark their appointment as completed.');
    }
    a.status = status;
    changed('Updated ${a.id} to $status.');
  }

  void saveGown(Gown g, {Gown? existing}) {
    catalogueAccess();
    if (g.price < 0 || !g.price.isFinite) throw StateError('Invalid price.');
    if (existing == null) {
      gowns.add(g);
    } else {
      existing.name = g.name;
      existing.category = g.category;
      existing.price = g.price;
      existing.size = g.size;
      existing.status = g.status;
      existing.description = g.description;
      existing.image = g.image;
    }
    changed('Saved dress ${g.id}.');
  }

  void savePackage(ServicePackage p, {ServicePackage? existing}) {
    managerOnly();
    if (p.price < 0 || !p.price.isFinite) throw StateError('Invalid price.');
    if (existing == null) {
      packages.add(p);
    } else {
      existing.name = p.name;
      existing.description = p.description;
      existing.price = p.price;
      existing.services = p.services;
      existing.active = p.active;
    }
    changed('Saved package ${p.id}.');
  }

  void assignTicket(SupportTicket t, String? id) {
    managerOnly();
    _activeStaff(id);
    t.staffId = id;
    changed('Assigned ${t.id} to ${staffName(id)}.');
  }

  void reply(SupportTicket t, String text, {bool internal = false}) {
    owns(t.staffId);
    if (t.status == 'Closed') throw StateError('Closed tickets are read-only.');
    if (text.trim().isEmpty) throw StateError('Enter a message first.');
    t.messages.add(
      TicketMessage(current!.name, text.trim(), internal: internal),
    );
    changed('Added ${internal ? 'internal note' : 'reply'} to ${t.id}.');
  }

  void ticketStatus(SupportTicket t, String status) {
    owns(t.staffId);
    if (t.status == 'Closed') throw StateError('Closed tickets are read-only.');
    if (!ticketStatuses.contains(status)) throw StateError('Invalid status.');
    t.status = status;
    changed('Updated ${t.id} to $status.');
  }

  void saveBride(BrideRecord b, String membership, String notes) {
    managerOnly();
    b.membership = membership;
    b.notes = notes;
    changed('Updated ${b.name}’s record.');
  }

  void saveStaff(TeamMember s, {TeamMember? existing}) {
    managerOnly();
    if (team.any(
      (t) => t != existing && t.email.toLowerCase() == s.email.toLowerCase(),
    )) {
      throw StateError('An account already uses this email.');
    }
    if (existing?.id == current?.id &&
        (!s.active || s.role != PortalRole.manager)) {
      throw StateError('You cannot deactivate or demote your own account.');
    }
    if (existing != null &&
        !s.active &&
        (appointments.any(
              (a) => a.staffId == s.id && a.status == 'Confirmed',
            ) ||
            tasks.any(
              (t) =>
                  t.staffId == s.id &&
                  !['Completed', 'Cancelled'].contains(t.status),
            ) ||
            tickets.any((t) => t.staffId == s.id && t.status != 'Closed'))) {
      throw StateError(
        'Reassign this person’s active appointments, tasks and tickets before deactivating their account.',
      );
    }
    if (existing == null) {
      team.add(s);
    } else {
      existing.name = s.name;
      existing.email = s.email;
      existing.role = s.role;
      existing.active = s.active;
      existing.phone = s.phone;
      existing.position = s.position;
      existing.joined = s.joined;
      existing.experience = s.experience;
    }
    changed('Saved staff account ${s.name}.');
  }
}

const taskStatuses = [
  'Not Started',
  'In Progress',
  'Delayed',
  'Completed',
  'Cancelled',
];
const ticketStatuses = [
  'Open',
  'In Progress',
  'Waiting for Customer',
  'Resolved',
  'Closed',
];
const gownStatuses = [
  'Available',
  'Reserved',
  'In Fitting',
  'Under Alteration',
  'Inactive',
];
String money(num n) => 'RM ${n.toStringAsFixed(2)}';
String dateText(DateTime d) =>
    '${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
String hourText(int h) => '${h > 12 ? h - 12 : h}:00 ${h >= 12 ? 'PM' : 'AM'}';

class PortalScope extends InheritedNotifier<PortalModel> {
  const PortalScope({
    super.key,
    required PortalModel model,
    required super.child,
  }) : super(notifier: model);
  static PortalModel of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PortalScope>()!.notifier!;
  static PortalModel? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PortalScope>()?.notifier;
}
