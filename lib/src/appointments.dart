import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import '../bookings/booking_screens.dart';
import '../planning/planning_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, this.assistantInAppBar = false});
  final bool assistantInAppBar;
  @override
  State<AppointmentsScreen> createState() => _AppointmentsState();
}

class _AppointmentsState extends State<AppointmentsScreen> {
  bool past = false;
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    if (m.accountId != null) {
      return LiveAppointments(
        uid: m.accountId!,
        name: m.name,
        phone: m.phone,
        assistantInAppBar: widget.assistantInAppBar,
      );
    }
    final list = m.bookings
        .where((b) => past ? b.status != 'Confirmed' : b.status == 'Confirmed')
        .toList();
    return PageList(
      children: [
        Text(
          'A date with your\ndream day.',
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        gap(18),
        Primary(
          'Book an appointment',
          () => go(c, const BookAppointmentScreen()),
          icon: Icons.add,
        ),
        gap(18),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Upcoming')),
            ButtonSegment(value: true, label: Text('Past & cancelled')),
          ],
          selected: {past},
          onSelectionChanged: (v) => setState(() => past = v.first),
        ),
        gap(20),
        if (list.isEmpty)
          const EmptyState(
            Icons.event_available,
            'No appointments here',
            'Your appointments will appear here once booked.',
          ),
        for (final b in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          b.type,
                          style: Theme.of(c).textTheme.titleMedium,
                        ),
                      ),
                      StatusPill(b.status),
                    ],
                  ),
                  gap(12),
                  Text('${dateLabel(b.date)} • ${b.time}'),
                  gap(6),
                  const Text(
                    'Luvly Bridal Boutique',
                    style: TextStyle(color: muted),
                  ),
                  gap(12),
                  OutlinedButton(
                    onPressed: () => go(c, BookingDetailScreen(booking: b)),
                    child: const Text('View details'),
                  ),
                ],
              ),
            ),
          ),
        const Section('One beautiful step at a time'),
        MenuTile(
          Icons.timeline,
          'My bridal timeline',
          'Follow your service progress',
          () => go(c, const TimelineScreen()),
        ),
        const DemoNote(),
      ],
    );
  }
}

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key, this.existing});
  final Booking? existing;
  @override
  State<BookAppointmentScreen> createState() => _BookState();
}

class _BookState extends State<BookAppointmentScreen> {
  int step = 0;
  String type = 'Dress Trial', time = '';
  DateTime date = DateTime.now().add(const Duration(days: 1));
  final notes = TextEditingController();
  bool calendar = false;
  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final b = widget.existing!;
      type = b.type;
      date = b.date.isBefore(DateTime.now())
          ? DateTime.now().add(const Duration(days: 1))
          : b.date;
      time = b.time;
      notes.text = b.notes;
      calendar = b.calendarRequested;
    }
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  bool unavailable(AppModel m, String slot) => m.bookings.any(
    (b) =>
        b != widget.existing &&
        b.status == 'Confirmed' &&
        DateUtils.isSameDay(b.date, date) &&
        b.time == slot,
  );
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    if (m.accountId != null) {
      return BookingRequestForm(
        uid: m.accountId!,
        name: m.name,
        phone: m.phone,
      );
    }
    return PageFrame(
      title: widget.existing == null
          ? 'Book an appointment'
          : 'Reschedule appointment',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Primary(step == 2 ? 'Confirm demo booking' : 'Continue', () {
            if (step == 0) {
              setState(() => step = 1);
            } else if (step == 1) {
              if (time.isEmpty || unavailable(m, time)) {
                toast(c, 'Choose an available time slot.');
                return;
              }
              setState(() => step = 2);
            } else {
              if (unavailable(m, time)) {
                toast(
                  c,
                  'This slot is no longer available. Please choose another.',
                );
                setState(() => step = 1);
                return;
              }
              final b =
                  widget.existing ??
                  Booking(type: type, date: date, time: time);
              b.date = date;
              b.time = time;
              b.notes = notes.text;
              b.calendarRequested = calendar;
              if (widget.existing == null) m.bookings.add(b);
              m.changed();
              Navigator.of(c).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BookingDetailScreen(booking: b, justBooked: true),
                ),
              );
            }
          }),
          if (step > 0)
            TextButton(
              onPressed: () => setState(() => step--),
              child: const Text('Back to previous step'),
            ),
        ],
      ),
      child: PageList(
        children: [
          Row(
            children: [
              for (int i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? rose : line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          gap(10),
          Text(
            'STEP ${step + 1} OF 3 • ${['APPOINTMENT TYPE', 'DATE & TIME', 'REVIEW'][step]}',
            style: const TextStyle(
              fontSize: 10,
              color: rose,
              letterSpacing: 1.5,
            ),
          ),
          gap(24),
          if (step == 0) ...[
            Text(
              'What shall we plan?',
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            gap(20),
            for (final v in [
              'Dress Trial',
              'Bridal Consultation',
              'Pre-wedding Photoshoot',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Surface(
                  color: type == v ? blush : Colors.white,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    selected: type == v,
                    leading: Icon(
                      type == v
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: rose,
                    ),
                    onTap: widget.existing != null
                        ? null
                        : () => setState(() => type = v),
                    title: Text(
                      v,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      v == 'Dress Trial'
                          ? '60 min · Find your favourite fit'
                          : v == 'Bridal Consultation'
                          ? '45 min · Let’s plan your journey'
                          : '120 min · Capture a little magic',
                    ),
                  ),
                ),
              ),
          ],
          if (step == 1) ...[
            Text(
              'Find your moment.',
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            gap(),
            Surface(
              padding: const EdgeInsets.all(4),
              child: CalendarDatePicker(
                initialDate: date,
                firstDate: DateUtils.dateOnly(DateTime.now()),
                lastDate: DateTime.now().add(const Duration(days: 180)),
                onDateChanged: (v) => setState(() {
                  date = v;
                  time = '';
                }),
              ),
            ),
            const Section('Available times'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final slot in [
                  '10:00 AM',
                  '11:00 AM',
                  '12:00 PM',
                  '2:00 PM',
                  '3:00 PM',
                  '4:00 PM',
                ])
                  ChoiceChip(
                    label: Text(slot),
                    selected: time == slot,
                    onSelected: unavailable(m, slot)
                        ? null
                        : (_) => setState(() => time = slot),
                  ),
              ],
            ),
            gap(),
            const Text(
              'Times shown in Malaysia time (MYT). Availability is demo data.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          if (step == 2) ...[
            Text(
              'Your moment, reserved.',
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            gap(20),
            Surface(
              child: Column(
                children: [
                  InfoRow('Appointment', type),
                  InfoRow('Date', dateLabel(date)),
                  InfoRow('Time', time),
                  const InfoRow('Stylist', 'Jane Lee'),
                  const InfoRow('Location', 'Luvly Bridal Boutique'),
                ],
              ),
            ),
            gap(20),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Anything we should know?',
                hintText: 'Your style preferences or special requests',
              ),
            ),
            gap(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Google Calendar reminder'),
              subtitle: const Text(
                'Preference preview only; no event will be created.',
                style: TextStyle(fontSize: 11),
              ),
              value: calendar,
              onChanged: (v) => setState(() => calendar = v),
            ),
            const DemoNote(
              text:
                  'This creates an in-app demo booking only. No boutique reservation or calendar event is made.',
            ),
          ],
        ],
      ),
    );
  }
}

class BookingDetailScreen extends StatelessWidget {
  const BookingDetailScreen({
    super.key,
    required this.booking,
    this.justBooked = false,
  });
  final Booking booking;
  final bool justBooked;
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    return PageFrame(
      title: 'Appointment details',
      child: PageList(
        children: [
          if (justBooked) ...[
            const EmptyState(
              Icons.check_circle_outline,
              'You’re all set!',
              'Your demo appointment has been saved.',
            ),
          ],
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        booking.type,
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                    ),
                    StatusPill(booking.status),
                  ],
                ),
                gap(16),
                InfoRow('Date', dateLabel(booking.date)),
                InfoRow('Time', '${booking.time} MYT'),
                const InfoRow('Your stylist', 'Jane Lee'),
                const InfoRow('Location', 'Luvly Bridal Boutique'),
                if (booking.notes.isNotEmpty) InfoRow('Notes', booking.notes),
              ],
            ),
          ),
          gap(18),
          const Text(
            'Please arrive 10 minutes early. Bring inspiration photos and any accessories you’d love to try.',
            style: TextStyle(color: muted),
          ),
          gap(20),
          if (booking.status == 'Confirmed') ...[
            Primary(
              'Reschedule appointment',
              () => go(c, BookAppointmentScreen(existing: booking)),
            ),
            gap(10),
            OutlinedButton(
              onPressed: () async {
                if (await confirm(
                      c,
                      'Cancel this appointment?',
                      'This will release your demo time slot.',
                      action: 'Cancel appointment',
                    ) &&
                    c.mounted) {
                  booking.status = 'Cancelled';
                  m.changed();
                  toast(c, 'Demo appointment cancelled.');
                }
              },
              child: const Text('Cancel appointment'),
            ),
          ],
          const DemoNote(),
        ],
      ),
    );
  }
}

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});
  @override
  Widget build(BuildContext c) => AppScope.of(c).accountId != null
      ? CustomerPlanningScreen(uid: AppScope.of(c).accountId!)
      : PageFrame(
          title: 'My bridal timeline',
          child: PageList(
            children: [
              Text(
                'Every step,\na little closer.',
                style: Theme.of(c).textTheme.headlineMedium,
              ),
              gap(12),
              const Text(
                'A simple view of your preparation journey.',
                style: TextStyle(color: muted),
              ),
              gap(24),
              for (final item in [
                (
                  'Bridal consultation',
                  'Completed',
                  'Your vision, preferences and plans are recorded.',
                ),
                (
                  'Measurements',
                  'Completed',
                  'Your initial measurements have been saved.',
                ),
                (
                  'First dress fitting',
                  'In Progress',
                  'Try your shortlisted gowns with your stylist.',
                ),
                (
                  'Final fitting & collection',
                  'Not Started',
                  'Your final touches before the big day.',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Surface(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: blush,
                          child: Icon(
                            item.$2 == 'Completed'
                                ? Icons.check
                                : Icons.schedule,
                            color: rose,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                style: Theme.of(c).textTheme.titleMedium,
                              ),
                              gap(7),
                              StatusPill(item.$2),
                              gap(8),
                              Text(
                                item.$3,
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const DemoNote(
                text:
                    'Sample progress milestones. Staff updates will appear here once the backend is connected.',
              ),
            ],
          ),
        );
}
