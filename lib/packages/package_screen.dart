import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../bookings/booking_screens.dart';
import '../bookings/booking_repository.dart';
import '../payments/payment_api.dart';
import '../payments/payment_screen.dart';
import '../src/model.dart';
import '../src/design.dart' show CustomerUi, blush;
import 'package_api.dart';
import 'rental_availability.dart';
import 'rental_date_fields.dart';
import 'package_gowns.dart';
import 'package_presentation.dart';
import 'accessory_catalogue.dart';
import 'package_rental_screen.dart';
import 'rental_workspace.dart';
import 'staff_rental_details.dart';
import 'package_filters.dart';
import 'customer_package_card.dart';
import 'customer_package_details.dart';
import 'staff_package_catalogue.dart';
import 'package_editor.dart';
import '../shared/list_controls.dart';
import '../support/assistant_launcher.dart';
export 'rental_workspace.dart' show customerRentalStage;
export 'package_editor.dart' show PackageEditor, serviceCents;

String packageError(Object error) => error is PaymentFailure
    ? error.message
    : 'Could not save these details. Please try again.';

class LivePackageScreen extends StatefulWidget {
  const LivePackageScreen({
    super.key,
    this.staff = false,
    this.manager = false,
    this.initialSelections = false,
    this.initialSelectionId,
    this.openInitialSelection = false,
    this.initialPackageId,
    this.api,
    this.profileWorkspace = false,
  });
  final bool staff, manager, initialSelections;
  final bool profileWorkspace;
  final String? initialSelectionId;
  final bool openInitialSelection;
  final String? initialPackageId;
  final PackageApi? api;
  @override
  State<LivePackageScreen> createState() => _LivePackageState();
}

class _LivePackageState extends State<LivePackageScreen> {
  late final PackageApi api;
  late bool selectedTab;
  late Future<(List<BridalPackage>, List<PackageSelection>)> feed;
  String search = '';
  String selectionQuery = '',
      selectionStage = 'All packages',
      priceBand = 'All prices';
  String catalogueStatus = 'All', rentalStatus = 'All';
  bool get canManage => widget.staff && widget.manager;
  bool get rentalWorkspace => widget.staff && selectedTab;
  String? focusedSelection;
  bool initialSelectionOpened = false;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    api = widget.api ?? HttpPackageApi();
    selectedTab = widget.profileWorkspace || widget.initialSelections;
    focusedSelection = widget.initialSelectionId;
    feed = load();
  }

  Future<(List<BridalPackage>, List<PackageSelection>)> load() async {
    if (!api.configured) return (<BridalPackage>[], <PackageSelection>[]);
    if (widget.profileWorkspace) {
      return (<BridalPackage>[], await api.selections());
    }
    // Staff workspaces are independent: a failed order request must not hide
    // the catalogue, and viewing orders must not fetch the catalogue.
    if (widget.staff) {
      return selectedTab
          ? (<BridalPackage>[], await api.selections())
          : (await api.catalogue(), <PackageSelection>[]);
    }
    final values = await Future.wait([api.catalogue(), api.selections()]);
    return (
      values[0] as List<BridalPackage>,
      values[1] as List<PackageSelection>,
    );
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  void reload() {
    if (!mounted) return;
    final next = load();
    setState(() {
      feed = next;
    });
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
    } catch (error) {
      message(packageError(error));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  Future<void> edit([BridalPackage? package]) async {
    if (!canManage) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PackageEditor(api: api, package: package),
      ),
    );
    if (saved == true) {
      message('Package saved.');
      reload();
    }
  }

  Future<void> view(BridalPackage package) async {
    if (widget.staff) {
      await showStaffPackageDetails(context, package);
      return;
    }
    PackageSelection? created;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PackageChoiceScreen(
          package: package,
          api: api,
          readOnly: widget.staff,
          onSelected: (selection) => created = selection,
        ),
      ),
    );
    if (saved == true && mounted) {
      final selection = created;
      setState(() {
        selectedTab = true;
        focusedSelection = selection?.id;
        selectionQuery = '';
        selectionStage = 'All packages';
      });
      reload();
      if (!widget.staff &&
          api is HttpPackageApi &&
          selection != null &&
          selection.selectedGowns.isNotEmpty) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PackageRentalScreen(
              selection: selection,
              api: api as HttpPackageApi,
              onBookFitting: (dates) => book(
                PackageSelection({
                  ...selection.data,
                  'rentalPlan': {...dates},
                }),
              ),
            ),
          ),
        );
        reload();
      } else {
        message('Your package is saved. You can now arrange an appointment.');
      }
    }
  }

  Future<void> toggle(BridalPackage p) async {
    if (!canManage) return;
    if (!p.active) {
      await edit(p);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deactivate package?'),
        content: const Text(
          'This package will be hidden from new selections. Existing customer selections and prices will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      await api.save(
        BridalPackage(
          id: p.id,
          name: p.name,
          description: p.description,
          basePriceCents: p.basePriceCents,
          revision: p.revision,
          active: false,
          services: p.services,
          includedGownCount: p.includedGownCount,
          eligibleDressIds: p.eligibleDressIds,
          allCatalogueGowns: p.allCatalogueGowns,
        ),
      );
      message('Package deactivated.');
    });
  }

  Future<void> remove(BridalPackage package) async {
    if (!canManage || api is! PackageDeletionApi || busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete package?'),
        content: Text(
          'Delete ${package.name} from the catalogue? Packages with customer records cannot be deleted; deactivate them instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      await (api as PackageDeletionApi).remove(package);
      message('Package deleted.');
    });
  }

  Future<bool> book(PackageSelection selection) async {
    final model = AppScope.of(context);
    final requestId = packageRequestId();
    var booked = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingRequestForm(
          uid: model.accountId!,
          name: model.name,
          phone: model.phone,
          packageName: selection.name,
          fittingIncluded: selection.data['rental']?['state'] == 'Locked',
          onSubmitted: () => booked = true,
          latestAppointmentDay:
              selection.data['rentalPlan']?['pickupDate'] is String
              ? DateTime.parse(
                  selection.data['rentalPlan']['pickupDate'],
                ).subtract(
                  Duration(
                    days:
                        selection.data['rental']?['state'] == 'Locked' &&
                            selection.data['rentalPlan']['pickupDate'] !=
                                selection.data['rentalPlan']['eventDate']
                        ? 0
                        : 1,
                  ),
                )
              : null,
          submitRequest: (type, start, notes) =>
              api.book(selection.id, type, start, notes, requestId),
        ),
      ),
    );
    reload();
    return booked;
  }

  Future<void> invoice(PackageSelection selection) async {
    final bookings = selection.appointments
        .where((b) => b['status'] == 'Confirmed')
        .toList();
    if (bookings.isEmpty) {
      message('Confirm the customer’s package appointment first.');
      return;
    }
    final appointmentId = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Issue invoice · ${packageMoney(selection.totalCents)}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${selection.customer}\n${selection.name}\nThe invoice uses the saved package total.',
            ),
          ),
          for (final b in bookings)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, b['id']),
              child: Text(
                'Confirm invoice for ${appointmentLabel(DateTime.fromMillisecondsSinceEpoch(b['startAt'], isUtc: true))}',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (appointmentId == null || !mounted) return;
    await run(() async {
      await api.invoice(selection.id, appointmentId);
      message(
        'Invoice issued. The customer can pay under Payments & receipts.',
      );
    });
  }

  void payments() => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) =>
              LivePaymentsScreen(staff: widget.staff, manager: widget.manager),
        ),
      )
      .then((_) => reload());

  Future<void> openRentalDetails(PackageSelection selection) =>
      showStaffRentalDetails(
        context,
        selection: selection,
        api: api,
        manager: widget.manager,
        onChanged: reload,
        onIssueInvoice: invoice,
      );

  Future<void> openCustomerDetails(PackageSelection selection) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerPackageDetails(
          selection: selection,
          api: api,
          onChanged: reload,
          onContinue: (s, step) => continueCustomer(s, step),
        ),
      ),
    );
    reload();
  }

  Future<void> continueCustomer(
    PackageSelection selection,
    CustomerPackageStep step, {
    bool recheck = false,
  }) async {
    var current = selection, next = step;
    if (recheck) {
      if (busy) return;
      setState(() => busy = true);
      try {
        final rows = await api.selections();
        final matches = rows.where((s) => s.id == selection.id);
        if (matches.length != 1) {
          throw const PaymentFailure(
            'This package could not be reloaded. Please refresh My packages.',
          );
        }
        current = matches.single;
        next = customerPackageStep(current);
      } catch (e) {
        message(packageError(e));
        return;
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    if (!mounted) return;
    switch (next.action) {
      case CustomerPackageAction.details:
      case CustomerPackageAction.proposal:
        await openCustomerDetails(current);
      case CustomerPackageAction.fitting:
        if (api is HttpPackageApi &&
            (current.selectedGowns.isNotEmpty ||
                (current.data['selectedAccessories'] as List? ?? [])
                    .isNotEmpty)) {
          final selected = current;
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => PackageRentalScreen(
                selection: selected,
                api: api as HttpPackageApi,
                onBookFitting: (dates) => book(
                  PackageSelection({
                    ...selected.data,
                    'rentalPlan': {...dates},
                  }),
                ),
              ),
            ),
          );
        } else {
          await book(current);
        }
      case CustomerPackageAction.includedFitting:
        await book(current);
      case CustomerPackageAction.payment:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LivePaymentsScreen(initialInvoiceId: next.targetId),
          ),
        );
      case CustomerPackageAction.appointment:
        final model = AppScope.maybeOf(context);
        if (model?.accountId == null) {
          message('Please sign in again to view your appointment.');
          return;
        }
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Your appointment')),
              body: LiveAppointments(
                uid: model!.accountId!,
                name: model.name,
                initialAppointmentId: next.targetId,
              ),
            ),
          ),
        );
    }
    reload();
  }

  void browsePackages() {
    if (widget.profileWorkspace) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => LivePackageScreen(api: api)),
      );
    } else {
      setState(() => selectedTab = false);
    }
  }

  Widget emptyCustomerPackages(
    BuildContext context, {
    required bool hasSelections,
    required bool focusedPlanMissing,
  }) {
    final (title, message) = focusedPlanMissing
        ? (
            'Selected plan unavailable',
            'Refresh or choose Show all selections.',
          )
        : hasSelections
        ? ('No matching packages', 'Try another search or adjust your filters.')
        : (
            'No packages selected yet',
            'Explore the bridal packages to find your look.',
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (!hasSelections && !focusedPlanMissing) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: browsePackages,
              child: const Text('Browse packages'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.profileWorkspace
        ? null
        : AppBar(
            title: Text(
              rentalWorkspace
                  ? 'Customer rentals'
                  : !widget.staff && selectedTab
                  ? 'My packages'
                  : 'Service packages',
            ),
            actions: [
              if (!widget.staff) const AssistantAppBarAction(),
              if (widget.staff && !selectedTab && api is HttpPackageApi)
                IconButton(
                  tooltip: 'Accessory stock',
                  icon: const Icon(Icons.inventory_2_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AccessoryStockScreen(api: api as HttpPackageApi),
                    ),
                  ),
                ),
              IconButton(
                onPressed: busy ? null : reload,
                tooltip: rentalWorkspace
                    ? 'Refresh customer rentals'
                    : 'Refresh packages',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
    body: !api.configured
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Service packages are currently unavailable. Please contact Luvly.',
              ),
            ),
          )
        : FutureBuilder<(List<BridalPackage>, List<PackageSelection>)>(
            future: feed,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snapshot.error is PaymentFailure
                              ? (snapshot.error as PaymentFailure).message
                              : rentalWorkspace
                              ? 'Could not load customer rentals. Please try again.'
                              : !widget.staff && selectedTab
                              ? 'Could not load your packages. Please try again.'
                              : 'Could not load service packages. Please try again.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(onPressed: reload, child: const Text('Retry')),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (packages, allSelections) = snapshot.data!;
              if (widget.openInitialSelection && !initialSelectionOpened) {
                final matches = allSelections
                    .where((s) => s.id == widget.initialSelectionId)
                    .toList();
                if (matches.length != 1) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'This package is no longer available to your account. Go back and refresh your notifications.',
                      ),
                    ),
                  );
                }
                initialSelectionOpened = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (widget.staff) {
                    openRentalDetails(matches.single);
                  } else {
                    openCustomerDetails(matches.single);
                  }
                });
              }
              if (rentalWorkspace) {
                return StaffRentalWorkspace(
                  selections: allSelections,
                  focusedId: focusedSelection,
                  onShowAll: () => setState(() => focusedSelection = null),
                  onOpen: openRentalDetails,
                );
              }
              if (widget.staff) {
                return StaffPackageCatalogue(
                  packages: packages
                      .where(
                        (p) =>
                            widget.initialPackageId == null ||
                            widget.initialPackageId == '' ||
                            p.id == widget.initialPackageId,
                      )
                      .toList(),
                  busy:
                      busy || snapshot.connectionState != ConnectionState.done,
                  onView: view,
                  onCreate: canManage ? () => edit() : null,
                  onEdit: canManage ? edit : null,
                  onToggle: canManage ? toggle : null,
                  onRemove: canManage && api is PackageDeletionApi
                      ? remove
                      : null,
                );
              }
              final scopedSelections = allSelections
                  .where(
                    (s) => focusedSelection == null || s.id == focusedSelection,
                  )
                  .toList();
              final selections = scopedSelections
                  .where(
                    (s) =>
                        (widget.staff ||
                            matchesPackageSelection(
                              s,
                              selectionQuery,
                              selectionStage,
                            )) &&
                        (!widget.staff ||
                            (rentalStatus == 'All' ||
                                    customerRentalStage(s) == rentalStatus) &&
                                '${s.name} ${s.customer} ${s.data['rentalPlan']?['eventDate'] ?? ''} ${s.data['rentalPlan']?['pickupDate'] ?? ''}'
                                    .toLowerCase()
                                    .contains(search.trim().toLowerCase())),
                  )
                  .toList();
              final filtered =
                  packages.indexed.where((entry) {
                    final (_, p) = entry;
                    return (widget.initialPackageId == null ||
                            widget.initialPackageId == '' ||
                            p.id == widget.initialPackageId) &&
                        matchesListSearch(search, [
                          p.name,
                          p.description,
                          ...p.services.map((s) => s.name),
                        ]) &&
                        matchesPackagePrice(p.basePriceCents, priceBand);
                  }).toList()..sort((a, b) {
                    final price = a.$2.basePriceCents.compareTo(
                      b.$2.basePriceCents,
                    );
                    return price == 0 ? a.$1.compareTo(b.$1) : price;
                  });
              final catalogueSearch = ListSearchField(
                value: search,
                hint: 'Search packages',
                compact: true,
                onChanged: (v) => setState(() => search = v),
              );
              final priceFilter = ListFilterSelect(
                label: 'Price',
                value: priceBand,
                compact: true,
                options: packagePriceBands,
                menuAnimationStyle: widget.staff
                    ? null
                    : CustomerUi.popupMotion(context),
                onChanged: (v) => setState(() => priceBand = v),
              );
              final resetCatalogue =
                  search.isNotEmpty ||
                      priceBand != 'All prices' ||
                      catalogueStatus != 'All'
                  ? ResetListFilters(
                      onReset: () => setState(() {
                        search = '';
                        priceBand = 'All prices';
                        catalogueStatus = 'All';
                      }),
                    )
                  : null;
              final content = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    key: widget.profileWorkspace
                        ? null
                        : PageStorageKey(
                            selectedTab ? 'my-packages' : 'packages',
                          ),
                    padding: selectedTab
                        ? const EdgeInsets.fromLTRB(16, 8, 16, 20)
                        : const EdgeInsets.all(16),
                    children: [
                      if (widget.profileWorkspace)
                        Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (allSelections.isNotEmpty)
                              TextButton(
                                onPressed: browsePackages,
                                child: const Text('Browse packages'),
                              ),
                            IconButton(
                              tooltip: 'Refresh packages',
                              onPressed: busy ? null : reload,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      if (!widget.staff && !selectedTab) ...[
                        const PackageEditorialHeader(),
                        const SizedBox(height: 6),
                      ],
                      if (widget.staff) ...[
                        Text(
                          rentalWorkspace
                              ? 'Customer rentals'
                              : 'Package catalogue',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (!widget.profileWorkspace &&
                          (!widget.staff || canManage && !selectedTab))
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (!widget.staff)
                              ChoiceChip(
                                label: const Text('Packages'),
                                shape: const StadiumBorder(),
                                chipAnimationStyle: CustomerUi.chipMotion(
                                  context,
                                ),
                                selected: !selectedTab,
                                onSelected: (_) =>
                                    setState(() => selectedTab = false),
                              ),
                            if (!widget.staff)
                              ChoiceChip(
                                label: const Text('My packages'),
                                shape: const StadiumBorder(),
                                chipAnimationStyle: CustomerUi.chipMotion(
                                  context,
                                ),
                                selected: selectedTab,
                                onSelected: (_) =>
                                    setState(() => selectedTab = true),
                              ),
                            if (canManage && !selectedTab)
                              FilledButton.icon(
                                onPressed: busy ? null : () => edit(),
                                icon: const Icon(Icons.add),
                                label: const Text('Create package'),
                              ),
                          ],
                        ),
                      if (selectedTab && focusedSelection != null)
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Showing your selected plan',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => focusedSelection = null),
                              child: const Text('Show all selections'),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      if (busy ||
                          selectedTab &&
                              snapshot.connectionState ==
                                  ConnectionState.waiting)
                        const LinearProgressIndicator(minHeight: 2),
                      if (!selectedTab) ...[
                        LayoutBuilder(
                          builder: (context, limits) {
                            final inline =
                                !widget.staff &&
                                limits.maxWidth >= 340 &&
                                MediaQuery.textScalerOf(context).scale(14) <=
                                    16;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (inline)
                                  Row(
                                    children: [
                                      Expanded(child: catalogueSearch),
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 164,
                                        ),
                                        child: priceFilter,
                                      ),
                                    ],
                                  )
                                else ...[
                                  catalogueSearch,
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [priceFilter, ?resetCatalogue],
                                  ),
                                ],
                                if (inline) ?resetCatalogue,
                              ],
                            );
                          },
                        ),
                        SizedBox(height: widget.staff ? 12 : 8),
                        if (widget.staff) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final status in [
                                'All',
                                'Active',
                                'Inactive',
                              ])
                                ChoiceChip(
                                  label: Text(status),
                                  selected: catalogueStatus == status,
                                  onSelected: (_) =>
                                      setState(() => catalogueStatus = status),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Text(
                              search.trim().isEmpty &&
                                      catalogueStatus == 'All' &&
                                      priceBand == 'All prices'
                                  ? (canManage
                                        ? 'No packages yet. Create the first package to make it available to customers.'
                                        : widget.staff
                                        ? 'No packages to display.'
                                        : 'No packages are available right now.')
                                  : widget.staff
                                  ? 'No packages match your search and filters.'
                                  : 'No packages match your search.',
                            ),
                          ),
                        for (final (index, p) in filtered)
                          PackageCollectionCard(
                            key: ValueKey('package-${p.id}'),
                            package: p,
                            index: index,
                            staff: widget.staff,
                            onExplore: () => view(p),
                            actions: canManage
                                ? [
                                    OutlinedButton(
                                      onPressed: busy ? null : () => edit(p),
                                      child: const Text('Edit'),
                                    ),
                                    TextButton(
                                      onPressed: busy ? null : () => toggle(p),
                                      child: Text(
                                        p.active
                                            ? 'Deactivate'
                                            : 'Review & publish',
                                      ),
                                    ),
                                    if (api is PackageDeletionApi)
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => remove(p),
                                        child: const Text('Delete'),
                                      ),
                                  ]
                                : const [],
                          ),
                      ] else ...[
                        if (!widget.staff && allSelections.isNotEmpty) ...[
                          ListSearchField(
                            value: selectionQuery,
                            hint: 'Search packages, gowns or dates',
                            compact: true,
                            onChanged: (v) =>
                                setState(() => selectionQuery = v),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ListFilterSelect(
                                label: 'Rental status',
                                value: selectionStage,
                                options: packageSelectionStages,
                                compact: true,
                                onChanged: (v) =>
                                    setState(() => selectionStage = v),
                              ),
                              if (selectionQuery.isNotEmpty ||
                                  selectionStage != 'All packages')
                                ResetListFilters(
                                  onReset: () => setState(() {
                                    selectionQuery = '';
                                    selectionStage = 'All packages';
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (widget.staff) ...[
                          TextField(
                            onChanged: (value) =>
                                setState(() => search = value),
                            decoration: const InputDecoration(
                              labelText: 'Search customer, package or date',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final status in [
                                'All',
                                'Not reserved',
                                'Awaiting deposit',
                                'Reserved',
                                'Collected',
                                'Returned',
                                'Expired',
                                'Cancelled',
                                'Needs review',
                              ])
                                ChoiceChip(
                                  label: Text(status),
                                  selected: rentalStatus == status,
                                  onSelected: (_) =>
                                      setState(() => rentalStatus = status),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (selections.isEmpty)
                          emptyCustomerPackages(
                            context,
                            hasSelections: allSelections.isNotEmpty,
                            focusedPlanMissing:
                                focusedSelection != null &&
                                scopedSelections.isEmpty,
                          ),
                        for (final s in selections)
                          CustomerPackageCard(
                            key: ValueKey('customer-package-${s.id}'),
                            selection: s,
                            busy: busy,
                            onContinue: () => continueCustomer(
                              s,
                              customerPackageStep(s),
                              recheck: true,
                            ),
                            onDetails: () => openCustomerDetails(s),
                          ),
                      ],
                    ],
                  ),
                ),
              );
              return selectedTab
                  ? SafeArea(top: false, child: content)
                  : content;
            },
          ),
  );
}

class PackageChoiceScreen extends StatefulWidget {
  const PackageChoiceScreen({
    super.key,
    required this.package,
    required this.api,
    this.readOnly = false,
    this.revising,
    this.initialRentalPlan,
    this.onSelected,
  });
  final BridalPackage package;
  final PackageApi api;
  final bool readOnly;
  final PackageSelection? revising;
  final Map<String, String>? initialRentalPlan;
  final ValueChanged<PackageSelection>? onSelected;
  @override
  State<PackageChoiceScreen> createState() => _PackageChoiceState();
}

class _PackageChoiceState extends State<PackageChoiceScreen> {
  late Map<String, String> dates = {
    for (final key in ['eventDate', 'pickupDate', 'returnDate'])
      key:
          widget.initialRentalPlan?[key] ??
          widget.revising?.data['rentalPlan']?[key] ??
          '',
  };
  RentalAvailability? availability;
  bool checkingAvailability = false;
  int availabilityRequest = 0;
  bool get dateFirst =>
      !widget.readOnly &&
      widget.package.includedGownCount > 0 &&
      widget.api is PackageAvailabilityApi;
  bool get completeDates => dates.values.every((v) => v.isNotEmpty);
  int get rentalDays =>
      3 +
      widget.package.services
          .where(included)
          .where((s) => s.addsRentalDay)
          .length;
  bool get selectedAvailable =>
      !dateFirst ||
      availability != null &&
          gowns.every((g) => availability!.available(g.dress.id, g.size));

  Future<void> editRentalDates() async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) =>
            PackageDatesScreen(initialDates: dates, allowedDays: rentalDays),
      ),
    );
    if (!mounted ||
        result == null ||
        completeDates &&
            result.entries.every((entry) => dates[entry.key] == entry.value)) {
      return;
    }
    updateDates(result);
  }

  void updateDates(Map<String, String> value) {
    setState(() {
      dates = value;
      availability = null;
      availabilityRequest++;
      checkingAvailability = false;
      requestId = packageRequestId();
      review = false;
      error = null;
    });
    if (completeDates) checkAvailability();
  }

  Future<bool> checkAvailability() async {
    if (!dateFirst) return true;
    if (!completeDates) {
      setState(
        () => error =
            'Choose your event, pickup and return dates before choosing gowns.',
      );
      return false;
    }
    final epoch = ++availabilityRequest;
    setState(() {
      checkingAvailability = true;
      availability = null;
      error = null;
    });
    try {
      final result = await (widget.api as PackageAvailabilityApi).availability(
        widget.package.id,
        widget.package.revision,
        removed,
        addons,
        {...dates},
      );
      if (!mounted || epoch != availabilityRequest) return false;
      setState(() {
        availability = result;
        checkingAvailability = false;
        if (gowns.any((g) => !result.available(g.dress.id, g.size))) {
          error =
              'A selected gown or size is not available for these dates. Choose another size, gown or rental period.';
        }
      });
      return true;
    } catch (e) {
      if (mounted && epoch == availabilityRequest) {
        setState(() {
          checkingAvailability = false;
          error = packageError(e);
        });
      }
      return false;
    }
  }

  final removed = <String>{}, addons = <String>{};
  final accessoryChoices = <String, Set<String>>{};
  AccessoryCatalogue? accessoryCatalogue;
  bool loadingAccessoryCatalogue = true;
  bool loadingSavedGowns = false;
  @override
  void initState() {
    super.initState();
    final previous = widget.revising;
    final samePackage =
        previous?.data['packageId'] == null ||
        previous?.data['packageId'] == widget.package.id;
    if (previous != null && samePackage) {
      customize = true;
      final currentServices = {
        for (final service in widget.package.services) service.id: service,
      };
      final oldServices = {
        for (final service in previous.services) service.id: service,
      };
      removed.addAll(
        (previous.data['removedServices'] as List? ?? [])
            .map((s) => s['id'] as String)
            .where((id) => currentServices[id]?.kind == 'Optional'),
      );
      addons.addAll(
        previous.services
            .where(
              (s) =>
                  s.kind == 'Add-on' &&
                  currentServices[s.id]?.kind == 'Add-on' &&
                  currentServices[s.id]?.serviceType == s.serviceType,
            )
            .map((s) => s.id),
      );
      for (final a in previous.data['selectedAccessories'] as List? ?? []) {
        final id = a['serviceId'] as String;
        final service = currentServices[id];
        if (service == null ||
            !service.isAccessory ||
            service.serviceType != oldServices[id]?.serviceType) {
          continue;
        }
        accessoryChoices.putIfAbsent(id, () => {}).add(a['id'] as String);
      }
    }
    if (previous != null && previous.selectedGowns.isNotEmpty) {
      loadingSavedGowns = true;
      widget.api
          .gowns()
          .then((rows) {
            if (!mounted) return;
            setState(() {
              loadingSavedGowns = false;
              final compatible = [
                for (final g in previous.selectedGowns)
                  for (final d in rows)
                    if (d.id == g['dressId'] &&
                        (samePackage ||
                            widget.package.allCatalogueGowns ||
                            widget.package.eligibleDressIds.contains(d.id)) &&
                        d.sizes.split(', ').contains(g['size']))
                      PackageGownChoice(d, g['size']),
              ];
              if (compatible.length <= widget.package.includedGownCount) {
                gowns = compatible;
              }
            });
          })
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                loadingSavedGowns = false;
                error =
                    'Could not load your saved gowns. Choose them again before saving.';
              });
            }
          });
    }
    if (dateFirst && completeDates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && availabilityRequest == 0) checkAvailability();
      });
    }
    AccessoryCatalogue.load()
        .then((c) {
          if (mounted) {
            setState(() {
              accessoryCatalogue = c;
              loadingAccessoryCatalogue = false;
            });
          }
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() => loadingAccessoryCatalogue = false);
          }
        });
  }

  Iterable<PackageServiceItem> get selectedAccessoryServices => widget
      .package
      .services
      .where((service) => isAccessory(service) && included(service));
  Set<String> accessoryIds(PackageServiceItem service) =>
      accessoryChoices[service.id] ??
      {if (service.standardVeilId case final String id) id};
  Set<String> validAccessoryIds(PackageServiceItem service) {
    final selected = accessoryIds(service);
    return {
      for (final item
          in accessoryCatalogue?.choices(service) ?? <AccessoryItem>[])
        if (selected.contains(item.id) &&
            (!dateFirst ||
                availability == null ||
                availability!.accessories[item.id] == 'Available'))
          item.id,
    };
  }

  int get accessoryExtra => selectedAccessoryServices.fold(
    0,
    (total, service) =>
        total +
        (accessoryCatalogue?.extra(service, validAccessoryIds(service)) ?? 0),
  );
  int get veilUpgrade => selectedAccessoryServices
      .where((s) => s.packageVeil)
      .fold(
        0,
        (total, s) =>
            total + (accessoryCatalogue?.extra(s, validAccessoryIds(s)) ?? 0),
      );
  int get accessoryValue => selectedAccessoryServices
      .where((service) => !service.packageVeil)
      .fold(
        0,
        (total, service) =>
            total +
            (accessoryCatalogue?.subtotal(validAccessoryIds(service)) ?? 0),
      );
  String? get accessoryValidation {
    for (final service in selectedAccessoryServices) {
      if (loadingAccessoryCatalogue) return 'Loading accessory prices…';
      if (accessoryCatalogue == null) {
        return 'Accessory pricing is unavailable. Reopen this package to retry.';
      }
      if (dateFirst &&
          availability != null &&
          (service.itemPriced || service.packageVeil) &&
          availability!.accessoryCatalogueVersion !=
              accessoryCatalogue!.version) {
        return 'Accessory prices could not be verified. Refresh the package and check for an app update.';
      }
      final valid = validAccessoryIds(service);
      final count = accessoryIds(service).length;
      if (valid.length != count) {
        return 'A selected style is unavailable or no longer priced. Edit accessories to choose an available style.';
      }
      if (valid.isEmpty || (service.packageVeil && valid.length != 1)) {
        return service.kind == 'Required'
            ? 'Choose an available style for ${service.name} to continue.'
            : 'Please choose at least one available style for ${service.name} or remove the service to continue.';
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get accessoryPayload => [
    for (final s in widget.package.services.where(included))
      for (final id in accessoryIds(s)) {'serviceId': s.id, 'itemId': id},
  ];
  bool isAccessory(PackageServiceItem s) => s.isAccessory;
  bool included(PackageServiceItem s) =>
      s.kind == 'Add-on' ? addons.contains(s.id) : !removed.contains(s.id);

  String requestId = packageRequestId();
  bool customize = false, review = false, busy = false;
  String? error;
  List<PackageGownChoice> gowns = [];
  Future<void> chooseGowns() async {
    if (!await checkAvailability() || !mounted) return;
    final picked = await Navigator.of(context).push<List<PackageGownChoice>>(
      MaterialPageRoute(
        builder: (_) => PackageGownPicker(
          api: widget.api,
          eligibleIds: widget.package.eligibleDressIds.toSet(),
          allCatalogueGowns: widget.package.allCatalogueGowns,
          allowance: widget.package.includedGownCount,
          initial: gowns,
          availability: availability,
          rentalPlan: dateFirst ? {...dates} : null,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      gowns = picked;
      requestId = packageRequestId();
      error = null;
    });
  }

  Future<void> change(PackageServiceItem s, bool selected) async {
    final action = s.kind == 'Add-on'
        ? (selected ? 'Add' : 'Remove')
        : (selected ? 'Keep' : 'Remove');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$action ${s.name}?'),
        content: Text(
          s.itemPriced
              ? (selected
                    ? 'Choose the accessories you would like to rent.'
                    : 'Remove the selected accessories and their charges?')
              : s.kind == 'Add-on'
              ? '${packageMoney(s.priceCents)} ${selected ? 'will be added to' : 'will be removed from'} your total.'
              : '${packageMoney(s.priceCents)} ${selected ? 'will be restored to' : 'will be deducted from'} your total.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      if (s.kind == 'Add-on') {
        selected ? addons.add(s.id) : addons.remove(s.id);
      } else {
        selected ? removed.remove(s.id) : removed.add(s.id);
      }
      if (!selected) accessoryChoices.remove(s.id);
      requestId = packageRequestId();
      error = null;
    });
    if (dateFirst) {
      final pickup = DateTime.tryParse(dates['pickupDate'] ?? '');
      final returned = DateTime.tryParse(dates['returnDate'] ?? '');
      if (pickup != null &&
          returned != null &&
          returned.difference(pickup).inDays >= rentalDays) {
        updateDates({...dates, 'returnDate': ''});
      } else {
        await checkAvailability();
      }
    }
  }

  Future<void> submit() async {
    if (loadingSavedGowns || checkingAvailability || busy) return;
    if (dateFirst && (!await checkAvailability() || !selectedAvailable)) return;
    final issue = accessoryValidation;
    if (issue != null) {
      setState(() => error = issue);
      return;
    }
    if (gowns.length != widget.package.includedGownCount) {
      setState(
        () => error =
            'Choose ${widget.package.includedGownCount} different included gowns and their sizes before continuing.',
      );
      return;
    }
    if (!review) {
      setState(() {
        review = true;
        error = null;
      });
      return;
    }
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.revising != null) {
        final old = widget.revising!, api = widget.api as HttpPackageApi;
        final payload = <String, dynamic>{
          'requestId': requestId,
          'revision': old.data['selectionRevision'] ?? 0,
          'packageRevision': widget.package.revision,
          'packageId': widget.package.id,
          'removedIds': removed.toList(),
          'addonIds': addons.toList(),
          'gowns': gowns.map((g) => g.toJson()).toList(),
          'accessories': accessoryPayload,
          'accessoryCatalogueVersion': accessoryCatalogue?.version,
          'previewOnly': true,
          if (dateFirst) 'rentalPlan': {...dates},
          if (dateFirst) 'planRevision': old.data['rentalPlanRevision'] ?? 0,
        };
        final quote = await api.transport.businessRequest(
          '/v1/package-selections/${old.id}/revise',
          body: payload,
        );
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Review updated selection'),
            content: Text(
              'Updated package total: ${packageMoney(quote['totalCents'])}. Your fitting history and eligible credit stay with this plan. Any previous adjustment proposal will need a new review. ${old.data['packageId'] != widget.package.id ? 'The previous offer is removed when changing packages; review eligible offers again. ' : ''}Stock is not reserved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep current'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save changes'),
              ),
            ],
          ),
        );
        if (accepted != true) {
          if (mounted) setState(() => busy = false);
          return;
        }
        await api.transport.businessRequest(
          '/v1/package-selections/${old.id}/revise',
          body: {
            ...payload,
            'previewOnly': false,
            'expectedTotalCents': quote['totalCents'],
          },
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (dateFirst) {
        final saved = await (widget.api as HttpPackageApi).saveSelection(
          widget.package,
          removed,
          addons,
          requestId,
          gowns: gowns.map((g) => g.toJson()).toList(),
          accessories: accessoryPayload,
          accessoryCatalogueVersion: accessoryCatalogue?.version,
          rentalPlan: {...dates},
          expectedTotalCents:
              widget.package.total(removed, addons) + accessoryExtra,
        );
        widget.onSelected?.call(saved);
      } else {
        await widget.api.select(
          widget.package,
          removed,
          addons,
          requestId,
          gowns: gowns.map((g) => g.toJson()).toList(),
          accessories: accessoryPayload,
          accessoryCatalogueVersion: accessoryCatalogue?.version,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = packageError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    final theme = Theme.of(context);
    final total = p.total(removed, addons) + accessoryExtra;
    final services = p.services.where((s) => !review || included(s)).toList();
    final hasGowns = p.includedGownCount > 0;
    final selectionIncomplete =
        dateFirst && !completeDates || gowns.length != p.includedGownCount;
    final gownNoun = p.includedGownCount == 1 ? 'gown' : 'gowns';
    final includes = <(String, bool)>[
      if (hasGowns) ('${p.includedGownCount} wedding $gownNoun rental', false),
      for (final service in p.services)
        if (service.kind != 'Add-on' &&
            included(service) &&
            !(hasGowns &&
                service.kind == 'Required' &&
                RegExp(
                  r'^(?:one\s+|1\s+)?(?:wedding[ -])?(?:dress|gown) rental$',
                  caseSensitive: false,
                ).hasMatch(service.name.trim())))
          (service.name, service.kind == 'Optional'),
      if (hasGowns) ('Up to $rentalDays calendar days', false),
    ];
    return Scaffold(
      appBar: AppBar(
        title: AssistantExclusion(
          child: Text(review ? 'Review your package' : 'Package details'),
        ),
      ),
      bottomNavigationBar: widget.readOnly
          ? null
          : PackageReviewBar(
              totalCents: total,
              error: error,
              hint: busy || checkingAvailability
                  ? null
                  : review
                  ? hasGowns
                        ? 'No payment is due. Saving does not reserve a gown.'
                        : 'No payment is due when you save.'
                  : dateFirst && !completeDates
                  ? 'Choose rental dates before choosing gowns.'
                  : gowns.length < p.includedGownCount
                  ? 'Select each included gown and its size before review.'
                  : accessoryValidation,
              label: busy
                  ? 'Saving…'
                  : loadingSavedGowns
                  ? 'Loading saved gowns…'
                  : checkingAvailability
                  ? 'Checking availability…'
                  : review
                  ? 'Save package selection'
                  : 'Review selection',
              onPressed:
                  busy ||
                      loadingSavedGowns ||
                      checkingAvailability ||
                      selectionIncomplete
                  ? null
                  : submit,
            ),
      body: PopScope(
        canPop: !review && !busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && review && !busy) {
            setState(() {
              review = false;
              error = null;
            });
          }
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              children: [
                PackageDetailsHeader(package: p, showCover: !review),
                if (widget.revising?.data['packageRevision']
                    case final int revision when revision != p.revision)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Package pricing or services have changed. Review the updated choices and total before saving.',
                    ),
                  ),
                const SizedBox(height: 16),
                if (includes.isNotEmpty) ...[
                  PackageIncludes(items: includes),
                  const SizedBox(height: 14),
                ],
                if (dateFirst) ...[
                  PackageRentalDatesCard(
                    dates: completeDates ? dates : null,
                    onEdit: review || busy ? null : editRentalDates,
                  ),
                  if (checkingAvailability) const LinearProgressIndicator(),
                  const SizedBox(height: 18),
                ],
                if (hasGowns) ...[
                  Text(
                    review
                        ? 'Selected wedding gowns'
                        : 'Choose your wedding $gownNoun',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${gowns.length} of ${p.includedGownCount} selected',
                    style: theme.textTheme.bodySmall,
                  ),
                  for (final gown in gowns)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          (gown.dress.imageUrl.isNotEmpty ||
                                  gown.dress.photoRevision > 0) &&
                              context
                                      .getInheritedWidgetOfExactType<
                                        CatalogueScope
                                      >() !=
                                  null
                          ? SizedBox(
                              width: 44,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CatalogueDressPhoto(
                                  dress: gown.dress,
                                  height: 44,
                                  compact: true,
                                ),
                              ),
                            )
                          : const Icon(Icons.checkroom_outlined),
                      title: Text('${gown.dress.name} · ${gown.size}'),
                      subtitle: Text(
                        dateFirst &&
                                availability != null &&
                                !availability!.available(
                                  gown.dress.id,
                                  gown.size,
                                )
                            ? 'Not available for these dates · choose again'
                            : 'Included · no extra charge',
                      ),
                    ),
                  if (!widget.readOnly && !review) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed:
                          busy ||
                              loadingSavedGowns ||
                              checkingAvailability ||
                              dateFirst && !completeDates
                          ? null
                          : chooseGowns,
                      icon: const Icon(Icons.checkroom_outlined, size: 18),
                      label: Text(
                        gowns.isEmpty
                            ? 'Explore wedding gowns'
                            : gowns.length < p.includedGownCount
                            ? 'Add another gown'
                            : 'Edit gown selection',
                      ),
                    ),
                    if (dateFirst && !completeDates)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Choose your rental dates first to explore available gowns.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (!widget.readOnly &&
                    !review &&
                    p.services.any(
                      (service) => service.kind != 'Required',
                    )) ...[
                  AnimatedContainer(
                    duration: CustomerUi.motion(context, CustomerUi.selection),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: customize ? blush : CustomerUi.linen,
                      borderRadius: CustomerUi.cardRadius,
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      title: Text(
                        'Customize your package',
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        'Choose optional services and extras.',
                        style: theme.textTheme.bodySmall,
                      ),
                      value: customize,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => customize = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (services.isNotEmpty)
                  Material(
                    color: CustomerUi.paper,
                    shape: const RoundedRectangleBorder(
                      borderRadius: CustomerUi.cardRadius,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (index, service) in services.indexed) ...[
                          if (index > 0)
                            const Divider(height: 1, indent: 14, endIndent: 14),
                          serviceRow(service),
                        ],
                      ],
                    ),
                  ),
                if (hasGowns && !widget.readOnly) ...[
                  ExpansionTile(
                    expansionAnimationStyle: CustomerUi.expansionMotion(
                      context,
                    ),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 10),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: const Text('Fitting & rental information'),
                    children: const [
                      Text(
                        'RM50 covers one 60-minute fitting visit. Try different styles and sizes as time and stock allow. You can change your gown or package after the fitting, before the booking deposit is issued.',
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                PackagePriceBreakdown(
                  package: p,
                  removed: removed,
                  addons: addons,
                  accessoryExtraCents: accessoryExtra,
                  veilUpgradeCents: veilUpgrade,
                  accessoryValueCents: accessoryValue,
                  showPaymentEstimate: !widget.readOnly,
                  datesChecked: dateFirst,
                ),
                if (!widget.readOnly && review) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => review = false),
                    child: const Text('Edit selection'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget serviceRow(PackageServiceItem service) {
    final theme = Theme.of(context);
    final selected = included(service);
    final required = service.kind == 'Required';
    final addOn = service.kind == 'Add-on';
    final editable =
        !review &&
        !widget.readOnly &&
        !required &&
        (customize || isAccessory(service) || service.requiresTeamScheduling);
    final price = packageMoney(service.priceCents);
    final subtitle = service.itemPriced
        ? 'Optional · Pay for selected items'
        : required
        ? 'Mandatory · included'
        : addOn
        ? '${selected ? 'Added · ' : ''}+ $price'
        : selected
        ? editable
              ? 'Included · Remove to save $price'
              : 'Included'
        : editable
        ? 'Removed · Add back for $price'
        : 'Removed · − $price';
    final catalogue = accessoryCatalogue;
    final showAccessories =
        isAccessory(service) &&
        selected &&
        !widget.readOnly &&
        catalogue != null;
    final description =
        (widget.readOnly ? service.description : service.customerDescription)
            .trim();
    final title = Text(service.name, style: theme.textTheme.titleSmall);
    final status = Text(subtitle, style: theme.textTheme.bodySmall);
    final details = !showAccessories && description.isNotEmpty
        ? IconButton(
            tooltip: 'Details for ${service.name}',
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(service.name),
                content: Text(description),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (editable && details != null) details,
            Expanded(
              child: editable
                  ? CheckboxListTile(
                      contentPadding: EdgeInsetsDirectional.only(
                        start: details == null ? 14 : 0,
                        end: 4,
                      ),
                      value: selected,
                      onChanged: busy
                          ? null
                          : (value) => change(service, value!),
                      title: title,
                      subtitle: status,
                    )
                  : ListTile(
                      contentPadding: const EdgeInsetsDirectional.only(
                        start: 14,
                        end: 4,
                      ),
                      horizontalTitleGap: 10,
                      minLeadingWidth: 20,
                      leading: Icon(
                        required
                            ? Icons.lock_outline
                            : addOn && !selected
                            ? Icons.add_circle_outline
                            : selected
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                        size: 18,
                      ),
                      title: title,
                      subtitle: status,
                    ),
            ),
            if (!editable && details != null) details,
          ],
        ),
        if (showAccessories)
          AccessoryServicePicker(
            key: ValueKey('accessories-${service.id}'),
            catalogue: catalogue,
            service: service,
            selected: accessoryIds(service),
            readOnly: review || busy,
            availability: dateFirst ? availability?.accessories ?? {} : null,
            onChanged: (values) => setState(() {
              accessoryChoices[service.id] = values;
              requestId = packageRequestId();
              error = null;
            }),
          ),
      ],
    );
  }
}
