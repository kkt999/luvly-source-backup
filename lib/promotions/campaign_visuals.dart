import 'package:flutter/material.dart';
import 'promotion_api.dart';

const campaignImageDisclosure =
    'AI-generated style image. Browse the package to see which gowns you can choose.';

class CampaignLook {
  const CampaignLook(this.image, this.background, this.accent);
  final String image;
  final Color background, accent;
  static const _essentials = CampaignLook(
    'assets/images/promo_essentials_v1.png',
    Color(0xFF783A4C),
    Color(0xFFF7DFCA),
  );
  static CampaignLook of(Campaign p) => forPackage(p.packageId) ?? _essentials;
  static CampaignLook? forPackage(String? packageId) => switch (packageId) {
    'bridal-essentials' => _essentials,
    'signature-bridal' => const CampaignLook(
      'assets/images/promo_signature_v1.png',
      Color(0xFF344D45),
      Color(0xFFE0EBDF),
    ),
    'luxe-bridal' => const CampaignLook(
      'assets/images/promo_luxe_v1.png',
      Color(0xFF48372D),
      Color(0xFFF3D6A5),
    ),
    _ => null,
  };
}

String compactOfferMoney(int cents) =>
    cents % 100 == 0 ? 'RM${cents ~/ 100}' : offerMoney(cents);
String campaignPackageLabel(Campaign p) => p.data['packageName'] is String
    ? p.data['packageName']
    : switch (p.packageId) {
        'bridal-essentials' => 'Bridal Essentials',
        'signature-bridal' => 'Signature Bridal',
        'luxe-bridal' => 'Luxe Bridal',
        _ => p.title,
      };

/// Measure real wrapped text, rather than clipping it at large accessibility sizes.
double campaignCreativeHeight(
  BuildContext context,
  double width,
  Campaign p, {
  String actionLabel = 'View offer',
}) {
  final compact = width < 320;
  final textWidth = width * .57 - (compact ? 16 : 20) - 10;
  double measure(
    String text,
    TextStyle style, {
    double? available,
    int? lines,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: lines,
    )..layout(maxWidth: available ?? textWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final kicker = measure(
    p.offer ? 'A LUVLY PRIVILEGE' : 'FROM THE BOUTIQUE',
    const TextStyle(
      fontSize: 8,
      letterSpacing: 1.3,
      fontWeight: FontWeight.w600,
    ),
  );
  var content = measure(
    campaignPackageLabel(p),
    TextStyle(
      fontFamily: 'LuvlySerif',
      fontSize: compact ? 22 : 25,
      height: 1.04,
    ),
    lines: 3,
  );
  if (p.offer) {
    content +=
        measure(
          p.data['discountType'] == 'Percent'
              ? '${p.data['value']}%'
              : compactOfferMoney(p.data['value']),
          TextStyle(
            fontSize: compact ? 31 : 36,
            height: 1.05,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ) +
        measure(
          p.data['discountType'] == 'Percent'
              ? 'OFF · CAP ${compactOfferMoney(p.data['maxDiscountCents'])}'
              : 'OFF YOUR PACKAGE',
          const TextStyle(fontSize: 8.5, letterSpacing: 1.1),
        ) +
        14 +
        10 +
        measure(
          'Min. spend ${compactOfferMoney(p.data['minimumCents'])}',
          const TextStyle(fontSize: 10, height: 1.3),
        );
  }
  final action = measure(
    actionLabel,
    const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
    available: textWidth - 43,
  );
  final button = (action < 14 ? 14 : action) + 18;
  final required = 42 + kicker + content + button + 24;
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final baseline = 238.0 + (scale - 1).clamp(0, 2) * 190;
  return required > baseline ? required.ceilToDouble() : baseline;
}

/// Local, generated editorial assets, never treated as stock/product photography.
class CampaignCreative extends StatelessWidget {
  const CampaignCreative({
    super.key,
    required this.campaign,
    this.onTap,
    this.actionLabel = 'View offer',
  });
  final Campaign campaign;
  final VoidCallback? onTap;
  final String actionLabel;
  @override
  Widget build(BuildContext context) {
    final p = campaign, look = CampaignLook.of(p);
    return Semantics(
      label: '${p.title}. ${p.saving}. $campaignImageDisclosure',
      button: onTap != null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: look.background,
          child: InkWell(
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, box) {
                final compact = box.maxWidth < 320;
                return SizedBox(
                  height: campaignCreativeHeight(
                    context,
                    box.maxWidth,
                    p,
                    actionLabel: actionLabel,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 57,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 20,
                            22,
                            10,
                            20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p.offer
                                    ? 'A LUVLY PRIVILEGE'
                                    : 'FROM THE BOUTIQUE',
                                style: TextStyle(
                                  color: look.accent,
                                  fontSize: 8,
                                  letterSpacing: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (p.offer) ...[
                                    Text(
                                      p.data['discountType'] == 'Percent'
                                          ? '${p.data['value']}%'
                                          : compactOfferMoney(p.data['value']),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: compact ? 31 : 36,
                                        height: 1.05,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                    Text(
                                      p.data['discountType'] == 'Percent'
                                          ? 'OFF · CAP ${compactOfferMoney(p.data['maxDiscountCents'])}'
                                          : 'OFF YOUR PACKAGE',
                                      style: TextStyle(
                                        color: look.accent,
                                        fontSize: 8.5,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  Text(
                                    campaignPackageLabel(p),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'LuvlySerif',
                                      fontSize: compact ? 22 : 25,
                                      height: 1.04,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (p.offer)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        'Min. spend ${compactOfferMoney(p.data['minimumCents'])}',
                                        style: TextStyle(
                                          color: look.accent,
                                          fontSize: 10,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF9F1),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        actionLabel,
                                        style: TextStyle(
                                          color: look.background,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 14,
                                      color: look.background,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 43,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              look.image,
                              key: ValueKey(look.image),
                              fit: BoxFit.cover,
                              alignment: const Alignment(.15, -.25),
                              excludeFromSemantics: true,
                              errorBuilder: (_, _, _) => ColoredBox(
                                color: look.background,
                                child: Icon(
                                  Icons.checkroom,
                                  color: look.accent,
                                  size: 42,
                                ),
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [look.background, Colors.transparent],
                                  stops: const [0, .27],
                                ),
                              ),
                            ),
                            const Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0x88000000),
                                    ],
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(6, 20, 6, 8),
                                  child: Text(
                                    'Illustrative image',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 7.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
