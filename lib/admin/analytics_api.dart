import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' show RequestAbortedException;
import '../payments/payment_api.dart';

String analyticsDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime analyticsToday() {
  final d = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(d.year, d.month, d.day);
}

String analyticsMoney(int cents) => 'RM ${(cents / 100).toStringAsFixed(2)}';

class BusinessReport {
  const BusinessReport(
    this.id,
    this.title,
    this.basis,
    this.headers,
    this.rows,
    this.summary,
  );
  final String id, title, basis, summary;
  final List<String> headers;
  final List<List<String>> rows;
  factory BusinessReport.fromJson(Map<String, dynamic> v) => BusinessReport(
    v['id'] as String,
    v['title'] as String,
    v['basis'] as String,
    (v['headers'] as List).cast<String>(),
    (v['rows'] as List).map((r) => (r as List).cast<String>()).toList(),
    v['summary'] as String,
  );
}

class AnalyticsSnapshot {
  AnalyticsSnapshot(this.data, {bool requireReports = false}) {
    if (data['environment'] != 'sandbox' ||
        data['timezone'] != 'Asia/Kuala_Lumpur' ||
        data['generatedAt'] is! int ||
        data['operations'] is! Map ||
        (requireReports &&
            (data['totals'] is! Map ||
                data['reports'] is! List ||
                data['range'] is! Map ||
                data['quality'] is! Map ||
                (data['reports'] as List).length != 4))) {
      throw const PaymentFailure(
        'Could not verify dashboard data. Please refresh.',
      );
    }
    for (final key in [
      'todayConfirmed',
      'awaitingPayment',
      'openConversations',
      'activeHolds',
      'overdueReturns',
    ]) {
      if (operations[key] is! int || operations[key] < 0) {
        throw const PaymentFailure(
          'Could not verify dashboard counts. Please refresh.',
        );
      }
    }
    if (requireReports) {
      for (final key in [
        'serviceCents',
        'securityCents',
        'otherCents',
        'grossCents',
        'paidCount',
        'reviewCount',
        'packageSelections',
        'paidPackageBookings',
        'completedFittings',
        'convertedFittings',
        'appointments',
        'customers',
        'classifiedProfiles',
      ]) {
        if (totals[key] is! int || totals[key] < 0) {
          throw const PaymentFailure(
            'Could not verify report totals. Please refresh.',
          );
        }
      }
      if (totals['conversionPercent'] is! num ||
          !(totals['conversionPercent'] as num).isFinite) {
        throw const PaymentFailure(
          'Could not verify report percentages. Please refresh.',
        );
      }
      // Parse now, inside the request, so malformed data becomes a retry state.
      reports;
      for (final key in [
        'trend',
        'packages',
        'statuses',
        'bodyTypes',
        'collectionMix',
      ]) {
        series(key);
      }
    }
  }
  final Map<String, dynamic> data;
  Map<String, dynamic> get operations =>
      Map<String, dynamic>.from(data['operations']);
  Map<String, dynamic> get totals =>
      Map<String, dynamic>.from(data['totals'] ?? {});
  Map<String, dynamic> get quality =>
      Map<String, dynamic>.from(data['quality'] ?? {});
  List<Map<String, dynamic>> series(String key) => (data[key] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  int total(String key) => totals[key] as int? ?? 0;
  int operation(String key) => operations[key] as int? ?? 0;
  List<BusinessReport> get reports => (data['reports'] as List? ?? [])
      .map((r) => BusinessReport.fromJson(Map<String, dynamic>.from(r)))
      .toList();
}

abstract class AnalyticsApi {
  Future<AnalyticsSnapshot> dashboard();
  Future<AnalyticsSnapshot> report(DateTime from, DateTime to);
  void close();
}

abstract class LiveAnalyticsApi {
  Stream<String> changes();
}

class HttpAnalyticsApi implements AnalyticsApi, LiveAnalyticsApi {
  HttpAnalyticsApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi(),
      ownsTransport = transport == null;
  final HttpPaymentApi transport;
  final bool ownsTransport;
  @override
  Stream<String> changes() {
    final abort = Completer<void>();
    late StreamController<String> controller;
    StreamSubscription<String>? subscription;
    controller = StreamController<String>(
      onListen: () {
        subscription = transport
            .analyticsEvents(abort.future)
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        if (!abort.isCompleted) abort.complete();
        try {
          await subscription?.cancel();
        } on RequestAbortedException {
          // The browser may report our own abort when it cancels the reader.
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<AnalyticsSnapshot> dashboard() async => AnalyticsSnapshot(
    Map<String, dynamic>.from(await transport.businessRequest('/v1/dashboard')),
  );
  @override
  Future<AnalyticsSnapshot> report(DateTime from, DateTime to) async =>
      AnalyticsSnapshot(
        Map<String, dynamic>.from(
          await transport.businessRequest(
            '/v1/analytics?from=${analyticsDate(from)}&to=${analyticsDate(to)}',
          ),
        ),
        requireReports: true,
      );
  @override
  void close() {
    if (ownsTransport) transport.close();
  }
}

class AnalyticsScope extends InheritedWidget {
  const AnalyticsScope({
    super.key,
    required this.api,
    required super.child,
    this.today,
  });
  final AnalyticsApi api;
  final DateTime? today;
  static DateTime? todayOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AnalyticsScope>()?.today;
  static AnalyticsApi? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AnalyticsScope>()?.api;
  @override
  bool updateShouldNotify(AnalyticsScope oldWidget) =>
      oldWidget.api != api || oldWidget.today != today;
}

String analyticsError(Object error) {
  if (error is! PaymentFailure) {
    return 'Could not load verified dashboard data. Refresh to try again.';
  }
  if (error.message.contains('issue invoices')) {
    return 'Only an active manager can access financial reports.';
  }
  if (error.message.startsWith('Cannot connect to Luvly')) {
    return 'Cannot connect to the reporting service. Check your connection and refresh. No totals are being estimated.';
  }
  if (error.message.startsWith('Unable to complete this request')) {
    return 'The reporting request could not be completed. Refresh to try again; no partial totals are displayed.';
  }
  return error.message;
}

String? validateReportDates(DateTime from, DateTime to, {DateTime? today}) {
  final end = today ?? analyticsToday();
  if (from.isBefore(DateTime(2020)) || from.isAfter(to) || to.isAfter(end)) {
    return 'Choose a start date on or before the end date, with no future dates.';
  }
  if (to.difference(from).inDays >= 366) {
    return 'Choose a period of up to 366 days.';
  }
  return null;
}

/// RFC-style quoting plus spreadsheet-formula neutralisation for editable names.
String safeReportCsv(BusinessReport report, AnalyticsSnapshot snapshot) {
  String quote(String text) {
    final safe = RegExp(r'^[\s\x00-\x1f]*[=+@-]').hasMatch(text)
        ? "'$text"
        : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final dateRange = report.id == 'body-types'
      ? 'Current snapshot (not date-filtered)'
      : '${snapshot.data['range']['from']} to ${snapshot.data['range']['to']}';
  return <List<String>>[
    ['Luvly | BUSINESS REPORT | TEST TRANSACTIONS'],
    [report.title],
    [dateRange],
    [
      'Generated (MYT)',
      DateTime.fromMillisecondsSinceEpoch(
        snapshot.data['generatedAt'],
        isUtc: true,
      ).add(const Duration(hours: 8)).toIso8601String().replaceAll('Z', ' MYT'),
    ],
    [report.basis],
    [report.summary],
    [
      'Current source data quality',
      '${snapshot.quality['paidMissingMetadata']} paid records missing verification metadata; ${snapshot.quality['selectionsMissingDate']} selections and ${snapshot.quality['appointmentsMissingDate']} appointments missing dates. Excluded from corresponding dated totals.',
    ],
    [],
    report.headers,
    ...report.rows,
  ].map((row) => row.map(quote).join(',')).join('\r\n');
}
