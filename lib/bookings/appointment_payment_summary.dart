import 'package:flutter/material.dart';
import '../packages/package_api.dart' show packageMoney;
import '../src/design.dart' show line;
import '../src/model.dart' show months;
import 'booking_repository.dart' show makeupTrial;

const dressTrialFeeCents = 5000;
const boutiqueVisitMinutes = 60;

/// Shows the customer’s current selection and the applicable booking terms.
class AppointmentPaymentSummary extends StatelessWidget {
  const AppointmentPaymentSummary({
    super.key,
    required this.chargeable,
    required this.included,
    this.visitStart,
    this.packageName = '',
    this.linkedToPackage = false,
    this.serviceLabel = 'Dress Trial',
  });
  final bool chargeable, included, linkedToPackage;
  final DateTime? visitStart;
  final String packageName, serviceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMakeupTrial = serviceLabel == makeupTrial;
    final local = visitStart?.toUtc().add(const Duration(hours: 8));
    final time = local == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(local),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final feeLabel = chargeable
        ? 'Fitting fee'
        : included
        ? 'Included fitting'
        : isMakeupTrial
        ? 'In-boutique trial'
        : 'Consultation';
    final amount = chargeable
        ? packageMoney(dressTrialFeeCents)
        : included
        ? 'Included'
        : isMakeupTrial
        ? 'RM 0 online'
        : 'Free';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (local != null || packageName.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      size: 21,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (local != null) ...[
                            Text(
                              serviceLabel,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${local.day} ${months[local.month - 1]} ${local.year} · $time MYT',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          if (packageName.isNotEmpty) ...[
                            if (local != null) const SizedBox(height: 2),
                            Text(
                              'Selected package: $packageName',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack =
                      constraints.maxWidth <
                      MediaQuery.textScalerOf(context).scale(210);
                  final label = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(feeLabel, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        chargeable
                            ? '$boutiqueVisitMinutes minutes · fee per visit, not per gown'
                            : '$boutiqueVisitMinutes-minute visit',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  );
                  return Flex(
                    direction: stack ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (stack) label else Expanded(child: label),
                      const SizedBox(width: 12, height: 4),
                      Text(
                        amount,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Divider(height: 22),
              if (chargeable) ...[
                Text(
                  'Pay to confirm your appointment. Unpaid holds expire after 15 minutes or when the visit starts, whichever comes first.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
              ],
              Text(
                chargeable
                    ? linkedToPackage
                          ? 'Your package booking deposit is separate. Once Luvly records your attendance, an eligible paid fitting can be credited towards that deposit once.'
                          : 'After Luvly records your attendance, you may link an eligible paid fitting to a package and use the credit once towards its booking deposit.'
                    : included
                    ? 'Covered by your booked package. No additional fitting fee.'
                    : isMakeupTrial
                    ? 'No payment is collected when you book. Contact Luvly to confirm the service price before your visit.'
                    : 'No payment is required for this consultation.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (isMakeupTrial)
          const _BookingDisclosure(
            title: 'Booking & cancellation',
            lines: [
              'Use Bookings to change or cancel an eligible appointment.',
              'Makeup trials are booked separately from gown fittings and rental packages.',
            ],
          ),
        if (!isMakeupTrial)
          const _BookingDisclosure(
            title: 'Booking & cancellation',
            lines: [
              'Use Reschedule in Bookings to move an eligible confirmed visit and keep its verified fitting fee. Complete any unpaid fitting payment first.',
              'Paid cancellations, late payments and no-shows need staff review. Refunds are not automatic.',
              'A fitting appointment does not reserve a gown.',
            ],
          ),
        if (!isMakeupTrial)
          const _BookingDisclosure(
            title: 'Package payment details',
            lines: [
              'Package rental is optional and billed separately after your fitting.',
              '50% booking deposit, less eligible fitting credit. Pay within the 15-minute rental hold to lock available items.',
              'Pay the remaining 50% and a separate RM300 refundable security deposit per gown before pickup.',
              'Security is returned after inspection, less documented, agreed deductions.',
            ],
          ),
      ],
    );
  }
}

class _BookingDisclosure extends StatelessWidget {
  const _BookingDisclosure({required this.title, required this.lines});
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(horizontal: 6),
    childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    shape: const Border(bottom: BorderSide(color: line)),
    collapsedShape: const Border(bottom: BorderSide(color: line)),
    title: Text(title, style: Theme.of(context).textTheme.titleSmall),
    children: [
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Text('•  ')),
              Expanded(
                child: Text(
                  line,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class AppointmentBookingFooter extends StatelessWidget {
  const AppointmentBookingFooter({
    super.key,
    required this.chargeable,
    required this.included,
    required this.busy,
    required this.onContinue,
    this.error,
    this.hint,
  });
  final bool chargeable, included, busy;
  final VoidCallback? onContinue;
  final String? error, hint;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feedback = error ?? hint;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8DFDC))),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Due today',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        chargeable
                            ? packageMoney(dressTrialFeeCents)
                            : included
                            ? 'Included'
                            : 'RM 0.00',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (feedback != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            feedback,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: error == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: busy ? null : onContinue,
                      child: busy
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Flexible(child: Text('Preparing…')),
                              ],
                            )
                          : Text(
                              chargeable
                                  ? 'Continue to payment'
                                  : 'Book appointment',
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
