import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'catalogue_repository.dart';
import 'catalogue_widgets.dart';
import 'gown_size_help.dart';

/// Shared product presentation. Choosing a size does not reserve stock.
class GownProductContent extends StatefulWidget {
  const GownProductContent({
    super.key,
    required this.dress,
    this.repository,
    this.api,
    this.initialSize,
    this.onSizeChanged,
    this.included = false,
    this.availableSizes,
    this.availabilityNote,
    this.belowPhoto,
    this.rating,
  });
  final CatalogueDress dress;
  final CatalogueRepository? repository;
  final HttpPaymentApi? api;
  final String? initialSize;
  final ValueChanged<String>? onSizeChanged;
  final bool included;
  final Set<String>? availableSizes;
  final String? availabilityNote;
  final Widget? belowPhoto;
  final Widget? rating;
  @override
  State<GownProductContent> createState() => _GownProductContentState();
}

class _GownProductContentState extends State<GownProductContent> {
  String? size;
  @override
  void initState() {
    super.initState();
    size = widget.initialSize;
  }

  void choose(String value) {
    if (widget.availableSizes != null &&
        !widget.availableSizes!.contains(value)) {
      return;
    }
    setState(() => size = value);
    widget.onSizeChanged?.call(value);
  }

  Future<void> guide() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: GownSizeHelp(
          dressId: widget.dress.id,
          dressName: widget.dress.name,
          api: widget.api,
          selectableSizes: widget.dress.sizes
              .split(', ')
              .where(
                (s) =>
                    widget.availableSizes == null ||
                    widget.availableSizes!.contains(s),
              )
              .toList(),
        ),
      ),
    );
    if (mounted &&
        chosen != null &&
        widget.dress.sizes.split(', ').contains(chosen)) {
      choose(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dress;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Enlarge ${d.name} photograph',
          child: InkWell(
            key: ValueKey('zoom-${d.id}'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(d.name),
                    leading: IconButton(
                      tooltip: 'Close photograph',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  body: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: CatalogueDressPhoto(
                        dress: d,
                        repository: widget.repository,
                        height: MediaQuery.sizeOf(context).height * .75,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: Container(
              color: const Color(0xFFF5EFEB),
              child: Stack(
                children: [
                  CatalogueDressPhoto(
                    dress: d,
                    repository: widget.repository,
                    height:
                        MediaQuery.sizeOf(context).height.clamp(600, 900) * .45,
                  ),
                  const Positioned(
                    right: 12,
                    bottom: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.zoom_in, color: Color(0xFF7D3D4E)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.belowPhoto != null) widget.belowPhoto!,
        const SizedBox(height: 22),
        Text(
          d.category.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(d.name, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          widget.included ? 'Included in your package' : d.priceLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (!widget.included) ...[
          const SizedBox(height: 4),
          Text(
            'Up to 3 calendar days · pickup and return included',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (widget.rating != null) widget.rating!,
        const Divider(height: 32),
        Text('Colour · ${d.colour}', style: theme.textTheme.titleSmall),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                size == null || size!.isEmpty
                    ? 'Select a size'
                    : 'Selected size: $size',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('product-size-guide'),
              onPressed: guide,
              icon: const Icon(Icons.straighten, size: 18),
              label: const Text('Size guide'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in d.sizes.split(', '))
              ChoiceChip(
                key: ValueKey('size-${d.id}-$value'),
                label: Text(value),
                selected: size == value,
                onSelected:
                    widget.availableSizes != null &&
                        !widget.availableSizes!.contains(value)
                    ? null
                    : (_) => choose(value),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          widget.availabilityNote ??
              'Fit and availability for your rental dates are confirmed by the boutique.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('About this gown'),
          initiallyExpanded: true,
          childrenPadding: const EdgeInsets.only(bottom: 18),
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(d.description)),
            const SizedBox(height: 16),
            for (final entry in <String, String>{
              'Silhouette': d.category,
              'Colour': d.colour,
              if (d.productDetails['neckline'] != null)
                'Neckline': d.productDetails['neckline']!,
              if (d.productDetails['fabricAppearance'] != null)
                'Fabric & finish': d.productDetails['fabricAppearance']!,
              if (d.productDetails['train'] != null)
                'Skirt & train': d.productDetails['train']!,
              if (d.productDetails['features'] != null)
                'Design details': d.productDetails['features']!,
            }.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final label = Text(
                      entry.key,
                      style: theme.textTheme.bodySmall,
                    );
                    final value = Text(entry.value);
                    if (box.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                      return SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [label, const SizedBox(height: 3), value],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 110, child: label),
                        const SizedBox(width: 12),
                        Expanded(child: value),
                      ],
                    );
                  },
                ),
              ),
            if (d.arModelId.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Images are 3D style illustrations. Confirm the fabric, colour and final details at your fitting.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Fit & sizing'),
          childrenPadding: const EdgeInsets.only(bottom: 18),
          children: [
            const Text(
              'Check the size guide using your bust, waist and hip measurements. A fitting confirms the final fit.',
            ),
            TextButton(onPressed: guide, child: const Text('Open size guide')),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Rental & care'),
          childrenPadding: const EdgeInsets.only(bottom: 18),
          children: const [
            Text(
              'Your rental includes pickup and return within the agreed rental period. Extra days are available through package options, subject to availability.',
            ),
            SizedBox(height: 12),
            Text(
              'The boutique handles cleaning after return. Please keep the gown dry and contact us before washing, altering or repairing it.',
            ),
            SizedBox(height: 12),
            Text(
              'Your selection is a preference. Stock is reserved through the confirmed rental and verified booking deposit.',
            ),
          ],
        ),
      ],
    );
  }
}
