import 'dart:async';

import 'package:flutter/material.dart';

import '../payments/payment_api.dart';
import '../src/design.dart' show CustomerUi;
import '../support/assistant_launcher.dart';
import 'accessory_catalogue.dart';
import 'package_api.dart';
import 'package_gowns.dart';
import 'rental_availability.dart';
import 'rental_date_fields.dart';

const _veil = PackageServiceItem(
  id: 'custom-veil',
  name: 'Veil rental',
  description: '',
  kind: 'Add-on',
  priceCents: 0,
  serviceType: PackageServiceType.itemVeil,
);
const _accessories = PackageServiceItem(
  id: 'custom-accessories',
  name: 'Bridal accessories',
  description: '',
  kind: 'Add-on',
  priceCents: 0,
  serviceType: PackageServiceType.itemAccessories,
);

class CustomPackageBuilder extends StatefulWidget {
  const CustomPackageBuilder({super.key, required this.api, this.selection});
  final HttpPackageApi api;
  final PackageSelection? selection;

  @override
  State<CustomPackageBuilder> createState() => _CustomPackageBuilderState();
}

class _CustomPackageBuilderState extends State<CustomPackageBuilder> {
  late final String requestId = packageRequestId();
  late Future<void> loading = load();
  List<Map<String, dynamic>> options = [];
  final quantities = <String, int>{};
  final unavailableServices = <String, String>{};
  int maxGowns = 0, gownCount = 0;
  List<PackageGownChoice> gowns = [];
  Map<String, String> dates = {};
  final items = <String, Set<String>>{};
  late AccessoryCatalogue catalogue;
  RentalAvailability? stock;
  String? error;
  bool busy = false;
  Map<String, dynamic>? quote;
  Timer? quoteTimer;
  int quoteRevision = 0, step = 0;
  bool estimating = false;
  String? estimateError;

  static const stages = [
    'Wedding or event date',
    'Wedding gowns',
    'Bridal services',
    'Veil & accessories',
    'Review',
  ];
  static const instructions = [
    'Start with your wedding or event date.',
    'Choose a style and size for each gown you want to rent.',
    'Add the services you want for your wedding.',
    'Choose a veil or accessories to complete your look.',
    'Check your dates, selection and quoted prices before saving.',
  ];

  HttpPackageApi get api => widget.api;
  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async => Map<String, dynamic>.from(
    await api.transport.businessRequest(path, body: body),
  );

  Future<void> load() async {
    final results = await Future.wait([
      request('/v1/custom-package-options'),
      AccessoryCatalogue.load(),
    ]);
    final configuration = results[0] as Map<String, dynamic>;
    catalogue = results[1] as AccessoryCatalogue;
    if (catalogue.version != configuration['accessoryCatalogueVersion']) {
      throw const PaymentFailure(
        'Update Luvly to use the latest accessory catalogue.',
      );
    }
    maxGowns = configuration['maxGowns'];
    options = (configuration['services'] as List).cast<Map<String, dynamic>>();
    final old = widget.selection?.data;
    if (old == null) return;
    final savedGowns = old['selectedGowns'] as List? ?? [];
    final dresses = savedGowns.isEmpty ? const [] : await api.gowns();
    for (final row in savedGowns) {
      final dress = dresses.where((d) => d.id == row['dressId']).firstOrNull;
      if (dress != null) gowns.add(PackageGownChoice(dress, row['size']));
    }
    gownCount = old['includedGownCount'];
    dates = Map<String, String>.from(old['rentalPlan'] ?? {});
    for (final row in old['customServices'] as List) {
      if (options.any((option) => option['id'] == row['id'])) {
        quantities[row['id']] = row['quantity'];
      } else {
        final previous = (old['services'] as List? ?? [])
            .where((service) => service['id'] == row['id'])
            .firstOrNull;
        unavailableServices[row['id']] =
            previous?['name'] ?? 'Previously selected service';
      }
    }
    for (final row in old['selectedAccessories'] as List? ?? []) {
      items.putIfAbsent(row['serviceId'], () => {}).add(row['id']);
    }
    if (mounted) scheduleQuote();
  }

  bool eligible(Map<String, dynamic> row) =>
      gownCount > 0 || row['standaloneEligible'] == true;
  bool get eventReady => DateTime.tryParse(dates['eventDate'] ?? '') != null;
  bool get hasSelection => gownCount > 0 || selectedServices.isNotEmpty;
  Map<String, String> get selectedDates =>
      gownCount == 0 ? {'eventDate': dates['eventDate']!} : dates;

  String unit(Map<String, dynamic> row) => switch (row['method']) {
    'per-session' => 'Per session',
    'per-day' => 'Per day',
    'per-gown' => 'Per gown',
    _ => switch (row['serviceType']) {
      'makeup-hair' || 'second-beauty-look' => 'Per look',
      'makeup-trial' => 'Per trial',
      _ => 'Per service',
    },
  };
  List<Map<String, dynamic>> get selectedServices => [
    for (final entry in options)
      if (eligible(entry) && quantities.containsKey(entry['id']))
        {
          'id': entry['id'],
          'revision': entry['revision'],
          'quantity': quantities[entry['id']],
        },
  ];

  int get rentalDays =>
      3 +
      options
          .where(
            (entry) =>
                quantities.containsKey(entry['id']) &&
                entry['serviceType'] == 'extra-rental-day',
          )
          .length;

  Map<String, dynamic> get input => {
    'requestId': requestId,
    'packageId': 'custom-bridal',
    'revision': 1,
    'removedIds': <String>[],
    'addonIds': gownCount == 0 ? <String>[] : items.keys.toList(),
    'customServices': selectedServices,
    'rentalPlan': selectedDates,
    'gowns': gowns.map((g) => g.toJson()).toList(),
    'accessoryCatalogueVersion': catalogue.version,
    'accessories': [
      if (gownCount > 0)
        for (final entry in items.entries)
          for (final id in entry.value) {'serviceId': entry.key, 'itemId': id},
    ],
  };

  Future<RentalAvailability> availability() async => RentalAvailability(
    await request('/v1/package-availability', {
      'packageId': 'custom-bridal',
      'revision': 1,
      'rentalPlan': dates,
      'customServices': selectedServices,
    }),
  );

  bool get datesReady =>
      eventReady &&
      (gownCount == 0 ||
          [
            'eventDate',
            'pickupDate',
            'returnDate',
          ].every((key) => DateTime.tryParse(dates[key] ?? '') != null));
  bool get gownsReady =>
      gowns.length == gownCount && gowns.every((g) => g.size.isNotEmpty);
  bool get accessoriesReady =>
      gownCount == 0 || items.values.every((selection) => selection.isNotEmpty);

  void change(VoidCallback update) {
    setState(() {
      update();
      error = null;
    });
    scheduleQuote();
  }

  Future<Map<String, dynamic>> fetchQuote() {
    final old = widget.selection;
    return old == null
        ? request('/v1/custom-package-quote', input)
        : request(
            '/v1/package-selections/${old.id}/revise',
            revisionInput(true),
          );
  }

  void scheduleQuote() {
    final revision = ++quoteRevision;
    quoteTimer?.cancel();
    setState(() {
      quote = null;
      estimateError = null;
      estimating =
          hasSelection &&
          datesReady &&
          gownsReady &&
          accessoriesReady &&
          unavailableServices.isEmpty;
    });
    if (!estimating) return;
    quoteTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await fetchQuote();
        if (mounted && revision == quoteRevision) {
          setState(() => quote = result);
        }
      } catch (failure) {
        if (mounted && revision == quoteRevision) {
          setState(
            () => estimateError = failure is PaymentFailure
                ? failure.message
                : 'Could not calculate the quote. Try reviewing again.',
          );
        }
      } finally {
        if (mounted && revision == quoteRevision) {
          setState(() => estimating = false);
        }
      }
    });
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not check your selection. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseEvent() async {
    final malaysia = DateTime.now().toUtc().add(const Duration(hours: 8));
    final first = DateTime(malaysia.year, malaysia.month, malaysia.day);
    final last = DateTime(first.year, first.month, first.day + 365);
    final current = DateTime.tryParse(dates['eventDate'] ?? '');
    final selected = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate:
          current != null && !current.isBefore(first) && !current.isAfter(last)
          ? current
          : first,
    );
    if (!mounted ||
        selected == null ||
        rentalDateText(selected) == dates['eventDate']) {
      return;
    }
    change(() {
      dates = {'eventDate': rentalDateText(selected)};
      stock = null;
    });
  }

  Future<void> chooseDates() async {
    final selected = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PackageDatesScreen(initialDates: dates, allowedDays: rentalDays),
      ),
    );
    if (selected != null && mounted) {
      change(() {
        dates = selected;
        stock = null;
      });
    }
  }

  Future<void> chooseGowns() async {
    final available = stock ?? await availability();
    if (!mounted) return;
    stock = available;
    final selected = await Navigator.push<List<PackageGownChoice>>(
      context,
      MaterialPageRoute(
        builder: (_) => PackageGownPicker(
          api: api,
          eligibleIds: const {},
          allCatalogueGowns: true,
          initial: gowns,
          allowance: gownCount,
          availability: available,
          rentalPlan: dates,
        ),
      ),
    );
    if (selected != null && mounted) change(() => gowns = selected);
  }

  Future<void> chooseAccessories(PackageServiceItem service) async {
    final available = stock ?? await availability();
    if (!mounted) return;
    stock = available;
    final selected = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AccessoryBrowser(
          catalogue: catalogue,
          service: service,
          initial: items[service.id] ?? {},
          availability: available.accessories,
        ),
      ),
    );
    if (selected != null && mounted) change(() => items[service.id] = selected);
  }

  Map<String, dynamic> revisionInput(bool preview) {
    final old = widget.selection!.data;
    return {
      ...input,
      'revision': old['selectionRevision'] ?? 0,
      'packageRevision': 1,
      'planRevision': old['rentalPlanRevision'] ?? 0,
      'previewOnly': preview,
      if (!preview) 'expectedTotalCents': quote!['totalCents'],
    };
  }

  void goTo(int index, {String? message}) => setState(() {
    step = index;
    error = message;
  });

  Future<void> next() async {
    if (!eventReady) {
      goTo(0, message: 'Choose your wedding or event date.');
    } else if (step >= 1 && !datesReady) {
      goTo(1, message: 'Choose pickup and return dates for your gowns.');
    } else if (step >= 1 && !gownsReady) {
      goTo(1, message: 'Select all $gownCount gowns and confirm their sizes.');
    } else if (step >= 2 && unavailableServices.isNotEmpty) {
      goTo(2, message: 'Remove the unavailable service to continue.');
    } else if (step >= 2 && !hasSelection) {
      goTo(
        2,
        message: 'Choose at least one gown or an eligible standalone service.',
      );
    } else if (step == 3 && !accessoriesReady) {
      goTo(
        3,
        message: items[_veil.id]?.isEmpty == true
            ? 'Choose a veil or turn off veil rental.'
            : 'Choose at least one accessory or turn off bridal accessories.',
      );
    } else if (step < 3) {
      goTo(step + 1);
    } else {
      quoteTimer?.cancel();
      quoteRevision++;
      setState(() {
        quote = null;
        estimating = false;
        estimateError = null;
      });
      final result = await fetchQuote();
      if (mounted) {
        setState(() {
          quote = result;
          step = 4;
        });
      }
    }
  }

  @override
  void dispose() {
    quoteTimer?.cancel();
    super.dispose();
  }

  Future<void> save() async {
    final old = widget.selection;
    if (old == null) {
      await request('/v1/package-selections', {
        ...input,
        'quoteId': quote!['quoteId'],
        'expectedTotalCents': quote!['totalCents'],
      });
    } else {
      await request(
        '/v1/package-selections/${old.id}/revise',
        revisionInput(false),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget quoteLines(Map<String, dynamic> result) {
    final pricing = result['pricingSnapshot'] as Map;
    return Column(
      children: [
        for (final line in [
          ...pricing['gownLines'] as List,
          ...pricing['lines'] as List,
          ...pricing['selectedAccessories'] as List,
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(line['name']),
            subtitle: line['size'] is String
                ? Text('Size ${line['size']}')
                : line['quantity'] is int
                ? Text('Quantity: ${line['quantity']}')
                : null,
            trailing: Text(
              packageMoney(line['amountCents'] ?? line['priceCents']),
            ),
          ),
      ],
    );
  }

  List<Widget> stageContent() => switch (step) {
    0 => [
      OutlinedButton.icon(
        onPressed: busy ? null : chooseEvent,
        icon: const Icon(Icons.event_outlined),
        label: Text(
          eventReady
              ? rentalDateLabel(dates['eventDate']!)
              : 'Choose event date',
        ),
      ),
    ],
    1 => [
      Text('${gowns.length} of $gownCount gowns selected'),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        initialValue: gownCount,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Number of gowns'),
        items: [
          const DropdownMenuItem(
            value: 0,
            child: Text('0 — No wedding gown rental'),
          ),
          for (var count = 1; count <= maxGowns; count++)
            DropdownMenuItem(value: count, child: Text('$count')),
        ],
        onChanged: busy
            ? null
            : (count) => change(() {
                gownCount = count!;
                gowns = gowns.take(gownCount).toList();
                stock = null;
              }),
      ),
      const SizedBox(height: 12),
      if (gownCount == 0)
        const Text(
          'No wedding gown needed? Continue to choose bridal services.',
        )
      else ...[
        PackageRentalDatesCard(
          dates: datesReady ? dates : null,
          onEdit: busy ? null : chooseDates,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy || !datesReady ? null : () => run(chooseGowns),
          child: Text(
            gowns.isEmpty ? 'Choose gowns and sizes' : 'Edit gowns and sizes',
          ),
        ),
        for (final gown in gowns)
          ListTile(
            title: Text(gown.dress.name),
            subtitle: Text(gown.size),
            trailing: Text(gown.dress.priceLabel),
          ),
      ],
    ],
    2 => [
      for (final service in unavailableServices.entries)
        ListTile(
          title: Text(service.value),
          subtitle: const Text('No longer offered for custom packages'),
          trailing: TextButton(
            onPressed: busy
                ? null
                : () => change(() => unavailableServices.remove(service.key)),
            child: const Text('Remove'),
          ),
        ),
      if (options.isEmpty)
        const Text(
          'No bridal services are currently offered for custom packages.',
        ),
      for (final row in options) ...[
        CheckboxListTile(
          title: Text(row['name']),
          subtitle: Text(
            [
              if ((row['description'] as String?)?.isNotEmpty == true)
                row['description'],
              '${packageMoney(row['priceCents'])} · ${unit(row)}',
              if (!eligible(row))
                'Requires gown rental'
              else if (row['standaloneEligible'] == true)
                'Available without gown rental',
            ].join('\n'),
          ),
          value: eligible(row) && quantities.containsKey(row['id']),
          onChanged: busy || !eligible(row)
              ? null
              : (checked) => change(() {
                  if (checked == true) {
                    quantities[row['id']] = 1;
                  } else {
                    quantities.remove(row['id']);
                  }
                  stock = null;
                }),
        ),
        if (eligible(row) &&
            row['method'] == 'per-session' &&
            quantities.containsKey(row['id']))
          DropdownButtonFormField<int>(
            key: ValueKey(row['id']),
            initialValue: quantities[row['id']],
            decoration: const InputDecoration(labelText: 'Sessions'),
            items: [
              for (var count = 1; count <= 12; count++)
                DropdownMenuItem(value: count, child: Text('$count')),
            ],
            onChanged: busy
                ? null
                : (count) => change(() => quantities[row['id']] = count!),
          ),
      ],
    ],
    3 => [
      if (gownCount == 0)
        const Text('Veils and accessories are available with a gown rental.')
      else
        for (final service in [_veil, _accessories]) ...[
          CheckboxListTile(
            title: Text(service.name),
            value: items.containsKey(service.id),
            onChanged: busy
                ? null
                : (checked) => change(() {
                    if (checked == true) {
                      items[service.id] = {};
                    } else {
                      items.remove(service.id);
                    }
                  }),
          ),
          if (items[service.id] case final selected?)
            OutlinedButton(
              onPressed: dates.isEmpty || busy
                  ? null
                  : () => run(() => chooseAccessories(service)),
              child: Text(
                selected.isEmpty
                    ? 'Choose ${service.name.toLowerCase()}'
                    : '${selected.length} selected · ${packageMoney(catalogue.subtotal(selected))}',
              ),
            ),
        ],
    ],
    _ => [
      if (gownCount == 0)
        Text('Event date · ${rentalDateLabel(dates['eventDate']!)}')
      else
        PackageRentalDatesCard(dates: dates),
      const SizedBox(height: 12),
      if (quote case final result?) quoteLines(result),
      const Divider(),
      Text(
        gownCount == 0
            ? 'Save your service quote. Appointment arrangements are handled separately.'
            : 'Save your selection to arrange a fitting. The refundable gown security deposit is charged separately during booking.',
      ),
    ],
  };

  Widget quoteSummary() => DecoratedBox(
    decoration: CustomerUi.tintedCard,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Estimated price breakdown',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (quote case final result?) ...[
            quoteLines(result),
            const Divider(),
            Text(
              packageMoney(result['totalCents']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ] else if (estimating)
            const Text('Checking availability and prices…')
          else if (estimateError != null) ...[
            Text(
              estimateError!,
              style: const TextStyle(color: CustomerUi.error),
            ),
            TextButton(
              onPressed: busy ? null : scheduleQuote,
              child: const Text('Retry quote'),
            ),
          ] else
            const Text(
              'Choose dates, gowns and any enabled accessories to see your quote.',
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: loading,
    builder: (context, state) {
      final ready =
          state.connectionState == ConnectionState.done && !state.hasError;
      return PopScope(
        canPop: step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !busy && step > 0) goTo(step - 1);
        },
        child: Scaffold(
          backgroundColor: CustomerUi.canvas,
          appBar: AppBar(
            leading: step == 0
                ? null
                : BackButton(onPressed: busy ? () {} : () => goTo(step - 1)),
            title: const AssistantExclusion(
              child: Text('Build your bridal package'),
            ),
            actions: const [AssistantAppBarAction()],
          ),
          body: !ready
              ? Center(
                  child: state.hasError
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                packagePricingLoadError(
                                  state.error,
                                  unavailable:
                                      'Could not load the custom package options.',
                                  updateRequired:
                                      'Custom packages will be available after Luvly updates its booking service.',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => loading = load()),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(
                      key: ValueKey(step),
                      padding: const EdgeInsets.all(CustomerUi.pageInset),
                      children: [
                        Text(
                          'Step ${step + 1} of ${stages.length}',
                          style: const TextStyle(color: CustomerUi.activeText),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (step + 1) / stages.length,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          stages[step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          instructions[step],
                          style: const TextStyle(
                            color: CustomerUi.secondaryText,
                          ),
                        ),
                        const SizedBox(height: CustomerUi.sectionSpacing),
                        DecoratedBox(
                          decoration: CustomerUi.softCard,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: stageContent(),
                            ),
                          ),
                        ),
                        if (step < 4) ...[
                          const SizedBox(height: CustomerUi.sectionSpacing),
                          quoteSummary(),
                        ],
                      ],
                    ),
                  ),
                ),
          bottomNavigationBar: ready
              ? DecoratedBox(
                  decoration: const BoxDecoration(
                    color: CustomerUi.paper,
                    border: Border(top: BorderSide(color: CustomerUi.divider)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                error!,
                                style: const TextStyle(color: CustomerUi.error),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (quote case final result?)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    step == 4
                                        ? 'Package total'
                                        : 'Estimated total',
                                  ),
                                ),
                                Text(
                                  packageMoney(result['totalCents']),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => run(step == 4 ? save : next),
                            child: Text(
                              busy
                                  ? 'Please wait…'
                                  : step == 4
                                  ? 'Save selection'
                                  : step == 3
                                  ? 'Review selection'
                                  : 'Continue',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
        ),
      );
    },
  );
}
