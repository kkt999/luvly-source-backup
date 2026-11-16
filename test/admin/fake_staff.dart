import 'dart:async';
import 'package:luvly_app/admin/portal_auth.dart';

class FakeStaff implements StaffAccessGateway {
  final channels = <String, StreamController<StaffAccessSnapshot>>{};
  final initial = <String, StaffAccessSnapshot>{};
  @override
  Stream<StaffAccessSnapshot> watch(String uid) async* {
    final channel = channels.putIfAbsent(
      uid,
      () => StreamController<StaffAccessSnapshot>.broadcast(),
    );
    if (initial.containsKey(uid)) yield initial[uid]!;
    yield* channel.stream;
  }

  void emit(String uid, StaffAccessSnapshot snapshot) {
    initial[uid] = snapshot;
    channels[uid]?.add(snapshot);
  }

  Future<void> close() async {
    for (final channel in channels.values) {
      await channel.close();
    }
  }
}
