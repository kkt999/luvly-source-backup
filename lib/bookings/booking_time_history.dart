import 'package:flutter/material.dart';
import 'booking_repository.dart';

class BookingTimeHistory extends StatelessWidget {
  const BookingTimeHistory({super.key, required this.booking});
  final BookingRequest booking;
  @override
  Widget build(BuildContext context) {
    final raw = booking.data['rescheduleHistory'];
    final rows = raw is List
        ? raw
              .whereType<Map>()
              .where((h) => h['fromStartAt'] is int && h['toStartAt'] is int)
              .toList()
        : <Map>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    String label(int ms) =>
        appointmentLabel(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Recent time changes'),
      children: [
        for (final h in rows.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${label(h['fromStartAt'])}\nto ${label(h['toStartAt'])}',
              ),
            ),
          ),
      ],
    );
  }
}
