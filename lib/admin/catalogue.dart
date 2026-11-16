import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'live_inventory.dart';
import 'operations.dart' show ProgressPage;
import '../packages/package_screen.dart';

Future<void> successNotice(BuildContext c, String title, String description) =>
    showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 50, color: sage),
        title: Text(title),
        content: Text(description),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

Future<void> gownForm(BuildContext c, {Gown? gown}) async {
  final m = PortalScope.of(c);
  if (!m.signedIn) return;
  await editForm(
    c,
    gown == null ? 'Add New Dress' : 'Update Dress Details',
    [
      FieldSpec('name', 'Dress Name', gown?.name ?? ''),
      FieldSpec(
        'category',
        'Category',
        gown?.category ?? 'A-Line',
        options: choices(['A-Line', 'Ball Gown', 'Mermaid', 'Sheath']),
      ),
      FieldSpec('size', 'Available Sizes', gown?.size ?? 'S, M, L'),
      FieldSpec(
        'price',
        'Price (RM)',
        gown?.price.toStringAsFixed(2) ?? '',
        number: true,
      ),
      FieldSpec(
        'description',
        'Description',
        gown?.description ?? '',
        multiline: true,
      ),
      FieldSpec(
        'image',
        'Demo catalogue image',
        gown?.image ?? 'golden',
        options: choices([
          'golden',
          'eden',
          'blush',
          'satin',
          'pearl',
          'ivory',
        ]),
      ),
      FieldSpec(
        'status',
        'Availability',
        gown?.status ?? 'Available',
        options: choices(gownStatuses),
      ),
    ],
    (v) {
      final g = Gown(
        gown?.id ?? 'DR-${100 + m.gowns.length}',
        v['name']!,
        v['category']!,
        double.parse(v['price']!),
        v['image']!,
        size: v['size']!,
        status: v['status']!,
      )..description = v['description']!;
      m.saveGown(g, existing: gown);
    },
    submitLabel: gown == null ? 'Add Dress' : 'Save Changes',
  );
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryState();
}

class _InventoryState extends State<InventoryPage> {
  String query = '', status = 'Active inventory';
  Gown? selected;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (m.isLive) return const LiveInventoryPage();
    final g = selected;
    if (g != null) {
      return PageBody(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Dress Inventory List'),
            ),
          ),
          Heading(g.name, 'Dress Details', action: Pill(g.status)),
          ResponsiveGrid(
            minWidth: 350,
            children: [
              Panel(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/${g.image}.jpg',
                        height: 300,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                    gap(18),
                    Info('Dress ID', g.id),
                    Info('Category', g.category),
                    Info('Size', g.size),
                    Info('Price (RM)', money(g.price)),
                    Info('Status', g.status),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Description',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    gap(12),
                    Text(g.description),
                    gap(24),
                    Text(
                      'Available Sizes',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    gap(12),
                    Text(g.size),
                    gap(24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => gownForm(c, gown: g),
                          child: const Text('Update Dress'),
                        ),
                        if (g.status != 'Inactive')
                          OutlinedButton(
                            onPressed: () async {
                              if (!await confirm(
                                c,
                                'Remove Dress from Active Inventory?',
                                '${g.name} will no longer appear as available. Historical records will be retained.',
                              )) {
                                return;
                              }
                              if (!c.mounted) return;
                              try {
                                m.removeGown(g);
                                await successNotice(
                                  c,
                                  'Dress Removed Successfully',
                                  'Historical records have been retained.',
                                );
                              } on StateError catch (e) {
                                if (c.mounted) notice(c, e.message);
                              }
                            },
                            child: const Text('Remove Dress'),
                          ),
                      ],
                    ),
                    gap(18),
                    const Text(
                      'Demo catalogue images only. File uploads will be connected with cloud storage.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }
    final list = m.gowns
        .where(
          (g) =>
              ('${g.id} ${g.name}').toLowerCase().contains(
                query.toLowerCase(),
              ) &&
              (status == 'All statuses' ||
                  (status == 'Active inventory'
                      ? g.status != 'Inactive'
                      : g.status == status)),
        )
        .toList();
    return PageBody(
      children: [
        Heading(
          'Dress Inventory List',
          'View and manage wedding dresses.',
          action: FilledButton.icon(
            onPressed: m.isLive ? null : () => gownForm(c),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Dress'),
          ),
        ),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search dress name...',
          filters: [
            filterSelect(status, [
              'Active inventory',
              'All statuses',
              ...gownStatuses,
            ], (v) => setState(() => status = v)),
          ],
        ),
        RecordTable(
          columns: const [
            'Dress Name',
            'Category',
            'Size',
            'Price (RM)',
            'Status',
            'Action',
          ],
          rows: list
              .map(
                (g) => [
                  cell(g.name, sub: g.id),
                  cell(g.category),
                  cell(g.size),
                  cell(money(g.price)),
                  Pill(g.status),
                  OutlinedButton(
                    onPressed: () => setState(() => selected = g),
                    child: const Text('View'),
                  ),
                ],
              )
              .toList(),
        ),
        gap(18),
        Text(
          m.isLive
              ? 'Dress inventory is not connected yet.'
              : 'Showing ${list.length} dresses',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

Future<void> packageForm(BuildContext c, {ServicePackage? package}) async {
  final m = PortalScope.of(c);
  if (!m.isManager) return;
  await editForm(
    c,
    package == null ? 'Create Service Package' : 'Update Service Package',
    [
      FieldSpec('name', 'Package Name', package?.name ?? ''),
      FieldSpec(
        'price',
        'Price (RM)',
        package?.price.toStringAsFixed(2) ?? '',
        number: true,
      ),
      FieldSpec(
        'description',
        'Description',
        package?.description ?? '',
        multiline: true,
      ),
      FieldSpec(
        'services',
        'Included Services (one per line)',
        package?.services.join('\n') ??
            'Wedding Dress Rental\nBridal Consultation',
        multiline: true,
      ),
      FieldSpec(
        'status',
        'Status',
        package?.active == false ? 'Inactive' : 'Active',
        options: choices(['Active', 'Inactive']),
      ),
    ],
    (v) {
      final services = v['services']!
          .split('\n')
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
      if (services.isEmpty) throw StateError('Select at least one service.');
      m.savePackage(
        ServicePackage(
          package?.id ?? 'PKG-${100 + m.packages.length}',
          v['name']!,
          double.parse(v['price']!),
          v['description']!,
          services,
          active: v['status'] == 'Active',
        ),
        existing: package,
      );
    },
    submitLabel: package == null ? 'Create Package' : 'Save Changes',
  );
}

class CustomerRentalsPage extends StatelessWidget {
  const CustomerRentalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final model = PortalScope.of(context);
    if (model.isLive) {
      return LivePackageScreen(
        key: const ValueKey('customer-rentals'),
        staff: true,
        manager: model.isManager,
        initialSelections: true,
      );
    }
    // Preserve legacy preview tasks under the merged entry; never migrate or
    // delete these local-only tasks as though they were real rental records.
    return const ProgressPage(embedded: true);
  }
}

class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key});
  @override
  State<PackagesPage> createState() => _PackagesState();
}

class _PackagesState extends State<PackagesPage> {
  String query = '';
  ServicePackage? selected;
  @override
  Widget build(BuildContext c) {
    final m = PortalScope.of(c);
    if (m.isLive) return LivePackageScreen(staff: true, manager: m.isManager);
    final p = selected;
    if (p != null) {
      return PageBody(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Package List'),
            ),
          ),
          Heading(
            p.name,
            'Package Details',
            action: Pill(p.active ? 'Active' : 'Inactive'),
          ),
          ResponsiveGrid(
            minWidth: 350,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Info('Package ID', p.id),
                    Info('Price', money(p.price)),
                    Info('Status', p.active ? 'Active' : 'Inactive'),
                    gap(18),
                    Text(
                      'Description',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    gap(10),
                    Text(p.description),
                    gap(24),
                    Text(
                      'Included Services',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    gap(12),
                    for (final s in p.services)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.check, color: sage, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Summary', style: Theme.of(c).textTheme.titleMedium),
                    gap(20),
                    Info('Total Services', '${p.services.length}'),
                    Info('Price (RM)', money(p.price)),
                    gap(24),
                    if (m.isManager)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            onPressed: () => packageForm(c, package: p),
                            child: const Text('Update Package'),
                          ),
                          if (p.active)
                            OutlinedButton(
                              onPressed: () async {
                                if (!await confirm(
                                  c,
                                  'Deactivate Package?',
                                  'This package will become inactive and unavailable for new bookings. Historical records will be retained.',
                                )) {
                                  return;
                                }
                                if (!c.mounted) return;
                                m.deactivatePackage(p);
                                await successNotice(
                                  c,
                                  'Package Deactivated Successfully',
                                  '${p.name} is now inactive. Historical records are retained.',
                                );
                              },
                              child: const Text('Deactivate Package'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }
    final list = m.packages
        .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return PageBody(
      children: [
        Heading(
          'Service Package List',
          'View and manage bridal service packages.',
          action: m.isManager
              ? FilledButton.icon(
                  onPressed: m.isLive ? null : () => packageForm(c),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create Package'),
                )
              : null,
        ),
        Toolbar(
          onSearch: (v) => setState(() => query = v),
          hint: 'Search package name...',
        ),
        RecordTable(
          columns: const ['Package Name', 'Price (RM)', 'Status', 'Action'],
          minWidth: 650,
          rows: list
              .map(
                (p) => [
                  cell(p.name, sub: p.id),
                  cell(money(p.price)),
                  Pill(p.active ? 'Active' : 'Inactive'),
                  OutlinedButton(
                    onPressed: () => setState(() => selected = p),
                    child: const Text('View'),
                  ),
                ],
              )
              .toList(),
        ),
        gap(18),
        Text(
          m.isLive
              ? 'Service packages are not connected yet.'
              : 'Showing ${list.length} packages',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}
