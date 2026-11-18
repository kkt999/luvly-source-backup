import 'package:flutter/material.dart';
import '../admin/design.dart' show Pill, border, canvas, muted, rose;
import 'package_editor_section.dart';
import '../payments/payment_api.dart';
import 'package_api.dart';

part 'manager_service_views.dart';

typedef PricingRow = Map<String, dynamic>;

int? minorUnits(String amount) {
  final value = amount.trim();
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final cents =
      int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
  return cents <= 100000000 ? cents : null;
}

class ServicePricingEditor extends StatefulWidget {
  const ServicePricingEditor({
    super.key,
    required this.api,
    this.package,
    required this.onPreview,
  });
  final HttpPackageApi api;
  final BridalPackage? package;
  final ValueChanged<BridalPackage> onPreview;

  @override
  State<ServicePricingEditor> createState() => _ServicePricingEditorState();
}

class _ServicePricingEditorState extends State<ServicePricingEditor> {
  late final String id = widget.package?.id ?? packageRequestId();
  final name = TextEditingController(),
      description = TextEditingController(),
      discount = TextEditingController(text: '0');
  late Future<void> loading = load();
  List<PricingRow> services = [],
      catalogue = [],
      components = [],
      gownPrices = [];
  static const standardAllowanceId = 'standard-gown-allowance';
  int gownLimit = 0;
  PricingRow? published, review;
  bool active = true, busy = false, matchApproved = false, allGowns = true;
  bool dirty = false;
  List<String> eligible = [];
  int draftRevision = 0, count = 0;
  String discountKind = 'fixed';
  String? error;

  static const types = {
    'Required': 'Mandatory included',
    'Optional': 'Removable included',
    'Add-on': 'Paid add-on',
  };
  static const approvedIds = {
    'bridal-essentials',
    'signature-bridal',
    'luxe-bridal',
  };

  Future<PricingRow> request(String path, [PricingRow? body]) async =>
      Map<String, dynamic>.from(
        await widget.api.transport.businessRequest(path, body: body),
      );
  String get path => '/v1/packages/$id';

  Future<void> loadPrices() async {
    final result = await request('/v1/bridal-service-prices');
    catalogue = (result['services'] as List).cast<PricingRow>();
  }

  Future<void> load() async {
    final results = await Future.wait([
      request('$path/draft'),
      widget.api.gownLimit(),
      loadPrices().catchError((Object _) {}),
    ]);
    if (!mounted) return;
    final state = results[0] as PricingRow;
    gownLimit = results[1] as int;
    published = state['published'];
    final draft = state['draft'];
    draftRevision = draft?['revision'] ?? 0;
    final config = (draft?['configuration'] ?? published) as PricingRow?;
    setState(() => loaded = true);
    if (config == null) return;
    name.text = config['name'] ?? '';
    description.text = config['description'] ?? '';
    active = config['active'] == true;
    count = config['includedGownCount'] ?? 0;
    eligible = List<String>.from(config['eligibleDressIds'] ?? []);
    allGowns = config['allCatalogueGowns'] == true || eligible.isEmpty;
    setServices(config['services']);
    final pricing = config['pricing'];
    if (pricing == null) return;
    components = (pricing['components'] as List)
        .cast<PricingRow>()
        .map((r) => {...r})
        .toList();
    gownPrices = (pricing['gownPrices'] as List? ?? [])
        .cast<PricingRow>()
        .map((r) => {...r})
        .toList();
    if (gownPrices.length != count ||
        gownPrices.any(
          (row) => row['dressId'] == null || row['revision'] == null,
        )) {
      gownPrices = [];
    }
    final savedDiscount =
        pricing['bundleDiscount'] ?? {'kind': 'fixed', 'value': 0};
    discountKind = savedDiscount['kind'];
    discount.text = ((savedDiscount['value'] as int? ?? 0) / 100)
        .toStringAsFixed(2);
    matchApproved = pricing['matchApprovedPrice'] == true;
  }

  void setServices(Object? rows) {
    services = (rows as List? ?? [])
        .cast<PricingRow>()
        .map((r) => {...r})
        .toList();
  }

  int get publishedRevision => published?['revision'] ?? 0;
  int? get discountValue => minorUnits(discount.text);
  PricingRow get configuration => {
    'id': id,
    'name': name.text.trim(),
    'description': description.text.trim(),
    'active': active,
    'includedGownCount': count,
    'eligibleDressIds': allGowns || count == 0 ? <String>[] : eligible,
    if (allGowns && count > 0) 'allCatalogueGowns': true,
    'services': services,
    'pricing': {
      'components': components,
      'gownPrices': gownPrices,
      if (count > 0 && gownPrices.isEmpty) 'useStandardGownAllowance': true,
      'bundleDiscount': {'kind': discountKind, 'value': discountValue},
      if (matchApproved) 'matchApprovedPrice': true,
    },
  };
  PricingRow get version => {
    'draftRevision': draftRevision,
    'publishedRevision': publishedRevision,
  };

  void change(VoidCallback update) => setState(() {
    update();
    dirty = true;
    review = null;
    error = null;
  });

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save or calculate this package.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveDraft() async {
    final saved = await request('$path/draft', {
      ...version,
      'configuration': configuration,
    });
    if (mounted) {
      setState(() {
        draftRevision = saved['revision'];
        dirty = false;
      });
    }
  }

  Future<void> calculate() async {
    await saveDraft();
    if (!mounted) return;
    final result = await request('$path/preview', {
      ...version,
      'configuration': configuration,
    });
    if (mounted) setState(() => review = result);
  }

  Future<void> publish() async {
    final reviewed = review;
    if (reviewed == null || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Publish this package version?'),
        content: Text(
          'Selling price · ${packageMoney(reviewed['configuration']['basePriceCents'])}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm and publish'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await run(() async {
      await request('$path/publish', {
        ...version,
        'confirmed': true,
        'reviewedSnapshot': reviewed['reviewId'],
      });
      if (mounted) Navigator.pop(context, true);
    });
  }

  Set<Object?> usedIds({PricingRow? except}) => {
    for (final row in services)
      if (!identical(row, except)) row['id'],
    for (final row in components)
      if (row['serviceId'] != except?['id']) row['catalogueId'],
  };

  static const packageOptions = <String, PricingRow>{
    'veil-rental': {
      'id': 'veil-rental',
      'name': 'Veil Rental',
      'description': 'Standard veil included.',
      'serviceType': 'package-veil',
      'kind': 'Optional',
      'standardVeilId': 'veil-short',
      'priceCents': 8000,
    },
    'accessory-rental': {
      'id': 'accessory-rental',
      'name': 'Bridal Accessories',
      'description': 'Catalogue item pricing.',
      'serviceType': 'item-priced-accessories',
      'kind': 'Add-on',
      'priceCents': 0,
    },
  };

  Set<Object?> usedPackageServices({PricingRow? except}) {
    final ids = usedIds(except: except);
    for (final service in services.where((row) => !identical(row, except))) {
      final item = PackageServiceItem.fromJson({
        ...service,
        'priceCents': service['priceCents'] ?? 0,
      });
      if (item.includesVeils) ids.add('veil-rental');
      if (item.includesJewellery) ids.add('accessory-rental');
    }
    return ids;
  }

  Future<List<PricingRow>?> pickPrices({PricingRow? replace}) {
    final used = usedPackageServices(except: replace);
    return showDialog<List<PricingRow>>(
      context: context,
      builder: (_) => _ServicePricePicker(
        load: () async {
          await loadPrices();
          return [
            ...catalogue.where(
              (row) =>
                  row['id'] != standardAllowanceId &&
                  !packageOptions.containsKey(row['id']) &&
                  (replace?['serviceType'] == null ||
                      row['serviceType'] == replace?['serviceType']),
            ),
            if (replace == null)
              for (final option in packageOptions.values)
                {...option, 'active': true},
          ];
        },
        used: used,
        availableSlots: replace == null ? 12 - services.length : 1,
        linking: replace != null,
      ),
    );
  }

  Future<PricingRow?> editPrice(PricingRow selected) async {
    final result = await showDialog<PricingRow>(
      context: context,
      builder: (_) => _ServicePriceForm(
        initial: selected,
        request: request,
        existing: catalogue,
      ),
    );
    if (mounted && result != null) {
      setState(() {
        review = null;
        catalogue = [
          ...catalogue.where((row) => row['id'] != result['id']),
          result,
        ];
      });
    }
    return result;
  }

  void link(PricingRow service, PricingRow price) {
    components.removeWhere((row) => row['serviceId'] == service['id']);
    components.add({
      'serviceId': service['id'],
      'catalogueId': price['id'],
      'revision': price['revision'],
      'quantity': 1,
    });
    service.addAll({
      'serviceType': price['serviceType'],
      'name': price['name'],
      'description': price['description'],
    });
  }

  Future<void> addService() async {
    var selected = await pickPrices();
    if (!mounted || selected == null) return;
    if (selected.isEmpty) {
      final created = await editPrice({});
      if (!mounted || created == null || created['active'] != true) return;
      selected = [created];
    }
    final used = usedPackageServices();
    final names = services.map((row) => serviceNameKey(row)).toSet();
    if (services.length + selected.length > 12 ||
        !selected.every(
          (row) =>
              row['active'] == true &&
              used.add(row['id']) &&
              names.add(serviceNameKey(row)),
        )) {
      setState(
        () => error =
            'The group contains an unavailable or duplicate service, or exceeds the 12-service limit.',
      );
      return;
    }
    final additions = selected;
    change(() {
      for (final price in additions) {
        final option = packageOptions[price['id']];
        if (option != null) {
          services.add({...option});
          continue;
        }
        final row = <String, dynamic>{
          'id': price['id'],
          'kind': 'Required',
          'priceCents': 0,
        };
        link(row, price);
        services.add(row);
      }
    });
  }

  Future<void> managePrices() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ServiceCataloguePage(
          load: () async {
            await loadPrices();
            return catalogue;
          },
          editPrice: editPrice,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> loadApproved() async {
    final approved = await widget.api.approvedPricing(id);
    if (!mounted) return;
    change(() {
      matchApproved = true;
      description.text = approved.description;
      final byId = {for (final row in services) row['id']: row};
      final next = approved.services.map((service) {
        return service.isAccessory
            ? service.toJson()
            : byId[service.id] ?? service.toJson();
      }).toList();
      services = next;
      components.removeWhere(
        (row) => !next.any(
          (service) =>
              service['id'] == row['serviceId'] &&
              ![
                'package-veil',
                'item-priced-accessories',
              ].contains(service['serviceType']),
        ),
      );
    });
  }

  Future<void> history() async {
    final versions = List<int>.from(
      published?['versionRevisions'] ??
          (publishedRevision == 0 ? [] : [publishedRevision]),
    );
    if (versions.isEmpty) return;
    final revision = await showDialog<int>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Published versions'),
        children: [
          for (final version in versions.reversed)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, version),
              child: Text('Version $version'),
            ),
        ],
      ),
    );
    if (revision == null || !mounted) return;
    await run(() async {
      final row = revision == publishedRevision
          ? published!
          : await request('$path/versions/$revision');
      if (!mounted) return;
      final date = row['publishedAt'] ?? row['updatedAt'];
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Version $revision · ${row['name']}'),
          content: SingleChildScrollView(
            child: Text(
              [
                packageMoney(row['basePriceCents']),
                if (date is int)
                  'Date · ${DateTime.fromMillisecondsSinceEpoch(date).toLocal()}',
                if (row['publishedBy'] != null)
                  'Manager · ${row['publishedBy']}',
                for (final service in row['services'] as List)
                  '${service['name']} · ${service['kind']}',
              ].join('\n'),
            ),
          ),
        ),
      );
    });
  }

  Widget section(String title, List<Widget> children) {
    final (icon, subtitle) = switch (title) {
      'Package details' => (
        Icons.description_outlined,
        'Set the name, description and availability customers will see.',
      ),
      'Gown rentals' => (Icons.checkroom_outlined, null as String?),
      'Services & add-ons' => (
        Icons.list_alt_outlined,
        'Choose which services are included and which customers can add.',
      ),
      'Bundle discount' => (
        Icons.sell_outlined,
        'Apply a fixed amount or percentage to the included items and services.',
      ),
      _ => (Icons.receipt_long_outlined, null),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PackageEditorSection(
        title: title,
        icon: icon,
        subtitle: subtitle,
        children: children,
      ),
    );
  }

  Widget amountRow(String title, String value, {bool total = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: total ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: total ? rose : null,
          ),
        ),
      ],
    ),
  );
  Future<void> editConfiguration(
    PricingRow service,
    PricingRow? component,
    PricingRow? entry,
  ) async {
    final result = await showDialog<_ServiceConfiguration>(
      context: context,
      builder: (_) => _ServiceConfigurationDialog(
        service: service,
        entry: entry,
        choose: () => pickPrices(replace: service),
      ),
    );
    if (!mounted || result == null) return;
    final price = result.price;
    if (price != null &&
        services.any(
          (other) =>
              !identical(other, service) &&
              serviceNameKey(other) == serviceNameKey(price),
        )) {
      setState(
        () => error = 'This package already contains a service with that name.',
      );
      return;
    }
    change(() {
      if (price != null) {
        link(service, price);
        if (entry?['method'] == 'per-session' &&
            price['method'] == 'per-session') {
          components.last['quantity'] = component?['quantity'] ?? 1;
        }
      }
      if (result.deduction != null) service['priceCents'] = result.deduction;
    });
  }

  List<Widget> serviceCells(PricingRow service) {
    final component = components
        .where((row) => row['serviceId'] == service['id'])
        .firstOrNull;
    final entry = catalogue
        .where((row) => row['id'] == component?['catalogueId'])
        .firstOrNull;
    final veil = service['serviceType'] == 'package-veil';
    final accessory = service['serviceType'] == 'item-priced-accessories';
    final itemService = PackageServiceItem.fromJson({
      ...service,
      'priceCents': service['priceCents'] ?? 0,
    }).isAccessory;
    final fixedRole = veil || accessory || itemService;
    final validPrice =
        entry?['active'] == true &&
        entry?['revision'] == component?['revision'];
    final role = service['kind'] as String;
    return [
      Text(
        service['name'],
        key: ValueKey(service['id']),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      if (fixedRole)
        Text(accessory ? 'Optional catalogue-based' : types[role] ?? role)
      else
        DropdownButtonFormField<String>(
          key: ValueKey("${service['id']}-$role"),
          initialValue: role,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          ),
          items: [
            for (final pair in types.entries)
              DropdownMenuItem(
                value: pair.key,
                child: Text(pair.value, maxLines: 2),
              ),
          ],
          onChanged: busy
              ? null
              : (kind) => change(() {
                  service['kind'] = kind;
                  if (kind == 'Required') service['priceCents'] = 0;
                }),
        ),
      if (!fixedRole && entry?['method'] == 'per-session')
        DropdownButtonFormField<int>(
          initialValue: component!['quantity'],
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          ),
          items: [
            for (var n = 1; n <= 12; n++)
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: busy
              ? null
              : (n) => change(() => component['quantity'] = n),
        )
      else
        const Text('—'),
      Text(
        veil
            ? 'Included · Remove to save ${packageMoney(service['priceCents'])}'
            : accessory
            ? 'Catalogue-based · Variable'
            : validPrice
            ? '${packageMoney(entry!['priceCents'])} / ${priceUnit(entry)}'
            : 'Price configuration required',
      ),
      Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Edit configuration',
            visualDensity: VisualDensity.compact,
            onPressed: busy || fixedRole
                ? null
                : () => editConfiguration(service, component, entry),
            icon: const Icon(Icons.tune, size: 18),
          ),
          IconButton(
            tooltip: veil && approvedIds.contains(id)
                ? 'Standard veil required for this package'
                : 'Remove service',
            onPressed: busy || veil && approvedIds.contains(id)
                ? null
                : () => change(() {
                    services.remove(service);
                    components.removeWhere(
                      (row) => row['serviceId'] == service['id'],
                    );
                  }),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    ];
  }

  Widget serviceSummary(String title, Iterable<PricingRow> rows) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (rows.isEmpty)
          const Text('None selected', style: TextStyle(color: muted))
        else
          for (final row in rows)
            Text(
              row['kind'] == 'Optional'
                  ? "${row['name']} · Included, removable"
                  : row['name'],
              style: const TextStyle(color: muted),
            ),
      ],
    ),
  );
  Widget summary() {
    final snapshot = review?['pricingSnapshot'];
    final proposed = review?['configuration'];
    final old = {
      for (final s in published?['services'] as List? ?? []) s['id']: s,
    };
    return section('Package summary', [
      Text(
        name.text.isEmpty ? 'Unnamed package' : name.text.trim(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Pill(
            published == null ? 'Unpublished' : 'Published v$publishedRevision',
          ),
          if (draftRevision > 0) const Pill('Unpublished changes'),
        ],
      ),
      const SizedBox(height: 8),
      amountRow('Included gowns', '$count'),
      Text(
        active ? 'Active on publication' : 'Inactive on publication',
        style: const TextStyle(color: muted),
      ),
      for (final (title, required) in [
        ('Included services', true),
        ('Optional services', false),
      ])
        serviceSummary(
          title,
          services.where((row) => (row['kind'] == 'Required') == required),
        ),
      const Divider(height: 28),
      amountRow(
        'Services and gowns',
        snapshot == null ? '—' : packageMoney(snapshot['subtotalCents']),
      ),
      amountRow(
        'Bundle discount',
        snapshot == null ? '—' : packageMoney(snapshot['discountCents']),
      ),
      amountRow(
        'Selling price',
        snapshot == null ? '—' : packageMoney(snapshot['sellingPriceCents']),
        total: true,
      ),
      const SizedBox(height: 12),
      if (busy)
        const LinearProgressIndicator()
      else if (snapshot == null && error == null)
        const Text(
          'Review the package to validate its configuration and calculate pricing.',
          style: TextStyle(color: muted),
        )
      else if (snapshot != null)
        const Text(
          'Pricing verified',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      if (snapshot != null) ...[
        const Divider(),
        const Text('Review changes'),
        if (published != null) ...[
          Text(
            '${packageMoney(published!['basePriceCents'])} → ${packageMoney(proposed['basePriceCents'])}',
          ),
          Text('Gowns · ${published!['includedGownCount'] ?? 0} → $count'),
          Text(
            'Bundle discount · ${packageMoney(published!['pricingSnapshot']?['discountCents'] ?? 0)} → ${packageMoney(snapshot['discountCents'])}',
          ),
          for (final service in proposed['services'] as List)
            if (old[service['id']] == null)
              Text('Added · ${service['name']}')
            else if ([
              'kind',
              'serviceType',
              'priceCents',
              'standardVeilId',
            ].any((k) => old[service['id']][k] != service[k]))
              Text(
                'Updated · ${service['name']} · ${types[old[service['id']]['kind']]} → ${types[service['kind']]}',
              ),
          for (final s in old.values)
            if (!(proposed['services'] as List).any((v) => v['id'] == s['id']))
              Text('Removed · ${s['name']}'),
        ],
        OutlinedButton(
          onPressed: busy
              ? null
              : () => widget.onPreview(BridalPackage.fromJson(proposed)),
          child: const Text('Customer preview'),
        ),
        FilledButton(
          onPressed: busy ? null : publish,
          child: const Text('Publish package'),
        ),
      ],
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ]);
  }

  Widget editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      section('Package details', [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Package name'),
          onChanged: (_) => change(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: description,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description'),
          onChanged: (_) => change(() {}),
        ),
        SwitchListTile(
          title: const Text('Active on publication'),
          value: active,
          onChanged: busy ? null : (value) => change(() => active = value),
        ),
        if (published != null)
          TextButton(
            onPressed: busy ? null : history,
            child: const Text('Version history'),
          ),
      ]),
      section('Gown rentals', [
        Text(
          'Number of gowns included',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: count,
          isExpanded: true,
          items: [
            for (var n = 0; n <= gownLimit || n <= count; n++)
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value == null || value == count) return;
                  change(() {
                    count = value;
                    gownPrices = [];
                  });
                },
        ),
        const SizedBox(height: 10),
        const Text(
          'Customers choose their gown styles and sizes in the app.',
          style: TextStyle(color: muted),
        ),
      ]),
      section('Services & add-ons', [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: busy || services.length >= 12 ? null : addService,
              child: const Text('Add service'),
            ),
            OutlinedButton(
              onPressed: busy ? null : managePrices,
              child: const Text('Manage service prices'),
            ),
            if (approvedIds.contains(id) &&
                published?['pricingModel'] != 'service-based')
              TextButton(
                onPressed: busy ? null : () => run(loadApproved),
                child: const Text('Use approved package configuration'),
              ),
          ],
        ),
        if (services.isNotEmpty)
          _ServiceGrid(
            headings: const [
              'Service',
              'Package role',
              'Quantity',
              'Unit price / rule',
              'Actions',
            ],
            flexes: const [22, 30, 11, 23, 14],
            rows: [for (final service in services) serviceCells(service)],
          ),
      ]),
      section('Bundle discount', [
        if (approvedIds.contains(id))
          CheckboxListTile(
            title: const Text(
              'Calculate discount to match the approved selling price',
            ),
            value: matchApproved,
            onChanged: busy
                ? null
                : (value) => change(() {
                    matchApproved = value == true;
                    if (matchApproved) discount.text = '0';
                  }),
          ),
        if (!matchApproved) ...[
          DropdownButtonFormField<String>(
            initialValue: discountKind,
            decoration: const InputDecoration(labelText: 'Discount type'),
            items: const [
              DropdownMenuItem(
                value: 'fixed',
                child: Text('Fixed amount (RM)'),
              ),
              DropdownMenuItem(value: 'percent', child: Text('Percentage')),
            ],
            onChanged: busy
                ? null
                : (value) => change(() => discountKind = value!),
          ),
          TextField(
            controller: discount,
            decoration: InputDecoration(
              labelText: discountKind == 'fixed'
                  ? 'Discount (RM)'
                  : 'Discount (%)',
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => change(() {}),
          ),
        ],
      ]),
    ],
  );

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !dirty && !busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || busy || !dirty) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Leave with unsaved changes?'),
          content: const Text(
            'You can save your changes as unpublished before leaving.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (context.mounted && discard == true) Navigator.pop(context);
    },
    child: Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: Text(
          widget.package == null
              ? 'Create service package'
              : 'Edit service package',
        ),
      ),
      body: FutureBuilder<void>(
        future: loading,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      packagePricingLoadError(
                        state.error,
                        unavailable: 'Could not load package pricing.',
                        updateRequired:
                            'The pricing service needs a backend update before you can edit packages.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () {
                        final next = load();
                        setState(() {
                          loading = next;
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return IgnorePointer(
            ignoring: busy,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 16,
                        20,
                        wide ? 28 : 16,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Build your package',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Configure gowns, services and pricing before reviewing your package.',
                            style: TextStyle(color: muted),
                          ),
                          const SizedBox(height: 18),
                          Expanded(
                            child: wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ListView(
                                          primary: false,
                                          children: [editor()],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      SizedBox(
                                        width: 330,
                                        child: ListView(
                                          primary: false,
                                          children: [summary()],
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView(children: [editor(), summary()]),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: busy || !loadingReady
                      ? null
                      : () => run(saveDraft),
                  child: const Text('Save unpublished'),
                ),
                FilledButton(
                  onPressed: busy || !loadingReady
                      ? null
                      : () => run(calculate),
                  child: const Text('Review package'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  bool get loadingReady => loaded;
  bool loaded = false;
}

const serviceDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(16)),
  side: BorderSide(color: border),
);

class _ServicePriceForm extends StatefulWidget {
  const _ServicePriceForm({
    required this.initial,
    required this.request,
    required this.existing,
  });
  final PricingRow initial;
  final List<PricingRow> existing;
  final Future<PricingRow> Function(String, PricingRow) request;
  @override
  State<_ServicePriceForm> createState() => _ServicePriceFormState();
}

class _ServicePriceFormState extends State<_ServicePriceForm> {
  bool get allowance =>
      widget.initial['id'] == _ServicePricingEditorState.standardAllowanceId;
  late final name = TextEditingController(
    text: allowance ? 'Standard gown allowance' : widget.initial['name'],
  );
  late final description = TextEditingController(
    text: widget.initial['description'],
  );
  late final price = TextEditingController(
    text: widget.initial['priceCents'] == null
        ? ''
        : (widget.initial['priceCents'] / 100).toStringAsFixed(2),
  );
  late String method = widget.initial['method'] ?? 'fixed';
  late PackageServiceType type =
      PackageServiceType.fromCode(widget.initial['serviceType']) ??
      PackageServiceType.custom;
  late bool active = widget.initial['active'] != false;
  late bool customEligible = widget.initial['customEligible'] != false;
  late bool standalone = widget.initial['standaloneEligible'] == true;
  late int revision = widget.initial['revision'] ?? 0;
  bool get supportsStandalone =>
      !allowance &&
      customEligible &&
      const {
        'custom',
        'makeup-hair',
        'makeup-trial',
        'portrait-session',
      }.contains(type.code) &&
      const {'fixed', 'per-session'}.contains(method);
  String? error;
  bool busy = false;
  bool advanced = false;
  bool categoryConfirmed = false;
  bool get creating => widget.initial.isEmpty;

  bool get needsCategory => RegExp(
    r'\b(make[ -]?up|hair\s*styl\w+|fitting|portraits?|rental days?|beauty look)\b',
    caseSensitive: false,
  ).hasMatch(name.text);

  Future<void> save() async {
    final amount = minorUnits(price.text);
    if (amount == null ||
        allowance && amount == 0 ||
        name.text.trim().length < 2) {
      setState(() => error = 'Enter a service name and valid price.');
      return;
    }
    if (!allowance &&
        widget.existing.any(
          (row) =>
              row['id'] != widget.initial['id'] &&
              (row['name'] as String).trim().toLowerCase() ==
                  name.text.trim().toLowerCase(),
        )) {
      setState(
        () => error =
            'A service with this name already exists. Select it from the catalogue.',
      );
      return;
    }
    if (creating && needsCategory && !categoryConfirmed) {
      setState(() {
        advanced = true;
        error =
            'Choose the service category so Luvly can apply the right booking and pricing rules.';
      });
      return;
    }
    final standaloneEligible = supportsStandalone && standalone;
    if (!creating) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(
            allowance ? 'Save catalogue price?' : 'Save service changes?',
          ),
          content: Text(
            [
              '${name.text.trim()} · ${packageMoney(amount)} · ${active ? 'Active' : 'Inactive'}',
              if (!allowance)
                'Custom packages: ${customEligible ? 'Available' : 'Unavailable'}',
              if (!allowance)
                'Without gown rental: ${standaloneEligible ? 'Available' : 'Unavailable'}',
              'Published packages retain their stored prices.',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(allowance ? 'Save price' : 'Save changes'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true) return;
    }
    setState(() => busy = true);
    try {
      final result = await widget.request('/v1/bridal-service-prices', {
        'id': widget.initial['id'] ?? packageRequestId(),
        'revision': revision,
        'name': name.text.trim(),
        'description': description.text.trim(),
        'method': allowance ? 'per-gown' : method,
        'serviceType': type.code,
        'priceCents': amount,
        'active': active,
        'customEligible': !allowance && customEligible,
        'standaloneEligible': standaloneEligible,
      });
      if (!mounted) return;
      if ((result['standaloneEligible'] == true) != standaloneEligible) {
        setState(() {
          busy = false;
          if (result['revision'] case final int savedRevision) {
            revision = savedRevision;
          }
          error =
              'The catalogue service did not save availability without a gown. The server may need an update. Other changes may have been saved.';
        });
        return;
      }
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is PaymentFailure
              ? e.message
              : 'Could not save catalogue price.';
        });
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    super.dispose();
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool priceField = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !busy,
          maxLines: lines,
          keyboardType: priceField
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          decoration: InputDecoration(
            hintText: priceField
                ? '0.00'
                : label == 'Service name'
                ? 'e.g. Bridal consultation'
                : null,
          ),
          onChanged: (_) {
            if (error != null) setState(() => error = null);
          },
        ),
      ],
    ),
  );

  Widget advancedSettings() => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: ValueKey(advanced),
      initiallyExpanded: advanced,
      onExpansionChanged: (expanded) => advanced = expanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      title: const Text('Advanced settings'),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Service category'),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<PackageServiceType>(
          initialValue: creating && needsCategory && !categoryConfirmed
              ? null
              : type,
          hint: const Text('Choose a category'),
          isExpanded: true,
          items: [
            for (final value in PackageServiceType.values.where(
              (v) => !v.isAccessory,
            ))
              DropdownMenuItem(
                value: value,
                child: Text(
                  value == PackageServiceType.custom
                      ? 'General bridal service'
                      : value.label,
                ),
              ),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() {
                  type = value!;
                  categoryConfirmed = true;
                  error = null;
                  advanced = true;
                  method = type == PackageServiceType.extraRentalDay
                      ? 'per-day'
                      : 'fixed';
                }),
        ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Pricing method'),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey(type),
          initialValue: method,
          items: [
            for (final value
                in type == PackageServiceType.extraRentalDay
                    ? ['per-day']
                    : ['fixed', 'per-session', 'per-gown'])
              DropdownMenuItem(
                value: value,
                child: Text(switch (value) {
                  'per-day' => 'Per rental day',
                  'per-session' => 'Per session',
                  'per-gown' => 'Per gown',
                  _ => 'Fixed price',
                }),
              ),
          ],
          onChanged: busy ? null : (value) => setState(() => method = value!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active in catalogue'),
          value: active,
          onChanged: busy ? null : (value) => setState(() => active = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Available for custom packages'),
          value: customEligible,
          onChanged: busy
              ? null
              : (value) => setState(() => customEligible = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Available without gown rental'),
          subtitle: Text(
            supportsStandalone
                ? 'Allows a quote for this service without renting a gown.'
                : 'Requires custom availability and a supported standalone service type.',
          ),
          value: supportsStandalone && standalone,
          onChanged: busy || !supportsStandalone
              ? null
              : (value) => setState(() => standalone = value),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    shape: serviceDialogShape,
    title: Text(
      allowance
          ? 'Standard gown allowance'
          : creating
          ? 'Create new service'
          : 'Edit service price',
    ),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allowance
                  ? 'Set the approved amount per gown for predefined package pricing.'
                  : creating
                  ? 'Add a reusable service to your catalogue.'
                  : 'Published packages retain their stored prices.',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            if (!allowance) field('Service name', name),
            field(
              allowance
                  ? 'Standard amount per gown (RM)'
                  : 'Standard price (RM)',
              price,
              priceField: true,
            ),
            if (!allowance) ...[
              field('Description (optional)', description, lines: 2),
              advancedSettings(),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: busy
                    ? null
                    : (value) => setState(() => active = value),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(
          busy
              ? 'Saving…'
              : creating
              ? 'Create service'
              : allowance
              ? 'Review price change'
              : 'Review changes',
        ),
      ),
    ],
  );
}
