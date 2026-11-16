import 'package:flutter/material.dart';
import 'catalogue_repository.dart';
import '../reviews/gown_rating.dart';

enum GownSort { name, priceLow, priceHigh, ratingHigh }

class GownFilters {
  const GownFilters({
    this.colour,
    this.size,
    this.maxPriceCents,
    this.minRating,
    this.sort = GownSort.name,
  });
  final String? colour, size;
  final int? maxPriceCents;
  final double? minRating;
  final GownSort sort;
  bool get hasProductConstraints =>
      colour != null || size != null || maxPriceCents != null || needsRatings;
  bool get needsRatings => minRating != null || sort == GownSort.ratingHigh;
  List<CatalogueDress> apply(
    Iterable<CatalogueDress> source, {
    Map<String, GownRating> ratings = const {},
  }) {
    final result = source
        .where(
          (d) =>
              (colour == null || d.colour == colour) &&
              (size == null || d.sizes.split(', ').contains(size)) &&
              (maxPriceCents == null || d.priceCents <= maxPriceCents!) &&
              (minRating == null ||
                  (ratings[d.id]?.rated == true &&
                      ratings[d.id]!.average >= minRating!)),
        )
        .toList();
    result.sort((a, b) {
      final compared = switch (sort) {
        GownSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        GownSort.priceLow => a.priceCents.compareTo(b.priceCents),
        GownSort.priceHigh => b.priceCents.compareTo(a.priceCents),
        GownSort.ratingHigh => compareRatings(a, b, ratings),
      };
      return compared == 0 ? a.id.compareTo(b.id) : compared;
    });
    return result;
  }

  static int compareRatings(
    CatalogueDress a,
    CatalogueDress b,
    Map<String, GownRating> ratings,
  ) {
    final left = ratings[a.id], right = ratings[b.id];
    final compared = (right?.rated == true ? right!.average : -1).compareTo(
      left?.rated == true ? left!.average : -1,
    );
    if (compared != 0) return compared;
    final byCount = (right?.count ?? 0).compareTo(left?.count ?? 0);
    return byCount != 0
        ? byCount
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

class GownFilterPanel extends StatefulWidget {
  const GownFilterPanel({
    super.key,
    required this.onChanged,
    this.includePrice = true,
    this.compact = false,
    this.includeRatings = false,
    this.value,
  });
  final ValueChanged<GownFilters> onChanged;
  final bool includePrice;
  final bool compact;
  final bool includeRatings;
  final GownFilters? value;
  @override
  State<GownFilterPanel> createState() => _GownFilterPanelState();
}

class _GownFilterPanelState extends State<GownFilterPanel> {
  String? colour, size;
  double? minRating;
  GownSort sort = GownSort.name;
  final budget = TextEditingController();
  String? budgetError;
  void readValue(GownFilters value) {
    colour = value.colour;
    size = value.size;
    minRating = value.minRating;
    sort = value.sort;
    if (parsePriceCents(budget.text.trim()) != value.maxPriceCents) {
      budget.text = value.maxPriceCents == null
          ? ''
          : (value.maxPriceCents! / 100).toStringAsFixed(2);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.value != null) readValue(widget.value!);
  }

  @override
  void didUpdateWidget(GownFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      readValue(widget.value!);
    }
  }

  void update() {
    final text = budget.text.trim();
    final cents = text.isEmpty ? null : parsePriceCents(text);
    setState(
      () => budgetError = text.isNotEmpty && cents == null
          ? 'Enter a positive RM amount with up to 2 decimals.'
          : null,
    );
    if (budgetError != null) return;
    widget.onChanged(
      GownFilters(
        colour: colour,
        size: size,
        maxPriceCents: cents,
        sort: sort,
        minRating: minRating,
      ),
    );
  }

  @override
  void dispose() {
    budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: const Icon(Icons.tune),
    dense: widget.compact,
    title: Text(widget.compact ? 'Filters & sort' : 'Refine your selection'),
    subtitle: widget.compact
        ? null
        : Text(
            widget.includePrice
                ? 'Colour, size, budget and sorting'
                : 'Colour and size',
          ),
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: colour ?? 'Any',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Colour'),
              items: [
                'Any',
                ...dressColours,
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) {
                colour = v == 'Any' ? null : v;
                update();
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: size ?? 'Any',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Size'),
              items: [
                'Any',
                ...dressSizes,
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) {
                size = v == 'Any' ? null : v;
                update();
              },
            ),
          ),
          if (widget.includePrice) ...[
            SizedBox(
              width: 220,
              child: TextField(
                controller: budget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Maximum price (RM)',
                  hintText: 'No limit',
                  errorText: budgetError,
                ),
                onChanged: (_) => update(),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<GownSort>(
                initialValue: sort,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items: [
                  const DropdownMenuItem(
                    value: GownSort.name,
                    child: Text('Name'),
                  ),
                  const DropdownMenuItem(
                    value: GownSort.priceLow,
                    child: Text('Price: low to high'),
                  ),
                  const DropdownMenuItem(
                    value: GownSort.priceHigh,
                    child: Text('Price: high to low'),
                  ),
                  if (widget.includeRatings)
                    const DropdownMenuItem(
                      value: GownSort.ratingHigh,
                      child: Text('Highest rated'),
                    ),
                ],
                onChanged: (v) {
                  sort = v ?? GownSort.name;
                  update();
                },
              ),
            ),
          ],
          if (widget.includeRatings)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<double>(
                key: const Key('minimum-gown-rating'),
                initialValue: minRating ?? 0,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Minimum rating'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('All ratings')),
                  DropdownMenuItem(value: 4, child: Text('4 stars & up')),
                  DropdownMenuItem(value: 4.5, child: Text('4.5 stars & up')),
                ],
                onChanged: (v) {
                  minRating = v == 0 ? null : v;
                  update();
                },
              ),
            ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Listed sizes do not guarantee fit or availability on your rental dates.',
        ),
      ),
    ],
  );
}
