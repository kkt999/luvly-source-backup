import 'package:flutter/material.dart';
import '../src/design.dart';
import 'booking_repository.dart';
import 'reschedule_api.dart';

class RescheduleAppointmentScreen extends StatefulWidget {
  const RescheduleAppointmentScreen({
    super.key,
    required this.appointmentId,
    this.api,
  });
  final String appointmentId;
  final RescheduleApi? api;
  @override
  State<RescheduleAppointmentScreen> createState() => _RescheduleState();
}

class _RescheduleState extends State<RescheduleAppointmentScreen> {
  late final api = widget.api ?? RescheduleApi();
  RescheduleContext? current;
  DateTime? day;
  int? hour;
  List<int> hours = [];
  bool loading = true, loadingHours = false, saving = false;
  String? error, slotError, pendingKey, pendingId;
  int generation = 0, slotGeneration = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    slotGeneration++;
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> load() async {
    final g = ++generation;
    slotGeneration++;
    setState(() => loading = true);
    try {
      final result = await api.load(widget.appointmentId);
      if (!mounted || g != generation) return;
      final local = result.start.add(const Duration(hours: 8));
      var initial = DateTime(local.year, local.month, local.day);
      if (initial.isBefore(result.firstDay)) initial = result.firstDay;
      if (initial.isAfter(result.lastDay)) initial = result.lastDay;
      setState(() {
        current = result;
        day = initial;
        error = null;
        pendingId = null;
        pendingKey = null;
        hour = null;
      });
      if (result.eligible) await slots();
    } catch (e) {
      if (mounted && g == generation) setState(() => error = bookingError(e));
    } finally {
      if (mounted && g == generation) setState(() => loading = false);
    }
  }

  Future<void> slots() async {
    final c = current, d = day;
    if (c == null || d == null) return;
    final g = ++slotGeneration;
    setState(() {
      loadingHours = true;
      hours = [];
      hour = null;
      slotError = null;
    });
    try {
      final found = await api.hours(d, c.type);
      if (mounted && g == slotGeneration) {
        setState(
          () => hours = found.where((h) {
            final t = appointmentUtc(d, h);
            return t.isAfter(c.serverNow) && t != c.start;
          }).toList(),
        );
      }
    } catch (e) {
      if (mounted && g == slotGeneration) {
        setState(() => slotError = bookingError(e));
      }
    } finally {
      if (mounted && g == slotGeneration) setState(() => loadingHours = false);
    }
  }

  Future<void> pickDay() async {
    final c = current!;
    final picked = await showDatePicker(
      context: context,
      initialDate: day!,
      firstDate: c.firstDay,
      lastDate: c.lastDay,
      helpText: 'Choose a new appointment date',
    );
    if (picked != null && mounted) {
      setState(() {
        day = picked;
        error = null;
      });
      await slots();
    }
  }

  Future<void> save() async {
    if (saving || hour == null || day == null || current == null) return;
    final c = current!, start = appointmentUtc(day!, hour!);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm new appointment time?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current: ${appointmentLabel(c.start)}'),
              const SizedBox(height: 12),
              Text(
                'New: ${appointmentLabel(start)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                c.type == makeupTrial
                    ? 'Your current time is released only after the new time is confirmed. There is no online payment to reschedule.'
                    : 'This keeps the same appointment and any verified fitting fee. No new payment is taken. Rental dates do not change. Your current time is released only if the new time is successfully reserved.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current time'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm reschedule'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final key = '${c.revision}:${start.millisecondsSinceEpoch}';
    if (pendingKey != key) {
      pendingKey = key;
      pendingId = api.requestId();
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await api.save(c, start, pendingId!);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = bookingError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = current;
    return PopScope(
      canPop: !saving,
      child: PageFrame(
        title: 'Reschedule',
        bottom: c?.eligible == true
            ? Primary(
                saving ? 'Saving…' : 'Confirm new time',
                !loading && !loadingHours && !saving && hour != null
                    ? save
                    : null,
              )
            : null,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : c == null
            ? PageList(
                children: [
                  Text(error ?? 'Appointment unavailable.'),
                  gap(),
                  Primary('Retry', load),
                ],
              )
            : PageList(
                children: [
                  Text(
                    'A new time for your visit',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  gap(16),
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.type,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        gap(8),
                        Text(
                          'Current appointment: ${appointmentLabel(c.start)}',
                        ),
                        if (c.type != makeupTrial) ...[
                          gap(10),
                          Text(
                            c.feePreserved
                                ? 'Your verified fitting fee stays with this appointment.'
                                : 'This change does not create a new fitting fee.',
                          ),
                        ],
                      ],
                    ),
                  ),
                  gap(20),
                  if (!c.eligible) ...[
                    Text(rescheduleReason(c.reason)),
                    gap(12),
                    const Text(
                      'Your current appointment has not been changed.',
                    ),
                    gap(12),
                    Primary('Check latest status', load),
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month_outlined,
                        color: rose,
                      ),
                      title: const Text('New date'),
                      subtitle: Text(
                        '${day!.day}/${day!.month}/${day!.year} · MYT',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: saving ? null : pickDay,
                    ),
                    Text(
                      'Last eligible date: ${c.lastDay.day}/${c.lastDay.month}/${c.lastDay.year}.${c.type == makeupTrial ? '' : ' Linked fittings must remain within their rental dates.'}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    gap(20),
                    const Text(
                      'Available times',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    gap(12),
                    if (loadingHours)
                      const LinearProgressIndicator()
                    else if (slotError != null) ...[
                      Text(slotError!),
                      TextButton(
                        onPressed: saving ? null : slots,
                        child: const Text('Retry available times'),
                      ),
                    ] else if (hours.isEmpty)
                      const Text(
                        'No other times are available on this date. Choose another date; your current visit is unchanged.',
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final h in hours)
                            ChoiceChip(
                              key: ValueKey('reschedule-hour-$h'),
                              label: Text('${h.toString().padLeft(2, '0')}:00'),
                              selected: hour == h,
                              onSelected: saving
                                  ? null
                                  : (_) => setState(() {
                                      hour = h;
                                      error = null;
                                    }),
                            ),
                        ],
                      ),
                    gap(22),
                    const Text(
                      'We will keep your current staff member where available, or assign another qualified member of the team. Changing the visit does not change your gown selection or rental dates.',
                      style: TextStyle(color: muted, fontSize: 13, height: 1.5),
                    ),
                    if (error != null) ...[
                      gap(16),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      TextButton(
                        onPressed: saving ? null : slots,
                        child: const Text('Check availability again'),
                      ),
                    ],
                    gap(16),
                  ],
                ],
              ),
      ),
    );
  }
}
