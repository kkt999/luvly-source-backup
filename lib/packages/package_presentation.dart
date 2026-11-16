import 'package:flutter/material.dart';
import '../promotions/campaign_visuals.dart';
import '../src/design.dart' show CustomerUi, line;
import 'package_api.dart';

const bridalInk = Color(0xFF382B30);
const bridalRose = Color(0xFF9E5063);
const bridalCream = Color(0xFFFAF5F0);

class PackageDetailsHeader extends StatefulWidget {
  const PackageDetailsHeader({
    super.key,
    required this.package,
    this.showCover = true,
  });

  final BridalPackage package;
  final bool showCover;

  @override
  State<PackageDetailsHeader> createState() => _PackageDetailsHeaderState();
}

class _PackageDetailsHeaderState extends State<PackageDetailsHeader> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final package = widget.package;
    final theme = Theme.of(context);
    final cover = widget.showCover ? CampaignLook.forPackage(package.id) : null;
    final description = package.description.trim();
    final descriptionStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cover != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: CustomerUi.featureRadius,
              child: _PackageInspiration(cover.image),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final name = Text(
              package.name,
              style: theme.textTheme.headlineMedium,
            );
            final price = Text(
              packageMoney(package.basePriceCents),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            );
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            if (constraints.maxWidth < 320 || scale > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [name, const SizedBox(height: 4), price],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: name),
                const SizedBox(width: 12),
                price,
              ],
            );
          },
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(
                  text: description,
                  style: DefaultTextStyle.of(
                    context,
                  ).style.merge(descriptionStyle),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 2,
                ellipsis: '…',
              )..layout(maxWidth: constraints.maxWidth);
              final overflows = painter.didExceedMaxLines;
              painter.dispose();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: CustomerUi.motion(context, CustomerUi.expansion),
                    curve: Curves.easeInOutCubic,
                    alignment: AlignmentDirectional.topStart,
                    child: Text(
                      description,
                      style: descriptionStyle,
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                    ),
                  ),
                  if (overflows)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () {
                        if (expanded) Scrollable.ensureVisible(context);
                        setState(() => expanded = !expanded);
                      },
                      child: Text(expanded ? 'Read less' : 'Read more'),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _PackageInspiration extends StatelessWidget {
  const _PackageInspiration(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: double.infinity,
    height: 144,
    fit: BoxFit.cover,
    alignment: const Alignment(0, -.35),
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
    frameBuilder: (context, photo, frame, _) => Stack(
      alignment: AlignmentDirectional.bottomEnd,
      children: [
        photo,
        if (frame != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: CustomerUi.paper,
                borderRadius: CustomerUi.controlRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Style inspiration',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class PackageIncludes extends StatelessWidget {
  const PackageIncludes({super.key, required this.items});

  final List<(String, bool)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bridalCream,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Package Includes', style: theme.textTheme.titleLarge),
            const SizedBox(height: 7),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final width = constraints.maxWidth >= 270 && scale <= 1.3
                    ? (constraints.maxWidth - gap) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: gap,
                  runSpacing: 5,
                  children: [
                    for (final (label, removable) in items)
                      SizedBox(
                        width: width,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  if (removable)
                                    Text(
                                      'Removable',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PackageEditorialHeader extends StatelessWidget {
  const PackageEditorialHeader({super.key});
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: bridalCream,
      borderRadius: CustomerUi.featureRadius,
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 700;
        final theme = Theme.of(context);
        final copy = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 20 : 14,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your wedding look, beautifully considered.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  height: 1.05,
                  color: bridalInk,
                ),
              ),
            ],
          ),
        );
        final photo = Stack(
          children: [
            Image.asset(
              'assets/images/bridal_welcome_hd.png',
              height: wide ? 150 : 100,
              width: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment(0, wide ? -.55 : -.75),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              left: 8,
              child: Align(
                alignment: Alignment.bottomRight,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xCCFFFFFF),
                    borderRadius: CustomerUi.controlRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      'Bridal inspiration · not an included item',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: bridalInk,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        return wide
            ? Row(
                children: [
                  Expanded(child: copy),
                  Expanded(child: photo),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [photo, copy],
              );
      },
    ),
  );
}

class PackageCollectionCard extends StatelessWidget {
  const PackageCollectionCard({
    super.key,
    required this.package,
    required this.onExplore,
    required this.index,
    this.staff = false,
    this.actions = const [],
  });
  final BridalPackage package;
  final VoidCallback onExplore;
  final int index;
  final bool staff;
  final List<Widget> actions;
  static final _gownRental = RegExp(
    r'^(?:(?:one|two|three|four|[0-9]+) )?(?:wedding )?(?:gowns?|dress(?:es)?) rentals?$',
  );

  @override
  Widget build(BuildContext context) {
    final p = package;
    final theme = Theme.of(context);
    final names = <String>{};
    final included = <PackageServiceItem>[
      for (final service in p.services)
        if (service.kind != 'Add-on' && _showService(service.name, names))
          service,
    ];
    final extras = p.services.where((s) => s.kind == 'Add-on').length;
    final more = included.length - 3;
    final cover = staff ? null : CampaignLook.forPackage(p.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: staff
          ? BoxDecoration(
              color: Colors.white,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(18),
            )
          : CustomerUi.softCard,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cover != null) _PackageInspiration(cover.image),
          ColoredBox(
            color: staff ? bridalCream : CustomerUi.linen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (staff) ...[
                    Text(
                      'COLLECTION ${(index + 1).toString().padLeft(2, '0')}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: bridalRose,
                      ),
                    ),
                    Text(p.statusLabel, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    p.name,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: bridalInk,
                    ),
                  ),
                  if (p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          packageMoney(p.basePriceCents),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: bridalRose,
                          ),
                        ),
                        if (p.includedGownCount > 0)
                          Text(
                            '${p.includedGownCount} ${p.includedGownCount == 1 ? 'gown' : 'gowns'}',
                            style: theme.textTheme.labelLarge,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final service in included.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: bridalRose,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            service.name,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (more > 0)
                  Text(
                    '+ $more more included ${more == 1 ? 'service' : 'services'}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (extras > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$extras optional add-on${extras == 1 ? '' : 's'} available · priced separately',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: bridalRose,
                      ),
                    ),
                  ),
                if (included.isNotEmpty || extras > 0)
                  const SizedBox(height: 8),
                FilledButton(
                  onPressed: onExplore,
                  child: Text(staff ? 'View details' : 'Explore package'),
                ),
                if (actions.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 4, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _showService(String name, Set<String> seen) {
    final normalized = name.trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      ' ',
    );
    return !(package.includedGownCount > 0 &&
            _gownRental.hasMatch(normalized)) &&
        seen.add(normalized);
  }
}

class PackageReviewBar extends StatelessWidget {
  const PackageReviewBar({
    super.key,
    required this.totalCents,
    required this.label,
    this.error,
    this.hint,
    this.onPressed,
  });

  final int totalCents;
  final String label;
  final String? error;
  final String? hint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: const Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 764),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((error ?? hint) case final message?)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 84),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: error == null
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Package total',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        packageMoney(totalCents),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: onPressed,
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PackagePriceBreakdown extends StatelessWidget {
  const PackagePriceBreakdown({
    super.key,
    required this.package,
    required this.removed,
    required this.addons,
    this.accessoryExtraCents = 0,
    this.accessoryValueCents = 0,
    this.showPaymentEstimate = true,
    this.datesChecked = false,
  });
  final bool showPaymentEstimate, datesChecked;
  final BridalPackage package;
  final Set<String> removed, addons;
  final int accessoryExtraCents;
  final int accessoryValueCents;
  @override
  Widget build(BuildContext context) {
    final total = package.total(removed, addons) + accessoryExtraCents;
    final security = package.includedGownCount * packageGownSecurityCents;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CustomerUi.tintedCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Package summary', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          _row('Standard package', packageMoney(package.basePriceCents)),
          for (final s in package.services.where((s) => removed.contains(s.id)))
            _row('Remove ${s.name}', '− ${packageMoney(s.priceCents)}'),
          for (final s in package.services.where((s) => addons.contains(s.id)))
            _row(s.name, '+ ${packageMoney(s.priceCents)}'),
          if (accessoryValueCents > 0) ...[
            const Divider(height: 24),
            _row('Selected accessories', packageMoney(accessoryValueCents)),
            _row(
              'Covered by your package',
              '− ${packageMoney(accessoryValueCents - accessoryExtraCents)}',
            ),
            _row('Accessory surcharge', packageMoney(accessoryExtraCents)),
            if (accessoryExtraCents == 0)
              const Text(
                'Your selected accessories are included. No extra charge.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
          ] else if (accessoryExtraCents > 0)
            _row(
              'Accessories above allowance',
              '+ ${packageMoney(accessoryExtraCents)}',
            ),
          const Divider(height: 22),
          Text(
            'Total · ${packageMoney(total)}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'No payment due when saving your selection.',
            style: theme.textTheme.bodySmall,
          ),
          if (showPaymentEstimate && security > 0) ...[
            const Divider(height: 20),
            _row(
              '50% booking deposit (before credit)',
              packageMoney((total + 1) ~/ 2),
            ),
            _row('Refundable gown security', packageMoney(security)),
            _row(
              'Estimated package + security',
              packageMoney(total + security),
            ),
          ],
          ExpansionTile(
            key: const PageStorageKey('package-payment-details'),
            expansionAnimationStyle: CustomerUi.expansionMotion(context),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 6),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text('Payment details', style: theme.textTheme.titleSmall),
            children: [
              if (showPaymentEstimate && security > 0) ...[
                const Text(
                  'Estimates are before promotions and alterations. One eligible RM50 fitting fee is credited towards the booking deposit after attendance. The balance and security are due before pickup.',
                ),
                const SizedBox(height: 6),
              ],
              Text(
                datesChecked
                    ? 'Saving does not reserve stock. Availability is checked again before the booking deposit.'
                    : 'Saving does not reserve stock. Review rental dates and availability with Luvly before paying an issued invoice.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String price) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Expanded(child: Text(price, textAlign: TextAlign.end)),
      ],
    ),
  );
}
