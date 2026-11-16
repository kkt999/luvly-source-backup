import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../src/design.dart' show blush, line, Surface;
import 'package_api.dart';

class FittingGownSummary extends StatelessWidget {
  const FittingGownSummary({super.key, required this.selection});

  final PackageSelection selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gowns = selection.selectedGowns;
    final accessories = selection.data['selectedAccessories'] as List? ?? [];
    final repository = context
        .dependOnInheritedWidgetOfExactType<CatalogueScope>()
        ?.repository;

    Widget summary(List<CatalogueDress> catalogue) => Surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final gown in gowns)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GownSummaryRow(
                name: gown['name'],
                size: gown['size'],
                dress: catalogue
                    .where((d) => d.id == gown['dressId'])
                    .firstOrNull,
                repository: repository,
              ),
            ),
          for (final accessory in accessories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.diamond_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(accessory['name'])),
                ],
              ),
            ),
          Text(
            '${selection.name} · ${packageMoney(selection.totalCents)}',
            style: gowns.isNotEmpty || accessories.isNotEmpty
                ? theme.textTheme.bodySmall
                : theme.textTheme.titleMedium,
          ),
        ],
      ),
    );

    return repository == null || gowns.isEmpty
        ? summary(const [])
        : CatalogueFeed(
            inventory: false,
            builder: (_, snapshot) => summary(snapshot.dresses),
            fallbackBuilder: (_, _, _) => summary(const []),
          );
  }
}

class _GownSummaryRow extends StatelessWidget {
  const _GownSummaryRow({
    required this.name,
    required this.size,
    required this.dress,
    required this.repository,
  });

  final String name, size;
  final CatalogueDress? dress;
  final CatalogueRepository? repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Center(
      child: Icon(Icons.checkroom_outlined, color: theme.colorScheme.primary),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: 56,
            child: ColoredBox(
              color: blush,
              child: dress == null
                  ? fallback
                  : CatalogueDressPhoto(
                      key: ValueKey(dress!.id),
                      dress: dress!,
                      repository: repository,
                      height: 56,
                      placeholder: fallback,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleMedium),
              Text('Selected size: $size', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class FittingPreferenceCard<T> extends StatelessWidget {
  const FittingPreferenceCard({
    super.key,
    required this.value,
    required this.title,
    required this.description,
    required this.selected,
    required this.enabled,
  });

  final T value;
  final String title, description;
  final bool selected, enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? blush : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? theme.colorScheme.primary : line),
        ),
        clipBehavior: Clip.antiAlias,
        child: RadioListTile<T>(
          value: value,
          enabled: enabled,
          selected: selected,
          contentPadding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
          title: Text(title, style: theme.textTheme.titleMedium),
          subtitle: Text(description, style: theme.textTheme.bodySmall),
        ),
      ),
    );
  }
}
