import 'package:flutter/material.dart';

import '../admin/design.dart' show Pill, border, canvas, ink, muted, rose;
import '../catalogue/catalogue_repository.dart' show validateDressText;
import '../payments/payment_api.dart';
import 'accessory_catalogue.dart';
import 'package_api.dart';
import 'package_editor_section.dart';
import 'package_service_picker.dart';

const _maximumPrice = 100000000;
const _controlCharacters = r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]';

int? serviceCents(String text) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text.trim())) return null;
  final parts = text.trim().split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  return cents <= _maximumPrice ? cents : null;
}

class _ServiceDraft {
  _ServiceDraft([this.original, PackageServiceType? initialType])
    : id = original?.id ?? packageRequestId(),
      name = TextEditingController(
        text:
            original?.name ??
            (initialType == PackageServiceType.custom
                ? ''
                : initialType?.label) ??
            '',
      ),
      description = TextEditingController(text: original?.description ?? ''),
      price = TextEditingController(text: _amount(original?.priceCents ?? 0)),
      allowance = TextEditingController(
        text: _amount(original?.allowanceCents),
      ),
      kind =
          original?.kind ??
          ((initialType == PackageServiceType.makeupTrial ||
                  initialType == PackageServiceType.itemAccessories)
              ? 'Add-on'
              : 'Required'),
      type = original == null ? initialType : original.serviceType;

  final PackageServiceItem? original;
  final String id;
  final TextEditingController name, description, price, allowance;
  String kind;
  PackageServiceType? type;

  void changeType(PackageServiceType? next) {
    final previous = type;
    final currentName = name.text.trim();
    final usesCategoryName =
        previous != null &&
        previous != PackageServiceType.custom &&
        currentName == previous.label;
    type = next;
    if (itemPriced) kind = 'Add-on';
    if (currentName.isEmpty || usesCategoryName) {
      name.text = switch (next) {
        null => original?.name ?? '',
        PackageServiceType.custom => '',
        _ => next.label,
      };
    }
  }

  String? get nameError => name.text.trim().length < 2
      ? 'Enter the service name.'
      : _textError(name.text, 2, 100, 'service name');
  String? get descriptionError =>
      _textError(description.text, 0, 300, 'service description');
  String? get priceError =>
      !itemPriced && kind != 'Required' && serviceCents(price.text) == null
      ? 'Enter a valid amount with up to 2 decimals.'
      : null;
  bool get itemPriced => type == PackageServiceType.itemAccessories;
  bool get usesAllowance =>
      type?.isAccessory == true &&
      !itemPriced &&
      type != PackageServiceType.packageVeil;
  String? get allowanceError =>
      usesAllowance && serviceCents(allowance.text) == null
      ? 'Enter an allowance, or 0 if items are charged separately.'
      : null;
  bool get valid =>
      nameError == null &&
      descriptionError == null &&
      priceError == null &&
      allowanceError == null;

  PackageServiceItem toService() => PackageServiceItem(
    id: id,
    name: name.text.trim(),
    description: description.text.trim(),
    kind: kind,
    priceCents: kind == 'Required' || itemPriced
        ? 0
        : serviceCents(price.text) ?? 0,
    serviceType: type,
    standardVeilId: type == PackageServiceType.packageVeil
        ? original?.standardVeilId
        : null,
    accessoryAllowanceCents: usesAllowance
        ? serviceCents(allowance.text)
        : null,
  );

  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    allowance.dispose();
  }
}

String _amount(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);

String? _textError(String value, int min, int max, String label) {
  final text = value.trim();
  if (text.length < min || text.length > max) {
    return 'Enter a $label with ${min == 0 ? 'up to $max' : '$min–$max'} characters.';
  }
  if (RegExp(_controlCharacters).hasMatch(text)) {
    return 'Enter a readable $label.';
  }
  return null;
}

class PackageEditor extends StatefulWidget {
  const PackageEditor({super.key, required this.api, this.package});
  final PackageApi api;
  final BridalPackage? package;

  @override
  State<PackageEditor> createState() => _PackageEditorState();
}

class _PackageEditorState extends State<PackageEditor> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  final details = GlobalKey(),
      gowns = GlobalKey(),
      serviceSection = GlobalKey(),
      expandedService = GlobalKey();
  late final TextEditingController name, description, price;
  late final List<_ServiceDraft> services;
  late final String id;
  late int includedGownCount;
  int? gownLimit;
  bool loadingGownLimit = false;
  final removed = <String>{}, addons = <String>{};
  Future<AccessoryCatalogue>? accessoryCatalogue;
  String? editingServiceId;
  bool reviewing = false, busy = false;
  bool approvedPreview = false;
  String? error;

  bool get active => widget.package?.active ?? false;
  bool get preserveEligibility =>
      approvedPreview ||
      (widget.package?.services.any((s) => s.standardVeilId != null) ?? false);
  bool get canLoadApproved =>
      widget.api is HttpPackageApi &&
      const {
        'bridal-essentials',
        'signature-bridal',
        'luxe-bridal',
      }.contains(id);
  int? get base => quoteAmountCents(price.text);
  List<PackageServiceItem> get rows =>
      services.map((s) => s.toService()).toList();

  BridalPackage get preview => BridalPackage(
    id: id,
    name: name.text.trim(),
    description: description.text.trim(),
    basePriceCents: base ?? 0,
    revision: widget.package?.revision ?? 0,
    active: active,
    services: rows,
    includedGownCount: includedGownCount,
    allCatalogueGowns:
        !preserveEligibility || widget.package?.allCatalogueGowns == true,
    eligibleDressIds: preserveEligibility
        ? widget.package?.eligibleDressIds ?? const []
        : const [],
  );

  @override
  void initState() {
    super.initState();
    final p = widget.package;
    id = p?.id ?? packageRequestId();
    name = TextEditingController(text: p?.name ?? '');
    description = TextEditingController(text: p?.description ?? '');
    price = TextEditingController(text: _amount(p?.basePriceCents));
    services = p?.services.map(_ServiceDraft.new).toList() ?? [];
    includedGownCount = p?.includedGownCount ?? 0;
    loadGownLimit();
  }

  Future<void> loadApprovedPricing() async {
    if (busy) return;
    change(() => busy = true);
    try {
      final proposal = await (widget.api as HttpPackageApi).approvedPricing(id);
      if (!mounted) return;
      if (proposal.revision != widget.package?.revision) {
        setState(
          () => error = 'This package changed. Reopen its latest version.',
        );
        return;
      }
      change(() {
        approvedPreview = true;
        price.text = _amount(proposal.basePriceCents);
        description.text = proposal.description;
        final previous = services.toList();
        services
          ..clear()
          ..addAll(proposal.services.map(_ServiceDraft.new));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final service in previous) {
            service.dispose();
          }
        });
        removed.clear();
        addons.clear();
        editingServiceId = null;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not load approved pricing.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadGownLimit() async {
    setState(() => loadingGownLimit = true);
    try {
      final limit = await (widget.api as PackageGownLimitApi).gownLimit();
      if (mounted) setState(() => gownLimit = limit);
    } catch (_) {
      if (mounted) setState(() => gownLimit = null);
    } finally {
      if (mounted) setState(() => loadingGownLimit = false);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    name.dispose();
    description.dispose();
    price.dispose();
    for (final service in services) {
      service.dispose();
    }
    super.dispose();
  }

  void change(VoidCallback update) => setState(() {
    update();
    error = null;
  });

  bool validateContent() {
    final visibleValid = form.currentState?.validate() ?? true;
    final invalidService = services.where((s) => !s.valid).firstOrNull;
    if (!visibleValid ||
        validateDressText(name.text, 'package name', 3, 100) != null ||
        _textError(description.text, 10, 1500, 'description') != null ||
        base == null ||
        invalidService != null) {
      setState(() {
        error =
            'Check the package name, description, price and every service row.';
        if (invalidService != null) editingServiceId = invalidService.id;
      });
      if (invalidService != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            form.currentState?.validate();
            jumpTo(expandedService);
          }
        });
      }
      return false;
    }
    final p = preview;
    final optional = p.services.where((s) => s.kind == 'Optional');
    final extras = p.services.where((s) => s.kind == 'Add-on');
    final issue = !p.services.any((s) => s.kind == 'Required')
        ? 'Include at least one mandatory service.'
        : p.services.map((s) => s.name.toLowerCase()).toSet().length !=
              p.services.length
        ? 'Use a different name for each service.'
        : p.total(optional.map((s) => s.id).toSet(), {}) < 100
        ? 'Removing optional services must leave at least RM 1.00.'
        : p.total({}, extras.map((s) => s.id).toSet()) > _maximumPrice
        ? 'The total with all add-ons must be at most RM 1,000,000.00.'
        : null;
    setState(() => error = issue);
    return issue == null;
  }

  String? get quantityIssue {
    if (includedGownCount == 0) return null;
    final limit = gownLimit;
    if (limit == null || loadingGownLimit) {
      return 'Check the gown limit before saving this quantity.';
    }
    if (includedGownCount > limit) {
      return 'Choose $limit or fewer gowns. The current catalogue cannot cover this quantity.';
    }
    return null;
  }

  String? get publishIssue {
    if (quantityIssue case final issue?) return issue;
    if (includedGownCount == 0 &&
        services.any((s) => s.type?.needsGownRental == true)) {
      return 'Include a gown rental to use scheduled services, accessories or an extra rental day.';
    }
    if (includedGownCount > 0) {
      final p = preview;
      final optionalIds = p.services
          .where((s) => s.kind == 'Optional')
          .map((s) => s.id);
      if (p.total(optionalIds.toSet(), {}) < 200) {
        return 'A gown rental must cost at least RM 2.00 after deductions.';
      }
    }
    return null;
  }

  void showReview(bool value) {
    if (value && !validateContent()) return;
    change(() {
      reviewing = value;
      if (value) {
        removed.clear();
        addons.clear();
      }
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> save({required bool publish}) async {
    if (busy || !validateContent()) return;
    final issue = publish ? publishIssue : quantityIssue;
    if (issue != null) {
      setState(() => error = issue);
      return;
    }
    final p = preview;
    final usesItemPricing = p.services.any(
      (s) => s.itemPriced || s.packageVeil,
    );
    if (publish && usesItemPricing) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirm package pricing'),
          content: Text(
            [
              'Approved base price · ${packageMoney(p.basePriceCents)}',
              for (final veil in p.services.where((s) => s.packageVeil))
                switch (veil.kind) {
                  'Optional' =>
                    '${veil.name} · Deduct ${packageMoney(veil.priceCents)} if removed',
                  'Add-on' =>
                    '${veil.name} · Add ${packageMoney(veil.priceCents)} if selected',
                  _ => '${veil.name} · Included in the base price',
                },
              'Bridal Accessories are charged at the catalogue item prices.',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm and publish'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true || busy) return;
    }
    setState(() => busy = true);
    try {
      await widget.api.save(
        BridalPackage(
          id: p.id,
          name: p.name,
          description: p.description,
          basePriceCents: p.basePriceCents,
          revision: p.revision,
          active: publish,
          accessoryPricingApproved: publish && usesItemPricing,
          services: p.services,
          includedGownCount: p.includedGownCount,
          allCatalogueGowns: p.allCatalogueGowns,
          eligibleDressIds: p.eligibleDressIds,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is PaymentFailure
              ? e.message
              : 'Could not save this package. Please try again.';
        });
        if (p.includedGownCount > 0) await loadGownLimit();
      }
    }
  }

  Future<void> chooseService([_ServiceDraft? service]) async {
    FocusScope.of(context).unfocus();
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => PackageServicePicker(
        selected: service?.type,
        canKeepExisting:
            service?.original != null && service?.original?.serviceType == null,
      ),
    );
    if (!mounted || selected == null) return;
    final type = PackageServiceType.fromCode(selected);
    change(() {
      if (service != null) {
        service.changeType(type);
      } else if (type != null && services.length < 12) {
        final added = _ServiceDraft(null, type);
        services.add(added);
        editingServiceId = added.id;
      }
    });
    if (service == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) jumpTo(expandedService);
      });
    }
  }

  void jumpTo(GlobalKey key) {
    if (key.currentContext case final context?) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 240),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: Text(
          widget.package == null
              ? 'Create service package'
              : 'Edit service package',
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          return Scrollbar(
            controller: scroll,
            child: SingleChildScrollView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(
                wide ? 36 : 16,
                24,
                wide ? 36 : 16,
                28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header(context),
                      const SizedBox(height: 20),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: reviewing
                                  ? customerPreview(context)
                                  : editor(),
                            ),
                            const SizedBox(width: 24),
                            SizedBox(width: 330, child: summary()),
                          ],
                        )
                      else ...[
                        if (reviewing) customerPreview(context) else editor(),
                        const SizedBox(height: 16),
                        summary(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: footer(),
    ),
  );

  Widget header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            reviewing ? 'Review your package' : 'Build your package',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (widget.package case final package?) Pill(package.statusLabel),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        reviewing
            ? 'Try the same service choices customers will see before you publish.'
            : 'Set the price, number of gowns and included services.',
        style: const TextStyle(color: muted),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Package setup'),
            selected: !reviewing,
            onSelected: busy || !reviewing ? null : (_) => showReview(false),
          ),
          ChoiceChip(
            label: const Text('Customer preview'),
            selected: reviewing,
            onSelected: busy || reviewing ? null : (_) => showReview(true),
          ),
        ],
      ),
    ],
  );

  Widget editor() => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PackageEditorSection(
          key: details,
          title: 'Package details',
          icon: Icons.description_outlined,
          subtitle: 'The name, description and standard price customers see.',
          children: [
            if (canLoadApproved)
              OutlinedButton(
                onPressed: busy ? null : loadApprovedPricing,
                child: Text(
                  approvedPreview
                      ? 'Reload approved pricing'
                      : 'Load approved pricing',
                ),
              ),
            _FieldPair(
              first: TextFormField(
                controller: name,
                enabled: !busy,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Package name',
                  counterText: '',
                ),
                validator: (v) =>
                    validateDressText(v ?? '', 'package name', 3, 100),
                onChanged: (_) => change(() {}),
              ),
              second: TextFormField(
                controller: price,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Standard price',
                  prefixText: 'RM ',
                ),
                validator: (_) => base == null
                    ? 'Enter RM 1.00–1,000,000.00 with up to 2 decimals.'
                    : null,
                onChanged: (_) => change(() {}),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: description,
              enabled: !busy,
              maxLines: 3,
              maxLength: 1500,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe the package and who it suits',
                alignLabelWithHint: true,
                counterText: '',
              ),
              validator: (_) =>
                  _textError(description.text, 10, 1500, 'description'),
              onChanged: (_) => change(() {}),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PackageEditorSection(
          key: gowns,
          title: 'Gown rentals',
          icon: Icons.checkroom_outlined,
          subtitle: 'How many gowns can a customer rent with this package?',
          children: [gownQuantity()],
        ),
        const SizedBox(height: 16),
        PackageEditorSection(
          key: serviceSection,
          title: 'Services & add-ons',
          icon: Icons.list_alt_outlined,
          subtitle:
              'Included services are covered by the base price. Optional services can be removed for a deduction. Add-ons increase the total.',
          children: [
            if (services.length < 12)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : () => chooseService(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add service'),
                ),
              ),
            if (services.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Add at least one service that is always included.',
                style: TextStyle(color: muted),
              ),
            ] else ...[
              const SizedBox(height: 12),
              for (final service in services) serviceRow(service),
            ],
          ],
        ),
      ],
    ),
  );

  Widget gownQuantity() {
    final limit = gownLimit;
    final label = includedGownCount == 0
        ? 'No gowns'
        : '$includedGownCount gown${includedGownCount == 1 ? '' : 's'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.outlined(
              tooltip: 'Fewer gowns',
              onPressed: busy || includedGownCount == 0
                  ? null
                  : () => change(() => includedGownCount--),
              icon: const Icon(Icons.remove, size: 18),
            ),
            Semantics(
              liveRegion: true,
              child: SizedBox(
                width: 96,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'More gowns',
              onPressed:
                  busy ||
                      loadingGownLimit ||
                      limit == null ||
                      includedGownCount >= limit
                  ? null
                  : () => change(() => includedGownCount++),
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (loadingGownLimit)
          const Text(
            'Checking rental catalogue…',
            style: TextStyle(color: muted),
          )
        else if (limit == null)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Could not check the gown limit.',
                style: TextStyle(color: rose),
              ),
              TextButton(
                onPressed: busy ? null : loadGownLimit,
                child: const Text('Retry'),
              ),
            ],
          )
        else
          Text(
            quantityIssue ??
                (limit == 0
                    ? 'No gown styles with configured stock are available.'
                    : 'Up to $limit ${limit == 1 ? 'gown' : 'gowns'} from the rental catalogue.'),
            style: TextStyle(color: quantityIssue == null ? muted : rose),
          ),
      ],
    );
  }

  Widget serviceRow(_ServiceDraft service) {
    final p = service.toService();
    final type = service.type;
    final expanded = service.id == editingServiceId;
    final pricing = p.itemPriced
        ? 'Pay for selected items'
        : switch (p.kind) {
            'Required' => 'Always included',
            'Optional' => 'Deduct ${packageMoney(p.priceCents)} if removed',
            _ => '+ ${packageMoney(p.priceCents)} add-on',
          };
    final behaviour = [
      pricing,
      if (p.requiresTeamScheduling) 'Confirm timing',
      if (p.addsRentalDay) '+1 rental day',
      if (p.isAccessory &&
          service.usesAllowance &&
          service.allowanceError == null)
        '${packageMoney(p.allowanceCents)} allowance',
    ].join(' · ');
    return Container(
      key: ValueKey(service.id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: canvas,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: expanded ? expandedService : null,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 10),
                child: Icon(serviceCategoryIcon(type), color: rose, size: 19),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name.isEmpty ? (type?.label ?? 'Service') : p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(behaviour, style: const TextStyle(color: muted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: expanded ? 'Collapse service' : 'Edit service',
                onPressed: busy
                    ? null
                    : () => change(
                        () => editingServiceId = expanded ? null : service.id,
                      ),
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.edit_outlined,
                  size: 19,
                ),
              ),
              if (expanded)
                IconButton(
                  tooltip: 'Remove service row',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: busy
                      ? null
                      : () {
                          change(() {
                            services.remove(service);
                            editingServiceId = null;
                          });
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => service.dispose(),
                          );
                        },
                ),
            ],
          ),
          if (expanded) ...[
            const Divider(height: 20, color: border),
            const SizedBox(height: 10),
            _FieldPair(
              first: OutlinedButton.icon(
                onPressed: busy ? null : () => chooseService(service),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Change category'),
              ),
              second: service.itemPriced
                  ? const Text('Optional · catalogue item prices')
                  : DropdownButtonFormField<String>(
                      initialValue: service.kind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'How it’s priced',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Required',
                          child: Text('Always included'),
                        ),
                        DropdownMenuItem(
                          value: 'Optional',
                          child: Text('Included, removable'),
                        ),
                        DropdownMenuItem(
                          value: 'Add-on',
                          child: Text('Paid add-on'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (kind) => change(() => service.kind = kind!),
                    ),
            ),
            if (type != null) ...[
              const SizedBox(height: 10),
              Text(
                '${type.label} · ${serviceCategoryDescription(type)}',
                style: const TextStyle(color: muted),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: service.name,
              enabled: !busy,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Service name',
                counterText: '',
              ),
              validator: (_) => service.nameError,
              onChanged: (_) => change(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: service.description,
              enabled: !busy,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Service description (optional)',
                counterText: '',
              ),
              validator: (_) => service.descriptionError,
              onChanged: (_) => change(() {}),
            ),
            if (!service.itemPriced &&
                (service.kind != 'Required' || service.usesAllowance)) ...[
              const SizedBox(height: 12),
              if (service.kind == 'Required')
                allowanceField(service)
              else
                _FieldPair(
                  first: TextFormField(
                    controller: service.price,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: service.kind == 'Add-on'
                          ? 'Add-on price'
                          : 'Deduction if removed',
                      prefixText: 'RM ',
                    ),
                    validator: (_) => service.priceError,
                    onChanged: (_) => change(() {}),
                  ),
                  second: service.usesAllowance
                      ? allowanceField(service)
                      : null,
                ),
            ],
            if (p.isAccessory) ...[
              const SizedBox(height: 12),
              accessoryCatalogueLink(p),
            ],
          ],
        ],
      ),
    );
  }

  Widget allowanceField(_ServiceDraft service) => TextFormField(
    controller: service.allowance,
    enabled: !busy,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(
      labelText: 'Accessory allowance',
      prefixText: 'RM ',
    ),
    validator: (_) => service.allowanceError,
    onChanged: (_) => change(() {}),
  );

  Widget accessoryCatalogueLink(PackageServiceItem service) {
    final label = switch ((service.includesVeils, service.includesJewellery)) {
      (true, true) => 'View veils & jewellery',
      (true, false) => 'View veils',
      _ => 'View jewellery',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: busy
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) => _AccessoryCatalogueDialog(
                  service: service,
                  catalogue: accessoryCatalogue ??= AccessoryCatalogue.load(),
                  onRetry: () => accessoryCatalogue = AccessoryCatalogue.load(),
                ),
              ),
        icon: const Icon(Icons.diamond_outlined, size: 18),
        label: Text(label),
      ),
    );
  }

  Widget customerPreview(BuildContext context) {
    final p = preview;
    return PackageEditorSection(
      title: p.name,
      subtitle: p.description,
      icon: Icons.visibility_outlined,
      children: [
        if (p.includedGownCount > 0) ...[
          Text(
            '${p.includedGownCount} gown${p.includedGownCount == 1 ? '' : 's'} included',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
        ],
        for (final service in p.services) ...[
          const Divider(height: 1, color: border),
          if (service.kind == 'Required')
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(service.name),
              subtitle: Text(servicePreviewDetails(service)),
            )
          else
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(service.name),
              subtitle: Text(servicePreviewDetails(service)),
              value: service.kind == 'Add-on'
                  ? addons.contains(service.id)
                  : !removed.contains(service.id),
              onChanged: busy
                  ? null
                  : (selected) => change(() {
                      if (service.kind == 'Add-on') {
                        selected!
                            ? addons.add(service.id)
                            : addons.remove(service.id);
                      } else {
                        selected!
                            ? removed.remove(service.id)
                            : removed.add(service.id);
                      }
                    }),
            ),
          if (service.isAccessory &&
              (service.kind == 'Add-on'
                  ? addons.contains(service.id)
                  : !removed.contains(service.id))) ...[
            accessoryCatalogueLink(service),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  String servicePreviewDetails(PackageServiceItem service) => [
    switch (service.kind) {
      'Required' => 'Included',
      'Optional' => 'Remove to deduct ${packageMoney(service.priceCents)}',
      _ => '+ ${packageMoney(service.priceCents)}',
    },
    if (service.isAccessory)
      if (service.usesAccessoryAllowance)
        '${packageMoney(service.allowanceCents)} accessory allowance',
    if (service.customerDescription.isNotEmpty) service.customerDescription,
  ].join(' · ');

  Widget summary() {
    final p = preview;
    final issue = reviewing ? publishIssue : null;
    final total = p.total(removed, addons);
    return PackageEditorSection(
      title: reviewing ? 'Price preview' : 'Package summary',
      icon: Icons.receipt_long_outlined,
      children: [
        summaryLine(
          'Standard price',
          base == null ? '—' : packageMoney(p.basePriceCents),
        ),
        if (reviewing) ...[
          for (final s in p.services)
            if (removed.contains(s.id))
              summaryLine('Remove ${s.name}', '− ${packageMoney(s.priceCents)}')
            else if (addons.contains(s.id))
              summaryLine(s.name, '+ ${packageMoney(s.priceCents)}'),
          const Divider(height: 20, color: border),
          summaryLine('Package total', packageMoney(total), prominent: true),
          if (p.includedGownCount > 0)
            summaryLine(
              'Separate refundable security',
              packageMoney(p.includedGownCount * packageGownSecurityCents),
            ),
          const SizedBox(height: 8),
          const Text(
            'Before promotions, alterations and selected accessory charges.',
            style: TextStyle(color: muted),
          ),
          if (issue != null) ...[
            const SizedBox(height: 12),
            Text(issue, style: const TextStyle(color: rose)),
          ],
        ] else ...[
          summaryLine('Gowns included', '$includedGownCount'),
          summaryLine('Services', '${p.services.length}'),
          const Divider(height: 20, color: border),
          Text(
            active
                ? 'This package is visible to customers.'
                : 'Only the team can see this package until it’s published.',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => jumpTo(details),
                child: const Text('Details'),
              ),
              TextButton(
                onPressed: () => jumpTo(gowns),
                child: const Text('Gowns'),
              ),
              TextButton(
                onPressed: () => jumpTo(serviceSection),
                child: const Text('Services'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget summaryLine(String label, String amount, {bool prominent = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: prominent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                amount,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: prominent ? rose : ink,
                  fontWeight: FontWeight.w600,
                  fontSize: prominent ? 18 : null,
                ),
              ),
            ),
          ],
        ),
      );

  Widget footer() => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: border)),
    ),
    child: SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(message, style: const TextStyle(color: rose)),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (reviewing)
                      TextButton(
                        onPressed: busy ? null : () => showReview(false),
                        child: const Text('Back to setup'),
                      ),
                    if (!active)
                      OutlinedButton(
                        onPressed: busy || (approvedPreview && active)
                            ? null
                            : () => save(publish: false),
                        child: const Text('Save unpublished'),
                      ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : reviewing
                          ? () => save(publish: true)
                          : () => showReview(true),
                      child: Text(
                        busy
                            ? 'Saving…'
                            : !reviewing
                            ? 'Review package'
                            : active
                            ? 'Save changes'
                            : 'Publish package',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AccessoryCatalogueDialog extends StatefulWidget {
  const _AccessoryCatalogueDialog({
    required this.service,
    required this.catalogue,
    required this.onRetry,
  });

  final PackageServiceItem service;
  final Future<AccessoryCatalogue> catalogue;
  final Future<AccessoryCatalogue> Function() onRetry;

  @override
  State<_AccessoryCatalogueDialog> createState() =>
      _AccessoryCatalogueDialogState();
}

class _AccessoryCatalogueDialogState extends State<_AccessoryCatalogueDialog> {
  late Future<AccessoryCatalogue> catalogue = widget.catalogue;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Customer accessory choices'),
    scrollable: true,
    content: SizedBox(
      width: 520,
      child: FutureBuilder<AccessoryCatalogue>(
        future: catalogue,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Could not load the accessory catalogue.'),
                TextButton(
                  onPressed: () => setState(() => catalogue = widget.onRetry()),
                  child: const Text('Retry'),
                ),
              ],
            );
          }
          final items = snapshot.data!.choices(widget.service);
          if (items.isEmpty) {
            return const Text('There are no items in this category.');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${items.length} styles${widget.service.usesAccessoryAllowance ? ' · ${packageMoney(widget.service.allowanceCents)} allowance' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Stock is checked for the selected rental dates.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 10),
              for (final item in items) ...[
                const Divider(height: 1, color: border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      item.image,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.category} · ${snapshot.data!.stylePrice(widget.service, item)}',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class _FieldPair extends StatelessWidget {
  const _FieldPair({required this.first, this.second});
  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) {
    final other = second;
    if (other == null) return first;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 470) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), other],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: other),
          ],
        );
      },
    );
  }
}
