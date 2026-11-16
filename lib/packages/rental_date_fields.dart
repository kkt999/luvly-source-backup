import 'package:flutter/material.dart';
import '../src/design.dart' show CustomerUi;
import '../support/assistant_launcher.dart';

String rentalDateText(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String rentalDateLabel(String value) {
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class PackageRentalDatesCard extends StatelessWidget {
  const PackageRentalDatesCard({super.key, required this.dates, this.onEdit});

  final Map<String, String>? dates;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = dates;
    Widget date(String key, String label, TextStyle? style) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(rentalDateLabel(selection![key]!), style: style),
      ],
    );
    return DecoratedBox(
      decoration: CustomerUi.tintedCard,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          onEdit == null || selection == null ? 12 : 6,
          14,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your rental dates',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (selection != null && onEdit != null)
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onEdit,
                        child: const Text(
                          'Change dates',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (selection == null) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Choose rental dates'),
              ),
            ] else ...[
              if (onEdit == null) const SizedBox(height: 8),
              date(
                'eventDate',
                'Wedding / event date',
                theme.textTheme.titleLarge,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: date(
                      'pickupDate',
                      'Pickup',
                      theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: date(
                      'returnDate',
                      'Return',
                      theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Rental dates are subject to staff confirmation.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RentalDatesSummary extends StatelessWidget {
  const RentalDatesSummary({super.key, required this.dates, this.onEdit});
  final Map<String, String> dates;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Your rental dates',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Change dates'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Wedding / event · ${rentalDateLabel(dates['eventDate']!)}'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in const {
                'pickupDate': 'Pickup',
                'returnDate': 'Return',
              }.entries)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        rentalDateLabel(dates[entry.key]!),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class PackageDatesScreen extends StatefulWidget {
  const PackageDatesScreen({
    super.key,
    required this.initialDates,
    required this.allowedDays,
  });
  final Map<String, String> initialDates;
  final int allowedDays;

  @override
  State<PackageDatesScreen> createState() => _PackageDatesScreenState();
}

class _PackageDatesScreenState extends State<PackageDatesScreen> {
  late final DateTime today;
  late final DateTime lastEvent;
  DateTime? event, pickup, returned;
  bool showDateOptions = false;
  bool suggested = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    today = DateTime(now.year, now.month, now.day);
    lastEvent = DateUtils.addDaysToDate(today, 365);
    final savedEvent = DateTime.tryParse(
      widget.initialDates['eventDate'] ?? '',
    );
    if (savedEvent == null || !_within(savedEvent, today, lastEvent)) return;
    event = savedEvent;
    final savedPickup = DateTime.tryParse(
      widget.initialDates['pickupDate'] ?? '',
    );
    final savedReturn = DateTime.tryParse(
      widget.initialDates['returnDate'] ?? '',
    );
    if (savedPickup != null && _within(savedPickup, firstPickup, savedEvent)) {
      pickup = savedPickup;
      if (savedReturn != null && _within(savedReturn, savedEvent, lastReturn)) {
        returned = savedReturn;
        return;
      }
    }
    suggestDates();
  }

  static bool _within(DateTime date, DateTime first, DateTime last) =>
      !date.isBefore(first) && !date.isAfter(last);

  DateTime get firstPickup {
    final earliest = DateUtils.addDaysToDate(event!, 1 - widget.allowedDays);
    return earliest.isBefore(today) ? today : earliest;
  }

  DateTime get lastReturn =>
      DateUtils.addDaysToDate(pickup!, widget.allowedDays - 1);

  DateTime get suggestedReturn {
    final dayAfter = DateUtils.addDaysToDate(event!, 1);
    return dayAfter.isAfter(lastReturn) ? lastReturn : dayAfter;
  }

  void suggestDates() {
    final dayBefore = DateUtils.addDaysToDate(event!, -1);
    pickup ??= dayBefore.isBefore(firstPickup) ? firstPickup : dayBefore;
    returned = suggestedReturn;
    suggested = true;
  }

  void setEvent(DateTime date) {
    if (DateUtils.isSameDay(date, event)) return;
    setState(() {
      event = date;
      showDateOptions = false;
      if (suggested || pickup == null || !_within(pickup!, firstPickup, date)) {
        pickup = null;
      } else if (returned != null && _within(returned!, date, lastReturn)) {
        return;
      }
      suggestDates();
    });
  }

  Future<void> changeEvent() async {
    final date = await showDatePicker(
      context: context,
      initialDate: event,
      firstDate: today,
      lastDate: lastEvent,
      currentDate: today,
      helpText: 'Wedding / event date',
    );
    if (mounted && date != null) setEvent(date);
  }

  void saveDates() => Navigator.pop(context, {
    'eventDate': rentalDateText(event!),
    'pickupDate': rentalDateText(pickup!),
    'returnDate': rentalDateText(returned!),
  });

  Widget dateChoices(
    BuildContext context, {
    required String label,
    required DateTime first,
    required DateTime last,
    required DateTime? selected,
    required ValueChanged<DateTime> onSelected,
  }) {
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (
              var date = first;
              !date.isAfter(last);
              date = DateUtils.addDaysToDate(date, 1)
            )
              ChoiceChip(
                key: ValueKey('$label-${rentalDateText(date)}'),
                label: Text(localizations.formatMediumDate(date)),
                selected: DateUtils.isSameDay(date, selected),
                onSelected: (_) => onSelected(date),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const AssistantExclusion(child: Text('Rental dates')),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              if (event == null) ...[
                Text(
                  'When is your event?',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text('Choose the day you’ll wear your gown.'),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: CalendarDatePicker(
                    initialDate: event,
                    firstDate: today,
                    lastDate: lastEvent,
                    currentDate: today,
                    onDateChanged: setEvent,
                  ),
                ),
              ] else ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Wedding / event'),
                    subtitle: Text(rentalDateLabel(rentalDateText(event!))),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: changeEvent,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggested
                              ? 'Suggested rental dates'
                              : 'Pickup & return',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (label, date) in [
                              ('Pickup', pickup!),
                              ('Return', returned!),
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      Text(
                                        rentalDateLabel(rentalDateText(date)),
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => showDateOptions = !showDateOptions,
                          ),
                          icon: Icon(
                            showDateOptions ? Icons.expand_less : Icons.tune,
                          ),
                          label: Text(
                            showDateOptions
                                ? 'Hide date options'
                                : 'Adjust dates',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showDateOptions) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Up to ${widget.allowedDays} calendar days, including pickup and return.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  dateChoices(
                    context,
                    label: 'Pickup',
                    first: firstPickup,
                    last: event!,
                    selected: pickup,
                    onSelected: (date) => setState(() {
                      pickup = date;
                      if (!_within(returned!, event!, lastReturn)) {
                        returned = suggestedReturn;
                      }
                      suggested = false;
                    }),
                  ),
                  const SizedBox(height: 20),
                  dateChoices(
                    context,
                    label: 'Return',
                    first: event!,
                    last: lastReturn,
                    selected: returned,
                    onSelected: (date) => setState(() {
                      returned = date;
                      suggested = false;
                    }),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: returned == null ? null : saveDates,
                child: const Text('Use these dates'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
