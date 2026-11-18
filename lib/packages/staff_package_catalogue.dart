import 'package:flutter/material.dart';
import '../admin/design.dart';
import '../shared/list_controls.dart';
import 'package_api.dart';
import 'package_filters.dart';

String staffPackagePrice(BridalPackage package) =>
    package.serviceBased && package.draft
    ? 'Pricing pending'
    : packageMoney(package.basePriceCents);

List<BridalPackage> sortStaffPackages(
  Iterable<BridalPackage> source,
  String sort,
) {
  final rows = source.toList();
  rows.sort((a, b) {
    final result = switch (sort) {
      'Price: low to high' => a.basePriceCents.compareTo(b.basePriceCents),
      'Price: high to low' => b.basePriceCents.compareTo(a.basePriceCents),
      'Active first' => (a.active ? 0 : 1).compareTo(b.active ? 0 : 1),
      _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    };
    if (result != 0) return result;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name != 0 ? name : a.id.compareTo(b.id);
  });
  return rows;
}

class StaffPackageCatalogue extends StatefulWidget {
  const StaffPackageCatalogue({
    super.key,
    required this.packages,
    required this.busy,
    required this.onView,
    this.onCreate,
    this.onEdit,
    this.onToggle,
    this.onRemove,
  });
  final List<BridalPackage> packages;
  final bool busy;
  final ValueChanged<BridalPackage> onView;
  final VoidCallback? onCreate;
  final ValueChanged<BridalPackage>? onEdit, onToggle, onRemove;
  @override
  State<StaffPackageCatalogue> createState() => _StaffPackageCatalogueState();
}

class _StaffPackageCatalogueState extends State<StaffPackageCatalogue> {
  String query = '', price = 'All prices', status = 'All', sort = 'Name: A–Z';
  int page = 0;
  void reset() => setState(() {
    query = '';
    price = 'All prices';
    status = 'All';
    sort = 'Name: A–Z';
    page = 0;
  });
  Widget serviceSummary(BridalPackage p) {
    final included = p.services.where((s) => s.kind != 'Add-on').toList(),
        extras = p.services.where((s) => s.kind == 'Add-on').length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          included.isEmpty
              ? 'No included services'
              : included.take(2).map((s) => s.name).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${included.length} included · $extras optional extras',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      ],
    );
  }

  Widget actions(BridalPackage p) => Wrap(
    spacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        key: ValueKey('view-package-${p.id}'),
        onPressed: widget.busy ? null : () => widget.onView(p),
        child: const Text('View details'),
      ),
      if (widget.onEdit != null)
        IconButton(
          tooltip: 'Edit ${p.name}',
          onPressed: widget.busy ? null : () => widget.onEdit!(p),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
      if (widget.onToggle != null || widget.onRemove != null)
        PopupMenuButton<String>(
          tooltip: 'More actions for ${p.name}',
          enabled: !widget.busy,
          onSelected: (v) {
            if (v == 'status') {
              widget.onToggle?.call(p);
            } else if (v == 'remove') {
              widget.onRemove?.call(p);
            }
          },
          itemBuilder: (_) => [
            if (widget.onToggle != null)
              PopupMenuItem(
                value: 'status',
                child: Text(p.active ? 'Deactivate' : 'Review & publish'),
              ),
            if (widget.onRemove != null && !p.serviceBased) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'remove', child: Text('Delete')),
            ],
          ],
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final filtered = sortStaffPackages(
      widget.packages.where(
        (p) =>
            matchesListSearch(query, [
              p.id,
              p.name,
              p.description,
              ...p.services.map((s) => s.name),
            ]) &&
            matchesPackagePrice(p.basePriceCents, price) &&
            (status == 'All' || p.statusLabel == status),
      ),
      sort,
    );
    final last = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ 20,
        current = page.clamp(0, last),
        shown = filtered.skip(current * 20).take(20).toList();
    return PageBody(
      children: [
        Heading(
          'Package catalogue',
          widget.onCreate == null
              ? 'Compare package contents and prices. Your access is read-only.'
              : 'Manage catalogue prices, included services and availability to new customers.',
          action: widget.onCreate == null
              ? null
              : FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Create package'),
                ),
        ),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text('${widget.packages.length} packages'),
            Text(
              '${widget.packages.where((p) => p.active).length} active',
              style: const TextStyle(color: sage),
            ),
            Text(
              '${widget.packages.where((p) => !p.active && !p.draft).length} inactive',
              style: const TextStyle(color: muted),
            ),
            if (widget.packages.any((p) => p.draft))
              Text(
                '${widget.packages.where((p) => p.draft).length} unpublished',
                style: const TextStyle(color: muted),
              ),
          ],
        ),
        gap(20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListSearchField(
                value: query,
                hint: 'Search packages or included services',
                onChanged: (v) => setState(() {
                  query = v;
                  page = 0;
                }),
              ),
              gap(12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ListFilterSelect(
                    label: 'Package price',
                    value: price,
                    options: packagePriceBands,
                    onChanged: (v) => setState(() {
                      price = v;
                      page = 0;
                    }),
                  ),
                  ListFilterSelect(
                    label: 'Sort by',
                    value: sort,
                    options: const [
                      'Name: A–Z',
                      'Price: low to high',
                      'Price: high to low',
                      'Active first',
                    ],
                    onChanged: (v) => setState(() {
                      sort = v;
                      page = 0;
                    }),
                  ),
                  if (query.isNotEmpty ||
                      price != 'All prices' ||
                      status != 'All' ||
                      sort != 'Name: A–Z')
                    ResetListFilters(onReset: reset),
                ],
              ),
              gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in [
                    'All',
                    'Active',
                    'Inactive',
                    if (widget.packages.any((p) => p.draft)) 'Unpublished',
                  ])
                    ChoiceChip(
                      label: Text(s),
                      selected: status == s,
                      onSelected: (_) => setState(() {
                        status = s;
                        page = 0;
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        gap(16),
        const Text(
          'Base prices are shown below. Optional extras and discounts are agreed in each customer’s rental; gown availability is checked against rental dates.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        gap(16),
        Text(
          '${filtered.length} matching packages',
          style: const TextStyle(color: muted),
        ),
        gap(12),
        if (widget.busy) const LinearProgressIndicator(),
        LayoutBuilder(
          builder: (context, bounds) {
            if (filtered.isEmpty) {
              return Panel(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    widget.packages.isEmpty
                        ? 'No packages to display.'
                        : 'No packages match your search and filters.',
                  ),
                ),
              );
            }
            if (bounds.maxWidth < 950) {
              return Column(
                children: [
                  for (final p in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            gap(6),
                            Pill(
                              p.pendingDraft
                                  ? '${p.statusLabel} · Pending changes'
                                  : p.statusLabel,
                            ),
                            gap(10),
                            Text(
                              staffPackagePrice(p),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${p.includedGownCount} included gown${p.includedGownCount == 1 ? '' : 's'}',
                            ),
                            gap(10),
                            serviceSummary(p),
                            gap(8),
                            actions(p),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }
            return RecordTable(
              connected: true,
              minWidth: 1000,
              columns: const [
                'Package',
                'Base price',
                'Included gowns',
                'Services',
                'Status',
                'Actions',
              ],
              rows: [
                for (final p in shown)
                  [
                    SizedBox(
                      width: 210,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            p.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    cell(staffPackagePrice(p)),
                    cell('${p.includedGownCount} per rental'),
                    SizedBox(width: 225, child: serviceSummary(p)),
                    Pill(
                      p.pendingDraft
                          ? '${p.statusLabel} · Pending changes'
                          : p.statusLabel,
                    ),
                    actions(p),
                  ],
              ],
            );
          },
        ),
        gap(12),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              filtered.isEmpty
                  ? '0 records'
                  : 'Page ${current + 1} of ${last + 1} · 20 per page',
            ),
            IconButton(
              tooltip: 'Previous package page',
              onPressed: current > 0
                  ? () => setState(() => page = current - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next package page',
              onPressed: current < last
                  ? () => setState(() => page = current + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showStaffPackageDetails(
  BuildContext context,
  BridalPackage p,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: border),
    ),
    title: Text(p.name),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Pill(
              p.pendingDraft
                  ? '${p.statusLabel} · Pending changes'
                  : p.statusLabel,
            ),
            gap(16),
            Info('Base price', staffPackagePrice(p)),
            Info(
              'Gowns included',
              '${p.includedGownCount} included per rental',
            ),
            gap(8),
            Text(p.description),
            const Divider(),
            Text(
              'Included services',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final service in p.services.where((s) => s.kind != 'Add-on'))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(
                  '${service.description}\n${service.kind == 'Optional' ? 'Included · removable for a ${packageMoney(service.priceCents)} reduction' : 'Included · required'}',
                ),
              ),
            if (!p.services.any((s) => s.kind != 'Add-on'))
              const Text('No included services recorded.'),
            const Divider(),
            Text(
              'Optional extras',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final service in p.services.where((s) => s.kind == 'Add-on'))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(
                  '${service.description}\n+ ${packageMoney(service.priceCents)} · not in the base price',
                ),
              ),
            if (!p.services.any((s) => s.kind == 'Add-on'))
              const Text('No optional extras recorded.'),
            gap(),
            const Text(
              'Viewing a package does not reserve a gown. Confirm rental dates and stock in Customer rentals.',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
