import 'package:flutter/material.dart';

import '../payments/payment_api.dart';
import 'package_api.dart';
import 'rental_date_fields.dart' show rentalDateLabel, rentalDateText;

class FittingMakeupDraft {
  FittingMakeupDraft(this.service, Map? saved)
    : savedTiming = saved?['timing'] as String?,
      day = saved?['schedule']?['day'] as String?,
      minute = saved?['schedule']?['minuteOfDay'] as int?,
      artistId = saved?['schedule']?['artistId'] as String?,
      appointmentId = saved?['schedule']?['appointmentId'] as String?,
      appointmentRevision = saved?['schedule']?['appointmentRevision'] as int?;

  final PackageServiceItem service;
  final String? savedTiming;
  String? day, artistId, appointmentId;
  int? minute, appointmentRevision;
  bool get isTrial => service.schedulingType == PackageServiceType.makeupTrial;

  static bool handles(PackageServiceItem service) =>
      service.schedulingType == PackageServiceType.makeupHair ||
      service.schedulingType == PackageServiceType.makeupTrial;

  bool matchesTrial(Map trial) =>
      trial['id'] == appointmentId && trial['revision'] == appointmentRevision;

  Map<String, dynamic>? confirmation(String? wedding) {
    if (DateTime.tryParse(wedding ?? '') == null) return null;
    if (isTrial && appointmentId != null) {
      return {
        'serviceId': service.id,
        'appointmentId': appointmentId,
        'appointmentRevision': appointmentRevision,
      };
    }
    if (minute == null || artistId == null) return null;
    if (isTrial && (day == null || day!.compareTo(wedding!) >= 0)) return null;
    return {
      'serviceId': service.id,
      'artistId': artistId,
      'minuteOfDay': minute,
      if (isTrial) 'day': day,
    };
  }
}

class FittingMakeupFields extends StatefulWidget {
  const FittingMakeupFields({
    super.key,
    required this.load,
    required this.drafts,
    required this.wedding,
    required this.enabled,
  });

  final Future<dynamic> Function() load;
  final List<FittingMakeupDraft> drafts;
  final String? wedding;
  final bool enabled;

  @override
  State<FittingMakeupFields> createState() => _FittingMakeupFieldsState();
}

class _FittingMakeupFieldsState extends State<FittingMakeupFields> {
  late Future<dynamic> options = widget.load();

  String clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')} MYT';

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Makeup & hair', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Confirm the time with the makeup artist before sharing the proposal.',
          ),
          const SizedBox(height: 12),
          FutureBuilder<dynamic>(
            future: options,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error is PaymentFailure
                          ? error.message
                          : 'Could not load makeup artists and trial appointments.',
                    ),
                    TextButton(
                      onPressed: widget.enabled
                          ? () => setState(() => options = widget.load())
                          : null,
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              final data = snapshot.data as Map;
              final artists = (data['artists'] as List).cast<Map>();
              final trials = (data['trials'] as List).cast<Map>();
              final wedding = DateTime.tryParse(widget.wedding ?? '');
              if (wedding == null) {
                return const Text(
                  'Set the wedding date in the rental plan before arranging makeup.',
                );
              }
              if (artists.isEmpty) {
                return const Text(
                  'No eligible makeup artists. Ask a manager to assign Bridal Makeup to an active staff account.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final draft in widget.drafts) ...[
                    if (draft != widget.drafts.first) const Divider(height: 28),
                    Text(
                      draft.service.schedulingType!.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (draft.savedTiming != null &&
                        draft.minute == null &&
                        draft.appointmentId == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Previous arrangement · ${draft.savedTiming}',
                        ),
                      ),
                    if (draft.isTrial &&
                        (trials.isNotEmpty || draft.appointmentId != null))
                      DropdownButtonFormField<String>(
                        key: ValueKey((
                          draft.service.id,
                          draft.appointmentId,
                          draft.appointmentRevision,
                        )),
                        initialValue: trials.any(draft.matchesTrial)
                            ? draft.appointmentId
                            : '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Trial booking',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Enter agreed time'),
                          ),
                          for (final row in trials)
                            DropdownMenuItem(
                              value: row['id'] as String,
                              child: Text(
                                '${rentalDateLabel(row['day'] as String)} · ${clock(row['minuteOfDay'] as int)} · ${row['artistName']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: widget.enabled
                            ? (value) => setState(() {
                                draft.appointmentId = value == ''
                                    ? null
                                    : value;
                                draft.appointmentRevision =
                                    trials
                                            .where((row) => row['id'] == value)
                                            .firstOrNull?['revision']
                                        as int?;
                              })
                            : null,
                      ),
                    if (draft.appointmentId != null &&
                        !trials.any(draft.matchesTrial))
                      TextButton(
                        onPressed: widget.enabled
                            ? () => setState(() => draft.appointmentId = null)
                            : null,
                        child: const Text(
                          'Previous trial changed · Enter agreed time',
                        ),
                      ),
                    if (draft.appointmentId == null) ...[
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (!draft.isTrial)
                            Text(rentalDateLabel(widget.wedding!))
                          else
                            OutlinedButton.icon(
                              onPressed: widget.enabled
                                  ? () async {
                                      final last = DateTime(
                                        wedding.year,
                                        wedding.month,
                                        wedding.day - 1,
                                      );
                                      final first = DateTime(
                                        wedding.year - 1,
                                        wedding.month,
                                        wedding.day,
                                      );
                                      final saved = DateTime.tryParse(
                                        draft.day ?? '',
                                      );
                                      final day = await showDatePicker(
                                        context: context,
                                        firstDate: first,
                                        lastDate: last,
                                        initialDate:
                                            saved != null &&
                                                !saved.isBefore(first) &&
                                                !saved.isAfter(last)
                                            ? saved
                                            : last,
                                      );
                                      if (day != null && mounted) {
                                        setState(
                                          () => draft.day = rentalDateText(day),
                                        );
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: Text(
                                draft.day == null
                                    ? 'Choose trial date'
                                    : rentalDateLabel(draft.day!),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: widget.enabled
                                ? () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay(
                                        hour: (draft.minute ?? 600) ~/ 60,
                                        minute: (draft.minute ?? 600) % 60,
                                      ),
                                    );
                                    if (time != null && mounted) {
                                      setState(
                                        () => draft.minute =
                                            time.hour * 60 + time.minute,
                                      );
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.schedule_outlined),
                            label: Text(
                              draft.minute == null
                                  ? 'Choose time (MYT)'
                                  : clock(draft.minute!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue:
                            artists.any((row) => row['id'] == draft.artistId)
                            ? draft.artistId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Makeup artist',
                        ),
                        items: [
                          for (final artist in artists)
                            DropdownMenuItem(
                              value: artist['id'] as String,
                              child: Text(artist['name'] as String),
                            ),
                        ],
                        onChanged: widget.enabled
                            ? (value) => setState(() => draft.artistId = value)
                            : null,
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
