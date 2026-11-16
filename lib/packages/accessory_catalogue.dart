import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package_api.dart';
import '../shared/list_controls.dart';

class AccessoryItem {
  AccessoryItem(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get name => data['name'];
  String get category => data['category'];
  String get image => data['image'];
  String get description => data['description'];
  String get size => data['size'];
  String get material => data['material'];
  int get price => data['priceCents'];
}

class AccessoryCatalogue {
  AccessoryCatalogue(this.version, this.items);
  final int version;
  final List<AccessoryItem> items;
  static Future<AccessoryCatalogue> load() async {
    final d = jsonDecode(
      await rootBundle.loadString('assets/images/accessory-catalogue.json'),
    );
    return AccessoryCatalogue(
      d['version'],
      (d['items'] as List)
          .map((i) => AccessoryItem(Map<String, dynamic>.from(i)))
          .toList(),
    );
  }

  List<AccessoryItem> choices(PackageServiceItem service) {
    return items
        .where(
          (item) => item.category == 'Veils'
              ? service.includesVeils
              : service.includesJewellery,
        )
        .toList();
  }

  int subtotal(Set<String> ids) =>
      items.where((i) => ids.contains(i.id)).fold(0, (n, i) => n + i.price);
  int extra(PackageServiceItem s, Set<String> ids) =>
      (subtotal(ids) - s.allowanceCents).clamp(0, 100000000);
}

class AccessoryServicePicker extends StatelessWidget {
  const AccessoryServicePicker({
    super.key,
    required this.catalogue,
    required this.service,
    required this.selected,
    required this.onChanged,
    this.readOnly = false,
    this.availability,
  });
  final AccessoryCatalogue catalogue;
  final PackageServiceItem service;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool readOnly;
  final Map<String, String>? availability;
  @override
  Widget build(BuildContext context) {
    final stock = availability;
    final choices = catalogue.choices(service);
    final noAvailableStyles =
        stock != null &&
        stock.isNotEmpty &&
        !choices.any((item) => stock[item.id] == 'Available');
    final extra = catalogue.extra(service, selected);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              '${packageMoney(service.allowanceCents)} allowance',
              if (selected.isNotEmpty) '${selected.length} selected',
              if (extra > 0) '+ ${packageMoney(extra)}',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (!readOnly)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.diamond_outlined),
                label: Text(
                  selected.isEmpty
                      ? noAvailableStyles
                            ? 'Browse styles'
                            : 'Choose accessories'
                      : 'Edit accessories (${selected.length})',
                ),
                onPressed: () async {
                  final result = await Navigator.of(context).push<Set<String>>(
                    MaterialPageRoute(
                      builder: (_) => AccessoryBrowser(
                        catalogue: catalogue,
                        service: service,
                        initial: selected,
                        availability: availability,
                      ),
                    ),
                  );
                  if (context.mounted && result != null) onChanged(result);
                },
              ),
            ),
          ExpansionTile(
            key: PageStorageKey('accessory-details-${service.id}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            shape: const Border(),
            collapsedShape: const Border(),
            visualDensity: VisualDensity.compact,
            title: Text('Accessory details', style: theme.textTheme.labelLarge),
            children: [
              if (service.customerDescription.trim().isNotEmpty)
                Text(service.customerDescription),
              const Text(
                'The package covers styles up to the allowance. Any excess is added to your total.',
              ),
              if (selected.isEmpty)
                Text(
                  noAvailableStyles
                      ? 'No styles can be selected for these dates. Change dates or ask Luvly to check stock before the deposit.'
                      : 'Choose your styles now or finalise them with Luvly before the deposit.',
                ),
              for (final item in catalogue.items.where(
                (i) => selected.contains(i.id),
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      item.image,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.category} · ${packageMoney(item.price)} / 3 days',
                  ),
                  trailing: readOnly
                      ? null
                      : IconButton(
                          tooltip: 'Remove ${item.name}',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              onChanged({...selected}..remove(item.id)),
                        ),
                ),
              if (selected.isNotEmpty)
                Text(
                  'Selected value ${packageMoney(catalogue.subtotal(selected))} · extra ${packageMoney(extra)}',
                  style: theme.textTheme.titleSmall,
                ),
              const SizedBox(height: 6),
              Text(
                'Style illustrations. Confirm final details at your consultation.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccessoryBrowser extends StatefulWidget {
  const AccessoryBrowser({
    super.key,
    required this.catalogue,
    required this.service,
    required this.initial,
    this.availability,
  });
  final AccessoryCatalogue catalogue;
  final PackageServiceItem service;
  final Set<String> initial;
  final Map<String, String>? availability;
  @override
  State<AccessoryBrowser> createState() => _AccessoryBrowserState();
}

class _AccessoryBrowserState extends State<AccessoryBrowser> {
  late Set<String> selected = {...widget.initial};
  String category = 'All', search = '', sort = 'Featured';
  void toggle(AccessoryItem item) => setState(
    () => selected.contains(item.id)
        ? selected.remove(item.id)
        : selected.add(item.id),
  );
  bool canSelect(AccessoryItem item) =>
      widget.availability == null ||
      widget.availability![item.id] == 'Available';
  String? unavailableReason(AccessoryItem item) => canSelect(item)
      ? null
      : widget.availability![item.id] == 'Unavailable'
      ? 'Unavailable for your dates'
      : 'Not available to book yet';
  Future<void> details(AccessoryItem item) async {
    final next = {...selected};
    selected.contains(item.id) ? next.remove(item.id) : next.add(item.id);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccessoryDetailsScreen(
          item: item,
          isSelected: selected.contains(item.id),
          unavailableReason: unavailableReason(item),
          allowanceCents: widget.service.allowanceCents,
          resultingExtraCents: widget.catalogue.extra(widget.service, next),
          changeCents:
              widget.catalogue.extra(widget.service, next) -
              widget.catalogue.extra(widget.service, selected),
        ),
      ),
    );
    if (changed == true && mounted) toggle(item);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.catalogue.choices(widget.service);
    final categories = ['All', ...all.map((i) => i.category).toSet()];
    final visible = all
        .where(
          (i) =>
              (category == 'All' || i.category == category) &&
              '${i.name} ${i.category} ${i.material}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    if (sort != 'Featured') {
      visible.sort(
        (a, b) => sort == 'Price: low to high'
            ? a.price.compareTo(b.price)
            : b.price.compareTo(a.price),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('The accessory edit')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${selected.length} selected · ${packageMoney(widget.catalogue.subtotal(selected))} value',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Allowance ${packageMoney(widget.service.allowanceCents)} · extra ${packageMoney(widget.catalogue.extra(widget.service, selected))}',
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Use these accessories'),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Little details.\nA look that is yours.',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontFamily: 'LuvlySerif'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Explore by category, compare styles and build your own combination. Prices are for three days; your service allowance is deducted automatically.',
              ),
              const SizedBox(height: 12),
              const Text(
                'ACCESSORY STYLE GUIDE',
                style: TextStyle(fontSize: 11, letterSpacing: 1.2),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search accessories',
                ),
                onChanged: (v) => setState(() => search = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: categories
                    .map(
                      (c) => ChoiceChip(
                        label: Text(c),
                        selected: category == c,
                        onSelected: (_) => setState(() => category = c),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              ListFilterSelect(
                label: 'Sort by',
                value: sort,
                options: const [
                  'Featured',
                  'Price: low to high',
                  'Price: high to low',
                ],
                onChanged: (s) => setState(() => sort = s),
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No matching accessories. Try another category or search.',
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700
                      ? 3
                      : constraints.maxWidth >= 340
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: visible
                        .map(
                          (i) => SizedBox(
                            width: width,
                            child: Card(
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: selected.contains(i.id)
                                      ? Theme.of(context).colorScheme.primary
                                      : const Color(0xffe6dcd8),
                                  width: selected.contains(i.id) ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  InkWell(
                                    onTap: () => details(i),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Image.asset(
                                        i.image,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          i.category.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          i.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${packageMoney(i.price)} / 3 days',
                                        ),
                                        if (!canSelect(i))
                                          Text(
                                            unavailableReason(i)!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        TextButton(
                                          onPressed: () => details(i),
                                          child: const Text('View details'),
                                        ),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            onPressed:
                                                selected.contains(i.id) ||
                                                    canSelect(i)
                                                ? () => toggle(i)
                                                : null,
                                            child: Text(
                                              selected.contains(i.id)
                                                  ? 'Selected ✓'
                                                  : 'Select',
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
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product page with a persistent action; long details remain scrollable.
class AccessoryDetailsScreen extends StatelessWidget {
  const AccessoryDetailsScreen({
    super.key,
    required this.item,
    required this.isSelected,
    required this.allowanceCents,
    required this.resultingExtraCents,
    required this.changeCents,
    this.unavailableReason,
  });
  final AccessoryItem item;
  final bool isSelected;
  final int allowanceCents, resultingExtraCents, changeCents;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xffFFFCFA),
      appBar: AppBar(title: const Text('Accessory details')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xffEADFDB))),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                unavailableReason != null && !isSelected
                    ? unavailableReason!
                    : changeCents == 0
                    ? 'No change to your package total'
                    : '${changeCents > 0 ? '+' : '−'} ${packageMoney(changeCents.abs())} ${changeCents > 0 ? 'added to' : 'off'} your package',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: unavailableReason == null || isSelected
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(
                  isSelected ? 'Remove from selection' : 'Add to selection',
                ),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: const Color(0xffF4EEE8),
                  height: 280,
                  child: Image.asset(item.image, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                item.category.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.8,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'LuvlySerif',
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                packageMoney(item.price),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text('3-day rental'),
              const SizedBox(height: 18),
              Text(item.description, style: const TextStyle(height: 1.5)),
              const Divider(height: 32),
              _detail(context, 'Material', item.material),
              _detail(context, 'Size & fit', item.size),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xffF5EEEB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your package allowance',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${packageMoney(allowanceCents)} is already included for this service. Only the excess is added.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Service surcharge after ${isSelected ? 'removing' : 'adding'} this style: ${packageMoney(resultingExtraCents)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Style preview · confirm fit and final details at your fitting.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('About this style', style: TextStyle(fontSize: 14)),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Images are AI-generated style illustrations. The boutique will confirm materials, fit and stock at your fitting. Jewellery is costume jewellery.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(height: 1.4)),
      ],
    ),
  );
}
