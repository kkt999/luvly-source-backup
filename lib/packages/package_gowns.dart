import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../catalogue/gown_product_content.dart';
import '../catalogue/gown_filters.dart';
import '../catalogue/gown_filter_sheet.dart';
import '../support/assistant_launcher.dart';
import '../src/support.dart';
import 'package_api.dart';
import 'rental_availability.dart';

class PackageGownChoice {
  const PackageGownChoice(this.dress, this.size);
  final CatalogueDress dress;
  final String size;
  Map<String, dynamic> toJson() => {
    'dressId': dress.id,
    'size': size,
    'revision': dress.revision,
  };
}

class PackageGownPicker extends StatefulWidget {
  const PackageGownPicker({
    super.key,
    required this.api,
    required this.eligibleIds,
    this.allCatalogueGowns = false,
    this.allowance,
    this.initial = const [],
    this.repository,
    this.onContactSupport,
    this.availability,
    this.rentalPlan,
  });
  final PackageApi api;
  final Set<String> eligibleIds;
  final bool allCatalogueGowns;
  final int? allowance;
  final List<PackageGownChoice> initial;
  final CatalogueRepository? repository;
  final VoidCallback? onContactSupport;
  final RentalAvailability? availability;
  final Map<String, String>? rentalPlan;
  @override
  State<PackageGownPicker> createState() => _PackageGownPickerState();
}

class _PackageGownPickerState extends State<PackageGownPicker> {
  late Future<List<CatalogueDress>> feed;
  late final CatalogueRepository photos;
  final Map<String, String> sizes = {};
  late final Set<String> eligible;
  String search = '';
  GownFilters filters = const GownFilters();
  bool get editing => widget.allowance == null;
  @override
  void initState() {
    super.initState();
    photos = widget.repository ?? FirebaseCatalogueRepository();
    feed = widget.api.gowns();
    eligible = {...widget.eligibleIds};
    for (final item in widget.initial) {
      sizes[item.dress.id] = item.dress.sizes.split(', ').contains(item.size)
          ? item.size
          : '';
    }
  }

  Future<void> open(CatalogueDress d) async {
    if (editing) {
      setState(
        () => eligible.contains(d.id)
            ? eligible.remove(d.id)
            : eligible.add(d.id),
      );
      return;
    }
    final chosen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _IncludedGownDetail(
          dress: d,
          api: widget.api,
          photos: photos,
          initialSize: sizes[d.id],
          availability: widget.availability,
        ),
      ),
    );
    if (!mounted ||
        chosen == null ||
        !d.sizes.split(', ').contains(chosen) ||
        widget.availability != null &&
            !widget.availability!.available(d.id, chosen)) {
      return;
    }
    if (!sizes.containsKey(d.id) && sizes.length >= widget.allowance!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This package includes ${widget.allowance} gown(s). Deselect a gown first.',
          ),
        ),
      );
      return;
    }
    setState(() => sizes[d.id] = chosen);
  }

  void contact() {
    if (widget.onContactSupport != null) {
      widget.onContactSupport!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Talk to Luvly')),
          body: const SupportScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AssistantExclusion(
        child: Text(editing ? 'Eligible package gowns' : 'Choose your gowns'),
      ),
    ),
    body: FutureBuilder<List<CatalogueDress>>(
      future: feed,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load gowns. Please try again.'),
                TextButton(
                  onPressed: () => setState(() => feed = widget.api.gowns()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!
            .where((d) => d.published && d.availability == 'Available')
            .toList();
        final available = all
            .where(
              (d) =>
                  editing ||
                  (widget.allCatalogueGowns
                      ? d.sizes
                            .split(', ')
                            .any(
                              (size) =>
                                  size.isNotEmpty && size != 'Made to measure',
                            )
                      : widget.eligibleIds.contains(d.id)),
            )
            .toList();
        final dateAvailableCount = available
            .where(
              (d) =>
                  widget.availability == null ||
                  widget.availability!.availableSizes(d.id).isNotEmpty,
            )
            .length;
        final visible = filters.apply(
          available.where(
            (d) => '${d.name} ${d.colour} ${d.category}'.toLowerCase().contains(
              search,
            ),
          ),
        );
        final valid = available
            .where(
              (d) =>
                  sizes.containsKey(d.id) &&
                  d.sizes.split(', ').contains(sizes[d.id]) &&
                  (widget.availability == null ||
                      widget.availability!.available(d.id, sizes[d.id]!)),
            )
            .toList();
        final missing = eligible.where((id) => !all.any((d) => d.id == id));
        final theme = Theme.of(context);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Text(
                        editing
                            ? 'THE PACKAGE COLLECTION'
                            : 'CURATED FOR YOUR DAY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        editing
                            ? 'Choose eligible gowns'
                            : 'Find the one for you',
                        style: theme.textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        editing
                            ? 'Only selected gowns are included in this package.'
                            : '${widget.allowance} gown${widget.allowance == 1 ? '' : 's'} included · explore the details, then choose your size.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (!editing && dateAvailableCount < widget.allowance!)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Only $dateAvailableCount gown${dateAvailableCount == 1 ? ' is' : 's are'} available${widget.availability == null ? '' : ' for these dates'}. This package needs ${widget.allowance}. Choose different dates or another package.',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (!editing && widget.rentalPlan != null) ...[
                        Text(
                          '${widget.rentalPlan!['pickupDate']} → ${widget.rentalPlan!['returnDate']}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Text(
                          'Availability includes the cleaning period. Saving your choices does not reserve stock.',
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search gowns',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setState(() => search = value.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('package-gown-filters'),
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(
                              'Filter gowns${filters.hasProductConstraints ? ' · Selected' : ''}',
                            ),
                            onPressed: () async {
                              final result = await showGownFilterSheet(
                                context,
                                initial: filters,
                                availableOnly: false,
                                candidates: available
                                    .where(
                                      (d) =>
                                          '${d.name} ${d.colour} ${d.category}'
                                              .toLowerCase()
                                              .contains(search),
                                    )
                                    .toList(),
                                ratings: const {},
                                includeRatings: false,
                                ratingsReady: false,
                                includePrice: false,
                                includeSort: false,
                                includeAvailability: false,
                              );
                              if (mounted && result != null) {
                                setState(() => filters = result.filters);
                              }
                            },
                          ),
                          if (filters.hasProductConstraints)
                            TextButton(
                              onPressed: () =>
                                  setState(() => filters = const GownFilters()),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${visible.length} gown${visible.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching gowns.'),
                        ),
                      LayoutBuilder(
                        builder: (context, box) {
                          final columns =
                              visible.length <= 1 || box.maxWidth < 320
                              ? 1
                              : box.maxWidth >= 720
                              ? 3
                              : 2;
                          final width =
                              (box.maxWidth - 14 * (columns - 1)) / columns;
                          final height = columns == 1 ? 300.0 : width * 1.25;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: visible.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 18,
                                  mainAxisExtent:
                                      height +
                                      150 *
                                          MediaQuery.textScalerOf(
                                            context,
                                          ).scale(1).clamp(1, 2),
                                ),
                            itemBuilder: (context, index) {
                              final d = visible[index];
                              final selected = editing
                                  ? eligible.contains(d.id)
                                  : sizes.containsKey(d.id);
                              return Material(
                                color: Colors.white,
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                child: InkWell(
                                  key: ValueKey('gown-${d.id}'),
                                  onTap: () => open(d),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Stack(
                                        children: [
                                          Container(
                                            color: const Color(0xFFF5EFEB),
                                            child: CatalogueDressPhoto(
                                              dress: d,
                                              repository: photos,
                                              height: height,
                                            ),
                                          ),
                                          if (selected)
                                            Positioned(
                                              top: 10,
                                              right: 10,
                                              child: CircleAvatar(
                                                radius: 16,
                                                backgroundColor:
                                                    theme.colorScheme.primary,
                                                child: const Icon(
                                                  Icons.check,
                                                  size: 18,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          12,
                                          12,
                                          0,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              d.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall,
                                            ),
                                            Text(
                                              '${d.category} · ${d.colour}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              selected && !editing
                                                  ? 'Selected · ${sizes[d.id]}'
                                                  : widget.availability == null
                                                  ? 'Included in package'
                                                  : widget.availability!
                                                        .availableSizes(d.id)
                                                        .isNotEmpty
                                                  ? 'Available · ${widget.availability!.availableSizes(d.id).join(', ')}'
                                                  : (widget
                                                            .availability!
                                                            .gowns[d.id]
                                                            ?.values
                                                            .contains(
                                                              'Unconfirmed',
                                                            ) ??
                                                        true)
                                                  ? 'Contact Luvly to confirm availability'
                                                  : 'Unavailable for these dates',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      if (selected && !editing)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                            onPressed: () => setState(
                                              () => sizes.remove(d.id),
                                            ),
                                            child: const Text('Remove'),
                                          ),
                                        )
                                      else
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            8,
                                            12,
                                            12,
                                          ),
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  editing
                                                      ? selected
                                                            ? 'Included'
                                                            : 'Tap to include'
                                                      : 'View gown',
                                                  style: theme
                                                      .textTheme
                                                      .labelMedium,
                                                ),
                                              ),
                                              if (!editing)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 6,
                                                  ),
                                                  child: Icon(
                                                    Icons.arrow_forward,
                                                    size: 16,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      if (!editing) ...[
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: contact,
                          icon: const Icon(Icons.support_agent_outlined),
                          label: const Text(
                            'Need help choosing? Contact Luvly',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your choices are saved as preferences. Fit and rental stock are confirmed by the boutique.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (editing)
                        for (final id in missing)
                          CheckboxListTile(
                            value: true,
                            title: const Text(
                              'Previously linked gown is not currently available',
                            ),
                            subtitle: Text(id),
                            onChanged: (_) =>
                                setState(() => eligible.remove(id)),
                          ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (!editing)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${valid.length} of ${widget.allowance} selected',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: editing
                                  ? () => Navigator.pop(context, eligible)
                                  : valid.length == widget.allowance &&
                                        sizes.length == widget.allowance
                                  ? () => Navigator.pop(
                                      context,
                                      valid
                                          .map(
                                            (d) => PackageGownChoice(
                                              d,
                                              sizes[d.id]!,
                                            ),
                                          )
                                          .toList(),
                                    )
                                  : null,
                              child: Text(
                                editing
                                    ? 'Use ${eligible.length} eligible gowns'
                                    : 'Use selected gowns (${valid.length}/${widget.allowance})',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _IncludedGownDetail extends StatefulWidget {
  const _IncludedGownDetail({
    required this.dress,
    required this.api,
    required this.photos,
    this.initialSize,
    this.availability,
  });
  final CatalogueDress dress;
  final PackageApi api;
  final CatalogueRepository photos;
  final String? initialSize;
  final RentalAvailability? availability;
  @override
  State<_IncludedGownDetail> createState() => _IncludedGownDetailState();
}

class _IncludedGownDetailState extends State<_IncludedGownDetail> {
  late String? size = widget.initialSize;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AssistantExclusion(child: Text('Your included gown')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            GownProductContent(
              dress: widget.dress,
              repository: widget.photos,
              included: true,
              initialSize: size,
              availableSizes: widget.availability?.availableSizes(
                widget.dress.id,
              ),
              availabilityNote: widget.availability == null
                  ? null
                  : 'Only available sizes can be selected for your dates. Choose another size, gown or rental period if needed.',
              onSizeChanged: (value) => setState(() => size = value),
              api: widget.api is HttpPackageApi
                  ? (widget.api as HttpPackageApi).transport
                  : null,
            ),
            if (widget.availability != null)
              for (final value in widget.dress.sizes.split(', '))
                if (!widget.availability!.available(widget.dress.id, value))
                  Text(
                    '$value · ${widget.availability!.status(widget.dress.id, value) == 'Unavailable' ? 'Unavailable for these dates' : 'Contact Luvly to confirm availability'}',
                  ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed:
              widget.dress.sizes.split(', ').contains(size) &&
                  (widget.availability == null ||
                      widget.availability!.available(
                        widget.dress.id,
                        size ?? '',
                      ))
              ? () => Navigator.pop(context, size)
              : null,
          child: const Text('Select this gown'),
        ),
      ),
    ),
  );
}
