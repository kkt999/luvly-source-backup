import 'package:flutter/material.dart';
import '../packages/package_api.dart';
import 'promotion_api.dart';
import 'promotion_screen.dart';
import '../shared/list_controls.dart';

class PromotionManagementScreen extends StatefulWidget {
  const PromotionManagementScreen({
    super.key,
    this.api,
    this.canManage = false,
    this.preview = false,
  });
  final PromotionApi? api;
  final bool canManage, preview;
  @override
  State<PromotionManagementScreen> createState() => _ManagementState();
}

class _ManagementState extends State<PromotionManagementScreen> {
  late final PromotionApi api = widget.api ?? HttpPromotionApi();
  late Future<List<Campaign>> feed = widget.preview
      ? Future.value([])
      : api.list();
  String query = '', filter = 'All';
  String kind = 'All types';
  bool busy = false;
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

  void message(String v) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v)));
    }
  }

  Future<void> edit([Campaign? campaign]) async {
    if (busy) return;
    setState(() => busy = true);
    final packages = HttpPackageApi();
    try {
      final rows = await packages.catalogue();
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CampaignEditor(api: api, campaign: campaign, packages: rows),
        ),
      );
      if (saved == true && mounted) {
        message('Campaign saved.');
        reload();
      }
    } catch (e) {
      message(promotionError(e));
    } finally {
      packages.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Campaign p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete campaign?'),
        content: const Text(
          'Hide it from new customers. Existing held and paid quotations are preserved; the code cannot be reused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep campaign'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete campaign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await api.remove(p);
      if (mounted) {
        message('Campaign deleted.');
        reload();
      }
    } catch (e) {
      message(promotionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Promotions & advertisements'),
      actions: [
        if (!widget.preview)
          IconButton(
            onPressed: reload,
            tooltip: 'Refresh campaigns',
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Thoughtful offers. Clear terms.',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              widget.preview
                  ? 'Sign in to manage real campaigns. No sample offers are published.'
                  : widget.canManage
                  ? 'Manage package discounts and schedule in-app campaigns.'
                  : 'View campaigns. Only managers can publish or change financial offers.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: ListSearchField(
                    value: query,
                    hint: 'Search title or promo code',
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
                ListFilterSelect(
                  label: 'Campaign type',
                  value: kind,
                  options: const ['All types', 'Offer', 'Announcement'],
                  onChanged: (v) => setState(() => kind = v),
                ),
                if (query.isNotEmpty || filter != 'All' || kind != 'All types')
                  ResetListFilters(
                    onReset: () => setState(() {
                      query = '';
                      filter = 'All';
                      kind = 'All types';
                    }),
                  ),
                if (widget.canManage && !widget.preview)
                  FilledButton.icon(
                    onPressed: busy ? null : () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create campaign'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in [
                  'All',
                  'Inactive',
                  'Scheduled',
                  'Active',
                  'Ended',
                ])
                  ChoiceChip(
                    label: Text(s),
                    selected: filter == s,
                    onSelected: (_) => setState(() => filter = s),
                  ),
              ],
            ),
            const SizedBox(height: 20),
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
                          (filter == 'All' || p.status == filter) &&
                          (kind == 'All types' || p.data['kind'] == kind) &&
                          matchesListSearch(query, [
                            p.title,
                            p.description,
                            p.code,
                          ]),
                    )
                    .toList();
                return Column(
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matching campaigns.'),
                      ),
                    for (final p in rows)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CampaignCard(campaign: p, showStatus: true),
                          if (widget.canManage && !widget.preview)
                            Wrap(
                              spacing: 10,
                              children: [
                                OutlinedButton(
                                  onPressed: busy ? null : () => edit(p),
                                  child: const Text('Edit campaign'),
                                ),
                                TextButton.icon(
                                  onPressed: busy ? null : () => remove(p),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class CampaignEditor extends StatefulWidget {
  const CampaignEditor({
    super.key,
    required this.api,
    this.campaign,
    required this.packages,
  });
  final PromotionApi api;
  final Campaign? campaign;
  final List<BridalPackage> packages;
  @override
  State<CampaignEditor> createState() => _EditorState();
}

class _EditorState extends State<CampaignEditor> {
  late final String campaignId = widget.campaign?.id ?? packageRequestId();
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      code = TextEditingController(),
      value = TextEditingController(),
      cap = TextEditingController(),
      minimum = TextEditingController();
  late String kind, discountType, packageId, start, end;
  bool active = false, banner = true, busy = false, newCustomerOnly = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final d = widget.campaign?.data;
    kind = d?['kind'] ?? 'Offer';
    discountType = d?['discountType'] ?? 'Fixed';
    packageId = d?['packageId'] ?? '';
    start = d?['startDate'] ?? todayInMalaysia();
    end =
        d?['endDate'] ??
        offerDay(DateTime.parse(start).add(const Duration(days: 30)));
    active = d?['active'] ?? false;
    banner = d?['banner'] ?? true;
    newCustomerOnly = widget.campaign?.newCustomerOnly ?? false;
    title.text = d?['title'] ?? '';
    description.text = d?['description'] ?? '';
    code.text = d?['code'] ?? '';
    value.text = d == null
        ? '50.00'
        : discountType == 'Fixed'
        ? (d['value'] / 100).toStringAsFixed(2)
        : '${d['value']}';
    cap.text = ((d?['maxDiscountCents'] ?? 0) / 100).toStringAsFixed(2);
    minimum.text = ((d?['minimumCents'] ?? 89900) / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final c in [title, description, code, value, cap, minimum]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> date(bool first) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(first ? start : end),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen != null && mounted) {
      setState(() => first ? start = offerDay(chosen) : end = offerDay(chosen));
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (start.compareTo(end) > 0) {
      setState(() => error = 'End date must be on or after the start date.');
      return;
    }
    if (active && end.compareTo(todayInMalaysia()) < 0) {
      setState(
        () => error = 'Choose a current or future end date before activating.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.save({
        'id': campaignId,
        'revision': widget.campaign?.revision ?? 0,
        'kind': kind,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'code': kind == 'Offer' ? code.text.trim().toUpperCase() : '',
        'discountType': kind == 'Offer' ? discountType : 'Fixed',
        'value': kind != 'Offer'
            ? 0
            : discountType == 'Fixed'
            ? promotionCents(value.text)
            : int.tryParse(value.text),
        'maxDiscountCents': kind == 'Offer' && discountType == 'Percent'
            ? promotionCents(cap.text)
            : 0,
        'minimumCents': kind == 'Offer' ? promotionCents(minimum.text) : 0,
        'packageId': packageId,
        'startDate': start,
        'endDate': end,
        'active': active,
        'banner': banner,
        if (kind == 'Offer' &&
            (newCustomerOnly || widget.campaign?.newCustomerOnly == true))
          'newCustomerOnly': newCustomerOnly,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = promotionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(TextEditingController c, String label, int min, int max) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: c,
          enabled: !busy,
          decoration: InputDecoration(labelText: label),
          maxLength: max,
          minLines: 1,
          maxLines: label == 'Description' ? 4 : 1,
          validator: (v) => v == null || v.trim().length < min
              ? 'Enter at least $min characters.'
              : null,
        ),
      );
  Widget money(
    TextEditingController c,
    String label, {
    bool positive = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      enabled: !busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final amount = promotionCents(v ?? '');
        return amount == null || amount > 100000000 || positive && amount < 100
            ? 'Enter a valid RM amount${positive ? ' of at least RM1' : ''}.'
            : null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.campaign == null ? 'Create campaign' : 'Edit campaign',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'A promotion discounts gown packages. An announcement is an informational advertisement, without a voucher.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Campaign type'),
                items: ['Offer', 'Announcement']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: widget.campaign != null || busy
                    ? null
                    : (v) => setState(() => kind = v!),
              ),
              const SizedBox(height: 16),
              field(title, 'Title', 3, 80),
              field(description, 'Description', 10, 500),
              DropdownButtonFormField<String>(
                initialValue: packageId,
                decoration: const InputDecoration(
                  labelText: 'Applicable / linked package',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All gown packages'),
                  ),
                  for (final p in widget.packages)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                  if (packageId.isNotEmpty &&
                      !widget.packages.any((p) => p.id == packageId))
                    DropdownMenuItem(
                      value: packageId,
                      child: const Text('Previously linked package'),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => packageId = v!),
              ),
              const SizedBox(height: 16),
              if (kind == 'Offer') ...[
                TextFormField(
                  controller: code,
                  enabled: !busy && widget.campaign == null,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Unique promo code',
                    helperText:
                        '4–20 letters / numbers. Cannot change or reuse a published code.',
                  ),
                  validator: (v) =>
                      !RegExp(
                        r'^[A-Z0-9]{4,20}$',
                      ).hasMatch((v ?? '').trim().toUpperCase())
                      ? 'Use 4–20 letters / numbers.'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: discountType,
                  decoration: const InputDecoration(labelText: 'Discount type'),
                  items: ['Fixed', 'Percent']
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'Fixed'
                                ? 'Fixed RM discount'
                                : 'Percentage discount',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          discountType = v!;
                          value.clear();
                        }),
                ),
                const SizedBox(height: 16),
                if (discountType == 'Fixed')
                  money(value, 'Discount (RM)', positive: true)
                else ...[
                  TextFormField(
                    controller: value,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Discount (%)',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 90
                          ? 'Enter a whole percentage from 1 to 90.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  money(cap, 'Maximum discount (RM)', positive: true),
                ],
                money(minimum, 'Minimum package spend (RM)'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('New customers only'),
                  subtitle: const Text(
                    'Available during the first 30 days after registration.',
                  ),
                  value: newCustomerOnly,
                  onChanged: busy
                      ? null
                      : (enabled) => setState(() {
                          newCustomerOnly = enabled;
                          if (enabled && widget.campaign == null) {
                            if (title.text.isEmpty) {
                              title.text = 'Welcome to Luvly';
                            }
                            if (code.text.isEmpty) code.text = 'WELCOME50';
                            if (description.text.isEmpty) {
                              description.text =
                                  'A welcome offer on eligible bridal packages. Apply the code in My packages before the deposit invoice.';
                            }
                          }
                        }),
                ),
                const Text(
                  'One use per customer. One code per package; no stacking. Fitting fees and refundable security are not discounted.',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 16),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starts (Malaysia date)'),
                subtitle: Text(start),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: busy ? null : () => date(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ends (inclusive, Malaysia date)'),
                subtitle: Text(end),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: busy ? null : () => date(false),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show as a home advertisement'),
                subtitle: const Text(
                  'Only displayed while the campaign is active and within its dates.',
                ),
                value: banner,
                onChanged: busy ? null : (v) => setState(() => banner = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activate campaign'),
                subtitle: const Text(
                  'Customers see the campaign during its scheduled dates once it is active.',
                ),
                value: active,
                onChanged: busy ? null : (v) => setState(() => active = v),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(
                  busy
                      ? 'Saving…'
                      : active
                      ? 'Save active campaign'
                      : 'Save inactive campaign',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
