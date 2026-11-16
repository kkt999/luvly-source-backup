import 'package:flutter/material.dart';
import '../src/design.dart';
import 'planning_api.dart';

const _wine = Color(0xFF743B4B), _quiet = Color(0xFF6B5C61);

/// Presentation of verified planning data only. Navigation stays with its owner.
class HomePlanCard extends StatelessWidget {
  const HomePlanCard({
    super.key,
    required this.plan,
    required this.next,
    required this.visit,
    required this.planCount,
    required this.onNext,
    required this.onJourney,
    required this.onVisit,
    required this.onSwitch,
    required this.onRefresh,
  });
  final BridalPlan? plan;
  final PlanningAction next;
  final PlanningVisit? visit;
  final int planCount;
  final VoidCallback onNext, onJourney, onVisit, onSwitch, onRefresh;

  String? get countdown {
    final days = plan?.daysToEvent;
    if (days == null) return null;
    if (days == 0) return 'Your event is today';
    if (days < 0) return 'Event date passed';
    return '$days ${days == 1 ? 'day' : 'days'} to your event';
  }

  PlanningPayment? get actionPayment {
    if (next.type != 'payments' || next.targetId == null) return null;
    final candidates = [
      if (plan != null) ...[
        plan!.payment('deposit'),
        plan!.payment('balance'),
        plan!.payment('security'),
      ],
      if (visit != null) visit!.payment,
    ];
    for (final p in candidates) {
      if (p.invoiceId == next.targetId && p.state == 'AwaitingPayment') {
        return p;
      }
    }
    return null;
  }

  String get customerDetail => next.detail
      .replaceAllMapped(RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), (match) {
        try {
          return planningDay(match[0]);
        } catch (_) {
          return match[0]!;
        }
      })
      .replaceAll(
        'Staff records the actual handover.',
        'Our team will help you collect your gown.',
      );

  @override
  Widget build(BuildContext context) {
    final upcomingVisit = visit;
    final payment = actionPayment;
    final planVisit = plan?.data['nextVisit'];
    final actionShowsVisit =
        next.type == 'appointments' &&
        upcomingVisit != null &&
        upcomingVisit.status == 'Confirmed' &&
        (next.targetId == null || next.targetId == upcomingVisit.id) &&
        (plan == null ||
            planVisit is Map && planVisit['id'] == upcomingVisit.id);
    final visitTime = upcomingVisit?.startAt == null
        ? 'Time to be confirmed'
        : planningTime(upcomingVisit!.startAt!);
    final actionTitle = actionShowsVisit
        ? (upcomingVisit.type == 'Dress Trial'
              ? 'View fitting appointment'
              : 'View appointments')
        : next.title == 'Your gown is reserved'
        ? 'View pickup details'
        : next.title;
    final journeyInHeader =
        MediaQuery.sizeOf(context).width >= 360 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.25;
    final state = plan == null
        ? null
        : plan!.data['needsReview'] == true
        ? 'NeedsReview'
        : plan!.completed
        ? 'Returned'
        : plan!.rentalState;
    final stateColor = planningDone(state ?? '')
        ? const Color(0xFF36584A)
        : const Color(0xFF805228);
    return Container(
      key: const Key('home-plan-summary'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6EEEB),
        borderRadius: CustomerUi.cardRadius,
        border: Border.all(color: const Color(0xFFE7D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'YOUR BRIDAL PLAN',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    color: _quiet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (plan != null && journeyInHeader)
                TextButton(
                  onPressed: onJourney,
                  style: TextButton.styleFrom(
                    foregroundColor: _wine,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'View journey',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              IconButton(
                tooltip: 'Refresh my bridal plan',
                onPressed: onRefresh,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 18, color: _quiet),
              ),
            ],
          ),
          Text(
            plan?.name ?? 'Your boutique visit',
            style: const TextStyle(
              fontFamily: 'LuvlySerif',
              fontSize: 26,
              height: 1.12,
              color: ink,
            ),
          ),
          gap(6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (state != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    state == 'Locked' || state == 'Reserved'
                        ? 'Rental reserved'
                        : planningStatus(state),
                    style: TextStyle(
                      fontSize: 11,
                      color: stateColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (countdown != null)
                Text(
                  countdown!,
                  style: const TextStyle(fontSize: 12, color: _quiet),
                ),
            ],
          ),
          if (plan?.eventDate != null) ...[
            gap(5),
            Text(
              'Event · ${planningDay(plan!.eventDate)}',
              style: const TextStyle(fontSize: 12, color: _quiet),
            ),
          ],
          gap(10),
          Semantics(
            button: true,
            child: Material(
              color: _wine,
              borderRadius: CustomerUi.buttonRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('home-next-action'),
                onTap: onNext,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              actionTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (actionShowsVisit) ...[
                              gap(3),
                              Text(
                                '${planningStatus(upcomingVisit.status)} · $visitTime',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                            if (payment?.amount != null) ...[
                              gap(5),
                              Text(
                                planningMoney(payment!.amount),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.arrow_forward,
                        size: 19,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (payment?.amount == null && !actionShowsVisit) ...[
            gap(6),
            Text(
              customerDetail,
              style: const TextStyle(fontSize: 12, height: 1.45, color: _quiet),
            ),
          ],
          if (upcomingVisit != null && !actionShowsVisit) ...[
            const Divider(height: 16),
            Semantics(
              button: true,
              child: InkWell(
                key: const Key('home-next-visit'),
                onTap: onVisit,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: _wine,
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next visit · ${planningStatus(upcomingVisit.status)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _quiet,
                              ),
                            ),
                            gap(2),
                            Text(
                              visitTime,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: _wine, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (plan != null && !journeyInHeader)
                TextButton.icon(
                  onPressed: onJourney,
                  icon: const Icon(Icons.route_outlined, size: 16),
                  label: const Text('View journey'),
                  style: TextButton.styleFrom(
                    foregroundColor: _wine,
                    padding: EdgeInsets.zero,
                  ),
                ),
              if (planCount > 1)
                TextButton(
                  onPressed: onSwitch,
                  style: TextButton.styleFrom(
                    foregroundColor: _quiet,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                  ),
                  child: Text('Switch plan ($planCount)'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class HomePlanUnavailable extends StatelessWidget {
  const HomePlanUnavailable({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF6EEEB),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your plan is temporarily unavailable',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        gap(6),
        Text(message, style: const TextStyle(fontSize: 12, color: _quiet)),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Reload my plan'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: _wine,
          ),
        ),
      ],
    ),
  );
}
