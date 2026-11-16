import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../packages/package_api.dart';
import '../packages/package_screen.dart';
import '../payments/payment_api.dart';
import 'promotion_api.dart';
import 'campaign_visuals.dart';
import '../shared/list_controls.dart';

const _rose = Color(0xFF924653), _line = Color(0xFFE7D8DB);
String promotionError(Object e) =>
    e is PaymentFailure ? e.message : 'Could not load offers. Please retry.';

class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    this.api,
    this.preview = false,
    this.initialCampaignId,
  });
  final PromotionApi? api;
  final bool preview;
  final String? initialCampaignId;
  @override
  State<OffersScreen> createState() => _OffersState();
}

class _OffersState extends State<OffersScreen> {
  late final PromotionApi api = widget.api ?? HttpPromotionApi();
  late Future<List<Campaign>> feed = widget.preview
      ? Future.value([])
      : api.list();
  String query = '';
  bool offersOnly = false;
  bool newsOnly = false;
  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  void reload() {
    final next = api.list();
    next.ignore();
    setState(() {
      feed = next;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Offers & boutique news'),
      actions: [
        if (!widget.preview)
          IconButton(
            onPressed: reload,
            tooltip: 'Refresh offers',
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'The Bridal Edit',
          style: TextStyle(
            fontFamily: 'LuvlySerif',
            fontSize: 36,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        const Text('Beautiful beginnings. Thoughtful privileges.'),
        const SizedBox(height: 12),
        const Text(
          campaignImageDisclosure,
          style: TextStyle(fontSize: 10, color: Color(0xFF827579), height: 1.4),
        ),
        const SizedBox(height: 20),
        ListSearchField(
          value: query,
          hint: 'Search offers or code',
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All updates'),
              selected: !offersOnly && !newsOnly,
              onSelected: (_) => setState(() {
                offersOnly = false;
                newsOnly = false;
              }),
            ),
            ChoiceChip(
              label: const Text('Offers'),
              selected: offersOnly,
              onSelected: (_) => setState(() {
                offersOnly = true;
                newsOnly = false;
              }),
            ),
            ChoiceChip(
              label: const Text('Boutique news'),
              selected: newsOnly,
              onSelected: (_) => setState(() {
                offersOnly = false;
                newsOnly = true;
              }),
            ),
            if (query.isNotEmpty || offersOnly || newsOnly)
              ResetListFilters(
                onReset: () => setState(() {
                  query = '';
                  offersOnly = false;
                  newsOnly = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.preview)
          const Text('Sign in to explore your current offers.'),
        FutureBuilder<List<Campaign>>(
          future: feed,
          builder: (context, s) {
            if (s.hasError) {
              return Column(
                children: [
                  Text(promotionError(s.error!)),
                  TextButton(onPressed: reload, child: const Text('Retry')),
                ],
              );
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = s.data!
                .where(
                  (p) =>
                      (widget.initialCampaignId == null ||
                          p.id == widget.initialCampaignId) &&
                      (!offersOnly || p.offer) &&
                      (!newsOnly || !p.offer) &&
                      matchesListSearch(query, [
                        p.title,
                        p.description,
                        p.code,
                      ]),
                )
                .toList();
            return Column(
              children: [
                if (rows.isEmpty && !widget.preview)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching offers right now. Check back for future updates.',
                    ),
                  ),
                for (final p in rows)
                  CampaignCard(
                    campaign: p,
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            LivePackageScreen(initialPackageId: p.packageId),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class CampaignCard extends StatelessWidget {
  const CampaignCard({
    super.key,
    required this.campaign,
    this.onOpen,
    this.showStatus = false,
  });
  final Campaign campaign;
  final VoidCallback? onOpen;
  final bool showStatus;
  @override
  Widget build(BuildContext context) {
    final p = campaign;
    if (!showStatus) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CampaignCreative(
              campaign: p,
              onTap: onOpen,
              actionLabel: 'View package',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Valid through ${p.data['endDate']} · MYT',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF827579),
                    ),
                  ),
                  if (p.offer) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF4F1),
                        border: Border.all(color: _line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SelectableText(
                            p.code,
                            style: const TextStyle(
                              fontSize: 13,
                              letterSpacing: 1.5,
                              color: _rose,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: p.code),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Code copied. Apply it in My packages before the deposit invoice.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 15),
                            label: const Text(
                              'Copy code',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Offer details & terms',
                      style: TextStyle(fontSize: 12),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.description,
                              style: const TextStyle(fontSize: 12, height: 1.6),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              p.terms,
                              style: const TextStyle(fontSize: 12, height: 1.6),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (onOpen != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onOpen,
                        child: const Text('Explore packages'),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                p.offer ? Icons.local_offer_outlined : Icons.campaign_outlined,
                color: _rose,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  showStatus ? '${p.data['kind']} · ${p.status}' : p.saving,
                  style: const TextStyle(
                    color: _rose,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            p.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(p.description),
          if (p.offer)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Minimum ${offerMoney(p.data['minimumCents'])} · Ends ${p.data['endDate']} (MYT)',
                style: const TextStyle(fontSize: 11, color: Color(0xFF827579)),
              ),
            ),
          if (p.offer) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  p.code,
                  style: const TextStyle(
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                    color: _rose,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Code copied. Apply it in My packages before the deposit invoice.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy code'),
                ),
              ],
            ),
          ],
          if (p.data['packageName'] is String)
            Text('For ${p.data['packageName']}'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Details & terms',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  p.terms,
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ],
          ),
          if (onOpen != null)
            TextButton(
              onPressed: onOpen,
              child: const Text('Explore packages'),
            ),
        ],
      ),
    );
  }
}

class HomeOfferBanner extends StatefulWidget {
  const HomeOfferBanner({super.key, this.api, this.active = true});
  final PromotionApi? api;
  final bool active;
  @override
  State<HomeOfferBanner> createState() => _BannerState();
}

class _BannerState extends State<HomeOfferBanner> with WidgetsBindingObserver {
  late final PromotionApi api = widget.api ?? HttpPromotionApi();
  late Future<List<Campaign>> feed;
  final pages = PageController(viewportFraction: .94, keepPage: false);
  int current = 0;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    feed = load();
  }

  Future<List<Campaign>> load() async {
    loading = true;
    try {
      return await api.list();
    } finally {
      loading = false;
    }
  }

  void reload() {
    if (!mounted || loading) return;
    setState(() {
      current = 0;
      feed = load();
    });
  }

  @override
  void didUpdateWidget(covariant HomeOfferBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) reload();
  }

  Future<void> openOffers([Campaign? campaign]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            OffersScreen(api: widget.api, initialCampaignId: campaign?.id),
      ),
    );
    // Re-check eligibility/expiry after returning, not just on first app load.
    reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) api.close();
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Campaign>>(
    future: feed,
    builder: (context, s) {
      final rows = (s.data ?? [])
          .where((p) => p.data['banner'] == true && p.status == 'Active')
          .take(3)
          .toList();
      final index = rows.isEmpty ? 0 : current.clamp(0, rows.length - 1);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE LUVLY EDIT',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.6,
              color: Color(0xFF827579),
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Offers for your day',
                  style: TextStyle(
                    fontFamily: 'LuvlySerif',
                    fontSize: 24,
                    height: 1.1,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh offers',
                onPressed: s.connectionState == ConnectionState.waiting
                    ? null
                    : reload,
                icon: const Icon(Icons.refresh, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              TextButton(
                onPressed: openOffers,
                child: const Text('See all', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (s.connectionState == ConnectionState.waiting)
            Container(
              key: const Key('home-offers-loading'),
              height: 180,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF7ECEF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finding your bridal privileges…'),
                  SizedBox(height: 18),
                  LinearProgressIndicator(),
                ],
              ),
            )
          else if (s.hasError || rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF4F1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.hasError
                        ? 'We couldn’t load your offers.'
                        : 'New offers are on their way.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.hasError
                        ? 'Please try again in a moment.'
                        : 'See all for the latest boutique updates.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (s.hasError)
                    TextButton.icon(
                      onPressed: reload,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try again'),
                    ),
                ],
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                key: const Key('home-offer-carousel'),
                height: rows
                    .map(
                      (p) => campaignCreativeHeight(
                        context,
                        constraints.maxWidth * .94 - 10,
                        p,
                      ),
                    )
                    .reduce((a, b) => a > b ? a : b),
                child: PageView.builder(
                  controller: pages,
                  padEnds: false,
                  itemCount: rows.length,
                  onPageChanged: (v) => setState(() => current = v),
                  itemBuilder: (c, i) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: CampaignCreative(
                      key: ValueKey(rows[i].id),
                      campaign: rows[i],
                      onTap: () => openOffers(rows[i]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows.length > 1
                        ? 'Swipe to discover'
                        : 'Your bridal privilege',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF827579),
                    ),
                  ),
                ),
                for (var i = 0; i < rows.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: index == i ? 18 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: index == i ? _rose : const Color(0xFFE1D4D6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${index + 1}/${rows.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF827579),
                  ),
                ),
                if (rows.length > 1)
                  IconButton(
                    tooltip: 'Next offer',
                    onPressed: () => pages.animateToPage(
                      (index + 1) % rows.length,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

class PackagePromotion extends StatefulWidget {
  const PackagePromotion({
    super.key,
    required this.selection,
    required this.reload,
    this.staff = false,
    this.api,
  });
  final PackageSelection selection;
  final VoidCallback reload;
  final bool staff;
  final PromotionApi? api;
  @override
  State<PackagePromotion> createState() => _PackagePromotionState();
}

class _PackagePromotionState extends State<PackagePromotion> {
  late final PromotionApi api = widget.api ?? HttpPromotionApi();
  bool busy = false;
  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> edit() async {
    final controller = TextEditingController(
      text: widget.selection.data['promotion']?['code'] ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Package promo code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLength: 20,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Promo code'),
            ),
            const Text(
              'One code per package. Minimum spend applies to your customised package subtotal, so removing an optional service may affect eligibility. Luvly checks the offer again before issuing the booking deposit.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          if (widget.selection.data['promotion'] != null)
            TextButton(
              onPressed: () => Navigator.pop(c, ''),
              child: const Text('Remove code'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, controller.text.trim().toUpperCase()),
            child: const Text('Apply code'),
          ),
        ],
      ),
    );
    // The dialog's exit animation may still use its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => busy = true);
    try {
      await api.apply(
        widget.selection.id,
        result,
        widget.selection.data['promotionRevision'] ?? 0,
      );
      if (mounted) {
        widget.reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isEmpty
                  ? 'Promo code removed.'
                  : 'Promo code applied. Review your new total.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(promotionError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selection, p = s.data['promotion'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p != null) ...[
            Text('Package subtotal  ${offerMoney(p['subtotalCents'])}'),
            Text(
              '${p['code']}  −${offerMoney(p['discountCents'])}',
              style: const TextStyle(color: _rose, fontWeight: FontWeight.w600),
            ),
            if (s.data['fittingQuote']?['state'] == 'Accepted' &&
                (s.data['fittingQuote']['extraCents'] as int? ?? 0) > 0)
              Text(
                'Agreed adjustments  +${offerMoney(s.data['fittingQuote']['extraCents'])}',
              ),
            Text(
              'Package total  ${offerMoney(s.totalCents)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              '50% deposit is calculated on this total; any eligible fitting credit is applied afterwards.',
              style: TextStyle(fontSize: 11),
            ),
          ],
          if (!widget.staff &&
              s.data['invoiceId'] == null &&
              s.data['rentalId'] == null &&
              s.selectedGowns.isNotEmpty)
            TextButton.icon(
              onPressed: busy ? null : edit,
              icon: const Icon(Icons.local_offer_outlined, size: 18),
              label: Text(
                busy
                    ? 'Checking code…'
                    : p == null
                    ? 'Add promo code'
                    : 'Change promo code',
              ),
            ),
        ],
      ),
    );
  }
}
