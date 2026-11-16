import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

const stableBackendOrigin =
    'https://luvly-api-127519727979.asia-southeast1.run.app';
const useLocalBackend = bool.fromEnvironment(
  'LUVLY_LOCAL_BACKEND',
  defaultValue: false,
);

/// The local staff portal uses its co-located API, independently of the mobile
/// HTTPS tunnel. This fixed exception never comes from Firestore or user input.
String? localPortalBackend(Uri page, {required bool isWeb}) {
  if (!isWeb ||
      page.scheme != 'http' ||
      page.userInfo.isNotEmpty ||
      !['localhost', '127.0.0.1'].contains(page.host) ||
      page.port != 5000) {
    return null;
  }
  return 'http://127.0.0.1:8787';
}

bool isLocalPortalEndpoint(Uri endpoint) =>
    localPortalBackend(Uri.base, isWeb: kIsWeb) == endpoint.origin &&
    endpoint.scheme == 'http' &&
    endpoint.host == '127.0.0.1' &&
    endpoint.port == 8787;

/// This admin-managed document is the only discovery authority. Never resolve
/// a backend from a user profile, query parameter or an HTTP redirect.
Future<String> loadBackendEndpoint() async {
  final local = useLocalBackend
      ? localPortalBackend(Uri.base, isWeb: kIsWeb)
      : null;
  if (local != null) return local;
  final snapshot = await FirebaseFirestore.instance
      .doc('runtimeConfig/backend')
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 10));
  return validateBackendEndpoint(snapshot.data());
}

String validateBackendEndpoint(Map<String, dynamic>? data) {
  final raw = data?['baseUrl'];
  final uri = raw is String ? Uri.tryParse(raw) : null;
  if (data?['schemaVersion'] != 1 ||
      data?['environment'] != 'sandbox' ||
      data?['enabled'] != true ||
      raw is! String ||
      !(raw == stableBackendOrigin ||
          raw == '$stableBackendOrigin/' ||
          RegExp(
            r'^https://[a-z0-9]+(?:-[a-z0-9]+)*\.trycloudflare\.com/?$',
          ).hasMatch(raw)) ||
      uri == null ||
      uri.scheme != 'https' ||
      !(uri.host == Uri.parse(stableBackendOrigin).host ||
          RegExp(
            r'^[a-z0-9]+(?:-[a-z0-9]+)*\.trycloudflare\.com$',
          ).hasMatch(uri.host)) ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !['', '/'].contains(uri.path)) {
    throw const FormatException('Luvly backend configuration unavailable');
  }
  return uri.origin;
}
