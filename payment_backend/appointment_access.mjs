export const activeEmployee = staff =>
  staff?.active === true && ['staff', 'manager'].includes(staff.role);

export const canViewAllAppointments = (staff, scheduling) =>
  activeEmployee(staff) &&
  (staff.role === 'manager' || scheduling?.jobRole === 'FrontDesk');

export async function hasBoutiqueOperationsAccess(reader, uid, staff) {
  if (!activeEmployee(staff)) return false;
  if (staff.role === 'manager') return true;
  return canViewAllAppointments(staff, await reader.get(`staffScheduling/${uid}`));
}

export const isAssignedFitting = (uid, selection, appointment) =>
  appointment?.type === 'Dress Trial' &&
  appointment.uid === selection.uid && appointment.assignedStaffId === uid;

export async function hasPackageFittingAccess(reader, uid, staff, selection) {
  if (!activeEmployee(staff) || !selection) return false;
  if (await hasBoutiqueOperationsAccess(reader, uid, staff)) return true;
  for (const id of selection.appointmentIds ?? []) {
    const booking = await reader.get(`appointments/${id}`);
    if (isAssignedFitting(uid, selection, booking) &&
        ['Confirmed', 'Completed'].includes(booking.status) &&
        (await reader.get(`packageAppointments/${id}`))?.selectionId === selection.id) return true;
  }
  return false;
}

export async function hasAppointmentStaffAccess(reader, uid, staff, appointment) {
  if (!activeEmployee(staff) || !appointment) return false;
  if (staff.role === 'manager' || appointment.assignedStaffId === uid) return true;
  return hasBoutiqueOperationsAccess(reader, uid, staff);
}
