import 'package:flutter/material.dart';
import 'package_presentation.dart';

/// Design-only catalogue. Intentionally separate from stock, package pricing,
/// invoices and saved orders until actual products and policies are supplied.
class AccessoryConcept {
  const AccessoryConcept(
    this.id,
    this.name,
    this.category,
    this.style,
    this.unit,
    this.check,
  );
  final String id, name, category, style, unit, check;
}

const accessoryConcepts = [
  AccessoryConcept(
    'pearl-comb',
    'Pearl-inspired hair comb',
    'Headpieces',
    'Soft romantic styling',
    '1 piece',
    'Confirm dimensions, fastening and finish.',
  ),
  AccessoryConcept(
    'crystal-tiara',
    'Crystal-style tiara',
    'Headpieces',
    'A statement finishing touch',
    '1 piece',
    'Confirm head fit, weight and fastening.',
  ),
  AccessoryConcept(
    'fingertip-veil',
    'Fingertip veil',
    'Veils',
    'A light, understated silhouette',
    '1 piece',
    'Confirm length, colour and comb attachment.',
  ),
  AccessoryConcept(
    'cathedral-veil',
    'Cathedral veil',
    'Veils',
    'A longer ceremony silhouette',
    '1 piece',
    'Confirm length and compatibility with the gown train.',
  ),
  AccessoryConcept(
    'drop-earrings',
    'Pearl-style drop earrings',
    'Earrings',
    'A delicate accent beside the face',
    '1 pair',
    'Confirm pierced or clip-on fit, material and hygiene policy.',
  ),
  AccessoryConcept(
    'stud-earrings',
    'Crystal-style studs',
    'Earrings',
    'A minimal, light-catching detail',
    '1 pair',
    'Confirm metal composition, fastening and hygiene policy.',
  ),
  AccessoryConcept(
    'pendant',
    'Pendant necklace',
    'Necklaces & sets',
    'A simple focal point at the neckline',
    '1 piece',
    'Confirm chain length, material and clasp.',
  ),
  AccessoryConcept(
    'jewellery-set',
    'Coordinated jewellery set',
    'Necklaces & sets',
    'A necklace and matching earrings',
    '1 set · 2 pieces',
    'List every included piece; do not count it again as individual items.',
  ),
  AccessoryConcept(
    'bracelet',
    'Delicate bracelet',
    'Bracelets',
    'A subtle wrist detail',
    '1 piece',
    'Confirm wrist measurement, material and clasp.',
  ),
  AccessoryConcept(
    'dress-ring',
    'Decorative dress ring',
    'Decorative rings',
    'A styling accessory for a bridal look',
    '1 piece',
    'Confirm ring size and material. Not a wedding band or precious-jewellery claim.',
  ),
];

class InlineAccessoryChoices extends StatelessWidget {
  const InlineAccessoryChoices({
    super.key,
    required this.serviceName,
    required this.selected,
    required this.onChanged,
    this.readOnly = false,
  });
  final String serviceName;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final veil = serviceName.toLowerCase().contains('veil');
    final options = accessoryConcepts
        .where((a) => veil ? a.category == 'Veils' : a.category != 'Veils')
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            veil ? 'Choose veil styles' : 'Choose accessory styles',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Draft preferences · optional, not saved to your order or charged. Final items and allowance are not configured yet.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (readOnly)
            Text(
              selected.isEmpty
                  ? 'No draft preferences selected.'
                  : options
                        .where((a) => selected.contains(a.id))
                        .map((a) => a.name)
                        .join(' · '),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: options
                  .map(
                    (a) => FilterChip(
                      label: Text(a.name),
                      selected: selected.contains(a.id),
                      onSelected: (value) {
                        final next = {...selected};
                        value ? next.add(a.id) : next.remove(a.id);
                        onChanged(next);
                      },
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class AccessoryDraftScreen extends StatefulWidget {
  const AccessoryDraftScreen({super.key});
  @override
  State<AccessoryDraftScreen> createState() => _AccessoryDraftState();
}

class _AccessoryDraftState extends State<AccessoryDraftScreen> {
  String category = 'All', query = '';
  final selected = <String>{};
  IconData symbol(String category) => switch (category) {
    'Headpieces' => Icons.auto_awesome_outlined,
    'Veils' => Icons.checkroom_outlined,
    'Earrings' => Icons.grain,
    'Necklaces & sets' => Icons.diamond_outlined,
    'Bracelets' => Icons.circle_outlined,
    _ => Icons.trip_origin,
  };

  void details(AccessoryConcept item) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(item.name),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${item.category} · ${item.unit}'),
            const SizedBox(height: 16),
            Text(item.style),
            const SizedBox(height: 16),
            const Text(
              'Before this item can be offered',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(item.check),
            const SizedBox(height: 12),
            const Text(
              'Actual product photo, SKU, condition, rental price, package eligibility, stock and available dates must be supplied by Luvly.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Draft concept only. No stock is reserved and nothing is added to your package or payment.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = accessoryConcepts
        .where(
          (a) =>
              (category == 'All' || a.category == category) &&
              '${a.name} ${a.style}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('The finishing touches')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: bridalCream,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LUVLY / ACCESSORY CONCEPTS',
                      style: TextStyle(
                        color: bridalRose,
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Small details.\nA look that is yours.',
                      style: TextStyle(
                        fontFamily: 'LuvlySerif',
                        fontSize: 38,
                        height: 1.1,
                        color: bridalInk,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Explore headpieces, veils and jewellery as individual pieces, pairs or clearly defined sets.',
                      style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    const Chip(label: Text('DRAFT · NOT AVAILABLE TO RENT')),
                    const Text(
                      'These are proposed styles, not real stock. Your shortlist lasts only while this page is open and is not part of an order.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  labelText: 'Search accessory styles',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    ['All', ...accessoryConcepts.map((a) => a.category).toSet()]
                        .map(
                          (v) => ChoiceChip(
                            label: Text(v),
                            selected: category == v,
                            onSelected: (_) => setState(() => category = v),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 22),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No styles match. Try another category or search.',
                  ),
                ),
              LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth >= 850
                      ? 3
                      : box.maxWidth >= 580
                      ? 2
                      : 1;
                  final width = (box.maxWidth - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: visible
                        .map(
                          (a) => SizedBox(
                            width: width,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFE5D8D5),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 96,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: bridalCream,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            symbol(a.category),
                                            size: 32,
                                            color: bridalRose,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Product photo pending',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: bridalRose,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      a.category.toUpperCase(),
                                      style: const TextStyle(
                                        color: bridalRose,
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      a.name,
                                      style: const TextStyle(
                                        fontFamily: 'LuvlySerif',
                                        fontSize: 27,
                                        color: bridalInk,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${a.style}\n${a.unit}',
                                      style: const TextStyle(height: 1.5),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Rental price & availability: not configured',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () => setState(() {
                                        selected.contains(a.id)
                                            ? selected.remove(a.id)
                                            : selected.add(a.id);
                                      }),
                                      icon: Icon(
                                        selected.contains(a.id)
                                            ? Icons.check
                                            : Icons.add,
                                      ),
                                      label: Text(
                                        selected.contains(a.id)
                                            ? 'Shortlisted · draft'
                                            : 'Shortlist concept',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => details(a),
                                      child: const Text('View item details'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: bridalCream,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your concept shortlist (${selected.length})',
                      style: const TextStyle(
                        fontFamily: 'LuvlySerif',
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selected.isEmpty)
                      const Text(
                        'Shortlist a style to compare the finishing touches.',
                      ),
                    for (final a in accessoryConcepts.where(
                      (a) => selected.contains(a.id),
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(a.name),
                        subtitle: Text(a.unit),
                        trailing: IconButton(
                          tooltip: 'Remove ${a.name}',
                          onPressed: () =>
                              setState(() => selected.remove(a.id)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'No payable total — real prices and package allowances have not been set. A set counts as its defined unit; it is not an unlimited jewellery rental.',
                      style: TextStyle(height: 1.5, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
