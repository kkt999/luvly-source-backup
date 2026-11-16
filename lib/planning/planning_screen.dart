import 'dart:async';
import 'package:flutter/material.dart';
import '../src/design.dart';
import '../src/model.dart';
import '../src/support.dart';
import '../bookings/booking_screens.dart';
import '../packages/package_screen.dart';
import '../payments/payment_screen.dart';
import 'planning_api.dart';
import 'home_plan_card.dart';
import '../shared/list_controls.dart';

const _wine = Color(0xFF783A4C),
    _sage = Color(0xFF46665B),
    _amber = Color(0xFF9A682A);

class CustomerPlanningScreen extends StatelessWidget {
  const CustomerPlanningScreen({
    super.key,
    required this.uid,
    this.api,
    this.initialPlanId,
    this.onAction,
  });
  final String uid;
  final PlanningApi? api;
  final String? initialPlanId;
  final Future<void> Function(PlanningAction)? onAction;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('My bridal journey')),
    body: CustomerPlanningView(
      uid: uid,
      api: api,
      initialPlanId: initialPlanId,
      onAction: onAction,
    ),
  );
}

class CustomerPlanningView extends StatefulWidget {
  const CustomerPlanningView({
    super.key,
    required this.uid,
    this.compact = false,
    this.active = true,
    this.api,
    this.initialPlanId,
    this.onAppointments,
    this.onSupport,
    this.onAction,
  });
  final String uid;
  final bool compact, active;
  final PlanningApi? api;
  final String? initialPlanId;
  final VoidCallback? onAppointments, onSupport;
  final Future<void> Function(PlanningAction)? onAction;
  @override
  State<CustomerPlanningView> createState() => _CustomerPlanningState();
}

class _CustomerPlanningState extends State<CustomerPlanningView>
    with WidgetsBindingObserver, RouteAware {
  late PlanningApi api;
  late Future<PlanningSnapshot> future;
  RouteObserver<PageRoute<dynamic>>? observer;
  PageRoute<dynamic>? route;
  bool covered = false;
  String? selection;
  Timer? expiryTimer;
  @override
  void initState() {
    super.initState();
    api = widget.api ?? HttpPlanningApi();
    selection = widget.initialPlanId;
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = PlanningNavigationScope.maybeOf(context),
        current = ModalRoute.of(context);
    if (next != observer && current is PageRoute<dynamic>) {
      observer?.unsubscribe(this);
      observer = next;
      route = current;
      observer?.subscribe(this, current);
    }
  }

  @override
  void didUpdateWidget(CustomerPlanningView old) {
    super.didUpdateWidget(old);
    if (widget.uid != old.uid) {
      selection = null;
      load();
    } else if (widget.active && !old.active) {
      refresh();
    }
    if (!widget.active) expiryTimer?.cancel();
  }

  @override
  void dispose() {
    expiryTimer?.cancel();
    observer?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  void didPushNext() {
    covered = true;
    expiryTimer?.cancel();
  }

  @override
  void didPopNext() {
    covered = false;
    if (widget.active) refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active && !covered) {
      refresh();
    } else if (state != AppLifecycleState.resumed) {
      expiryTimer?.cancel();
    }
  }

  void load() {
    expiryTimer?.cancel();
    final request = api.load(widget.uid);
    request.ignore();
    future = request;
    request.then<void>((data) {
      if (!mounted ||
          !identical(request, future) ||
          !widget.active ||
          covered) {
        return;
      }
      final deadlines = data.deadlines..sort();
      if (deadlines.isNotEmpty) {
        expiryTimer = Timer(
          Duration(milliseconds: deadlines.first - data.generatedAt + 800),
          () {
            if (mounted && widget.active && !covered) refresh();
          },
        );
      }
    }, onError: (Object _, StackTrace _) {});
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(load);
    try {
      await future;
    } catch (_) {
      /* The visible retry state owns the error. */
    }
  }

  BridalPlan? chosen(PlanningSnapshot data) {
    for (final plan in data.plans) {
      if (plan.id == selection) return plan;
    }
    return data.plans.isEmpty ? null : data.plans.first;
  }

  Future<void> act(PlanningAction action) async {
    if (widget.onAction != null) {
      await widget.onAction!(action);
      if (mounted) await refresh();
      return;
    }
    if (action.type == 'appointments' && widget.onAppointments != null) {
      widget.onAppointments!();
      return;
    }
    if (action.type == 'support' && widget.onSupport != null) {
      widget.onSupport!();
      return;
    }
    final profile = AppScope.maybeOf(context);
    final Widget destination = switch (action.type) {
      'packages' => LivePackageScreen(
        initialSelections: action.targetId != null,
        initialSelectionId: action.targetId,
      ),
      'payments' => LivePaymentsScreen(initialInvoiceId: action.targetId),
      'appointments' => PageFrame(
        title: 'My appointments',
        child: LiveAppointments(
          uid: widget.uid,
          name: profile?.name ?? '',
          phone: profile?.phone ?? '',
        ),
      ),
      _ => const PageFrame(title: 'Support', child: SupportScreen()),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => destination));
    if (mounted && observer == null) await refresh();
  }

  Future<void> switchPlan(PlanningSnapshot data) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _PlanPicker(plans: data.plans, selected: chosen(data)?.id),
    );
    if (id != null && mounted) setState(() => selection = id);
  }

  Future<void> openJourney(BridalPlan? plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerPlanningScreen(
          uid: widget.uid,
          api: api,
          initialPlanId: plan?.id,
          onAction: widget.onAction,
        ),
      ),
    );
    if (mounted && observer == null) await refresh();
  }

  @override
  Widget build(BuildContext c) {
    Widget homeSummary(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: CustomerUi.sectionSpacing),
      child: child,
    );
    final content = FutureBuilder<PlanningSnapshot>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return widget.compact
              ? homeSummary(const _LoadingPlan())
              : const _LoadingPlan();
        }
        if (s.hasError || !s.hasData) {
          if (widget.compact) {
            return homeSummary(
              HomePlanUnavailable(
                message: planningError(s.error ?? Object()),
                onRetry: refresh,
              ),
            );
          }
          return Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your plan is temporarily unavailable',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                gap(8),
                Text(
                  planningError(s.error ?? Object()),
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                gap(12),
                OutlinedButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reload my plan'),
                ),
              ],
            ),
          );
        }
        final data = s.data!,
            plan = chosen(data),
            next = plan?.next ?? data.next;
        final nextVisit = widget.compact || plan == null
            ? data.nextVisit
            : plan.data['nextVisit'] == null
            ? null
            : PlanningVisit(Map<String, dynamic>.from(plan.data['nextVisit']));
        final history = data.visits
            .where(
              (v) =>
                  (plan == null ||
                      (plan.data['appointmentIds'] as List).contains(v.id)) &&
                  v.id != nextVisit?.id,
            )
            .toList();
        if (widget.compact) {
          if (plan == null && nextVisit == null) return const SizedBox.shrink();
          return homeSummary(
            HomePlanCard(
              plan: plan,
              next: next,
              visit: nextVisit,
              planCount: data.plans.length,
              onNext: () => act(next),
              onJourney: () => openJourney(plan),
              onVisit: () => act(
                PlanningAction({
                  'type': 'appointments',
                  'title': '',
                  'detail': '',
                  'targetId': null,
                }),
              ),
              onSwitch: () => switchPlan(data),
              onRefresh: refresh,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'YOUR BRIDAL PLAN',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh my bridal plan',
                  onPressed: refresh,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 19),
                ),
              ],
            ),
            gap(8),
            _PlanHero(
              plan: plan,
              onOpen: widget.compact ? () => openJourney(plan) : null,
              onStart: () => act(
                plan == null
                    ? PlanningAction({
                        'type': 'packages',
                        'title': '',
                        'detail': '',
                        'targetId': null,
                      })
                    : next,
              ),
            ),
            if (data.plans.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => switchPlan(data),
                  icon: const Icon(Icons.swap_horiz, size: 17),
                  label: Text('Switch plan (${data.plans.length})'),
                ),
              )
            else
              gap(14),
            if (plan != null || data.nextVisit != null)
              _NextStep(action: next, onTap: () => act(next)),
            if (nextVisit case final PlanningVisit visit) ...[
              gap(14),
              if (widget.compact)
                _CompactVisit(
                  visit: visit,
                  onOpen: () => act(
                    PlanningAction({
                      'type': 'appointments',
                      'title': '',
                      'detail': '',
                      'targetId': null,
                    }),
                  ),
                )
              else
                _VisitCard(
                  visit: visit,
                  onOpen: () => act(
                    PlanningAction({
                      'type': 'appointments',
                      'title': '',
                      'detail': '',
                      'targetId': null,
                    }),
                  ),
                  onPay: () => act(
                    PlanningAction({
                      'type': 'payments',
                      'title': '',
                      'detail': '',
                      'targetId': visit.payment.invoiceId,
                    }),
                  ),
                ),
            ],
            if (!widget.compact) ...[
              gap(24),
              if (plan != null) ...[
                _heading('Your rental at a glance'),
                gap(12),
                _Dates(plan: plan),
                gap(16),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      gap(6),
                      Text(
                        'Package total ${planningMoney(plan.data['totalCents'])}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      gap(10),
                      if (plan.gowns.isEmpty)
                        const Text(
                          'No gown preferences saved yet.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      for (final gown in plan.gowns)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            '${gown['name']} · ${gown['size']}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      Text(
                        '${plan.data['accessoriesCount']} accessory choices saved',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      gap(10),
                      TextButton.icon(
                        onPressed: () => act(
                          PlanningAction({
                            'type': 'packages',
                            'title': '',
                            'detail': '',
                            'targetId': plan.id,
                          }),
                        ),
                        icon: const Icon(Icons.checkroom_outlined, size: 17),
                        label: const Text('Manage this package'),
                      ),
                    ],
                  ),
                ),
                gap(24),
                _heading('One beautiful step at a time'),
                gap(6),
                const Text(
                  'Your progress at a glance.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                gap(14),
                for (final item in plan.steps) _Milestone(item: item),
                gap(16),
                _heading('Your payment overview'),
                gap(6),
                const Text(
                  'Refundable security is separate from your package price.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                gap(14),
                for (final item in [
                  ('deposit', 'Booking deposit'),
                  ('balance', 'Package balance'),
                  ('security', 'Refundable security'),
                  if (plan.data['extension']?['invoiceId'] != null)
                    ('extension', 'Rental date extension'),
                ])
                  _PaymentRow(
                    title: item.$2,
                    payment: plan.payment(item.$1),
                    onOpen: () => act(
                      PlanningAction({
                        'type': 'payments',
                        'title': '',
                        'detail': '',
                        'targetId': plan.payment(item.$1).invoiceId,
                      }),
                    ),
                  ),
                if ((plan.data['additionalRentalPaidCents'] as int? ?? 0) > 0)
                  Text(
                    'Additional rental fees paid: ${planningMoney(plan.data['additionalRentalPaidCents'])} · separate from the base package price.',
                  ),
              ] else ...[
                gap(10),
                const Text(
                  'A saved package will create a separate journey here. You can still view your existing appointments.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
              gap(22),
              _heading('Other recorded visits'),
              gap(12),
              if (history.isEmpty)
                const Surface(
                  child: Text(
                    'No other linked visits recorded.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              for (final visit in history.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VisitCard(
                    visit: visit,
                    onOpen: () => act(
                      PlanningAction({
                        'type': 'appointments',
                        'title': '',
                        'detail': '',
                        'targetId': null,
                      }),
                    ),
                    onPay: () => act(
                      PlanningAction({
                        'type': 'payments',
                        'title': '',
                        'detail': '',
                        'targetId': visit.payment.invoiceId,
                      }),
                    ),
                  ),
                ),
            ],
            if (data.reviewPayments > 0)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${data.reviewPayments} payment record(s) need team review. Please check Payments or contact support before paying again.',
                  style: const TextStyle(
                    color: _amber,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            gap(10),
            Text(
              'Updated ${planningTime(data.generatedAt)}',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
            if (!widget.compact) ...[
              gap(18),
              OutlinedButton.icon(
                onPressed: () => act(
                  PlanningAction({
                    'type': 'support',
                    'title': '',
                    'detail': '',
                    'targetId': null,
                  }),
                ),
                icon: const Icon(Icons.support_agent, size: 18),
                label: const Text('Talk to our team'),
              ),
            ],
          ],
        );
      },
    );
    return widget.compact
        ? content
        : RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [content],
            ),
          );
  }
}

Widget _heading(String text) => Text(
  text,
  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
);

class _PlanHero extends StatelessWidget {
  const _PlanHero({required this.plan, this.onOpen, required this.onStart});
  final BridalPlan? plan;
  final VoidCallback? onOpen;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext c) {
    final days = plan?.daysToEvent;
    final headline = plan == null
        ? 'A beautiful beginning.'
        : days == null
        ? 'Let’s plan your dates.'
        : days == 0
        ? 'Your event is today.'
        : days < 0
        ? 'Your event date has passed.'
        : '$days ${days == 1 ? 'day' : 'days'} to your event.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_wine, Color(0xFF9C5665)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontFamily: 'LuvlySerif',
                    fontSize: 29,
                    height: 1.08,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.favorite_border,
                color: Color(0xFFF1D9CD),
                size: 22,
              ),
            ],
          ),
          gap(14),
          Text(
            plan == null
                ? 'Your gown, your fitting, your dates — all in one place.'
                : plan!.eventDate == null
                ? plan!.name
                : '${planningDay(plan!.eventDate)} · ${plan!.name}',
            style: const TextStyle(
              color: Color(0xFFF5E7E1),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          gap(18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (plan != null)
                _Badge(
                  state: plan!.data['needsReview'] == true
                      ? 'NeedsReview'
                      : plan!.completed
                      ? 'Returned'
                      : plan!.rentalState,
                  onDark: true,
                ),
              TextButton.icon(
                onPressed: plan == null ? onStart : onOpen ?? onStart,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF8F0),
                  foregroundColor: _wine,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                icon: Icon(
                  plan == null ? Icons.arrow_forward : Icons.route_outlined,
                  size: 16,
                ),
                label: Text(
                  plan == null
                      ? 'Explore packages'
                      : onOpen != null
                      ? 'View journey'
                      : 'View next step',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.action, required this.onTap});
  final PlanningAction action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => Material(
    color: const Color(0xFFF6F0E8),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            const Icon(Icons.north_east, size: 19, color: _amber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR NEXT STEP',
                    style: TextStyle(
                      color: _amber,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  gap(4),
                  Text(
                    action.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  gap(4),
                  Text(
                    action.detail,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: _amber, size: 19),
          ],
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.state, this.onDark = false});
  final String state;
  final bool onDark;
  @override
  Widget build(BuildContext c) {
    final done = planningDone(state),
        alert = {
          'Overdue',
          'NeedsReview',
          'Expired',
          'DatePassed',
          'Cancelled',
        }.contains(state);
    final color = onDark
        ? Colors.white
        : done
        ? _sage
        : alert
        ? _amber
        : rose;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: .15)
            : color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        planningStatus(state),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CompactVisit extends StatelessWidget {
  const _CompactVisit({required this.visit, required this.onOpen});
  final PlanningVisit visit;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext c) => InkWell(
    onTap: onOpen,
    borderRadius: BorderRadius.circular(15),
    child: Surface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, size: 21, color: rose),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next visit · ${planningStatus(visit.status)}',
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
                gap(4),
                Text(
                  visit.startAt == null
                      ? 'Date needs review'
                      : planningTime(visit.startAt!),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: rose, size: 18),
        ],
      ),
    ),
  );
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.visit,
    required this.onOpen,
    required this.onPay,
  });
  final PlanningVisit visit;
  final VoidCallback onOpen, onPay;
  @override
  Widget build(BuildContext c) => Surface(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.calendar_month_outlined, color: rose, size: 21),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.type,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  gap(5),
                  Text(
                    visit.startAt == null
                        ? 'Date needs team review'
                        : planningTime(visit.startAt!),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        gap(10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Badge(state: visit.status),
            TextButton(
              onPressed: onOpen,
              child: const Text('View booking', style: TextStyle(fontSize: 11)),
            ),
            if (visit.status == 'AwaitingPayment' &&
                visit.payment.invoiceId != null)
              TextButton(
                onPressed: onPay,
                child: const Text(
                  'View fitting payment',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        if (visit.status == 'AwaitingPayment' &&
            visit.data['expiresAt'] != null)
          Text(
            'Time held until ${planningTime(visit.data['expiresAt'])}; payment verification confirms the visit.',
            style: const TextStyle(color: _amber, fontSize: 10, height: 1.5),
          ),
      ],
    ),
  );
}

class _Dates extends StatelessWidget {
  const _Dates({required this.plan});
  final BridalPlan plan;
  @override
  Widget build(BuildContext c) => LayoutBuilder(
    builder: (c, box) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in [
          ('pickupDate', 'Pickup'),
          ('eventDate', 'Wedding / event'),
          ('returnDate', 'Return'),
        ])
          SizedBox(
            width: box.maxWidth >= 360 ? (box.maxWidth - 20) / 3 : box.maxWidth,
            child: Surface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$2,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                  gap(7),
                  Text(
                    planningDay(plan.data[item.$1]),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _Milestone extends StatelessWidget {
  const _Milestone({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext c) {
    final done = planningDone(item['state']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: done ? const Color(0xFFECF2EE) : blush,
              child: Icon(
                done ? Icons.check : Icons.radio_button_unchecked,
                size: 16,
                color: done ? _sage : rose,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  gap(7),
                  _Badge(state: item['state']),
                  gap(7),
                  Text(
                    item['detail'],
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.title,
    required this.payment,
    required this.onOpen,
  });
  final String title;
  final PlanningPayment payment;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          gap(8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                planningMoney(payment.amount),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _Badge(state: payment.state),
            ],
          ),
          if (payment.invoiceId != null)
            TextButton(
              onPressed: onOpen,
              child: const Text(
                'View payment / receipt',
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    ),
  );
}

class _LoadingPlan extends StatelessWidget {
  const _LoadingPlan();
  @override
  Widget build(BuildContext c) => const Surface(
    child: Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Loading your bridal plan…',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _PlanPicker extends StatefulWidget {
  const _PlanPicker({required this.plans, required this.selected});
  final List<BridalPlan> plans;
  final String? selected;
  @override
  State<_PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends State<_PlanPicker> {
  String query = '';
  String stage = 'All plans';
  @override
  Widget build(BuildContext c) {
    final rows = widget.plans
        .where(
          (p) =>
              matchesListSearch(query, [
                p.name,
                p.eventDate,
                planningDay(p.eventDate),
              ]) &&
              (stage == 'All plans' || planningStatus(p.rentalState) == stage),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(c).bottom + 12,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * .7,
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(child: _heading('Choose your bridal plan')),
                IconButton(
                  onPressed: () => Navigator.pop(c),
                  tooltip: 'Close plan picker',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              'Each saved package keeps its own dates and status.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            gap(16),
            ListSearchField(
              value: query,
              hint: 'Search packages or event date',
              onChanged: (v) => setState(() => query = v),
            ),
            gap(12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ListFilterSelect(
                  label: 'Rental status',
                  value: stage,
                  options: [
                    'All plans',
                    ...{
                      for (final p in widget.plans)
                        planningStatus(p.rentalState),
                    },
                  ],
                  onChanged: (v) => setState(() => stage = v),
                ),
                if (query.isNotEmpty || stage != 'All plans')
                  ResetListFilters(
                    onReset: () => setState(() {
                      query = '';
                      stage = 'All plans';
                    }),
                  ),
              ],
            ),
            gap(12),
            if (rows.isEmpty)
              const Text('No matching plans.', style: TextStyle(color: muted)),
            for (final p in rows)
              ListTile(
                key: ValueKey('plan-choice-${p.id}'),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                title: Text(
                  p.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${p.eventDate == null ? 'Event date not set' : planningDay(p.eventDate)}\n${planningStatus(p.rentalState)}${p.data['createdAt'] == null ? '' : ' · Saved ${planningTime(p.data['createdAt'])}'}',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                trailing: p.id == widget.selected
                    ? const Icon(Icons.check_circle, color: _sage)
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, p.id),
              ),
          ],
        ),
      ),
    );
  }
}
