import 'package:flutter/material.dart';
import '../bookings/booking_repository.dart'
    show appointmentLabel, bookingStatusLabel;
import '../payments/payment_api.dart';
import '../payments/payment_screen.dart';
import 'package_api.dart';
import 'package_rental_screen.dart';
import 'rental_extension_status.dart';
import 'rental_workspace.dart';
import 'rental_service_progress.dart';
import 'final_fitting_panel.dart';
import '../admin/model.dart' show PortalScope;
import '../bookings/booking_screens.dart' show LiveAppointments;
import 'fitting_workbench.dart';
import 'fitting_proposal_screen.dart';
import 'fitting_gown_change.dart';
import 'rental_handover_screen.dart';
part 'staff_rental_workbench.dart';

Future<void> showStaffRentalDetails(
  BuildContext context, {
  required PackageSelection selection,
  required PackageApi api,
  required bool manager,
  required VoidCallback onChanged,
  required Future<void> Function(PackageSelection) onIssueInvoice,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close rental details',
  barrierColor: Colors.black.withValues(alpha: .24),
  transitionDuration: const Duration(milliseconds: 220),
  transitionBuilder: (_, animation, secondary, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
  pageBuilder: (context, animation, secondary) => Align(
    alignment: Alignment.centerRight,
    child: SizedBox(
      width: MediaQuery.sizeOf(context).width < 700
          ? MediaQuery.sizeOf(context).width
          : 660,
      child: StaffRentalDetails(
        selection: selection,
        api: api,
        manager: manager,
        onChanged: onChanged,
        onIssueInvoice: onIssueInvoice,
      ),
    ),
  ),
);

class StaffRentalDetails extends StatefulWidget {
  const StaffRentalDetails({
    super.key,
    required this.selection,
    required this.api,
    required this.manager,
    required this.onChanged,
    required this.onIssueInvoice,
    this.workspace = false,
  });
  final PackageSelection selection;
  final PackageApi api;
  final bool manager;
  final VoidCallback onChanged;
  final Future<void> Function(PackageSelection) onIssueInvoice;
  final bool workspace;
  @override
  State<StaffRentalDetails> createState() => _StaffRentalDetailsState();
}

class _StaffRentalDetailsState extends State<StaffRentalDetails> {
  late PackageSelection selection = widget.selection;
  bool loading = false;
  String? error;
  String? operationMessage;
  int tab = 0;
  bool verified = false;
  bool get blocked => loading || error != null || widget.workspace && !verified;
  @override
  void initState() {
    super.initState();
    if (widget.workspace) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  void selectTab(int value) => setState(() => tab = value);
  Future<void> openWorkspace() async {
    if (blocked) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StaffRentalDetails(
          selection: selection,
          api: widget.api,
          manager: widget.manager,
          workspace: true,
          onChanged: widget.onChanged,
          onIssueInvoice: widget.onIssueInvoice,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> openPayments([String? invoiceId]) async {
    if (blocked) return;
    final rental = StaffRentalView(selection).rental;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LivePaymentsScreen(
          staff: true,
          manager: widget.manager,
          api: widget.api is HttpPackageApi
              ? (widget.api as HttpPackageApi).transport
              : null,
          initialInvoiceId:
              invoiceId ??
              rental['invoiceId'] ??
              selection.invoice?.id ??
              selection.data['invoiceId'],
          focusInitialInvoice: true,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> openHandover() async {
    if (blocked || widget.api is! HttpPackageApi) return;
    final rental = StaffRentalView(selection).rental;
    if (rental['state'] != 'Locked' || rental['policyVersion'] != 1) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RentalHandoverScreen(
          rental: Map<String, dynamic>.from(rental),
          api: (widget.api as HttpPackageApi).transport,
          manager: widget.manager,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> editPreparation() async {
    if (blocked || widget.api is! HttpPackageApi) return;
    final api = widget.api as HttpPackageApi;
    final saved = await editRentalServiceProgress(
      context,
      selection: selection,
      save: (body) async {
        await api.transport.businessRequest(
          '/v1/package-selections/${selection.id}/service-progress',
          body: body,
        );
      },
    );
    if (!mounted) return;
    await refresh();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service preparation saved.')),
      );
    }
  }

  Future<void> openAppointment(String id) async {
    final actor = PortalScope.maybeOf(context)?.current;
    if (actor == null || blocked) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Linked appointment')),
          body: LiveAppointments(
            uid: actor.id,
            name: actor.name,
            staff: true,
            manager: widget.manager,
            initialAppointmentId: id,
          ),
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> issueInvoice() async {
    if (blocked) return;
    if (!selection.appointments.any((a) => a['status'] == 'Confirmed')) {
      setState(
        () => operationMessage =
            'Confirm the customer’s package appointment first.',
      );
      return;
    }
    setState(() => operationMessage = null);
    await widget.onIssueInvoice(selection);
    await refresh();
  }

  Future<void> refresh() async {
    if (loading || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    widget.onChanged();
    try {
      final matches = (await widget.api.selections()).where(
        (s) => s.id == selection.id,
      );
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(
          () => error =
              'This record is no longer available. Close this panel and refresh the list.',
        );
      } else {
        setState(() {
          selection = matches.first;
          verified = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not refresh this record. Refresh before continuing.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> cancel() async {
    if (blocked ||
        widget.api is! HttpPackageApi ||
        !StaffRentalView(selection).canCancel) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this rental?'),
        content: const Text(
          'Reserved items will be released. Any paid amounts will need a separate refund review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep rental'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel rental'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => loading = true);
    try {
      await (widget.api as HttpPackageApi).transport.businessRequest(
        '/v1/rentals/${selection.data['rental']['id']}/cancel',
        body: {},
      );
      if (!mounted) return;
      setState(() => loading = false);
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is PaymentFailure
              ? e.message
              : 'Could not cancel this rental. Refresh its status before trying again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _rentalDetailLayout(this);
}

String fittingLabel(PackageSelection selection) {
  final decision = selection.data['fittingDecision'] as Map?;
  if (selection.data['fittingWorkflowVersion'] == 2) {
    return switch (decision?['state']) {
      'QuoteNeeded' => 'Chosen gown · proposal needed',
      'AwaitingCustomer' => 'Awaiting customer confirmation',
      'Approved' => 'Selection agreed',
      'Reselect' => 'Choosing another gown',
      'Considering' => 'Customer is considering',
      'Declined' => 'Not proceeding',
      'ChangesRequested' => 'Changes requested',
      _ => 'Team review needed',
    };
  }
  if (decision?['state'] == 'Approved') {
    return decision?['mode'] == 'Waived'
        ? 'No-fitting request approved'
        : 'Fitting completed · satisfied';
  }
  if (decision != null) return 'Fitting needs follow-up';
  return selection.data['fittingChoice']?['mode'] == 'SkipFitting'
      ? 'No-fitting request awaiting review'
      : 'Fitting outcome not recorded';
}

class _DateTile extends StatelessWidget {
  const _DateTile(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: rentalRose),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: rentalMuted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow(this.line, {this.showAction = false, this.onView});
  final RentalPaymentLine line;
  final bool showAction;
  final VoidCallback? onView;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: rentalLine)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(line.label, style: const TextStyle(fontSize: 13));
        final amount = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              line.amountLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              line.status,
              style: TextStyle(
                fontSize: 12,
                color: line.paid
                    ? rentalGreen
                    : line.due
                    ? rentalAmber
                    : rentalRose,
              ),
            ),
          ],
        );
        final action = TextButton(
          onPressed: onView,
          child: Text('View ${line.label.toLowerCase()}'),
        );
        final values = SizedBox(
          width: constraints.maxWidth,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [label, amount],
          ),
        );
        if (!showAction) return values;
        if (constraints.maxWidth >= 650 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.7) {
          return Row(
            children: [
              Expanded(child: label),
              amount,
              const SizedBox(width: 24),
              SizedBox(width: 210, child: action),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            values,
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      },
    ),
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: rentalMuted),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
