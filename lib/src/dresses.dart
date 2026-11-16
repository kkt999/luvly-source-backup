import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import '../recommendations/recommendation_screen.dart';
import 'live_try_on.dart';
import 'live_catalogue.dart';
import '../shortlist/shortlist_screen.dart';
export 'saved_looks.dart';

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});
  @override
  State<CatalogueScreen> createState() => _CatalogueState();
}

class _CatalogueState extends State<CatalogueScreen> {
  String query = '', category = 'All';
  double maxPrice = 5000;
  @override
  Widget build(BuildContext c) {
    if (AppScope.of(c).accountId != null) return const LiveCatalogueScreen();
    final filtered = List.generate(dresses.length, (i) => i)
        .where(
          (i) =>
              dresses[i].name.toLowerCase().contains(query.toLowerCase()) &&
              (category == 'All' || dresses[i].shape == category) &&
              dresses[i].price <= maxPrice,
        )
        .toList();
    return PageList(
      children: [
        Text(
          'The one is waiting.',
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        gap(6),
        const Text(
          'Find a dress that feels like you.',
          style: TextStyle(color: muted),
        ),
        gap(20),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  hintText: 'Search dresses',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: 'Filter by price',
              onPressed: () => showModalBottomSheet<void>(
                context: c,
                showDragHandle: true,
                builder: (c) => StatefulBuilder(
                  builder: (c, change) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Make it yours',
                            style: Theme.of(c).textTheme.headlineMedium,
                          ),
                          gap(),
                          Text('Maximum price: ${money(maxPrice)}'),
                          Slider(
                            value: maxPrice,
                            min: 2500,
                            max: 5000,
                            divisions: 10,
                            onChanged: (v) {
                              change(() => maxPrice = v);
                              setState(() => maxPrice = v);
                            },
                          ),
                          Primary(
                            'Show matching dresses',
                            () => Navigator.pop(c),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        gap(14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in [
                'All',
                'A-Line',
                'Ball Gown',
                'Mermaid',
                'Sheath',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item),
                    selected: category == item,
                    onSelected: (_) => setState(() => category = item),
                  ),
                ),
            ],
          ),
        ),
        gap(14),
        Row(
          children: [
            Expanded(
              child: Text(
                '${filtered.length} beautiful possibilities',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'My shortlist',
              onPressed: () => go(c, const ShortlistScreen()),
              icon: const Icon(Icons.favorite_border, color: rose),
            ),
          ],
        ),
        gap(6),
        if (filtered.isEmpty)
          const EmptyState(
            Icons.search_off,
            'No dresses found',
            'Try a different name, style or price range.',
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              mainAxisExtent: 280,
            ),
            itemBuilder: (_, i) => DressCard(index: filtered[i]),
          ),
        gap(20),
        MenuTile(
          Icons.auto_awesome,
          'A little help finding the one',
          'Find gowns for your style',
          () => go(c, const RecommendationsScreen()),
        ),
      ],
    );
  }
}

class DressCard extends StatelessWidget {
  const DressCard({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext c) {
    final d = dresses[index], m = AppScope.of(c);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => go(c, DressDetailScreen(index: index)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                photo(
                  d.asset,
                  height: 172,
                  width: double.infinity,
                  fit: d.referenceUrl != null ? BoxFit.contain : BoxFit.cover,
                ),
                Positioned(
                  right: 5,
                  top: 5,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton.filledTonal(
                      style: IconButton.styleFrom(backgroundColor: ivory),
                      padding: EdgeInsets.zero,
                      tooltip: m.shortlist.contains(index)
                          ? 'Remove ${d.name} from shortlist'
                          : 'Save ${d.name}',
                      onPressed: () => m.toggleShortlist(index),
                      icon: Icon(
                        m.shortlist.contains(index)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 18,
                        color: rose,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  gap(4),
                  Text(
                    d.referenceUrl != null ? 'Reference study' : d.priceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: rose, fontSize: 12),
                  ),
                  Text(
                    '${d.shape}${d.arAsset != null ? ' • AR preview' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DressDetailScreen extends StatefulWidget {
  const DressDetailScreen({super.key, required this.index});
  final int index;
  @override
  State<DressDetailScreen> createState() => _DressDetailState();
}

class _DressDetailState extends State<DressDetailScreen> {
  String size = 'M', colour = 'Ivory';
  @override
  Widget build(BuildContext c) {
    final d = dresses[widget.index], m = AppScope.of(c);
    return PageFrame(
      title: 'The details',
      actions: [
        IconButton(
          tooltip: 'Toggle shortlist',
          onPressed: () => m.toggleShortlist(widget.index),
          icon: Icon(
            m.shortlist.contains(widget.index)
                ? Icons.favorite
                : Icons.favorite_border,
            color: rose,
          ),
        ),
      ],
      bottom: Primary(
        d.arAsset != null ? 'AR try-on' : 'AR preview unavailable',
        () => go(c, TryOnGuideScreen(index: widget.index)),
        icon: Icons.camera_alt_outlined,
      ),
      child: PageList(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: photo(
              d.asset,
              height: 330,
              width: double.infinity,
              fit: d.referenceUrl != null ? BoxFit.contain : BoxFit.cover,
            ),
          ),
          gap(22),
          Row(
            children: [
              Expanded(
                child: Text(
                  d.name,
                  style: Theme.of(c).textTheme.headlineMedium,
                ),
              ),
              StatusPill(d.referenceUrl != null ? 'Study' : 'Available'),
            ],
          ),
          gap(8),
          Text(
            d.priceLabel,
            style: const TextStyle(
              color: rose,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          gap(14),
          Text(d.description, style: const TextStyle(color: muted)),
          if (d.credits != null)
            SelectableText(
              d.credits!,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          if (d.referenceUrl != null)
            SelectableText(
              'Reference: ${d.referenceUrl}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          if (d.referenceUrl == null) ...[
            const Section('Colour'),
            Wrap(
              spacing: 8,
              children: [
                for (final v in ['Ivory', 'Champagne', 'White'])
                  ChoiceChip(
                    label: Text(v),
                    selected: colour == v,
                    onSelected: (_) => setState(() => colour = v),
                  ),
              ],
            ),
            const Section('Your size'),
            Wrap(
              spacing: 8,
              children: [
                for (final v in ['XS', 'S', 'M', 'L', 'XL'])
                  ChoiceChip(
                    label: Text(v),
                    selected: size == v,
                    onSelected: (_) => setState(() => size = v),
                  ),
              ],
            ),
          ],
          gap(18),
          OutlinedButton.icon(
            onPressed: () => m.toggleShortlist(widget.index),
            icon: Icon(
              m.shortlist.contains(widget.index)
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
            label: Text(
              m.shortlist.contains(widget.index)
                  ? 'Saved to shortlist'
                  : 'Add to shortlist',
            ),
          ),
          DemoNote(
            text:
                d.previewNote ??
                (d.referenceUrl != null
                    ? 'Independent approximate reference study. Ivory model only. No manufacturer affiliation or sizing guarantee.'
                    : 'Catalogue photography is temporary imagery taken from your Chapter 4 reference. Size and colour selections are preview-only.'),
          ),
        ],
      ),
    );
  }
}

class ShortlistScreen extends StatelessWidget {
  const ShortlistScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    if (m.accountId != null) {
      return const LiveShortlistScreen();
    }
    return PageFrame(
      title: 'My shortlist',
      child: PageList(
        children: [
          Text(
            'The dresses you love.',
            style: Theme.of(c).textTheme.headlineMedium,
          ),
          gap(18),
          if (m.shortlist.isEmpty)
            const EmptyState(
              Icons.favorite_border,
              'Your favourites live here',
              'Tap the heart on a dress to save it.',
            ),
          for (final i in m.shortlist.toList())
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: photo(dresses[i].asset, height: 90, width: 70),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        onTap: () => go(c, DressDetailScreen(index: i)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dresses[i].name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            gap(5),
                            Text(
                              dresses[i].priceLabel,
                              style: const TextStyle(color: rose),
                            ),
                            TextButton(
                              onPressed: () =>
                                  go(c, TryOnGuideScreen(index: i)),
                              child: const Text('Try-on preview'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove from shortlist',
                      onPressed: () => m.toggleShortlist(i),
                      icon: const Icon(Icons.favorite, color: rose),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key});
  @override
  Widget build(BuildContext context) => const PersonalizedGownsScreen();
}

class TryOnGuideScreen extends StatelessWidget {
  const TryOnGuideScreen({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Your try-on moment',
    bottom: dresses[index].arAsset != null
        ? Primary(
            'Start live try-on',
            () => openLiveTryOn(c, dress: dresses[index]),
          )
        : Primary('Browse AR dresses', () => go(c, const CatalogueScreen())),
    child: PageList(
      children: [
        Text(dresses[index].name, style: Theme.of(c).textTheme.headlineSmall),
        if (dresses[index].arAsset == null)
          const DemoNote(
            text:
                'AR preview unavailable for this dress. No substitute model will be shown. Select Princess Wedding Dress or Francine — reference study from the catalogue to try a supported model.',
          ),
        Surface(
          color: blush,
          child: const SizedBox(
            height: 160,
            width: double.infinity,
            child: Icon(Icons.accessibility_new, size: 110, color: rose),
          ),
        ),
        const Section('A few little preparations'),
        for (final s in [
          'Choose a bright, well-lit space',
          'Keep your whole body in the frame',
          'Wear fitted clothing',
          'Use the widest camera view; step back only as needed',
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.check_circle_outline,
              color: rose,
              size: 22,
            ),
            title: Text(s),
          ),
        const Section('See your look, then decide'),
        const Text(
          'Place your phone securely and tap Preview · 10s before stepping back. You have 10 seconds to pose; the dress aligns automatically. Then choose Retake or Save look. Compare saved looks from Profile → My try-on history.',
        ),
        const DemoNote(
          text:
              'Appearance preview only—not a size or fit assessment. Your existing clothes are not removed. Reference models are approximate and not verified shop stock. Nothing is saved until you tap Save look. Saved looks stay in this installation, are not backed up, and are removed if you uninstall the app. Confirm colour, size and comfort at a real fitting.',
        ),
      ],
    ),
  );
}
