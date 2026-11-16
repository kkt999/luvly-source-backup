import 'package:flutter/material.dart';
import '../reviews/gown_rating.dart';
import '../src/design.dart'
    show CustomerUi, blush, ink, ivory, line, muted, rose;
import 'catalogue_repository.dart';
import 'gown_filters.dart';

class GownBrowseFilters {
  const GownBrowseFilters(this.filters, this.availableOnly);
  final GownFilters filters;
  final bool availableOnly;
}

Future<GownBrowseFilters?> showGownFilterSheet(
  BuildContext context, {
  required GownFilters initial,
  required bool availableOnly,
  required List<CatalogueDress> candidates,
  required Map<String, GownRating> ratings,
  required bool includeRatings,
  required bool ratingsReady,
  bool includePrice = true,
  bool includeSort = true,
  bool includeAvailability = true,
}) => showModalBottomSheet<GownBrowseFilters>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  sheetAnimationStyle: CustomerUi.expansionMotion(context),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: FractionallySizedBox(
      heightFactor:
          !includeSort &&
              !includePrice &&
              !includeRatings &&
              !includeAvailability
          ? MediaQuery.textScalerOf(context).scale(1) > 1.4
                ? .85
                : .58
          : .91,
      child: GownFilterSheet(
        initial: initial,
        availableOnly: availableOnly,
        candidates: candidates,
        ratings: ratings,
        includeRatings: includeRatings,
        ratingsReady: ratingsReady,
        includePrice: includePrice,
        includeSort: includeSort,
        includeAvailability: includeAvailability,
      ),
    ),
  ),
);

/// Local draft: dismissing the sheet never changes the collection.
class GownFilterSheet extends StatefulWidget {
  const GownFilterSheet({
    super.key,
    required this.initial,
    required this.availableOnly,
    required this.candidates,
    required this.ratings,
    required this.includeRatings,
    required this.ratingsReady,
    this.includePrice = true,
    this.includeSort = true,
    this.includeAvailability = true,
  });
  final GownFilters initial;
  final bool availableOnly, includeRatings, ratingsReady;
  final bool includePrice, includeSort, includeAvailability;
  final List<CatalogueDress> candidates;
  final Map<String, GownRating> ratings;
  @override
  State<GownFilterSheet> createState() => _GownFilterSheetState();
}

class _GownFilterSheetState extends State<GownFilterSheet> {
  late String? colour = widget.initial.colour, size = widget.initial.size;
  late double? minimum = widget.initial.minRating;
  late GownSort sort = widget.initial.sort;
  late bool available = widget.availableOnly;
  late final budget = TextEditingController(
    text: widget.initial.maxPriceCents == null
        ? ''
        : (widget.initial.maxPriceCents! / 100).toStringAsFixed(2),
  );
  bool get invalidBudget =>
      budget.text.trim().isNotEmpty &&
      parsePriceCents(budget.text.trim()) == null;
  GownFilters get draft => GownFilters(
    colour: colour,
    size: size,
    maxPriceCents: parsePriceCents(budget.text.trim()),
    minRating: minimum,
    sort: sort,
  );
  int? get count => invalidBudget || draft.needsRatings && !widget.ratingsReady
      ? null
      : draft
            .apply(
              widget.candidates.where(
                (d) => !available || d.availability == 'Available',
              ),
              ratings: widget.ratings,
            )
            .length;
  @override
  void dispose() {
    budget.dispose();
    super.dispose();
  }

  void reset() => setState(() {
    colour = null;
    size = null;
    minimum = null;
    sort = GownSort.name;
    available = false;
    budget.clear();
  });
  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
  Widget choice(
    String label,
    bool selected,
    VoidCallback choose, {
    Key? key,
    bool enabled = true,
    bool star = false,
  }) => ChoiceChip(
    key: key,
    label: star
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_rounded,
                size: 14,
                color: selected ? rose : muted,
              ),
              const SizedBox(width: 4),
              Text(label),
            ],
          )
        : Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: enabled ? (_) => setState(choose) : null,
    backgroundColor: Colors.white,
    selectedColor: blush,
    side: BorderSide(color: selected ? rose : line),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected ? const Color(0xFF7D3D4E) : ink,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  @override
  Widget build(BuildContext context) {
    final colours = widget.candidates.map((d) => d.colour).toSet()
      ..addAll([?colour]);
    final sizes = widget.candidates.expand((d) => d.sizes.split(', ')).toSet()
      ..addAll([?size]);
    final resultCount = count;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.includeSort ? 'Filters & sort' : 'Filter gowns',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('close-gown-filters'),
                  tooltip: 'Close filters',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 21),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('gown-filter-options'),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (widget.includeSort)
                  section('Sort by', [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in {
                          GownSort.name: 'Name',
                          GownSort.priceLow: 'Price: low to high',
                          GownSort.priceHigh: 'Price: high to low',
                          if (widget.includeRatings)
                            GownSort.ratingHigh: 'Highest rated',
                        }.entries)
                          choice(
                            entry.value,
                            sort == entry.key,
                            () => sort = entry.key,
                            key: ValueKey('filter-sort-${entry.key.name}'),
                            enabled:
                                entry.key != GownSort.ratingHigh ||
                                widget.ratingsReady,
                          ),
                      ],
                    ),
                  ]),
                if (widget.includeRatings)
                  section('Rating', [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        choice(
                          'Any rating',
                          minimum == null,
                          () => minimum = null,
                          key: const Key('filter-rating-any'),
                        ),
                        choice(
                          '4 & up',
                          minimum == 4,
                          () => minimum = 4,
                          key: const Key('filter-rating-4'),
                          star: true,
                          enabled: widget.ratingsReady,
                        ),
                        choice(
                          '4.5 & up',
                          minimum == 4.5,
                          () => minimum = 4.5,
                          key: const Key('filter-rating-4.5'),
                          star: true,
                          enabled: widget.ratingsReady,
                        ),
                      ],
                    ),
                    if (!widget.ratingsReady)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Ratings are unavailable right now. Other filters are still available.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                  ]),
                section('Colour', [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      choice(
                        'Any colour',
                        colour == null,
                        () => colour = null,
                        key: const Key('filter-colour-any'),
                      ),
                      for (final value in dressColours.where(colours.contains))
                        choice(
                          value,
                          colour == value,
                          () => colour = value,
                          key: ValueKey('filter-colour-$value'),
                        ),
                    ],
                  ),
                ]),
                section('Size', [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      choice(
                        'Any size',
                        size == null,
                        () => size = null,
                        key: const Key('filter-size-any'),
                      ),
                      for (final value in dressSizes.where(sizes.contains))
                        choice(
                          value,
                          size == value,
                          () => size = value,
                          key: ValueKey('filter-size-$value'),
                        ),
                    ],
                  ),
                ]),
                if (widget.includePrice)
                  section('Rental budget', [
                    TextField(
                      key: const Key('filter-rental-budget'),
                      controller: budget,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: const SizedBox(
                          width: 46,
                          child: Center(
                            child: Text(
                              'RM',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 46,
                          minHeight: 48,
                        ),
                        hintText: 'Maximum rental price',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        errorText: invalidBudget
                            ? 'Enter a positive amount with up to 2 decimals.'
                            : null,
                        suffixIcon: budget.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear budget',
                                onPressed: () => setState(budget.clear),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ]),
                if (widget.includeAvailability)
                  SwitchListTile.adaptive(
                    key: const Key('filter-available-now'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Available now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: available,
                    onChanged: (v) => setState(() => available = v),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Confirm your size and rental-date availability before booking.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: ivory,
              border: Border(top: BorderSide(color: line)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
            child: Row(
              children: [
                TextButton(
                  key: const Key('reset-gown-filters'),
                  onPressed: reset,
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: FilledButton(
                    key: const Key('apply-gown-filters'),
                    onPressed: invalidBudget
                        ? null
                        : () => Navigator.pop(
                            context,
                            GownBrowseFilters(draft, available),
                          ),
                    child: Text(
                      resultCount == null
                          ? 'Apply filters'
                          : 'Show $resultCount ${resultCount == 1 ? 'gown' : 'gowns'}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
