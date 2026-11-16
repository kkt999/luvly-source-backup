const schedulingRoles = {
  'FrontDesk': 'Front desk',
  'Consultant': 'Bridal consultant',
  'FittingSpecialist': 'Fitting specialist',
  'MakeupArtist': 'Makeup artist',
};
const otherStaffRole = 'Other';
const staffWorkRoles = {...schedulingRoles, otherStaffRole: 'Other role'};
const staffServices = ['Dress Trial', 'Bridal Consultation', 'Bridal Makeup'];

String staffWorkRoleLabel(String? role, String? title) {
  if (role == otherStaffRole && title != null && title.trim().isNotEmpty) {
    return title;
  }
  return staffWorkRoles[role] ?? 'Not configured';
}

String? validateStaffJobTitle(String? value) {
  final title = value?.trim() ?? '';
  if (title.isEmpty) return 'Enter the employee’s job title.';
  if (title.length > 80 ||
      !RegExp(r'\p{L}', unicode: true).hasMatch(title) ||
      RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(title)) {
    return 'Use up to 80 characters and include a letter.';
  }
  return null;
}
