import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../shared/list_controls.dart';
import 'design.dart';

/// Survives the details view; this is not a stock or availability cache.
class InventoryListState {
  String query = '', category = 'All styles', colour = 'All colours';
  String size = 'All sizes', visibility = 'All', availability = 'All statuses';
  String sort = 'Name: A–Z';
  int page = 0;
  void reset() {
    query = '';
    category = 'All styles';
    colour = 'All colours';
    size = 'All sizes';
    visibility = 'All';
    availability = 'All statuses';
    sort = 'Name: A–Z';
    page = 0;
  }
}

List<CatalogueDress> filterInventory(
  Iterable<CatalogueDress> records,
  InventoryListState state,
) {
  final rows = records
      .where(
        (d) =>
            matchesListSearch(state.query, [
              d.name,
              d.category,
              d.colour,
              d.sizes,
            ]) &&
            (state.category == 'All styles' || state.category == d.category) &&
            (state.colour == 'All colours' || state.colour == d.colour) &&
            (state.size == 'All sizes' ||
                d.sizes.split(',').map((s) => s.trim()).contains(state.size)) &&
            (state.visibility == 'All' ||
                d.published == (state.visibility == 'Published')) &&
            (state.availability == 'All statuses' ||
                state.availability == d.availability),
      )
      .toList();
  rows.sort((a, b) {
    final result = switch (state.sort) {
      'Price: low to high' => a.priceCents.compareTo(b.priceCents),
      'Price: high to low' => b.priceCents.compareTo(a.priceCents),
      _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    };
    return result != 0 ? result : a.id.compareTo(b.id);
  });
  return rows;
}

class InventoryWorkspace extends StatefulWidget {
  const InventoryWorkspace({
    super.key,
    required this.records,
    required this.state,
    required this.onView,
    required this.onStock,
    this.onEdit,
    this.cached = false,
  });
  final List<CatalogueDress> records;
  final InventoryListState state;
  final ValueChanged<CatalogueDress> onView, onStock;
  final ValueChanged<CatalogueDress>? onEdit;
  final bool cached;
  @override
  State<InventoryWorkspace> createState() => _InventoryWorkspaceState();
}

class _InventoryWorkspaceState extends State<InventoryWorkspace> {
  InventoryListState get s => widget.state;
  void change(VoidCallback update) => setState(() {
    update();
    s.page = 0;
  });
  Widget photo(CatalogueDress d, double height) => SizedBox(
    width: 88,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onView(d),
        child: Semantics(
          button: true,
          label: 'View ${d.name}',
          child: CatalogueDressPhoto(
            key: ValueKey('inventory-photo-${d.id}'),
            dress: d,
            height: height * MediaQuery.textScalerOf(context).scale(11) / 11,
            compact: true,
          ),
        ),
      ),
    ),
  );
  Widget actions(CatalogueDress d) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      TextButton(
        key: ValueKey('inventory-view-${d.id}'),
        onPressed: () => widget.onView(d),
        child: const Text('View'),
      ),
      TextButton.icon(
        key: ValueKey('inventory-stock-${d.id}'),
        onPressed: () => widget.onStock(d),
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: const Text('Stock by size'),
      ),
      if (widget.onEdit != null)
        IconButton(
          tooltip: 'Edit ${d.name}',
          onPressed: widget.cached ? null : () => widget.onEdit!(d),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final filtered = filterInventory(widget.records, s);
    final last = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ 20,
        current = s.page.clamp(
          0,
          filtered.isEmpty ? 0 : (filtered.length - 1) ~/ 20,
        );
    final shown = filtered.skip(current * 20).take(20).toList();
    Widget select(
      String label,
      String value,
      List<String> options,
      ValueChanged<String> onChanged,
    ) => ListFilterSelect(
      label: label,
      value: value,
      options: options,
      onChanged: (v) => change(() => onChanged(v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text('${widget.records.length} catalogue dresses'),
            Text(
              '${widget.records.where((d) => d.published).length} published',
              style: const TextStyle(color: sage),
            ),
            Text(
              '${widget.records.where((d) => !d.published).length} unpublished',
              style: const TextStyle(color: muted),
            ),
            if (widget.cached)
              const Text('Cached catalogue', style: TextStyle(color: muted)),
          ],
        ),
        gap(20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListSearchField(
                value: s.query,
                hint: 'Search dress name, style, colour or size',
                onChanged: (v) => change(() => s.query = v),
              ),
              gap(12),
              LayoutBuilder(
                builder: (context, bounds) {
                  final filters = Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      select('Style', s.category, [
                        'All styles',
                        ...{
                          ...dressCategories,
                          ...widget.records.map((d) => d.category),
                        },
                      ], (v) => s.category = v),
                      select('Colour', s.colour, [
                        'All colours',
                        ...{
                          ...dressColours,
                          ...widget.records.map((d) => d.colour),
                        },
                      ], (v) => s.colour = v),
                      select('Size', s.size, [
                        'All sizes',
                        ...dressSizes,
                      ], (v) => s.size = v),
                      select('Catalogue status', s.availability, [
                        'All statuses',
                        ...dressAvailability,
                      ], (v) => s.availability = v),
                      select('Sort by', s.sort, const [
                        'Name: A–Z',
                        'Price: low to high',
                        'Price: high to low',
                      ], (v) => s.sort = v),
                      ResetListFilters(onReset: () => setState(s.reset)),
                    ],
                  );
                  return bounds.maxWidth < 600
                      ? ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Refine inventory'),
                          subtitle: Text(
                            '${s.category} · ${s.colour} · ${s.size} · ${s.availability}',
                          ),
                          children: [filters],
                        )
                      : filters;
                },
              ),
              gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in ['All', 'Published', 'Unpublished'])
                    ChoiceChip(
                      label: Text(v),
                      selected: s.visibility == v,
                      onSelected: (_) => change(() => s.visibility = v),
                    ),
                ],
              ),
            ],
          ),
        ),
        gap(16),
        const Text(
          'Catalogue status controls presentation, not a reservation. Open Stock by size for physical quantities; rental availability also depends on dates, reservations and cleaning.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        gap(16),
        Text(
          '${filtered.length} ${filtered.length == 1 ? 'dress' : 'dresses'}',
          style: const TextStyle(color: muted),
        ),
        gap(12),
        if (widget.records.isEmpty)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No dresses added yet',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                gap(8),
                Text(
                  widget.onEdit == null
                      ? 'Your manager has not added any dresses yet.'
                      : 'Add your first dress, review its details, then publish it for brides.',
                ),
              ],
            ),
          )
        else if (shown.isEmpty)
          FilteredListEmpty(
            message: 'No dresses match your search.',
            onReset: () => setState(s.reset),
          )
        else
          LayoutBuilder(
            builder: (context, bounds) =>
                bounds.maxWidth >= 1100 &&
                    MediaQuery.textScalerOf(context).scale(14) < 22
                ? Panel(
                    padding: EdgeInsets.zero,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: bounds.maxWidth),
                        child: DataTable(
                          horizontalMargin: 20,
                          columnSpacing: 24,
                          dataRowMinHeight:
                              128 *
                              MediaQuery.textScalerOf(context).scale(11) /
                              11,
                          dataRowMaxHeight:
                              160 *
                              MediaQuery.textScalerOf(context).scale(11) /
                              11,
                          columns: const [
                            DataColumn(label: Text('DRESS')),
                            DataColumn(label: Text('COLOUR / SIZES')),
                            DataColumn(label: Text('PRICE')),
                            DataColumn(label: Text('CATALOGUE')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final d in shown)
                              DataRow(
                                key: ValueKey('inventory-row-${d.id}'),
                                cells: [
                                  DataCell(
                                    Row(
                                      children: [
                                        photo(d, 116),
                                        const SizedBox(width: 16),
                                        SizedBox(
                                          width: 180,
                                          child: cell(d.name, sub: d.category),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 140,
                                      child: cell(d.colour, sub: d.sizes),
                                    ),
                                  ),
                                  DataCell(Text(d.priceLabel)),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Pill(
                                          d.published
                                              ? 'Published'
                                              : 'Unpublished',
                                        ),
                                        gap(6),
                                        Text(
                                          d.availability,
                                          style: const TextStyle(color: muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(actions(d)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final d in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    photo(d, 116),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          gap(6),
                                          Text('${d.category} · ${d.colour}'),
                                          gap(6),
                                          Text(d.priceLabel),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                gap(12),
                                Text('Sizes: ${d.sizes}'),
                                gap(10),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Pill(
                                      d.published ? 'Published' : 'Unpublished',
                                    ),
                                    Text(
                                      d.availability,
                                      style: const TextStyle(color: muted),
                                    ),
                                  ],
                                ),
                                gap(8),
                                actions(d),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        gap(12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              shown.isEmpty
                  ? '0 shown'
                  : '${current * 20 + 1}–${current * 20 + shown.length} of ${filtered.length}',
            ),
            TextButton(
              onPressed: current > 0
                  ? () => setState(() => s.page = current - 1)
                  : null,
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: current < last
                  ? () => setState(() => s.page = current + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}
