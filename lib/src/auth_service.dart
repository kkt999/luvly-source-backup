import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'password_policy.dart';
import 'google_account.dart';
import 'contact_validation.dart';
export 'contact_validation.dart';

class AccountIdentity {
  const AccountIdentity(this.uid, this.email, {this.hasPassword = false});
  final String uid, email;
  final bool hasPassword;
}

class BrideProfile {
  const BrideProfile({
    required this.name,
    required this.phone,
    this.contact = 'Email',
    this.notes = '',
    this.membership = 'Standard',
    this.points = 0,
  });
  final String name, phone, contact, notes, membership;
  final int points;
  factory BrideProfile.fromMap(Map<String, dynamic> data) => BrideProfile(
    name: data['name'] as String,
    phone: data['phone'] as String,
    contact: data['contact'] as String? ?? 'Email',
    notes: data['notes'] as String? ?? '',
    membership: data['membership'] as String? ?? 'Standard',
    points: (data['points'] as num?)?.toInt() ?? 0,
  );
  BrideProfile normalized() {
    final nameError = validateName(name), phoneError = validatePhone(phone);
    if (nameError != null || phoneError != null) {
      throw ContactValidationException(nameError ?? phoneError!);
    }
    return BrideProfile(
      name: normalizeContactName(name),
      phone: normalizeMalaysiaPhone(phone)!,
      contact: contact,
      notes: notes.trim(),
      membership: membership,
      points: points,
    );
  }

  Map<String, Object> get editable {
    final valid = normalized();
    return {
      'name': valid.name,
      'phone': valid.phone,
      'contact': contact,
      'notes': notes.trim(),
    };
  }
}

abstract class AccountGateway {
  AccountIdentity? get current;
  Stream<AccountIdentity?> get changes;
  Future<void> signIn(String email, String password);
  Future<void> register(String email, String password);
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<BrideProfile?> loadProfile(String uid);
  Future<void> createProfile(AccountIdentity user, BrideProfile profile);
  Future<void> updateProfile(String uid, BrideProfile profile);
}

class FirebaseAccountGateway implements AccountGateway, GoogleAccountGateway {
  FirebaseAccountGateway({FirebaseAuth? auth, FirebaseFirestore? database})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = database ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  @override
  bool get googleLinked =>
      _auth.currentUser?.providerData.any(
        (provider) => provider.providerId == 'google.com',
      ) ??
      false;
  @override
  Future<void> signInGoogle() => GoogleAccountAuth(_auth).signIn();
  @override
  Future<void> linkGoogle() => GoogleAccountAuth(_auth).link();
  static const deadline = Duration(seconds: 20);
  AccountIdentity? _identity(User? u) => u == null
      ? null
      : AccountIdentity(
          u.uid,
          u.email ?? '',
          hasPassword: u.providerData.any(
            (provider) => provider.providerId == EmailAuthProvider.PROVIDER_ID,
          ),
        );
  @override
  AccountIdentity? get current => _identity(_auth.currentUser);
  @override
  Stream<AccountIdentity?> get changes =>
      _auth.authStateChanges().map(_identity);
  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> register(String email, String password) async {
    if (validateNewPassword(password) != null) {
      throw FirebaseAuthException(code: 'weak-password');
    }
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();
  @override
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Do not disclose whether an address has an account.
      if (e.code != 'user-not-found') rethrow;
    }
  }

  @override
  Future<BrideProfile?> loadProfile(String uid) async {
    final doc = await _db
        .collection('brides')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(deadline);
    return doc.exists ? BrideProfile.fromMap(doc.data()!) : null;
  }

  @override
  Future<void> createProfile(AccountIdentity user, BrideProfile profile) async {
    final ref = _db.collection('brides').doc(user.uid);
    // Safe to retry after an interrupted signup. Never overwrite an existing profile.
    await _db
        .runTransaction((tx) async {
          if (!(await tx.get(ref)).exists) {
            tx.set(ref, {
              ...profile.editable,
              'uid': user.uid,
              'email': user.email,
              'role': 'bride',
              'membership': 'Standard',
              'points': 0,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        })
        .timeout(deadline);
  }

  @override
  Future<void> updateProfile(String uid, BrideProfile profile) async {
    final ref = _db.collection('brides').doc(uid);
    final valid = profile.normalized();
    // Transactions fail offline instead of silently queuing a purported successful save.
    await _db
        .runTransaction((tx) async {
          final stored = (await tx.get(ref)).data();
          if (stored == null) throw StateError('Missing profile');
          tx.update(ref, {
            'name': valid.name,
            'phone': valid.phone,
            // Older profiles can lack these fields required by Firestore rules.
            if (stored['contact'] == null) 'contact': valid.contact,
            if (stored['notes'] == null) 'notes': valid.notes,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        })
        .timeout(deadline);
  }
}

String accountError(Object error) {
  if (error is ContactValidationException) return error.message;
  if (error is TimeoutException) {
    return 'The connection timed out. Check your internet and retry.';
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'google-cancelled' ||
      'popup-closed-by-user' ||
      'cancelled-popup-request' =>
        'Google sign-in was cancelled. You can try again or use email and password.',
      'google-configuration-required' ||
      'google-platform-not-configured' ||
      'unauthorized-domain' =>
        'Google sign-in setup is not complete. Please use email and password for now.',
      'account-exists-with-different-credential' =>
        'Sign in with your existing login first, then link Google from your profile.',
      'credential-already-in-use' =>
        'This Google account is already linked to another Luvly account. No accounts were merged.',
      'provider-already-linked' => 'Google is already linked to this account.',
      'requires-recent-login' => 'Please sign in again before linking Google.',
      'popup-blocked' => 'Allow the Google sign-in popup and try again.',
      'google-already-signed-in' =>
        'Use Link Google in your profile, or sign out first.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-login-credentials' =>
        'Email or password is incorrect. Please try again.',
      'email-already-in-use' =>
        'Unable to create this account. Try signing in or resetting your password.',
      'weak-password' || 'password-does-not-meet-requirements' =>
        'Use 8–128 characters with uppercase, lowercase, a number and a symbol.',
      'invalid-email' => 'Enter a valid email address.',
      'user-disabled' =>
        'This account is unavailable. Please contact Luvly support.',
      'too-many-requests' =>
        'Too many attempts. Please wait a while before trying again.',
      'network-request-failed' ||
      'unavailable' => 'Check your internet connection and try again.',
      'permission-denied' =>
        'Your profile could not be accessed. Please contact Luvly support if retrying does not help.',
      'operation-not-allowed' =>
        'This sign-in method is currently unavailable. Please use another method or contact Luvly support.',
      _ => 'Unable to complete the request. Please try again.',
    };
  }
  return 'Unable to complete the request. Please try again.';
}

String? validateEmail(String? value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((value ?? '').trim()) &&
        (value ?? '').trim().length <= 254
    ? null
    : 'Enter a valid email address';

enum AccountPhase { loading, signedOut, completeProfile, ready, blocked }

class AccountSession extends ChangeNotifier {
  AccountSession(this.gateway);
  final AccountGateway gateway;
  AccountPhase phase = AccountPhase.loading;
  AccountIdentity? identity;
  BrideProfile? profile;
  String? error;
  String pendingName = '', pendingPhone = '';
  bool busy = false, _working = false, _disposed = false;
  int _revision = 0;
  StreamSubscription<AccountIdentity?>? _subscription;

  void start() {
    _subscription ??= gateway.changes.listen(
      (user) {
        if (!_working) unawaited(_resolve(user));
      },
      onError: (Object e) {
        error = accountError(e);
        phase = AccountPhase.blocked;
        _notify();
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _resolve(AccountIdentity? user) async {
    final revision = ++_revision;
    identity = user;
    profile = null;
    error = null;
    phase = user == null ? AccountPhase.signedOut : AccountPhase.loading;
    _notify();
    if (user == null) return;
    try {
      final loaded = await gateway.loadProfile(user.uid);
      if (_disposed || revision != _revision) return;
      if (gateway.current?.uid != user.uid) {
        await _resolve(gateway.current);
        return;
      }
      profile = loaded;
      phase = loaded == null
          ? AccountPhase.completeProfile
          : AccountPhase.ready;
    } catch (e) {
      if (_disposed || revision != _revision) return;
      error = accountError(e);
      phase = AccountPhase.blocked;
    }
    _notify();
  }

  Future<void> _accountAction(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    _working = true;
    ++_revision;
    error = null;
    _notify();
    try {
      await action();
      await _resolve(gateway.current);
    } catch (e) {
      identity = gateway.current;
      profile = null;
      error = accountError(e);
      phase = identity == null ? AccountPhase.signedOut : AccountPhase.blocked;
    } finally {
      _working = false;
      busy = false;
      _notify();
    }
  }

  Future<void> signIn(String email, String password) =>
      _accountAction(() => gateway.signIn(email, password));
  bool get supportsGoogle => gateway is GoogleAccountGateway;
  Future<void> signInGoogle() => _accountAction(() async {
    final google = gateway;
    if (google is! GoogleAccountGateway) throw StateError('Google unavailable');
    pendingName = '';
    pendingPhone = '';
    await (google as GoogleAccountGateway).signInGoogle();
  });
  Future<void> register(
    String email,
    String password,
    String name,
    String phone,
  ) => _accountAction(() async {
    final valid = BrideProfile(name: name, phone: phone).normalized();
    pendingName = valid.name;
    pendingPhone = valid.phone;
    await gateway.register(email, password);
    await gateway.createProfile(
      gateway.current!,
      BrideProfile(name: pendingName, phone: pendingPhone),
    );
  });
  Future<void> completeProfile(String name, String phone) =>
      _accountAction(() async {
        final valid = BrideProfile(name: name, phone: phone).normalized();
        pendingName = valid.name;
        pendingPhone = valid.phone;
        await gateway.createProfile(
          gateway.current!,
          BrideProfile(name: pendingName, phone: pendingPhone),
        );
      });
  Future<void> retry() => _accountAction(() async {});
  Future<void> signOut() => _accountAction(() async {
    await gateway.signOut();
    pendingName = '';
    pendingPhone = '';
  });
  Future<void> updateProfile(BrideProfile value) async {
    final valid = value.normalized();
    final user = identity!;
    await gateway.updateProfile(user.uid, valid);
    if (identity?.uid != user.uid || _disposed) return;
    profile = valid;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    _subscription?.cancel();
    super.dispose();
  }
}

class AccountScope extends InheritedNotifier<AccountSession> {
  const AccountScope({
    super.key,
    required AccountSession session,
    required super.child,
  }) : super(notifier: session);
  static AccountSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()!.notifier!;
  static AccountSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()?.notifier;
}
