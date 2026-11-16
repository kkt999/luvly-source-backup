import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../catalogue/gown_filters.dart';
import '../catalogue/gown_filter_sheet.dart';
import '../catalogue/gown_product_content.dart';
import '../catalogue/gown_preview_tools.dart';
import '../reviews/gown_reviews.dart';
import '../reviews/review_api.dart';
import '../reviews/gown_rating.dart';
import 'design.dart';
import '../catalogue/ar_models.dart';
import 'ar_preview.dart';
import 'gown_viewer.dart';
import '../bookings/booking_screens.dart';
import 'model.dart' show AppScope;
import '../recommendations/recommendation_screen.dart';
import '../shortlist/shortlist_widgets.dart';
import '../shortlist/shortlist_screen.dart';

class LiveCatalogueScreen extends StatefulWidget {
  const LiveCatalogueScreen({super.key, this.reviewApi});
  final ReviewApi? reviewApi;
  @override
  State<LiveCatalogueScreen> createState() => _LiveCatalogueScreenState();
}

class _LiveCatalogueScreenState extends State<LiveCatalogueScreen> {
  String query = '', category = 'All';
  bool availableOnly = false;
  GownFilters filters = const GownFilters();
  late final reviewApi = widget.reviewApi ?? ReviewApi();
  Map<String, GownRating> ratings = {};
  String? ratingsError, ratingsUid;
  bool ratingsLoading = false, ratingsLoaded = false;
  int ratingGeneration = 0;
  int get activeFilterCount => [
    filters.colour,
    filters.size,
    filters.maxPriceCents,
    filters.minRating,
    if (filters.sort != GownSort.name) filters.sort,
    if (availableOnly) true,
  ].where((v) => v != null).length;
  Future<void> editFilters(List<CatalogueDress> candidates) async {
    final result = await showGownFilterSheet(
      context,
      initial: filters,
      availableOnly: availableOnly,
      candidates: candidates,
      ratings: ratings,
      includeRatings: ratingsUid != null,
      ratingsReady: ratingsLoaded,
    );
    if (mounted && result != null) {
      setState(() {
        filters = result.filters;
        availableOnly = result.availableOnly;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AppScope.maybeOf(context)?.accountId;
    if (uid != ratingsUid) {
      ratingsUid = uid;
      ratings = {};
      ratingsLoaded = false;
      ratingsError = null;
      ratingGeneration++;
      ratingsLoading = false;
      if (uid != null) loadRatings();
    }
  }

  Future<void> loadRatings() async {
    if (ratingsLoading || ratingsUid == null) return;
    final generation = ++ratingGeneration;
    setState(() {
      ratingsLoading = true;
      ratingsError = null;
    });
    try {
      final result = catalogueRatings(
        await reviewApi.call('/v1/reviews/ratings'),
      );
      if (mounted && generation == ratingGeneration) {
        setState(() {
          ratings = result;
          ratingsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted && generation == ratingGeneration) {
        setState(() {
          ratings = {};
          ratingsLoaded = false;
          ratingsError = 'Ratings are temporarily unavailable.';
        });
      }
    } finally {
      if (mounted && generation == ratingGeneration) {
        setState(() => ratingsLoading = false);
      }
    }
  }

  Future<void> openDress(CatalogueDress dress) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LiveDressDetailScreen(id: dress.id, reviewApi: reviewApi),
      ),
    );
    if (mounted) await loadRatings();
  }

  @override
  void dispose() {
    if (widget.reviewApi == null) reviewApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CatalogueFeed(
    inventory: false,
    builder: (context, snapshot) => collection(context, snapshot),
    fallbackBuilder: (context, loading, retry) => collection(
      context,
      const CatalogueSnapshot([]),
      loading: loading,
      retry: retry,
    ),
  );

  Widget collection(
    BuildContext context,
    CatalogueSnapshot snapshot, {
    bool loading = false,
    VoidCallback? retry,
  }) {
    // Only published records suppress their bundled reference card.
    // A private draft must never hide or reveal a reference association.
    final linkedIds = snapshot.dresses
        .where((d) => d.published)
        .map((d) => d.arModelId)
        .toSet();
    final references = browseArDresses
        .where(
          (d) =>
              !linkedIds.contains(d.id) &&
              !availableOnly &&
              !filters.hasProductConstraints &&
              '${d.name} white'.toLowerCase().contains(
                query.trim().toLowerCase(),
              ) &&
              (category == 'All' || category == d.shape),
        )
        .toList();
    final waitingForRatings = filters.needsRatings && !ratingsLoaded;
    final candidates = snapshot.dresses
        .where(
          (d) =>
              d.published &&
              '${d.name} ${d.colour}'.toLowerCase().contains(
                query.trim().toLowerCase(),
              ) &&
              (category == 'All' || category == d.category),
        )
        .toList();
    final dresses = waitingForRatings
        ? <CatalogueDress>[]
        : filters.apply(
            candidates.where(
              (d) => !availableOnly || d.availability == 'Available',
            ),
            ratings: ratings,
          );
    return PageList(
      children: [
        Text(
          'Find your kind of beautiful.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        gap(6),
        const Text(
          'Discover a gown for your day.',
          style: TextStyle(color: muted),
        ),
        if (AppScope.maybeOf(context)?.accountId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('catalogue-recommendations'),
              onPressed: () => go(context, const PersonalizedGownsScreen()),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Find my style'),
            ),
          ),
        gap(18),
        const ShortlistNotice(),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            hintText: 'Search dresses or colours',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        gap(12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final style in ['All', ...dressCategories])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    chipAnimationStyle: CustomerUi.chipMotion(context),
                    showCheckmark: false,
                    selectedColor: blush,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: category == style ? rose : line),
                    label: Text(style),
                    selected: category == style,
                    onSelected: (_) => setState(() => category = style),
                  ),
                ),
            ],
          ),
        ),
        gap(12),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (AppScope.maybeOf(context)?.accountId != null)
              TextButton.icon(
                onPressed: () => go(context, const LiveShortlistScreen()),
                icon: const Icon(Icons.favorite_border, size: 18),
                label: const Text('My shortlist'),
              ),
            OutlinedButton.icon(
              key: const Key('open-catalogue-filters'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              onPressed: () => editFilters(candidates),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(
                'Filters & sort${activeFilterCount == 0 ? '' : ' · $activeFilterCount'}',
              ),
            ),
            if (activeFilterCount > 0)
              TextButton(
                key: const Key('clear-catalogue-filters'),
                onPressed: () => setState(() {
                  filters = const GownFilters();
                  availableOnly = false;
                }),
                child: const Text('Clear'),
              ),
          ],
        ),
        if (activeFilterCount > 0) ...[
          gap(8),
          Text(
            [
              if (filters.colour != null) filters.colour!,
              if (filters.size != null) 'Size ${filters.size}',
              if (filters.maxPriceCents != null)
                'Up to RM ${(filters.maxPriceCents! / 100).toStringAsFixed(2)}',
              if (filters.minRating != null) '${filters.minRating}+ stars',
              if (availableOnly) 'Available now',
              if (filters.sort != GownSort.name)
                switch (filters.sort) {
                  GownSort.priceLow => 'Price: low to high',
                  GownSort.priceHigh => 'Price: high to low',
                  GownSort.ratingHigh => 'Highest rated',
                  GownSort.name => 'Name',
                },
            ].join(' · '),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
        gap(16),
        Text(
          'Boutique collection',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        gap(4),
        Text(
          '${dresses.length} ${dresses.length == 1 ? 'gown' : 'gowns'} · Confirm availability for your rental dates',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        gap(14),
        if (ratingsError != null) ...[
          Text(ratingsError!, style: const TextStyle(color: muted)),
          TextButton.icon(
            onPressed: ratingsLoading ? null : loadRatings,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry ratings'),
          ),
        ] else if (ratingsLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Loading ratings…',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (retry != null) ...[
          Text(
            loading
                ? 'Loading boutique dresses…'
                : 'Unable to load boutique dresses. AR previews are still available.',
          ),
          if (!loading)
            TextButton(onPressed: retry, child: const Text('Retry')),
        ] else if (waitingForRatings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              ratingsError == null
                  ? 'Loading the ratings for your selection…'
                  : 'Retry ratings or choose All ratings to continue browsing.',
            ),
          )
        else if (dresses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No matching gowns. Try another search or filter.',
              style: TextStyle(color: muted),
            ),
          ),
        if (snapshot.fromCache) ...[
          const Text(
            'Offline or reconnecting · Availability may have changed.',
            style: TextStyle(color: muted),
          ),
          gap(12),
        ],
        if (dresses.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
              final columns =
                  dresses.length == 1 || constraints.maxWidth < 300 || largeText
                  ? 1
                  : constraints.maxWidth >= 700
                  ? 3
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 22,
                children: [
                  for (final dress in dresses)
                    SizedBox(
                      width: width,
                      child: _BoutiqueGownCard(
                        dress: dress,
                        wide: columns == 1,
                        rating: ratings[dress.id],
                        onOpen: () => openDress(dress),
                      ),
                    ),
                ],
              );
            },
          ),
        if (references.isNotEmpty) ...[
          gap(28),
          const Divider(height: 1),
          gap(24),
          Row(
            children: [
              const Icon(Icons.view_in_ar_outlined, color: rose, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The AR studio',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          gap(6),
          Text(
            '${references.length} ${references.length == 1 ? 'preview' : 'previews'} · Explore digital gowns',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          gap(4),
          const Text(
            'Reference models only — not rental stock.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          gap(16),
          for (final reference in references) ...[
            _ArReferenceCard(
              key: ValueKey('ar-reference-${reference.id}'),
              name: reference.name,
              asset: reference.asset,
              onTryOn: () => go(context, ArTryOnGuideScreen(dress: reference)),
              onView: supportsGownViewer(reference)
                  ? () => openGownViewer(context, reference)
                  : null,
            ),
            gap(12),
          ],
        ],
        // Keep the last action above the customer assistant overlay.
        gap(72),
      ],
    );
  }
}

class _BoutiqueGownCard extends StatelessWidget {
  const _BoutiqueGownCard({
    required this.dress,
    required this.onOpen,
    this.wide = false,
    this.rating,
  });
  final CatalogueDress dress;
  final bool wide;
  final GownRating? rating;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: CustomerUi.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: CustomerUi.cardRadius,
              child: AspectRatio(
                aspectRatio: wide ? 1.2 : .8,
                child: LayoutBuilder(
                  builder: (_, constraints) => ColoredBox(
                    color: CustomerUi.linen,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CatalogueDressPhoto(
                          dress: dress,
                          height: constraints.maxHeight,
                          compact: true,
                        ),
                        if (resolveArDress(dress.arModelId) != null)
                          Positioned(
                            left: 8,
                            top: 8,
                            right: 62,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: IgnorePointer(
                                child: Container(
                                  key: ValueKey('ar-badge-${dress.id}'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xF2FFFFFF),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'AR available',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF743B4B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: ShortlistButton(
                            dressId: dress.id,
                            label: dress.name,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            gap(10),
            Text(
              dress.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            gap(3),
            Text(
              dress.priceLabel,
              style: const TextStyle(color: rose, fontWeight: FontWeight.w600),
            ),
            gap(3),
            Text(
              '${dress.colour} · ${dress.availability}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
            if (rating != null) ...[
              gap(6),
              Semantics(
                label: rating!.rated
                    ? 'Customer rating: ${rating!.average.toStringAsFixed(1)} out of 5, ${rating!.count} reviews'
                    : 'No reviews yet',
                child: Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      rating!.rated
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 15,
                      color: rose,
                    ),
                    Text(
                      rating!.label,
                      key: ValueKey('gown-rating-${dress.id}'),
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArReferenceCard extends StatelessWidget {
  const _ArReferenceCard({
    super.key,
    required this.name,
    required this.asset,
    required this.onTryOn,
    this.onView,
  });
  final String name, asset;
  final VoidCallback onTryOn;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFFF0EDE9),
        child: Image.asset(
          'assets/images/$asset.jpg',
          width: largeText ? double.infinity : 88,
          height: largeText ? 180 : 118,
          fit: BoxFit.contain,
        ),
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        gap(4),
        const Text(
          'Virtual try-on',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        gap(6),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 44),
              ),
              onPressed: onTryOn,
              child: const Text('AR try-on'),
            ),
            if (onView != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: onView,
                child: const Text('360° view'),
              ),
          ],
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: largeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [image, gap(12), content],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                image,
                const SizedBox(width: 14),
                Expanded(child: content),
              ],
            ),
    );
  }
}

class LiveDressDetailScreen extends StatelessWidget {
  const LiveDressDetailScreen({super.key, required this.id, this.reviewApi});
  final String id;
  final ReviewApi? reviewApi;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Gown details',
    actions: [ShortlistButton(dressId: id)],
    child: CatalogueFeed(
      inventory: false,
      builder: (context, snapshot) {
        CatalogueDress? found;
        for (final d in snapshot.dresses) {
          if (d.id == id && d.published) found = d;
        }
        final d = found;
        if (d == null) {
          return const EmptyState(
            Icons.checkroom_outlined,
            'Dress no longer listed',
            'Return to the catalogue to explore other dresses.',
          );
        }
        final arDress = resolveArDress(d.arModelId);
        return GownReviews(
          key: ValueKey('reviews-${d.id}'),
          dressId: d.id,
          dressName: d.name,
          api: reviewApi,
          enabled: AppScope.maybeOf(context)?.accountId != null,
          builder: (rating, reviews) => PageList(
            children: [
              if (snapshot.fromCache) ...[
                const Text(
                  'Showing cached details. Confirm current availability with the boutique.',
                ),
                gap(12),
              ],
              const ShortlistNotice(),
              GownProductContent(
                key: ValueKey('product-${d.id}'),
                dress: d,
                rating: rating,
                belowPhoto: arDress != null || BridalMakeupButton.isAvailable
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (arDress != null)
                            GownPreviewTools(
                              model: arDress,
                              catalogueName: d.name,
                            ),
                          if (BridalMakeupButton.isAvailable)
                            const BridalMakeupButton(),
                        ],
                      )
                    : null,
              ),
              gap(12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(d.availability),
              ),
              gap(24),
              if (AppScope.maybeOf(context)?.accountId != null) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Book a fitting'),
                  onPressed: () {
                    final account = AppScope.of(context);
                    go(
                      context,
                      BookingRequestForm(
                        uid: account.accountId!,
                        name: account.name,
                        phone: account.phone,
                        dressId: d.id,
                        dressName: d.name,
                      ),
                    );
                  },
                ),
                gap(12),
                Text(
                  'RM 50 per 60-minute fitting. Try multiple gowns during your visit. Check My rentals & packages for any rental reservation.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              reviews,
              gap(72),
            ],
          ),
        );
      },
    ),
  );
}
