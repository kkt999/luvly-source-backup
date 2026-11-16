import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../support/assistant_launcher.dart';
import '../bookings/booking_repository.dart';
import '../payments/payment_api.dart';
import '../payments/payment_screen.dart';
import 'catalogue_repository.dart';

String rentalDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class RentalScreen extends StatefulWidget {
  const RentalScreen({
    super.key,
    this.appointment,
    this.api,
    this.profileWorkspace = false,
    this.gownOnly = false,
  });
  final BookingRequest? appointment;
  final HttpPaymentApi? api;
  final bool profileWorkspace, gownOnly;
  @override
  State<RentalScreen> createState() => _RentalScreenState();
}

class _RentalScreenState extends State<RentalScreen> {
  late final api = widget.api ?? HttpPaymentApi();
  final deposit = TextEditingController();
  final requestId = List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  Map<String, dynamic>? intent;
  List<Map<String, dynamic>> rows = [], gowns = [];
  String? dressId, size, error;
  DateTime? pickup, event, returned;
  bool busy = false, loaded = false, submitted = false;
  int serverNow = 0;
  final elapsed = Stopwatch();
  Timer? timer;
  bool get staff => widget.appointment != null;
  int get now => serverNow + elapsed.elapsedMilliseconds;
  bool get active => rows.any(
    (r) =>
        ['Locked', 'PaymentReview'].contains(r['state']) ||
        (r['state'] == 'Held' && (r['expiresAt'] as int) > now),
  );
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await api.businessRequest('/v1/rentals');
      final catalogue = staff
          ? await api.businessRequest('/v1/package-gowns')
          : null;
      if (!mounted) return;
      setState(() {
        serverNow = response['serverNow'] as int;
        elapsed.reset();
        elapsed.start();
        rows = (response['rentals'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .where(
              (r) =>
                  (!staff || r['appointmentId'] == widget.appointment!.id) &&
                  (!widget.gownOnly ||
                      r['packageSelectionId'] == null ||
                      r['packageSelectionId'] == ''),
            )
            .toList();
        if (catalogue != null) {
          gowns = (catalogue['dresses'] as List)
              .map((v) => Map<String, dynamic>.from(v))
              .toList();
        }
        loaded = true;
        if (response['limited'] == true) {
          error =
              'Only the first 100 records are shown. Contact staff if a rental is missing.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not load rentals. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick(String label) async {
    final today = malaysiaNow();
    final d = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (d != null && mounted) {
      setState(() {
        switch (label) {
          case 'Pickup':
            pickup = d;
          case 'Event':
            event = d;
          case 'Return':
            returned = d;
        }
      });
    }
  }

  Future<void> hold() async {
    if (intent == null) {
      final cents = parsePriceCents(deposit.text);
      if (dressId == null ||
          size == null ||
          cents == null ||
          cents < 100 ||
          pickup == null ||
          event == null ||
          returned == null ||
          pickup!.isAfter(event!) ||
          event!.isAfter(returned!) ||
          returned!.difference(pickup!).inDays > 30) {
        setState(
          () => error =
              'Choose a gown, size, pickup ≤ event ≤ return dates (up to 31 calendar dates), and a deposit of at least RM 1.00.',
        );
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Confirm rental and start 15-minute hold?'),
          content: Text(
            'Customer: ${widget.appointment!.name}\nSize: $size\nPickup: ${rentalDate(pickup!)}\nEvent: ${rentalDate(event!)}\nReturn: ${rentalDate(returned!)}\nAvailable again: ${rentalDate(returned!.add(const Duration(days: 4)))}\nBooking deposit: RM ${(cents / 100).toStringAsFixed(2)}\n\nThis creates a deposit invoice. The customer must pay before the hold expires. This does not collect payment now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm rental'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      intent = {
        'requestId': requestId,
        'appointmentId': widget.appointment!.id,
        'pickupDate': rentalDate(pickup!),
        'eventDate': rentalDate(event!),
        'returnDate': rentalDate(returned!),
        'gowns': [
          {'dressId': dressId, 'size': size},
        ],
        'depositCents': cents,
      };
    }
    setState(() {
      busy = true;
      error = null;
    });
    bool saved = false;
    try {
      await api.businessRequest('/v1/rentals', body: intent);
      saved = true;
      submitted = true;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Confirmation not verified. Retry the same request.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && saved) await load();
  }

  Future<void> cancel(Map<String, dynamic> r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this rental?'),
        content: const Text(
          'Stock will be released. Any paid deposit requires refund review; this action does not issue a refund.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel rental'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    bool saved = false;
    try {
      await api.businessRequest('/v1/rentals/${r['id']}/cancel', body: {});
      saved = true;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not confirm cancellation. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && saved) await load();
  }

  @override
  void dispose() {
    timer?.cancel();
    elapsed.stop();
    deposit.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = gowns.where((g) => g['id'] == dressId).firstOrNull;
    final frozen = busy || intent != null;
    return Scaffold(
      appBar: widget.profileWorkspace
          ? null
          : AppBar(
              title: AssistantExclusion(
                child: Text(staff ? 'Confirm gown rental' : 'My gown rentals'),
              ),
              actions: [
                IconButton(
                  onPressed: busy ? null : load,
                  tooltip: 'Refresh rentals',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.profileWorkspace)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Refresh rentals',
                    onPressed: busy ? null : load,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              Text(
                widget.gownOnly
                    ? 'Gown rentals arranged without a package. Gowns included in your package are shown under Packages.'
                    : 'A rental is separate from your fitting appointment. Staff confirmation holds the size for 15 minutes. Only a verified deposit locks it. Return day plus 3 cleaning days are unavailable.',
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final r in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pickup ${r['pickupDate']} → Return ${r['returnDate']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Event: ${r['eventDate']} · Available again: ${r['availableAgain']}',
                        ),
                        for (final g in r['gowns'] as List)
                          Text(
                            '${g['name'] ?? g['dressId']} · Size ${g['size']}',
                          ),
                        Text(
                          'Booking deposit: RM ${((r['depositCents'] as int) / 100).toStringAsFixed(2)}',
                        ),
                        Text(
                          r['state'] == 'Held'
                              ? (r['expiresAt'] as int) <= now
                                    ? 'Expired — ask staff to check stock again'
                                    : 'Awaiting deposit · ${(((r['expiresAt'] as int) - now) ~/ 60000).toString().padLeft(2, '0')}:${((((r['expiresAt'] as int) - now) ~/ 1000) % 60).toString().padLeft(2, '0')} remaining'
                              : '${r['state']}',
                        ),
                        if (r['state'] == 'PaymentReview')
                          const Text(
                            'Payment received after the hold ended. Staff must review it; stock is not confirmed.',
                          ),
                        if (r['refundReviewRequired'] == true)
                          const Text(
                            'Refund review required. No automatic refund has been issued.',
                          ),
                        if (staff &&
                            [
                              'Held',
                              'Locked',
                              'PaymentReview',
                            ].contains(r['state']))
                          TextButton(
                            onPressed: busy ? null : () => cancel(r),
                            child: const Text('Cancel rental'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (!staff) ...[
                if (loaded && rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      widget.gownOnly
                          ? 'No gown-only rental records yet. Package selections and rentals are shown under Packages.'
                          : 'No gown rental confirmed yet. Your fitting appointment is shown under Bookings.',
                    ),
                  ),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const LivePaymentsScreen(),
                    ),
                  ),
                  child: const Text('Payments & receipts'),
                ),
              ],
              if (staff && loaded && !active && !submitted) ...[
                const SizedBox(height: 20),
                Text('Customer: ${widget.appointment!.name}'),
                DropdownButtonFormField<String>(
                  initialValue: dressId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Gown'),
                  items: gowns
                      .map(
                        (g) => DropdownMenuItem<String>(
                          value: g['id'],
                          child: Text(
                            g['name'],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: frozen
                      ? null
                      : (v) => setState(() {
                          dressId = v;
                          size = null;
                        }),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(dressId),
                  initialValue: size,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Size'),
                  items:
                      (selected == null
                              ? <String>[]
                              : (selected['sizes'] as String)
                                    .split(', ')
                                    .where((s) => s != 'Made to measure'))
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                  onChanged: frozen ? null : (v) => setState(() => size = v),
                ),
                for (final entry in {
                  'Pickup': pickup,
                  'Event': event,
                  'Return': returned,
                }.entries)
                  OutlinedButton.icon(
                    onPressed: frozen ? null : () => pick(entry.key),
                    icon: const Icon(Icons.event),
                    label: Text(
                      '${entry.key}: ${entry.value == null ? 'Choose date' : rentalDate(entry.value!)}',
                    ),
                  ),
                TextField(
                  controller: deposit,
                  enabled: !frozen,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Agreed booking deposit (RM)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : hold,
                  child: Text(
                    intent == null
                        ? 'Review rental'
                        : 'Retry same confirmation',
                  ),
                ),
                if (intent != null)
                  const Text(
                    'Details are locked to keep retries safe. Refresh to check whether the hold was created before starting another request.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
