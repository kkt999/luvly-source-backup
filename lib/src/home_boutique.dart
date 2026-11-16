import 'package:flutter/material.dart';
import 'design.dart';

const _wine = Color(0xFF743B4B), _secondary = Color(0xFF6B5C61);

/// Editorial home presentation. Every action opens the existing live feature.
class HomeBoutiqueSections extends StatelessWidget {
  const HomeBoutiqueSections({
    super.key,
    required this.onCollection,
    required this.onPackages,
    required this.onBookings,
    required this.onPayments,
    required this.onShortlist,
    required this.onTryOn,
    required this.onSupport,
    this.offers,
    this.onReviews,
  });
  final VoidCallback onCollection,
      onPackages,
      onBookings,
      onPayments,
      onShortlist,
      onTryOn,
      onSupport;
  final VoidCallback? onReviews;
  final Widget? offers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _CollectionCover(onCollection: onCollection, onTryOn: onTryOn),
      gap(24),
      _HomeShortcuts(
        onPackages: onPackages,
        onBookings: onBookings,
        onPayments: onPayments,
        onShortlist: onShortlist,
      ),
      if (offers != null) ...[gap(30), offers!],
      gap(28),
      const Divider(height: 1),
      if (onReviews != null)
        _HomeLink(
          icon: Icons.star_outline_rounded,
          title: 'Stories from our brides',
          detail: 'Explore customer reviews',
          onTap: onReviews!,
          actionKey: 'home-reviews',
        ),
      _HomeLink(
        icon: Icons.support_agent_outlined,
        title: 'A little guidance?',
        detail: 'Our team is here for you',
        onTap: onSupport,
        actionKey: 'home-support',
      ),
      const Divider(height: 1),
      const Padding(
        padding: EdgeInsets.only(top: 25, bottom: 70),
        child: Center(
          child: Text(
            'Thoughtfully chosen. Beautifully yours.',
            style: TextStyle(
              fontFamily: 'LuvlySerif',
              fontSize: 18,
              fontStyle: FontStyle.italic,
              color: _secondary,
            ),
          ),
        ),
      ),
    ],
  );
}

class _CollectionCover extends StatelessWidget {
  const _CollectionCover({required this.onCollection, required this.onTryOn});
  final VoidCallback onCollection, onTryOn;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final height =
          (box.maxWidth * .95).clamp(300.0, 390.0) +
          (scale - 1).clamp(0.0, 2.0) * 190;
      return ClipRRect(
        key: const Key('home-collection-cover'),
        borderRadius: CustomerUi.featureRadius,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/bridal_welcome_hd.png',
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.65),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFFBCA9A3)),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [.1, .46, 1],
                    colors: [
                      Color(0x00000000),
                      Color(0x33281720),
                      Color(0xF0402630),
                    ],
                  ),
                ),
              ),
              const Positioned(
                top: 16,
                right: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x88000000),
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      'Style inspiration',
                      style: TextStyle(fontSize: 9, color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'THE BRIDAL COLLECTION',
                      style: TextStyle(
                        color: Color(0xFFF5E7DF),
                        fontSize: 9,
                        letterSpacing: 1.7,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    gap(7),
                    const Text(
                      'Your dress.\nYour moment.',
                      style: TextStyle(
                        fontFamily: 'LuvlySerif',
                        fontSize: 35,
                        height: 1.0,
                        color: Colors.white,
                      ),
                    ),
                    gap(15),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const Key('home-collection'),
                          onPressed: onCollection,
                          style: FilledButton.styleFrom(
                            backgroundColor: ivory,
                            foregroundColor: _wine,
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text(
                            'Explore gowns',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('home-try-on'),
                          onPressed: onTryOn,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 12,
                            ),
                          ),
                          icon: const Icon(Icons.view_in_ar_outlined, size: 17),
                          label: const Text(
                            'Explore AR try-on',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
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
}

class _HomeShortcuts extends StatelessWidget {
  const _HomeShortcuts({
    required this.onPackages,
    required this.onBookings,
    required this.onPayments,
    required this.onShortlist,
  });
  final VoidCallback onPackages, onBookings, onPayments, onShortlist;
  @override
  Widget build(BuildContext context) {
    final entries = [
      (Icons.inventory_2_outlined, 'Packages', 'packages', onPackages),
      (
        Icons.calendar_month_outlined,
        'Appointments',
        'appointments',
        onBookings,
      ),
      (Icons.receipt_long_outlined, 'Payments', 'payments', onPayments),
      (Icons.favorite_border, 'Saved', 'shortlist', onShortlist),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final count = scale > 1.7 && box.maxWidth < 300
            ? 1
            : box.maxWidth < 310 || scale > 1.35
            ? 2
            : 4;
        final width = (box.maxWidth - 8 * (count - 1)) / count;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in entries)
              SizedBox(
                width: width,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: ValueKey('home-${item.$3}'),
                    onTap: item.$4,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: count < 4
                          ? Row(
                              children: [
                                _ShortcutIcon(item.$1),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.$2,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: ink,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _ShortcutIcon(item.$1),
                                gap(9),
                                Text(
                                  item.$2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ShortcutIcon extends StatelessWidget {
  const _ShortcutIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 45,
    height: 45,
    decoration: BoxDecoration(
      color: const Color(0xFFF2E8E5),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(icon, size: 21, color: _wine),
  );
}

class _HomeLink extends StatelessWidget {
  const _HomeLink({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.actionKey,
  });
  final IconData icon;
  final String title, detail, actionKey;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: Key(actionKey),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 3),
        child: Row(
          children: [
            Icon(icon, size: 23, color: _wine),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  gap(3),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 12, color: _secondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 17, color: _wine),
          ],
        ),
      ),
    ),
  );
}

class HomeSectionHeading extends StatelessWidget {
  const HomeSectionHeading({
    super.key,
    required this.kicker,
    required this.title,
  });
  final String kicker, title;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        kicker,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          color: _secondary,
        ),
      ),
      gap(7),
      Text(
        title,
        style: const TextStyle(
          fontFamily: 'LuvlySerif',
          fontSize: 26,
          height: 1.12,
        ),
      ),
    ],
  );
}
