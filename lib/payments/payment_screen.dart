import 'dart:async';
import 'package:flutter/material.dart';
import '../support/assistant_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bookings/booking_repository.dart';
import 'payment_api.dart';
import 'payment_method_dialog.dart';
import 'receipt_screen.dart';
import 'checkout_invoice_card.dart';
import 'payment_filters.dart';
import 'payment_review_dialog.dart';
import 'staff_payment_workspace.dart';

class LivePaymentsScreen extends StatefulWidget {
  const LivePaymentsScreen({
    super.key,
    this.manager = false,
    this.staff = false,
    this.api,
    this.openCheckout,
    this.initialInvoiceId,
    this.focusInitialInvoice = false,
  });
  final bool manager, staff;
  final String? initialInvoiceId;
  final bool focusInitialInvoice;
  final PaymentApi? api;
  final Future<bool> Function(Uri)? openCheckout;
  @override
  State<LivePaymentsScreen> createState() => _LivePaymentsState();
}

class _LivePaymentsState extends State<LivePaymentsScreen>
    with WidgetsBindingObserver {
  late final PaymentApi api;
  late Future<List<SandboxInvoice>> feed;
  bool busy = false;
  bool checkingStatus = false;
  bool showAll = false;
  String? staffInvoiceId;
  final staffListState = StaffPaymentListState();
  String? get focusInvoiceId => staffInvoiceId ?? widget.initialInvoiceId;
  bool get focused =>
      focusInvoiceId != null &&
      (!widget.staff || widget.focusInitialInvoice || staffInvoiceId != null) &&
      !showAll;
  final search = TextEditingController();
  PaymentListFilter filter = const PaymentListFilter();
  Timer? countdown;
  Timer? verification;
  int _readRevision = 0;
  int? _countdownUntil;
  @override
  void initState() {
    super.initState();
    api = widget.api ?? HttpPaymentApi();
    feed = api.configured ? load() : Future.value([]);
    WidgetsBinding.instance.addObserver(this);
    countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _countdownUntil;
      if (mounted && end != null) {
        setState(() {
          if (DateTime.now().millisecondsSinceEpoch >= end) {
            _countdownUntil = null;
          }
        });
      }
    });
    verification = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          !busy &&
          api.configured &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        reload(verify: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    countdown?.cancel();
    verification?.cancel();
    search.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload persisted state, but don't trust browser-return status or auto-retry payment.
    if (state == AppLifecycleState.resumed &&
        mounted &&
        api.configured &&
        !busy) {
      reload(verify: true);
    }
  }

  void reload({bool verify = false}) {
    setState(() {
      feed = load(verify: verify);
    });
  }

  void clearFilters() {
    search.clear();
    setState(() => filter = const PaymentListFilter());
  }

  Future<void> openFilters() async {
    FocusScope.of(context).unfocus();
    final next = await showPaymentFilters(context, filter);
    if (next != null && mounted) setState(() => filter = next);
  }

  Future<List<SandboxInvoice>> load({bool verify = false}) {
    final revision = ++_readRevision;
    final requestedInvoiceId = focusInvoiceId;
    Future<List<SandboxInvoice>> read() async {
      final verifyNow = verify && !checkingStatus;
      if (verifyNow) checkingStatus = true;
      try {
        var rows = List<SandboxInvoice>.from(await api.list());
        Future<void> focus() async {
          if (api is HttpPaymentApi &&
              requestedInvoiceId != null &&
              !rows.any((i) => i.id == requestedInvoiceId)) {
            rows.add(
              SandboxInvoice.fromJson(
                await (api as HttpPaymentApi).businessRequest(
                  '/v1/invoices/$requestedInvoiceId',
                ),
              ),
            );
          }
          rows.sort(
            (a, b) => a.id == b.id
                ? 0
                : a.id == requestedInvoiceId
                ? -1
                : b.id == requestedInvoiceId
                ? 1
                : (a.canPay
                          ? 0
                          : a.state == 'SandboxPaid'
                          ? 2
                          : 1) -
                      (b.canPay
                          ? 0
                          : b.state == 'SandboxPaid'
                          ? 2
                          : 1),
          );
        }

        await focus();
        if (verifyNow) {
          for (final invoice
              in rows
                  .where(
                    (i) => i.hasBill && ['Unpaid', 'Pending'].contains(i.state),
                  )
                  .take(3)) {
            try {
              await api.refresh(invoice.id);
            } catch (_) {
              /* Keep the saved state; never infer success. */
            }
          }
          rows = List<SandboxInvoice>.from(await api.list());
          await focus();
        }
        if (revision == _readRevision) {
          final now = DateTime.now().millisecondsSinceEpoch;
          _countdownUntil = null;
          for (final invoice in rows) {
            final expires = invoice.holdExpiresAt;
            if (expires != null &&
                expires > now &&
                expires >= (_countdownUntil ?? 0) &&
                invoice.state != 'SandboxPaid' &&
                !invoice.paymentBlocked) {
              _countdownUntil = expires;
            }
          }
        }
        return rows;
      } finally {
        if (verifyNow) checkingStatus = false;
      }
    }

    final request = read();
    // Observe fast failures before FutureBuilder attaches on the next frame.
    request.then<void>((_) {}, onError: (Object error, StackTrace trace) {});
    return request;
  }

  void message(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is PaymentFailure
              ? error.message
              : 'Unable to complete this request. Please try again.',
        ),
      ),
    );
  }

  Future<void> act(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (error) {
      message(error);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  Future<void> pay(SandboxInvoice invoice) async {
    final method = await showDialog<String>(
      context: context,
      builder: (c) => PaymentMethodDialog(invoice: invoice),
    );
    if (method == null || !mounted) return;
    await act(() async {
      if (invoice.purpose == 'RentalExtension') {
        if (api is! HttpPaymentApi) {
          throw const PaymentFailure(
            'Extension payment needs the connected payment service.',
          );
        }
        await (api as HttpPaymentApi).businessRequest(
          '/v1/invoices/${invoice.id}/extension-consent',
          body: {'accepted': true},
        );
      }
      final bill = await api.checkout(invoice.id, paymentMethod: method);
      if (!mounted) return;
      if (bill.checkoutUrl == null || !bill.canPay) {
        throw const PaymentFailure(
          'Check the invoice status before continuing.',
        );
      }
      final uri = sandboxCheckoutUri(bill.checkoutUrl!);
      final opened =
          await (widget.openCheckout?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) {
        throw const PaymentFailure(
          'Could not open checkout. The bill is saved; try again or check status.',
        );
      }
    });
  }

  Future<void> quote() => act(() async {
    final repository = BookingScope.maybeOf(context);
    if (repository == null) {
      throw const PaymentFailure('Appointment service is unavailable.');
    }
    final bookings = (await repository.watch().first.timeout(
      const Duration(seconds: 15),
    )).where((b) => b.status == 'Confirmed').toList();
    if (!mounted) return;
    if (bookings.isEmpty) {
      throw const PaymentFailure(
        'Confirm an appointment before issuing an invoice.',
      );
    }
    final draft = await showDialog<InvoiceDraft>(
      context: context,
      builder: (_) => QuoteDialog(bookings: bookings),
    );
    if (draft == null || !mounted) return;
    await api.quote(draft.appointmentId, draft.purpose, draft.amountCents);
  });
  void receipt(SandboxInvoice invoice) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VerifiedReceiptScreen(invoice: invoice),
      ),
    );
  }

  Widget _customerHistory(
    List<SandboxInvoice> invoices, {
    required bool refreshing,
  }) {
    final theme = Theme.of(context);
    final rows = invoices.where(filter.matches).toList();
    final indexById = {for (var i = 0; i < rows.length; i++) rows[i].id: i};
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            key: const PageStorageKey('customer-payment-history'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PaymentSearchControls(
                            controller: search,
                            filter: filter,
                            staff: false,
                            onChanged: (v) => setState(() => filter = v),
                            onFilters: openFilters,
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 30),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      '${rows.length} ${rows.length == 1 ? 'payment' : 'payments'}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                                if (rows.isNotEmpty && filter.active)
                                  TextButton(
                                    onPressed: clearFilters,
                                    child: const Text('Clear all'),
                                  ),
                              ],
                            ),
                          ),
                          if (busy || refreshing)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                semanticsLabel: 'Updating payments',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (rows.isNotEmpty)
                      SliverList.builder(
                        itemCount: rows.length,
                        findChildIndexCallback: (key) =>
                            indexById[(key as ValueKey<String>).value],
                        itemBuilder: (context, index) {
                          final invoice = rows[index];
                          return CheckoutInvoiceCard(
                            key: ValueKey(invoice.id),
                            invoice: invoice,
                            staff: false,
                            busy: busy || refreshing,
                            compact: true,
                            onPay: () => pay(invoice),
                            onCheck: () => act(() async {
                              await api.refresh(invoice.id);
                            }),
                            onReceipt: () => receipt(invoice),
                          );
                        },
                      )
                    else if (!refreshing)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(
                                invoices.isEmpty
                                    ? Icons.receipt_long_outlined
                                    : Icons.search_off_outlined,
                                size: 30,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                invoices.isEmpty
                                    ? 'No payments yet'
                                    : 'No matching payments',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                invoices.isEmpty
                                    ? 'Your bridal bookings, payments and receipts will appear here.'
                                    : 'Try another search term or adjust your filters.',
                                textAlign: TextAlign.center,
                              ),
                              if (filter.active)
                                TextButton(
                                  onPressed: clearFilters,
                                  child: const Text('Reset search & filters'),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: widget.staff && staffInvoiceId != null && focused
          ? BackButton(onPressed: () => setState(() => showAll = true))
          : null,
      title: AssistantExclusion(
        child: Text(
          focused
              ? widget.staff
                    ? 'Payment details'
                    : 'Your payment'
              : 'Payments & receipts',
        ),
      ),
      actions: [
        if (api.configured)
          IconButton(
            onPressed: busy ? null : reload,
            tooltip: 'Refresh invoices',
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: !api.configured
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Payments are currently unavailable. Please contact Luvly for assistance.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : FutureBuilder<List<SandboxInvoice>>(
            future: feed,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.error is PaymentFailure
                              ? (snapshot.error as PaymentFailure).message
                              : 'Could not load your payments. Please try again.',
                        ),
                        TextButton(
                          onPressed: busy ? null : reload,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final loading = snapshot.connectionState != ConnectionState.done;
              if (widget.staff && !focused) {
                return StaffPaymentWorkspace(
                  key: const PageStorageKey('staff-payment-workspace'),
                  viewState: staffListState,
                  invoices: snapshot.data!,
                  busy: busy || loading,
                  onIssue: widget.manager ? quote : null,
                  onOpen: (invoice) {
                    setState(() {
                      staffInvoiceId = invoice.id;
                      showAll = false;
                    });
                    reload();
                  },
                );
              }
              if (!focused) {
                return _customerHistory(snapshot.data!, refreshing: loading);
              }
              final rows = snapshot.data!.where((i) => i.id == focusInvoiceId);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (widget.manager)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: FilledButton.icon(
                            onPressed: busy ? null : quote,
                            icon: const Icon(Icons.add),
                            label: const Text('Issue invoice'),
                          ),
                        ),
                      if (busy) const LinearProgressIndicator(),
                      if (snapshot.data!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No payments yet. Your invoices and receipts will appear here.',
                          ),
                        ),
                      if (rows.isEmpty &&
                          (widget.staff || snapshot.data!.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            widget.staff
                                ? 'This invoice is not available in the current authorised list. Refresh or return to the payment workspace.'
                                : 'This payment is unavailable. Refresh or view your payment history.',
                          ),
                        ),
                      for (final invoice in rows) ...[
                        if (widget.staff)
                          StaffPaymentIdentity(invoice: invoice),
                        CheckoutInvoiceCard(
                          key: ValueKey(invoice.id),
                          invoice: invoice,
                          staff: widget.staff,
                          busy: busy || widget.staff && loading,
                          showStaffCustomer: !widget.staff,
                          focused: focused,
                          onPay: () => pay(invoice),
                          onCheck: () => act(() async {
                            await api.refresh(invoice.id);
                          }),
                          onReceipt: () => receipt(invoice),
                          onReview: widget.manager && api is HttpPaymentApi
                              ? () async {
                                  final saved = await showPaymentReview(
                                    context,
                                    invoice,
                                    api as HttpPaymentApi,
                                  );
                                  if (saved == true && mounted) reload();
                                }
                              : null,
                          onDone: widget.staff && staffInvoiceId != null
                              ? () => setState(() => showAll = true)
                              : Navigator.canPop(context)
                              ? () => Navigator.pop(context)
                              : null,
                        ),
                      ],
                      if (focused)
                        TextButton(
                          onPressed: () => setState(() => showAll = true),
                          child: const Text('View all payments & receipts'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

class InvoiceDraft {
  const InvoiceDraft(this.appointmentId, this.purpose, this.amountCents);
  final String appointmentId, purpose;
  final int amountCents;
}

class QuoteDialog extends StatefulWidget {
  const QuoteDialog({super.key, required this.bookings});
  final List<BookingRequest> bookings;
  @override
  State<QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<QuoteDialog> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController();
  String? appointmentId;
  String purpose = 'AppointmentDeposit';
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Issue invoice'),
    content: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose an appointment and enter the agreed amount.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmed appointment',
                ),
                items: [
                  for (final b in widget.bookings)
                    DropdownMenuItem(
                      value: b.id,
                      child: Text(
                        '${b.name} · ${appointmentLabel(b.start)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => appointmentId = v),
                validator: (v) => v == null ? 'Choose an appointment' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: purpose,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Payment purpose'),
                items: const [
                  DropdownMenuItem(
                    value: 'AppointmentDeposit',
                    child: Text(
                      'Appointment deposit',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'DressPayment',
                    child: Text(
                      'Dress payment',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => purpose = v!),
                validator: (v) =>
                    v == 'DressPayment' &&
                        !widget.bookings.any(
                          (b) =>
                              b.id == appointmentId &&
                              (b.data['dressId'] as String? ?? '').isNotEmpty,
                        )
                    ? 'Choose an appointment linked to a dress'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amount,
                decoration: const InputDecoration(
                  labelText: 'Agreed amount (RM)',
                  errorMaxLines: 2,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) => quoteAmountCents(v ?? '') == null
                    ? 'Enter RM 1.00–1,000,000.00, up to 2 decimal places'
                    : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'One invoice per purpose per appointment. Verify the amount before issuing; it cannot be overwritten here.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              InvoiceDraft(
                appointmentId!,
                purpose,
                quoteAmountCents(amount.text)!,
              ),
            );
          }
        },
        child: const Text('Issue invoice'),
      ),
    ],
  );
}
