/// Presentation only: never authorizes access or determines invoice amounts.
class AppointmentPackageNote {
  const AppointmentPackageNote(this.name, this.selectionId, this.customerNotes);
  final String name, selectionId, customerNotes;
  static AppointmentPackageNote? parse(String notes) {
    final match = RegExp(
      r'^Package: ([^\n]+)\nSelection: ([a-f0-9]{32})(?:\n([\s\S]*))?$',
    ).firstMatch(notes);
    return match == null
        ? null
        : AppointmentPackageNote(match[1]!, match[2]!, match[3] ?? '');
  }
}
