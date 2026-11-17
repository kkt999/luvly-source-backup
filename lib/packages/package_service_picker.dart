import 'package:flutter/material.dart';

import '../admin/design.dart' show blush, border, canvas, muted, rose;
import 'package_api.dart';

const _groups = {
  'Appointments': [
    PackageServiceType.makeupHair,
    PackageServiceType.makeupTrial,
    PackageServiceType.secondBeautyLook,
    PackageServiceType.portraits,
    PackageServiceType.extraFitting,
  ],
  'Rental & accessories': [
    PackageServiceType.extraRentalDay,
    PackageServiceType.packageVeil,
    PackageServiceType.itemAccessories,
  ],
  'Other': [PackageServiceType.custom],
};

String serviceCategoryDescription(PackageServiceType type) => switch (type) {
  PackageServiceType.makeupHair =>
    'Bridal makeup and hairstyling for the event.',
  PackageServiceType.makeupTrial =>
    'A separate session to try the makeup before the event.',
  PackageServiceType.secondBeautyLook =>
    'A second makeup or hair look, such as a reception look.',
  PackageServiceType.portraits =>
    'A bridal photo session. Specify what the customer receives.',
  PackageServiceType.extraFitting =>
    'An additional visit to try or adjust the gown.',
  PackageServiceType.extraRentalDay =>
    'Adds one calendar day to the rental period.',
  PackageServiceType.packageVeil =>
    'One veil priced through this package. Choose its inclusion or removal price below.',
  PackageServiceType.itemAccessories =>
    'Customers may add accessories at their catalogue rental prices.',
  PackageServiceType.veil =>
    'Customers choose a veil using the allowance you set.',
  PackageServiceType.jewellery =>
    'Customers choose jewellery and accessories using the allowance you set.',
  PackageServiceType.veilAndJewellery =>
    'Customers can choose both from one shared allowance.',
  PackageServiceType.custom =>
    'Describe a service such as gown steaming. Arrange any appointments separately.',
};

IconData serviceCategoryIcon(PackageServiceType? type) => switch (type) {
  PackageServiceType.makeupHair ||
  PackageServiceType.makeupTrial ||
  PackageServiceType.secondBeautyLook => Icons.brush_outlined,
  PackageServiceType.portraits => Icons.photo_camera_outlined,
  PackageServiceType.extraFitting => Icons.straighten_outlined,
  PackageServiceType.extraRentalDay => Icons.calendar_today_outlined,
  PackageServiceType.packageVeil ||
  PackageServiceType.veil => Icons.checkroom_outlined,
  PackageServiceType.itemAccessories ||
  PackageServiceType.jewellery ||
  PackageServiceType.veilAndJewellery => Icons.diamond_outlined,
  _ => Icons.description_outlined,
};

class PackageServicePicker extends StatefulWidget {
  const PackageServicePicker({
    super.key,
    this.selected,
    this.canKeepExisting = false,
  });
  final PackageServiceType? selected;
  final bool canKeepExisting;

  @override
  State<PackageServicePicker> createState() => _PackageServicePickerState();
}

class _PackageServicePickerState extends State<PackageServicePicker> {
  final scroll = ScrollController();
  String query = '';

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  bool matches(PackageServiceType type) =>
      query.isEmpty ||
      '${type.label} ${serviceCategoryDescription(type)}'
          .toLowerCase()
          .contains(query);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 800,
        height: (window.height - 40).clamp(0, 840).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.selected == null && !widget.canKeepExisting
                          ? 'Add a service'
                          : 'Change service category',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close service picker',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: TextField(
                onChanged: (value) {
                  setState(() => query = value.trim().toLowerCase());
                  if (scroll.hasClients) scroll.jumpTo(0);
                },
                decoration: const InputDecoration(
                  labelText: 'Search services',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            const Divider(height: 1, color: border),
            Expanded(
              child: Scrollbar(
                controller: scroll,
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    if (widget.canKeepExisting && query.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use original settings'),
                        subtitle: const Text(
                          'Keep the rules this service already uses.',
                        ),
                        trailing: widget.selected == null
                            ? const Icon(Icons.check, color: rose)
                            : null,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                    for (final group in _groups.entries)
                      if (group.value.any(matches)) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            group.key,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (group.key == 'Appointments') ...[
                          const Text(
                            'Staff confirm timing in the proposal before the booking deposit.',
                            style: TextStyle(color: muted),
                          ),
                          const SizedBox(height: 8),
                        ],
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns =
                                constraints.maxWidth >= 620 &&
                                MediaQuery.textScalerOf(context).scale(14) <=
                                    18;
                            final width = twoColumns
                                ? (constraints.maxWidth - 10) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                for (final type in group.value.where(matches))
                                  SizedBox(
                                    width: width,
                                    child: serviceOption(type),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                      ],
                    if (!PackageServiceType.values.any(matches))
                      const Text('No services match your search.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget serviceOption(PackageServiceType type) {
    final selected = type == widget.selected;
    final radius = BorderRadius.circular(9);
    return Material(
      color: selected ? blush : canvas,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: selected ? rose : border),
      ),
      child: InkWell(
        key: ValueKey('package-service-${type.code}'),
        borderRadius: radius,
        onTap: () => Navigator.pop(context, type.code),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(serviceCategoryIcon(type), size: 19, color: rose),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      serviceCategoryDescription(type),
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected ? Icons.check : Icons.chevron_right,
                size: 18,
                color: selected ? rose : muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
