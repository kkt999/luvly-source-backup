import 'package:flutter/material.dart';
import '../shared/list_controls.dart';
import '../payments/payment_api.dart';
import 'booking_api.dart';

const scheduleMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String scheduleMonth(DateTime d) => bookingDay(d).substring(0, 7);
String scheduleTime(int hour) => '${hour.toString().padLeft(2, '0')}:00';
String scheduleDate(DateTime d) =>
    '${d.day} ${scheduleMonths[d.month - 1]} ${d.year}';
bool validScheduleWindow(Object? own) =>
    own == null ||
    own is Map &&
        own['available'] is bool &&
        own['startHour'] is int &&
        own['endHour'] is int &&
        own['startHour'] >= 9 &&
        own['endHour'] <= 18 &&
        own['startHour'] < own['endHour'];
DateTime scheduleParseDay(Object? value) {
  final d = value is String ? DateTime.tryParse(value) : null;
  if (d == null || bookingDay(d) != value) {
    throw const PaymentFailure(
      'Could not verify schedule dates. Refresh and try again.',
    );
  }
  return DateTime(d.year, d.month, d.day);
}

class ScheduleVisit {
  ScheduleVisit(Map<String, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String,
      type = data['type'] as String,
      status = data['status'] as String,
      revision = data['revision'] as int?,
      assignedStaffName = data['assignedStaffName'] as String? ?? '',
      start = DateTime.fromMillisecondsSinceEpoch(
        data['startAt'] as int,
        isUtc: true,
      ).add(const Duration(hours: 8));
  final String id, name, type, status;
  final int? revision;
  final String assignedStaffName;
  final DateTime start;
  String get time =>
      '${scheduleTime(start.hour)}–${scheduleTime(start.hour + 1)}';
  String get statusLabel => status == 'AwaitingPayment'
      ? 'Awaiting payment'
      : status == 'NoShow'
      ? 'Did not attend'
      : status;
  bool matches(String query) =>
      matchesListSearch(query, [name, type, statusLabel, assignedStaffName]);
}

class ScheduleDay {
  ScheduleDay(this.day, this.own, this.visits);
  final DateTime day;
  final Map<String, dynamic>? own;
  final List<ScheduleVisit> visits;
  bool get unavailable => own?['available'] == false;
  bool get customHours =>
      own?['available'] == true &&
      (own!['startHour'] != 10 || own!['endHour'] != 17);
  String get window => own == null
      ? 'Normal hours'
      : '${scheduleTime(own!['startHour'])}–${scheduleTime(own!['endHour'])}';
}

class ScheduleMonth {
  ScheduleMonth.fromJson(Map<String, dynamic> data, String requested) {
    try {
      if (data['limited'] != false ||
          data['month'] != requested ||
          data['days'] is! List) {
        throw const FormatException();
      }
      today = scheduleParseDay(data['today']);
      until = scheduleParseDay(data['editableUntil']);
      scope = data['scope'] == 'all' ? 'all' : 'own';
      canViewAll = data['canViewAll'] == true;
      final month = DateTime.parse('$requested-01');
      final count = DateTime(month.year, month.month + 1, 0).day;
      for (final raw in data['days']) {
        final item = Map<String, dynamic>.from(raw),
            day = scheduleParseDay(item['day']);
        if (scheduleMonth(day) != requested ||
            days.containsKey(bookingDay(day)) ||
            item['appointments'] is! List) {
          throw const FormatException();
        }
        final own = item['own'] == null
            ? null
            : Map<String, dynamic>.from(item['own']);
        if (!validScheduleWindow(own)) throw const FormatException();
        final visits = (item['appointments'] as List)
            .map((v) => ScheduleVisit(Map<String, dynamic>.from(v)))
            .toList();
        if (visits.any((v) => bookingDay(v.start) != bookingDay(day))) {
          throw const FormatException();
        }
        days[bookingDay(day)] = ScheduleDay(day, own, visits);
      }
      if (days.length != count || until.isBefore(today)) {
        throw const FormatException();
      }
    } catch (_) {
      throw const PaymentFailure(
        'Could not verify the complete schedule. Refresh and try again.',
      );
    }
  }
  late final DateTime today, until;
  late final String scope;
  late final bool canViewAll;
  final days = <String, ScheduleDay>{};
  bool editable(DateTime day) => !day.isBefore(today) && !day.isAfter(until);
}

class ScheduleCalendar extends StatelessWidget {
  const ScheduleCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.data,
    required this.query,
    required this.filter,
    required this.onSelect,
  });
  final DateTime month, selected;
  final ScheduleMonth data;
  final String query, filter;
  final ValueChanged<DateTime> onSelect;
  List<ScheduleVisit> visits(ScheduleDay d) => filter == 'Unavailable'
      ? []
      : d.visits.where((v) => v.matches(query)).toList();
  bool showAbsence(ScheduleDay d) =>
      d.unavailable &&
      filter != 'Appointments' &&
      matchesListSearch(query, ['Unavailable', d.window]);
  bool showCustomHours(ScheduleDay d) =>
      d.customHours &&
      filter == 'All entries' &&
      matchesListSearch(query, ['Available hours', d.window]);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact =
          box.maxWidth < 550 || MediaQuery.textScalerOf(context).scale(12) > 18;
      final first = DateTime(month.year, month.month, 1),
          count = DateTime(month.year, month.month + 1, 0).day;
      final offset = first.weekday - 1, weeks = (offset + count + 6) ~/ 7;
      final scheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          Row(
            children: [
              for (final label in [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
          for (var week = 0; week < weeks; week++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final number = week * 7 + weekday - offset + 1;
                          if (number < 1 || number > count) {
                            return Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest,
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: .35,
                                  ),
                                ),
                              ),
                            );
                          }
                          final day = DateTime(month.year, month.month, number),
                              entry = data.days[bookingDay(day)]!;
                          final active = DateUtils.isSameDay(day, selected),
                              today = DateUtils.isSameDay(day, data.today),
                              editable = data.editable(day);
                          final rows = visits(entry),
                              absence = showAbsence(entry),
                              customHours = showCustomHours(entry);
                          final label =
                              '${scheduleDate(day)}, ${rows.length} matching visits${absence ? ', unavailable ${entry.window}' : ''}${active ? ', selected' : ''}${editable ? '' : ', read only'}';
                          return Semantics(
                            selected: active,
                            button: true,
                            label: label,
                            child: Material(
                              color: active
                                  ? scheme.primaryContainer.withValues(
                                      alpha: .4,
                                    )
                                  : scheme.surface,
                              child: InkWell(
                                key: ValueKey(
                                  'schedule-day-${bookingDay(day)}',
                                ),
                                onTap: () => onSelect(day),
                                child: Container(
                                  constraints: BoxConstraints(
                                    minHeight: compact ? 76 : 118,
                                  ),
                                  padding: EdgeInsets.all(compact ? 4 : 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: active
                                          ? scheme.primary
                                          : scheme.outlineVariant.withValues(
                                              alpha: .55,
                                            ),
                                      width: active ? 1.5 : .5,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: today
                                              ? scheme.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                        child: Text(
                                          '$number',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: today
                                                ? scheme.onPrimary
                                                : editable
                                                ? scheme.onSurface
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      if (customHours)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 5,
                                          ),
                                          child: Tooltip(
                                            message:
                                                'Available window · ${entry.window}',
                                            child: Text(
                                              compact
                                                  ? 'Hours'
                                                  : 'Hours ${entry.window}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (absence)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 5,
                                          ),
                                          child: Tooltip(
                                            message:
                                                'Unavailable · ${entry.window}',
                                            child: Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(3),
                                              color: const Color(0xFFF7ECF0),
                                              child: Text(
                                                compact
                                                    ? 'Away'
                                                    : 'Unavailable',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: compact ? 10 : 11,
                                                  color: scheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (rows.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        if (compact)
                                          Text(
                                            '${rows.length} visits',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF46665B),
                                            ),
                                          )
                                        else
                                          for (final visit in rows.take(2))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 3,
                                              ),
                                              child: Tooltip(
                                                message:
                                                    '${visit.time} · ${visit.name}\n${visit.type} · ${visit.statusLabel}',
                                                child: Container(
                                                  width: double.infinity,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        visit.status ==
                                                            'Confirmed'
                                                        ? const Color(
                                                            0xFFEAF2EE,
                                                          )
                                                        : scheme
                                                              .surfaceContainerLow,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${scheduleTime(visit.start.hour)} ${visit.name}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        if (!compact && rows.length > 2)
                                          Text(
                                            '+${rows.length - 2} more',
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
