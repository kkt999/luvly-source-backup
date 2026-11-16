import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../payments/payment_api.dart';
import 'design.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.api});
  final HttpPaymentApi? api;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  late final api = widget.api ?? HttpPaymentApi();
  Map<String, dynamic>? status;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load({bool sync = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await api.businessRequest(
        sync ? '/v1/calendar/sync' : '/v1/calendar',
        body: sync ? {} : null,
      );
      if (mounted) setState(() => status = Map<String, dynamic>.from(data));
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Calendar service could not be reached. Your appointment has not been changed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect() async {
    final accepted = await confirm(
      context,
      'Connect Google Calendar?',
      'Sync your confirmed appointments and cancellations to a separate Luvly calendar. Choose the Google account linked to Luvly. Gmail is not accessed.',
      action: 'Continue',
    );
    if (!accepted || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await api.businessRequest('/v1/calendar/connect', body: {});
      final url = Uri.parse(data['url'] as String);
      if (url.scheme != 'https' ||
          url.host != 'accounts.google.com' ||
          url.userInfo.isNotEmpty ||
          !await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Cannot open Google');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not start Calendar connection. Link Google in your profile first; if already linked, the server may still need setup.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    if (!await confirm(
          context,
          'Stop Calendar sync?',
          'Luvly will forget its saved Calendar credential. Existing calendar events remain, but will no longer update. Your Luvly bookings and Google login remain unchanged.',
          action: 'Disconnect',
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await api.businessRequest(
        '/v1/calendar/disconnect',
        body: {},
      );
      if (mounted) setState(() => status = Map<String, dynamic>.from(data));
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Disconnect could not be confirmed. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Google Calendar',
    child: PageList(
      children: [
        const Icon(Icons.calendar_month_outlined, size: 48, color: rose),
        gap(),
        const Text('Your Luvly appointments, in your calendar'),
        gap(),
        const Text(
          'Confirmed appointments are added automatically. Changes may take a moment to appear.',
        ),
        gap(),
        Text('Status: ${status?['state'] ?? 'Checking…'}'),
        if (status?['lastSyncedAt'] is num)
          Text(
            'Last synced: ${DateTime.fromMillisecondsSinceEpoch((status!['lastSyncedAt'] as num).toInt()).toLocal()}',
          ),
        if (error != null) ...[
          gap(),
          Text(error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        if (busy) ...[gap(), const LinearProgressIndicator()],
        gap(),
        if (status?['configured'] == true && status?['connected'] != true)
          Primary('Connect Google Calendar', busy ? null : connect),
        if (status?['connected'] == true) ...[
          Primary('Sync now', busy ? null : () => load(sync: true)),
          TextButton(
            onPressed: busy ? null : disconnect,
            child: const Text('Disconnect Calendar'),
          ),
        ],
        TextButton(
          onPressed: busy ? null : load,
          child: const Text('Check status'),
        ),
      ],
    ),
  );
}
