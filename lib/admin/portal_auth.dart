import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:stream_transform/stream_transform.dart';
import '../src/auth_service.dart';
import 'model.dart' show PortalRole;

/// Assigned by a trusted project administrator, never by a signup form.
class StaffAccess {
  const StaffAccess(this.name, this.role, {this.frontDesk = false});
  final String name;
  final PortalRole role;
  final bool frontDesk;
  bool get boutiqueOperations => role == PortalRole.manager || frontDesk;

  static StaffAccess? fromMap(Map<String, dynamic>? data) {
    if (data == null || data['active'] != true) return null;
    final name = data['name'];
    final role = switch (data['role']) {
      'manager' => PortalRole.manager,
      'staff' => PortalRole.staff,
      _ => null,
    };
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 100 ||
        role == null) {
      return null;
    }
    return StaffAccess(name.trim(), role);
  }
}

class StaffAccessSnapshot {
  const StaffAccessSnapshot(this.access, {this.confirmed = true});
  final StaffAccess? access;
  final bool confirmed;
}

abstract class StaffAccessGateway {
  Stream<StaffAccessSnapshot> watch(String uid);
}

class FirebaseStaffAccessGateway implements StaffAccessGateway {
  FirebaseStaffAccessGateway({FirebaseFirestore? database})
    : _database = database ?? FirebaseFirestore.instance;
  final FirebaseFirestore _database;

  @override
  Stream<StaffAccessSnapshot> watch(String uid) {
    final staff = _database.collection('staff').doc(uid);
    final scheduling = _database.collection('staffScheduling').doc(uid);
    return staff.snapshots(includeMetadataChanges: true).switchMap((account) {
      // Only server-confirmed account data can grant workspace access.
      final confirmed =
          !account.metadata.isFromCache && !account.metadata.hasPendingWrites;
      final access = confirmed ? StaffAccess.fromMap(account.data()) : null;
      if (access == null || access.role == PortalRole.manager) {
        return Stream.value(StaffAccessSnapshot(access, confirmed: confirmed));
      }
      return scheduling.snapshots(includeMetadataChanges: true).map((profile) {
        final frontDesk =
            !profile.metadata.isFromCache &&
            !profile.metadata.hasPendingWrites &&
            profile.data()?['jobRole'] == 'FrontDesk';
        return StaffAccessSnapshot(
          StaffAccess(access.name, access.role, frontDesk: frontDesk),
        );
      });
    });
  }
}

enum PortalPhase { checking, signedOut, ready, denied, blocked }

class PortalSession extends ChangeNotifier {
  PortalSession(this.accounts, this.staff);
  final AccountGateway accounts;
  final StaffAccessGateway staff;
  PortalPhase phase = PortalPhase.checking;
  AccountIdentity? identity;
  StaffAccess? access;
  String? error;
  bool busy = false;
  bool _started = false, _disposed = false;
  int _revision = 0;
  StreamSubscription<AccountIdentity?>? _authSubscription;
  StreamSubscription<StaffAccessSnapshot>? _accessSubscription;
  Timer? _deadline;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _acceptIdentity(accounts.current);
    _authSubscription = accounts.changes.listen(
      _acceptIdentity,
      onError: (Object e) {
        _invalidate();
        phase = PortalPhase.blocked;
        error = accountError(e);
        _notify();
      },
    );
  }

  void _invalidate() {
    _revision++;
    _accessSubscription?.cancel();
    _accessSubscription = null;
    _deadline?.cancel();
    _deadline = null;
    access = null;
  }

  void _acceptIdentity(AccountIdentity? user) {
    if (_disposed) return;
    if (user != null &&
        user.uid == identity?.uid &&
        _accessSubscription != null) {
      return;
    }
    _invalidate();
    identity = user;
    error = null;
    if (user == null) {
      phase = PortalPhase.signedOut;
      _notify();
      return;
    }
    phase = PortalPhase.checking;
    final revision = _revision;
    _waitForServer(revision);
    _notify();
    try {
      _accessSubscription = staff
          .watch(user.uid)
          .listen(
            (snapshot) {
              if (_disposed || revision != _revision) return;
              access = snapshot.confirmed ? snapshot.access : null;
              error = null;
              if (!snapshot.confirmed) {
                phase = PortalPhase.checking;
                _waitForServer(revision);
              } else {
                _deadline?.cancel();
                _deadline = null;
                phase = access == null ? PortalPhase.denied : PortalPhase.ready;
              }
              _notify();
            },
            onError: (Object e) {
              if (_disposed || revision != _revision) return;
              _accessFailed();
            },
            onDone: () {
              if (_disposed || revision != _revision) return;
              _accessFailed();
            },
          );
    } catch (_) {
      _accessFailed();
    }
  }

  void _waitForServer(int revision) {
    _deadline ??= Timer(const Duration(seconds: 20), () {
      _deadline = null;
      if (_disposed || revision != _revision) return;
      access = null;
      phase = PortalPhase.blocked;
      error =
          'Cannot verify workspace access. Check your connection and retry.';
      _notify();
    });
  }

  void _accessFailed() {
    _invalidate();
    phase = PortalPhase.blocked;
    error =
        'Cannot verify workspace access. Retry or contact your project administrator.';
    _notify();
  }

  void retry() {
    if (busy || _disposed) return;
    _invalidate();
    _acceptIdentity(accounts.current);
  }

  Future<void> signIn(String email, String password) async {
    if (busy || _disposed || phase != PortalPhase.signedOut) return;
    busy = true;
    error = null;
    _notify();
    try {
      await accounts.signIn(email.trim(), password);
      _acceptIdentity(accounts.current);
    } catch (e) {
      if (!_disposed) error = accountError(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> resetPassword(String email) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await accounts.resetPassword(email.trim());
      return true;
    } catch (e) {
      if (!_disposed) error = accountError(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> signOut() async {
    if (busy || _disposed) return;
    busy = true;
    _invalidate();
    phase = PortalPhase.checking;
    error = null;
    _notify();
    try {
      await accounts.signOut();
      _acceptIdentity(accounts.current);
    } catch (e) {
      if (!_disposed) {
        phase = PortalPhase.blocked;
        error = accountError(e);
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    _authSubscription?.cancel();
    super.dispose();
  }
}
