import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'catalogue_repository.dart';
import 'gown_measurements.dart';
import 'stock_filters.dart';
import '../shared/list_controls.dart';

class VariantStockScreen extends StatefulWidget {
  const VariantStockScreen({super.key, required this.dress, this.api});
  final CatalogueDress dress;
  final HttpPaymentApi? api;
  @override
  State<VariantStockScreen> createState() => _VariantStockScreenState();
}

class _VariantStockScreenState extends State<VariantStockScreen> {
  late final api = widget.api ?? HttpPaymentApi();
  List<Map<String, dynamic>>? variants;
  String? error;
  bool busy = false;
  String query = '', quantityFilter = 'All quantities';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await api.businessRequest(
        '/v1/rental-variants?dressId=${Uri.encodeQueryComponent(widget.dress.id)}',
      );
      if (mounted) {
        setState(
          () => variants = (response['variants'] as List)
              .map((v) => Map<String, dynamic>.from(v))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not load stock. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Map<String, dynamic> variant) async {
    final controller = TextEditingController(
      text: variant['quantity']?.toString() ?? '',
    );
    final form = GlobalKey<FormState>();
    final count = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Size ${variant['size']} stock'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the actual total number of physical gowns in this size, including reserved items. Do not guess missing quantities.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total quantity'),
                validator: (v) =>
                    v != null &&
                        RegExp(r'^\d{1,3}$').hasMatch(v) &&
                        int.parse(v) <= 100
                    ? null
                    : 'Enter a whole number from 0 to 100.',
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
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(controller.text));
              }
            },
            child: const Text('Save quantity'),
          ),
        ],
      ),
    );
    // Dialog route can still be animating while its field disposes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (count == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    bool saved = false;
    try {
      await api.businessRequest(
        '/v1/rental-variants',
        body: {
          'dressId': widget.dress.id,
          'size': variant['size'],
          'quantity': count,
          'revision': variant['revision'],
        },
      );
      saved = true;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save stock. Refresh before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (saved && mounted) await load();
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> editMeasurements(Map<String, dynamic> variant) async {
    final old = variant['measurements'] as Map?;
    final fields = {
      for (final key in measurementKeys)
        key: TextEditingController(text: old?[key]?.toString() ?? ''),
    };
    final measurementForm = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Size ${variant['size']} measurements'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: measurementForm,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter the body-measurement ranges this gown size can accommodate, based on verified fitting or supplier information. Gown length is the garment length. Use cm; do not guess.',
                  ),
                  const SizedBox(height: 16),
                  for (final key in measurementKeys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: fields[key],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${measurementLabels[measurementKeys.indexOf(key)]} (cm)',
                        ),
                        validator: (v) {
                          final value = measurementNumber(v ?? '');
                          if (value == null) {
                            return 'Enter 20–300 cm, with up to 1 decimal.';
                          }
                          if (key.endsWith('Max')) {
                            final min = measurementNumber(
                              fields[key.replaceFirst('Max', 'Min')]!.text,
                            );
                            if (min != null && value < min) {
                              return 'Maximum must be at least the minimum.';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          if (old != null)
            TextButton(
              onPressed: () => Navigator.pop(c, {'measurements': null}),
              child: const Text('Clear measurements'),
            ),
          FilledButton(
            onPressed: () {
              if (measurementForm.currentState!.validate()) {
                Navigator.pop(c, {
                  'measurements': fields.map(
                    (k, v) => MapEntry(k, measurementNumber(v.text)!),
                  ),
                });
              }
            },
            child: const Text('Save measurements'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final field in fields.values) {
      field.dispose();
    }
    if (result == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    bool saved = false;
    try {
      await api.businessRequest(
        '/v1/rental-variants',
        body: {
          'dressId': widget.dress.id,
          'size': variant['size'],
          'quantity': variant['quantity'],
          'revision': variant['revision'],
          'measurements': result['measurements'],
        },
      );
      saved = true;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not save measurements. Refresh and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (saved && mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Stock by size'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh stock',
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.dress.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Not configured is different from zero stock. Size quantities cannot be reduced below active reservations. Availability on a particular date is checked separately.',
            ),
            const SizedBox(height: 16),
            ListSearchField(
              value: query,
              hint: 'Search size',
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ListFilterSelect(
                  label: 'Stock quantity',
                  value: quantityFilter,
                  options: stockQuantityFilters,
                  onChanged: (v) => setState(() => quantityFilter = v),
                ),
                if (query.isNotEmpty || quantityFilter != 'All quantities')
                  ResetListFilters(
                    onReset: () => setState(() {
                      query = '';
                      quantityFilter = 'All quantities';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (variants != null &&
                !variants!.any(
                  (v) =>
                      matchesListSearch(query, [v['size']]) &&
                      matchesStockQuantity(v, quantityFilter),
                ))
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No sizes match your search and filters.'),
              ),
            for (final v in (variants ?? <Map<String, dynamic>>[]).where(
              (v) =>
                  matchesListSearch(query, [v['size']]) &&
                  matchesStockQuantity(v, quantityFilter),
            ))
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Size ${v['size']}'),
                      subtitle: Text(
                        v['size'] == 'Made to measure'
                            ? 'Custom order — not ready-stock inventory'
                            : v['quantity'] == null
                            ? 'Not configured'
                            : '${v['quantity']} total physical gowns',
                      ),
                      trailing: v['size'] == 'Made to measure'
                          ? null
                          : TextButton(
                              onPressed: busy ? null : () => edit(v),
                              child: const Text('Edit quantity'),
                            ),
                    ),
                    if (v['size'] != 'Made to measure')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v['measurements'] == null
                                  ? 'Measurements not provided'
                                  : measurementSourceLabel(v),
                            ),
                            TextButton(
                              onPressed: busy || v['quantity'] == null
                                  ? null
                                  : () => editMeasurements(v),
                              child: const Text('Edit measurements'),
                            ),
                            if (v['quantity'] == null)
                              const Text(
                                'Set the actual stock quantity before adding measurements.',
                                style: TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
