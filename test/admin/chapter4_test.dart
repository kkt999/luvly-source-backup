import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/reports.dart';

void main() {
  PortalModel model() => PortalModel(today: DateTime(2026, 9, 20));
  test(
    'Staff view packages; managers deactivate them with history retained',
    () {
      final m = model();
      expect(() => m.deactivatePackage(m.packages.first), throwsStateError);
      m.login(PortalRole.staff);
      expect(() => m.deactivatePackage(m.packages.first), throwsStateError);
      expect(m.packages.first.active, true);
      m.login(PortalRole.manager);
      m.deactivatePackage(m.packages.first);
      expect(m.packages.first.active, false);
      m.login(PortalRole.staff);
      final count = m.gowns.length;
      m.removeGown(m.gowns.first);
      expect(m.gowns.first.status, 'Inactive');
      expect(m.gowns.length, count);
      expect(
        () => m.removeGown(m.gowns.firstWhere((g) => g.status == 'Reserved')),
        throwsStateError,
      );
    },
  );
  test(
    'Availability and appointment conflicts block scheduled assignments',
    () {
      final m = model()..login(PortalRole.manager);
      final day = m.today.add(const Duration(days: 8));
      m.saveAvailability(Availability('S001', day, 9, 17, true));
      expect(m.isAvailable('S001', day, 8, 9), false);
      expect(m.isAvailable('S001', day, 10, 11), true);
      m.scheduleTask(m.tasks.first, 'S001', day, 10, 12);
      expect(m.isAvailable('S001', day, 11, 13), false);
      expect(m.isAvailable('S001', day, 12, 13), true);
      expect(
        () => m.saveAppointment(
          Appointment('new', 'B001', 'Dress Trial', day, 11, 'S001'),
        ),
        throwsStateError,
      );
      m.login(PortalRole.staff);
      expect(
        () => m.scheduleTask(m.tasks.first, 'S001', day, 12, 13),
        throwsStateError,
      );
      expect(
        () => m.saveAvailability(Availability('S002', day, 9, 17, true)),
        throwsStateError,
      );
    },
  );
  test('Trial and alteration updates are limited to assigned work', () {
    final m = model()..login(PortalRole.staff);
    final trial = Appointment(
      'trial',
      'B001',
      'Dress Trial',
      m.today,
      9,
      'S001',
    );
    m.recordTrial(trial, 'Alteration Required', 'Adjust hem');
    expect(trial.trialNotes, 'Adjust hem');
    trial.staffId = 'S002';
    expect(() => m.recordTrial(trial, 'Suitable', 'Ready'), throwsStateError);
    m.updateAlteration(m.visibleTasks.first, true, 'First Alteration');
    expect(m.visibleTasks.first.alterationRequired, true);
    expect(
      () => m.updateAlteration(m.visibleTasks.first, true, 'Unknown'),
      throwsStateError,
    );
  });
  test('Reports use real demo records, not completion as conversion', () {
    final m = model()..login(PortalRole.manager);
    m.packageBookings.add(PackageBooking(m.packages.first.id, 'B001', m.today));
    final p = calculateReport(m, reportTypes[0], m.today, m.today);
    expect(p.rows.first[1], '1');
    m.appointments.clear();
    m.appointments.add(
      Appointment(
        'test',
        'B001',
        'Dress Trial',
        m.today,
        10,
        'S001',
        status: 'Completed',
      ),
    );
    var a = calculateReport(m, reportTypes[1], m.today, m.today);
    expect(a.rows.single[2], 'Not converted');
    m.appointments.single.converted = true;
    a = calculateReport(m, reportTypes[1], m.today, m.today);
    expect(a.rows.single[2], 'Converted');
    m.login(PortalRole.staff);
    expect(
      () => calculateReport(m, reportTypes[2], m.today, m.today),
      throwsStateError,
    );
  });
}
