import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../src/design.dart';
import '../src/live_catalogue.dart';
import 'shortlist_controller.dart';
import 'shortlist_widgets.dart';

class LiveShortlistScreen extends StatelessWidget {
  const LiveShortlistScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = ShortlistScope.maybeOf(context);
    return PageFrame(
      title: 'My shortlist',
      child: state?.uid == null
          ? const EmptyState(
              Icons.favorite_border,
              'Your favourites, together',
              'Sign in to save gowns to your account.',
            )
          : state!.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? PageList(
              children: [
                const EmptyState(
                  Icons.cloud_off_outlined,
                  'Let’s reconnect',
                  'Your saved gowns could not be loaded.',
                ),
                Primary('Retry shortlist', state.retry),
              ],
            )
          : state.ids.isEmpty
          ? PageList(
              children: [
                const ShortlistNotice(),
                const EmptyState(
                  Icons.favorite_border,
                  'Find a gown to fall for',
                  'Tap the heart on a gown to keep it here for later.',
                ),
                Primary(
                  'Explore gowns',
                  () => go(
                    context,
                    const PageFrame(
                      title: 'Wedding dresses',
                      child: LiveCatalogueScreen(),
                    ),
                  ),
                ),
              ],
            )
          : CatalogueFeed(
              inventory: false,
              builder: (context, snapshot) =>
                  savedGowns(context, state, snapshot),
            ),
    );
  }

  Widget savedGowns(
    BuildContext context,
    ShortlistController state,
    CatalogueSnapshot snapshot,
  ) {
    final byId = {
      for (final d in snapshot.dresses.where((d) => d.published)) d.id: d,
    };
    return PageList(
      children: [
        Text(
          'The gowns you love.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        gap(8),
        Text(
          '${state.ids.length} saved ${state.ids.length == 1 ? 'gown' : 'gowns'}',
          style: const TextStyle(color: muted),
        ),
        gap(8),
        const Text(
          'Keep your favourites together while you find the one.',
          style: TextStyle(color: muted),
        ),
        gap(16),
        const ShortlistNotice(),
        if (snapshot.fromCache)
          const Text(
            'Showing saved catalogue details. Current prices and availability may have changed.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        for (final id in state.ids) ...[
          if (byId[id] case final dress?)
            _SavedGown(dress: dress)
          else
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gown no longer listed',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(6),
                  const Text(
                    'This gown is unavailable in the current collection. You can remove it from your shortlist.',
                    style: TextStyle(color: muted),
                  ),
                  ShortlistButton(dressId: id, outlined: true),
                ],
              ),
            ),
          gap(14),
        ],
        gap(6),
        const Text(
          'Saving a gown does not reserve it. Availability is checked for your rental dates.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        gap(72),
      ],
    );
  }
}

class _SavedGown extends StatelessWidget {
  const _SavedGown({required this.dress});
  final CatalogueDress dress;
  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(14) > 21;
    void open() => go(context, LiveDressDetailScreen(id: dress.id));
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: large ? double.infinity : 100,
        height: large ? 230 : 140,
        child: CatalogueDressPhoto(
          dress: dress,
          height: large ? 230 : 140,
          compact: true,
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dress.name, style: Theme.of(context).textTheme.titleMedium),
        gap(6),
        Text(
          dress.priceLabel,
          style: const TextStyle(color: rose, fontWeight: FontWeight.w600),
        ),
        gap(4),
        Text(
          '${dress.category} · ${dress.colour}',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        gap(4),
        Text(
          dress.availability,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        TextButton(onPressed: open, child: const Text('View gown')),
      ],
    );
    return Surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(12),
            child: large
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [image, gap(14), details],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      image,
                      const SizedBox(width: 14),
                      Expanded(child: details),
                    ],
                  ),
          ),
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: ShortlistButton(dressId: dress.id, outlined: true),
          ),
        ],
      ),
    );
  }
}
