import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:luvly_app/src/auth_service.dart';

class FakeAccounts implements AccountGateway {
  AccountIdentity? user;
  BrideProfile? saved;
  Object? loginError, profileError, saveError;
  Completer<void>? loginWait;
  int loginCalls = 0, registerCalls = 0, resetCalls = 0;
  String? lastEmail, lastPassword;
  final events = StreamController<AccountIdentity?>.broadcast();
  @override
  AccountIdentity? get current => user;
  @override
  Stream<AccountIdentity?> get changes async* {
    yield user;
    yield* events.stream;
  }

  void emit(AccountIdentity? value) {
    user = value;
    events.add(value);
  }

  @override
  Future<void> signIn(String email, String password) async {
    loginCalls++;
    lastEmail = email;
    lastPassword = password;
    if (loginWait != null) await loginWait!.future;
    if (loginError != null) throw loginError!;
    user = AccountIdentity('bride-a', email);
    events.add(user);
  }

  @override
  Future<void> register(String email, String password) async {
    registerCalls++;
    if (user != null) throw FirebaseAuthException(code: 'email-already-in-use');
    user = AccountIdentity('bride-a', email);
    events.add(user);
  }

  @override
  Future<void> signOut() async {
    user = null;
    events.add(null);
  }

  @override
  Future<void> resetPassword(String email) async {
    resetCalls++;
    lastEmail = email;
  }

  @override
  Future<BrideProfile?> loadProfile(String uid) async {
    if (profileError != null) throw profileError!;
    return saved;
  }

  @override
  Future<void> createProfile(AccountIdentity user, BrideProfile profile) async {
    if (saveError != null) throw saveError!;
    saved ??= profile;
  }

  @override
  Future<void> updateProfile(String uid, BrideProfile profile) async {
    if (saveError != null) throw saveError!;
    saved = profile;
  }
}
