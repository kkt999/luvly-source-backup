import 'package:flutter/material.dart';
import '../bookings/booking_repository.dart' show bookingStatusLabel;
import '../payments/payment_api.dart';
import '../promotions/promotion_screen.dart';
import 'package_api.dart';
import 'customer_package_card.dart';
import 'rental_workspace.dart' hide rentalDateLabel;
import 'rental_date_fields.dart';
import 'package_rental_screen.dart';
import 'fitting_proposal_screen.dart';
import 'rental_extension_status.dart';
import '../reviews/review_screen.dart';
import '../reviews/review_api.dart';

class CustomerPackageDetails extends StatefulWidget {
  const CustomerPackageDetails({
    super.key,
    required this.selection,
    required this.api,
    required this.onChanged,
    required this.onContinue,
  });
  final PackageSelection selection;
  final PackageApi api;
  final VoidCallback onChanged;
  final Future<void> Function(PackageSelection, CustomerPackageStep) onContinue;
  @override
  State<CustomerPackageDetails> createState() => _CustomerPackageDetailsState();
}

class _CustomerPackageDetailsState extends State<CustomerPackageDetails> {
  late PackageSelection selection = widget.selection;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final rows = await widget.api.selections();
      final matches = rows.where((s) => s.id == widget.selection.id);
      if (matches.length != 1) {
        throw const PaymentFailure(
          'This package could not be reloaded. Please return to My packages and refresh.',
        );
      }
      if (mounted) {
        setState(() {
          selection = matches.single;
          error = null;
        });
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not refresh this package. Please retry before making changes.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editDates() async {
    if (widget.api is! HttpPackageApi || loading || error != null) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PackageRentalScreen(
          selection: selection,
          api: widget.api as HttpPackageApi,
          editDates: true,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = selection, step = customerPackageStep(s), v = StaffRentalView(s);
    final blocked = loading || error != null;
    var validInvoice = true;
    try {
      s.invoice;
    } on PaymentFailure {
      validInvoice = false;
    }
    final editable = s.data['rentalId'] == null && s.data['invoiceId'] == null;
    final plan = s.data['rentalPlan'] as Map?;
    final completeDates =
        plan != null &&
        [
          'eventDate',
          'pickupDate',
          'returnDate',
        ].every((k) => plan[k] is String && (plan[k] as String).isNotEmpty);
    final showPrimary = ![
      CustomerPackageAction.details,
      CustomerPackageAction.proposal,
    ].contains(step.action);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Package details'),
        actions: [
          IconButton(
            onPressed: loading ? null : refresh,
            tooltip: 'Refresh package',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: loading ? null : refresh,
                  child: const Text('Retry'),
                ),
              ],
              Text(s.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(step.status, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(step.description),
              if (v.stage == 'Returned' && v.rental['id'] is String)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: OutlinedButton.icon(
                    onPressed: blocked
                        ? null
                        : () async {
                            final reviewApi = ReviewApi();
                            try {
                              if (context.mounted) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReviewEditor(
                                      api: reviewApi,
                                      rentalId: v.rental['id'],
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              reviewApi.close();
                            }
                          },
                    icon: const Icon(Icons.rate_review_outlined),
                    label: const Text('Review your experience'),
                  ),
                ),
              if (showPrimary) ...[
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: blocked
                      ? null
                      : () async {
                          await widget.onContinue(s, step);
                          if (mounted) await refresh();
                        },
                  child: Text(step.label),
                ),
              ],
              if (widget.api is HttpPackageApi &&
                  s.data['fittingWorkflowVersion'] == 2)
                AbsorbPointer(
                  absorbing: blocked,
                  child: FittingProposalPanel(
                    selection: s,
                    api: widget.api as HttpPackageApi,
                    staff: false,
                    manager: false,
                    reload: refresh,
                  ),
                ),
              const SizedBox(height: 20),
              if (completeDates)
                RentalDatesSummary(
                  dates: {
                    for (final k in ['eventDate', 'pickupDate', 'returnDate'])
                      k: plan[k] as String,
                  },
                  onEdit: editable && !blocked ? editDates : null,
                ),
              const SizedBox(height: 16),
              Text(
                'Your selected items',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final g in s.selectedGowns)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.checkroom_outlined),
                  title: Text(selectedPackageGownLabel(g)),
                  subtitle: g['colour'] == null ? null : Text(g['colour']),
                ),
              for (final a in s.data['selectedAccessories'] as List? ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.diamond_outlined),
                  title: Text(a['name']),
                  subtitle: Text('${a['category']} · ${a['size']}'),
                ),
              const SizedBox(height: 16),
              Text(
                'Price & payments',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Package total'),
                trailing: Text(
                  packageMoney(s.totalCents),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (widget.api is HttpPackageApi)
                AbsorbPointer(
                  absorbing: blocked,
                  child: PackagePromotion(selection: s, reload: refresh),
                ),
              if (v.rental.isNotEmpty) ...[
                for (final line in [v.deposit, v.balance, v.security])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line.label),
                    subtitle: Text(line.status),
                    trailing: Text(line.amountLabel),
                  ),
                const Text(
                  'Refundable security is separate from your package price. Refunds follow return inspection.',
                ),
                if (widget.api is HttpPackageApi)
                  AbsorbPointer(
                    absorbing: blocked,
                    child: RentalExtensionStatus(
                      rental: Map<String, dynamic>.from(v.rental),
                      api: (widget.api as HttpPackageApi).transport,
                      staff: false,
                      onChanged: (_) => refresh(),
                    ),
                  ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('What is included'),
                children: [
                  for (final item in s.services)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.check, size: 18),
                      title: Text(item.name),
                      subtitle: item.description.isEmpty
                          ? null
                          : Text(item.description),
                    ),
                  for (final charge
                      in s.data['accessoryCharges'] as List? ?? [])
                    Text(switch (charge['pricing']) {
                      'per-item' =>
                        '${charge['serviceName']} · ${packageMoney(charge['extraCents'])}',
                      'package' =>
                        (charge['extraCents'] as int? ?? 0) > 0
                            ? 'Veil upgrade · + ${packageMoney(charge['extraCents'])}'
                            : '${charge['serviceName']} · Included',
                      _ =>
                        '${charge['serviceName']} · allowance applied ${packageMoney(charge['appliedAllowanceCents'])} · extra ${packageMoney(charge['extraCents'])}',
                    }),
                ],
              ),
              if (s.appointments.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Fitting history'),
                  children: [
                    for (final a in s.appointments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(bookingStatusLabel(a['status'])),
                        subtitle: a['startAt'] is int
                            ? Text(paymentDateLabel(a['startAt']))
                            : null,
                        onTap: blocked
                            ? null
                            : () => widget.onContinue(
                                s,
                                CustomerPackageStep(
                                  '',
                                  '',
                                  '',
                                  CustomerPackageAction.appointment,
                                  targetId: a['id'],
                                ),
                              ),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              if (editable &&
                  s.data['reusedFittingAppointmentId'] == null &&
                  step.action != CustomerPackageAction.fitting &&
                  !s.appointments.any(
                    (a) => [
                      'Requested',
                      'Confirmed',
                      'AwaitingPayment',
                    ].contains(a['status']),
                  ))
                TextButton(
                  onPressed: blocked
                      ? null
                      : () => widget.onContinue(
                          s,
                          const CustomerPackageStep(
                            '',
                            '',
                            '',
                            CustomerPackageAction.fitting,
                          ),
                        ),
                  child: const Text('Change fitting preference'),
                ),
              if (widget.api is HttpPackageApi && validInvoice)
                AbsorbPointer(
                  absorbing: blocked,
                  child: PackageRentalSummary(
                    selection: s,
                    api: widget.api as HttpPackageApi,
                    staff: false,
                    reload: refresh,
                    actionsOnly: true,
                    showCustomerPlanningActions: false,
                    showProposal: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
