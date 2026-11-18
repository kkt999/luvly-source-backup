part of 'service_pricing_editor.dart';

String serviceNameKey(PricingRow row) =>
    (row['name'] as String).trim().toLowerCase();

String serviceCategory(PricingRow row) {
  final type = PackageServiceType.fromCode(row['serviceType']);
  return type == null || type == PackageServiceType.custom
      ? 'General bridal service'
      : type.label;
}

String priceUnit(PricingRow row) => switch (row['method']) {
  'per-session' => 'session',
  'per-day' => 'day',
  'per-gown' => 'gown',
  _ => switch (row['serviceType']) {
    'makeup-hair' || 'second-beauty-look' => 'look',
    'makeup-trial' => 'trial',
    _ => row['id'] == 'consultation' ? 'consultation' : 'service',
  },
};

String pickerPrice(PricingRow row) => switch (row['serviceType']) {
  'package-veil' =>
    'Included · Remove to save ${packageMoney(row['priceCents'])}',
  'item-priced-accessories' => 'Catalogue-based · Variable',
  _ =>
    '${serviceCategory(row)} · ${packageMoney(row['priceCents'])} / ${priceUnit(row)}',
};
bool matchesService(PricingRow row, String search) =>
    "${row['name']} ${serviceCategory(row)}".toLowerCase().contains(
      search.trim().toLowerCase(),
    );

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({
    required this.headings,
    required this.flexes,
    required this.rows,
  });
  final List<String> headings;
  final List<int> flexes;
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final desktop = box.maxWidth >= 610;
      Widget line(List<Widget> cells) => Row(
        children: [
          for (var index = 0; index < cells.length; index++)
            Expanded(
              flex: flexes[index],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: cells[index],
              ),
            ),
        ],
      );
      final headerStyle = Theme.of(context).textTheme.labelMedium;
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              Container(
                decoration: const BoxDecoration(
                  color: canvas,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 11,
                ),
                child: line(
                  headings
                      .map((heading) => Text(heading, style: headerStyle))
                      .toList(),
                ),
              ),
            for (var index = 0; index < rows.length; index++) ...[
              if (desktop || index > 0) const Divider(height: 1, color: border),
              Padding(
                key: ValueKey(rows[index].first.key ?? index),
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 6 : 14,
                  vertical: desktop ? 4 : 12,
                ),
                child: desktop
                    ? line(rows[index])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          rows[index].first,
                          const SizedBox(height: 8),
                          for (var cell = 1; cell < headings.length - 1; cell++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(headings[cell], style: headerStyle),
                                  rows[index][cell],
                                ],
                              ),
                            ),
                          rows[index].last,
                        ],
                      ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _ServicePricePicker extends StatefulWidget {
  const _ServicePricePicker({
    required this.load,
    required this.used,
    required this.availableSlots,
    required this.linking,
  });
  final Future<List<PricingRow>> Function() load;
  final Set<Object?> used;
  final int availableSlots;
  final bool linking;

  @override
  State<_ServicePricePicker> createState() => _ServicePricePickerState();
}

class _ServicePricePickerState extends State<_ServicePricePicker> {
  String search = '';
  String? selectionError;
  final selected = <Object?, PricingRow>{};
  late Future<List<PricingRow>> feed = widget.load();

  void toggle(PricingRow row, bool checked) {
    setState(() {
      selectionError = null;
      if (!checked) {
        selected.remove(row['id']);
        return;
      }
      if (selected.length >= widget.availableSlots) {
        selectionError = widget.linking
            ? 'Clear the current selection first.'
            : 'You can add up to ${widget.availableSlots} more services.';
        return;
      }
      if (selected.values.any(
        (other) => serviceNameKey(other) == serviceNameKey(row),
      )) {
        selectionError = 'A service with this name is already selected.';
        return;
      }
      selected[row['id']] = row;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PricingRow>>(
    future: feed,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      final matches = rows.where((row) => matchesService(row, search)).toList();
      final loaded =
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError;
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: serviceDialogShape,
        title: Text(widget.linking ? 'Link catalogue price' : 'Add services'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.linking)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Select services to include in this package.',
                    style: TextStyle(color: muted),
                  ),
                ),
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else if (snapshot.hasError) ...[
                const Text('Unable to load services. Please try again.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      final next = widget.load();
                      setState(() {
                        feed = next;
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ),
              ] else if (rows.isEmpty)
                const Text('No services are available yet.')
              else ...[
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search services...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => search = value),
                ),
                const SizedBox(height: 8),
                if (matches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('No matching services found.'),
                  )
                else
                  SizedBox(
                    height: (matches.length * 72.0).clamp(0, 288).toDouble(),
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final row = matches[index];
                        final added = widget.used.contains(row['id']);
                        final active = row['active'] == true;
                        return CheckboxListTile(
                          key: ValueKey(row['id']),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(row['name']),
                          subtitle: Text(
                            added
                                ? 'Added · ${serviceCategory(row)}'
                                : !active
                                ? 'Inactive · ${serviceCategory(row)}'
                                : pickerPrice(row),
                          ),
                          value: added || selected.containsKey(row['id']),
                          onChanged: added || !active
                              ? null
                              : (checked) => toggle(row, checked == true),
                        );
                      },
                    ),
                  ),
              ],
              if (selectionError != null)
                Text(
                  selectionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (loaded && !widget.linking && selected.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, <PricingRow>[]),
                    child: const Text('Create new service'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (loaded && !widget.linking)
            Text(
              '${selected.length} selected',
              style: const TextStyle(color: muted),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (loaded && rows.isNotEmpty)
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.values.toList()),
              child: Text(
                widget.linking
                    ? 'Use selected price'
                    : 'Add selected (${selected.length})',
              ),
            ),
        ],
      );
    },
  );
}

class _ServiceConfiguration {
  const _ServiceConfiguration(this.price, this.deduction);
  final PricingRow? price;
  final int? deduction;
}

class _ServiceConfigurationDialog extends StatefulWidget {
  const _ServiceConfigurationDialog({
    required this.service,
    required this.entry,
    required this.choose,
  });
  final PricingRow service;
  final PricingRow? entry;
  final Future<List<PricingRow>?> Function() choose;

  @override
  State<_ServiceConfigurationDialog> createState() =>
      _ServiceConfigurationDialogState();
}

class _ServiceConfigurationDialogState
    extends State<_ServiceConfigurationDialog> {
  late final deduction = TextEditingController(
    text: ((widget.service['priceCents'] as int? ?? 0) / 100).toStringAsFixed(
      2,
    ),
  );
  PricingRow? price;
  String? error;
  bool get removable => widget.service['kind'] == 'Optional';

  @override
  void dispose() {
    deduction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = price ?? widget.entry;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: serviceDialogShape,
      scrollable: true,
      title: Text(widget.service['name']),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry == null
                  ? 'Price configuration required'
                  : "${entry['name']} · ${packageMoney(entry['priceCents'])} / ${priceUnit(entry)}",
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final selected = await widget.choose();
                  if (mounted && selected != null && selected.isNotEmpty) {
                    setState(() => price = selected.single);
                  }
                },
                child: Text(
                  entry == null
                      ? 'Link a catalogue price'
                      : 'Change linked price',
                ),
              ),
            ),
            if (removable) ...[
              const Text('Removal deduction (RM)'),
              const SizedBox(height: 6),
              TextField(
                controller: deduction,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = minorUnits(deduction.text);
            if (removable && value == null) {
              setState(() => error = 'Enter a valid removal deduction.');
              return;
            }
            Navigator.pop(
              context,
              _ServiceConfiguration(price, removable ? value : null),
            );
          },
          child: const Text('Apply configuration'),
        ),
      ],
    );
  }
}

class _ServiceCataloguePage extends StatefulWidget {
  const _ServiceCataloguePage({required this.load, required this.editPrice});
  final Future<List<PricingRow>> Function() load;
  final Future<PricingRow?> Function(PricingRow) editPrice;

  @override
  State<_ServiceCataloguePage> createState() => _ServiceCataloguePageState();
}

class _ServiceCataloguePageState extends State<_ServiceCataloguePage> {
  late Future<List<PricingRow>> feed = widget.load();
  String search = '';
  String? category;

  Future<void> edit(PricingRow row, List<PricingRow> rows) async {
    final result = await widget.editPrice(row);
    if (mounted && result != null) {
      final updated = [
        ...rows.where((existing) => existing['id'] != result['id']),
        result,
      ]..sort((a, b) => serviceNameKey(a).compareTo(serviceNameKey(b)));
      setState(() {
        feed = Future.value(updated);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: canvas,
    appBar: AppBar(title: const Text('Service catalogue')),
    body: FutureBuilder<List<PricingRow>>(
      future: feed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load services. Please try again.'),
                TextButton(
                  onPressed: () {
                    final next = widget.load();
                    setState(() {
                      feed = next;
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final rows = snapshot.data ?? [];
        final allowanceId = _ServicePricingEditorState.standardAllowanceId;
        final normal = rows.where((row) => row['id'] != allowanceId).toList();
        final categories = normal.map(serviceCategory).toSet().toList()..sort();
        final selectedCategory = categories.contains(category)
            ? category
            : null;
        final matches = normal
            .where(
              (row) =>
                  matchesService(row, search) &&
                  (selectedCategory == null ||
                      selectedCategory == serviceCategory(row)),
            )
            .toList();
        final allowance = rows
            .where((row) => row['id'] == allowanceId)
            .firstOrNull;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Service catalogue',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage the standard rates and availability used by new package configurations.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => edit({}, rows),
                      icon: const Icon(Icons.add),
                      label: const Text('Create service'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          edit(allowance ?? {'id': allowanceId}, rows),
                      child: const Text('Standard gown allowance'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                PackageEditorSection(
                  title: 'Catalogue services',
                  icon: Icons.list_alt_outlined,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 300,
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search services...',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (value) =>
                                setState(() => search = value),
                          ),
                        ),
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<String>(
                            initialValue: categories.contains(category)
                                ? category
                                : null,
                            isExpanded: true,
                            hint: const Text(
                              'All categories',
                              overflow: TextOverflow.ellipsis,
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'All categories',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (final value in categories)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => category = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (matches.isEmpty)
                      Text(
                        normal.isEmpty
                            ? 'No services are available yet.'
                            : 'No matching services found.',
                      )
                    else
                      _ServiceGrid(
                        headings: const [
                          'Service',
                          'Category',
                          'Standard price',
                          'Pricing method',
                          'Status',
                          'Actions',
                        ],
                        flexes: const [24, 22, 16, 17, 12, 9],
                        rows: [
                          for (final row in matches)
                            [
                              Text(
                                row['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(serviceCategory(row)),
                              Text(packageMoney(row['priceCents'])),
                              Text(
                                row['method'] == 'fixed'
                                    ? 'Fixed · per ${priceUnit(row)}'
                                    : 'Per ${priceUnit(row)}',
                              ),
                              Pill(
                                row['active'] == true ? 'Active' : 'Inactive',
                              ),
                              IconButton(
                                tooltip: 'Edit ${row['name']}',
                                onPressed: () => edit(row, rows),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                            ],
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
