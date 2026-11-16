import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Authentication only. Calendar permissions are a separate, explicit consent.
abstract interface class GoogleAccountGateway {
  Future<void> signInGoogle();
  Future<void> linkGoogle();
  bool get googleLinked;
}

class GoogleAccountAuth {
  GoogleAccountAuth(
    this.auth, {
    Future<OAuthCredential> Function()? credentialLoader,
  }) : _credentialLoader = credentialLoader;
  final FirebaseAuth auth;
  final Future<OAuthCredential> Function()? _credentialLoader;
  static Future<void>? _initialization;

  Future<OAuthCredential> _nativeCredential() async {
    if (_credentialLoader != null) return _credentialLoader();
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw FirebaseAuthException(code: 'google-platform-not-configured');
    }
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize());
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw FirebaseAuthException(code: 'google-configuration-required');
      }
      return GoogleAuthProvider.credential(idToken: token);
    } on GoogleSignInException catch (error) {
      throw FirebaseAuthException(
        code: switch (error.code) {
          GoogleSignInExceptionCode.canceled => 'google-cancelled',
          GoogleSignInExceptionCode.clientConfigurationError ||
          GoogleSignInExceptionCode.providerConfigurationError =>
            'google-configuration-required',
          _ => 'google-sign-in-failed',
        },
      );
    }
  }

  GoogleAuthProvider _provider() =>
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});

  Future<void> signIn() async {
    // Never silently replace a signed-in user's identity.
    if (auth.currentUser != null) {
      throw FirebaseAuthException(code: 'google-already-signed-in');
    }
    if (kIsWeb) {
      await auth.signInWithPopup(_provider());
    } else {
      await auth.signInWithCredential(await _nativeCredential());
    }
  }

  Future<void> link() async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    // Use link, never signIn, so existing profile/orders remain on this UID.
    if (kIsWeb) {
      await user.linkWithPopup(_provider());
    } else {
      final credential = await _nativeCredential();
      if (auth.currentUser?.uid != user.uid) {
        throw FirebaseAuthException(code: 'requires-recent-login');
      }
      await user.linkWithCredential(credential);
    }
    await user.reload();
  }
}
