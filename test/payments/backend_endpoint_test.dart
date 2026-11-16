import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/backend_endpoint.dart';
import 'package:luvly_app/payments/payment_api.dart';

void main() {
  test('only the known local web portal can select the fixed loopback API', () {
    for (final host in ['localhost', '127.0.0.1']) {
      expect(
        localPortalBackend(Uri.parse('http://$host:5000/'), isWeb: true),
        'http://127.0.0.1:8787',
      );
      expect(
        localPortalBackend(
          Uri.parse('http://$host:5000/?backend=https://evil.example'),
          isWeb: true,
        ),
        'http://127.0.0.1:8787',
      );
      expect(
        localPortalBackend(Uri.parse('http://$host:5000/'), isWeb: false),
        isNull,
      );
    }
    for (final page in [
      'https://localhost:5000/',
      'http://localhost:5001/',
      'http://localhost.evil.example:5000/',
      'http://evil.example:5000/',
      'http://user@localhost:5000/',
      'file:///localhost:5000/',
    ]) {
      expect(localPortalBackend(Uri.parse(page), isWeb: true), isNull);
    }
    // Mobile/server-provided runtime config may never opt into HTTP.
    expect(
      () => validateBackendEndpoint({
        'schemaVersion': 1,
        'environment': 'sandbox',
        'enabled': true,
        'baseUrl': 'http://127.0.0.1:8787',
      }),
      throwsFormatException,
    );
  });
  Map<String, dynamic> config(String url) => {
    'schemaVersion': 1,
    'environment': 'sandbox',
    'enabled': true,
    'baseUrl': url,
  };
  test('discovery accepts only an enabled sandbox HTTPS tunnel origin', () {
    expect(
      validateBackendEndpoint(config(stableBackendOrigin)),
      stableBackendOrigin,
    );
    expect(
      validateBackendEndpoint(config('$stableBackendOrigin/')),
      stableBackendOrigin,
    );
    expect(
      validateBackendEndpoint(config('https://new-luvly.trycloudflare.com/')),
      'https://new-luvly.trycloudflare.com',
    );
    for (final url in [
      'http://new-luvly.trycloudflare.com',
      'https://evil.example',
      'https://another-api-127519727979.asia-southeast1.run.app',
      'https://luvly-api-999999999999.asia-southeast1.run.app',
      '$stableBackendOrigin.evil.example',
      '$stableBackendOrigin:443',
      '$stableBackendOrigin/v1',
      '$stableBackendOrigin?x=1',
      'https://new-luvly.trycloudflare.com.evil.example',
      'https://user@new-luvly.trycloudflare.com',
      'https://new-luvly.trycloudflare.com:443',
      'https://new-luvly.trycloudflare.com/path',
      'https://new-luvly.trycloudflare.com?x=1',
      'https://new-luvly.trycloudflare.com#fragment',
    ]) {
      expect(() => validateBackendEndpoint(config(url)), throwsFormatException);
    }
    for (final data in [
      null,
      <String, dynamic>{},
      {...config('https://new-luvly.trycloudflare.com'), 'enabled': false},
      {...config('https://new-luvly.trycloudflare.com'), 'environment': 'live'},
      {...config('https://new-luvly.trycloudflare.com'), 'schemaVersion': 2},
    ]) {
      expect(() => validateBackendEndpoint(data), throwsFormatException);
    }
  });
  test(
    'Retry resolves a changed endpoint without recreating the API',
    () async {
      var origin = 'https://first.trycloudflare.com';
      var reads = 0;
      final hosts = <String>[];
      final api = HttpPaymentApi(
        resolveBaseUrl: () async {
          reads++;
          return origin;
        },
        token: () async => 'fixture-token',
        client: MockClient((request) async {
          hosts.add(request.url.host);
          expect(request.headers['Authorization'], 'Bearer fixture-token');
          return http.Response(jsonEncode({'packages': []}), 200);
        }),
      );
      expect(api.configured, isTrue);
      await api.businessRequest('/v1/packages');
      origin = 'https://second.trycloudflare.com';
      await api.businessRequest('/v1/packages');
      expect(reads, 2);
      expect(hosts, ['first.trycloudflare.com', 'second.trycloudflare.com']);
    },
  );
  test('failed discovery sends no token and does not fall back', () async {
    var sends = 0;
    final api = HttpPaymentApi(
      resolveBaseUrl: () async => throw Exception('offline'),
      token: () async => 'fixture-token',
      client: MockClient((_) async {
        sends++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.businessRequest('/v1/packages'),
      throwsA(isA<PaymentFailure>()),
    );
    expect(sends, 0);
  });
  test(
    'native clients cannot send auth to a configured HTTP loopback endpoint',
    () async {
      var sends = 0;
      final api = HttpPaymentApi(
        baseUrl: 'http://127.0.0.1:8787',
        token: () async => 'fixture-token',
        client: MockClient((_) async {
          sends++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.businessRequest('/v1/packages'),
        throwsA(isA<PaymentFailure>()),
      );
      expect(sends, 0);
    },
  );
  test('failed POST is sent only once, never silently replayed', () async {
    var sends = 0;
    final api = HttpPaymentApi(
      resolveBaseUrl: () async => 'https://new.trycloudflare.com',
      token: () async => 'fixture-token',
      client: MockClient((request) async {
        sends++;
        expect(request.followRedirects, isFalse);
        throw http.ClientException('connection lost');
      }),
    );
    await expectLater(
      api.businessRequest('/v1/invoices', body: {}),
      throwsA(isA<PaymentFailure>()),
    );
    expect(sends, 1);
  });
}
