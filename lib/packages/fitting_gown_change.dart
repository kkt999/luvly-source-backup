import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';

/// An unsaved staff draft. The backend validates eligibility, revisions and stock
/// again together with the attendance record; opening this page reserves nothing.
class FittingGownChangeDraft {
  FittingGownChangeDraft(this.options, this.gowns);
  final Map<String, dynamic> options;
  final List<Map<String, dynamic>> gowns;
  Map<String, dynamic> toJson() => {
    'selectionRevision': options['selectionRevision'],
    'planRevision': options['planRevision'],
    'packageRevision': options['packageRevision'],
    'gowns': [
      for (final g in gowns)
        {'dressId': g['dressId'], 'size': g['size'], 'revision': g['revision']},
    ],
  };
}

class FittingGownPhoto extends StatelessWidget {
  const FittingGownPhoto({super.key, required this.gown});
  final Map<String, dynamic> gown;
  @override
  Widget build(BuildContext context) {
    final url = gown['imageUrl'] as String? ?? '';
    final uri = Uri.tryParse(url);
    final placeholder = Container(
      color: const Color(0xFFF6EFF0),
      child: const Center(child: Icon(Icons.checkroom_outlined)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 84,
        child: (gown['photoRevision'] as int? ?? 0) > 0
            ? CatalogueDressPhoto(
                dress: CatalogueDress(
                  id: gown['dressId'],
                  name: gown['name'],
                  category: gown['category'] ?? '',
                  description: '',
                  colour: gown['colour'] ?? '',
                  sizes: gown['size'] ?? '',
                  priceCents: 0,
                  imageUrl: url,
                  photoRevision: gown['photoRevision'],
                ),
                repository:
                    context
                        .dependOnInheritedWidgetOfExactType<CatalogueScope>()
                        ?.repository ??
                    FirebaseCatalogueRepository(),
                height: 84,
                compact: true,
              )
            : uri?.scheme == 'https' && uri!.host.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}

class FittingGownChangeSummary extends StatelessWidget {
  const FittingGownChangeSummary({super.key, required this.change});
  final Map change;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(
        'Gown selection updated at fitting',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Text(
        'Previously: ${(change['from'] as List).map((g) => '${g['name']} · ${g['size']}').join(', ')}',
      ),
      for (final g in change['to'] as List)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              FittingGownPhoto(gown: Map<String, dynamic>.from(g)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${g['name']} · ${g['size']}\n${g['colour'] ?? ''}',
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class FittingGownChangePicker extends StatefulWidget {
  const FittingGownChangePicker({
    super.key,
    required this.options,
    required this.original,
    this.initial = const [],
  });
  final Map<String, dynamic> options;
  final List<Map<String, dynamic>> original, initial;
  @override
  State<FittingGownChangePicker> createState() =>
      _FittingGownChangePickerState();
}

class _FittingGownChangePickerState extends State<FittingGownChangePicker> {
  final sizes = <String, String>{};
  String search = '';
  List<Map<String, dynamic>> get gowns => (widget.options['gowns'] as List)
      .map((g) => Map<String, dynamic>.from(g))
      .toList();
  int get count => widget.options['includedGownCount'] as int;
  List<String> available(Map g) => [
    for (final s in g['sizes'] as List)
      if (s['status'] == 'Available') s['size'] as String,
  ];
  List<Map<String, dynamic>> get chosen => [
    for (final g in gowns)
      if (available(g).contains(sizes[g['dressId']]))
        {...g, 'size': sizes[g['dressId']]},
  ];
  bool get changed => chosen.any(
    (g) => !widget.original.any(
      (old) => old['dressId'] == g['dressId'] && old['size'] == g['size'],
    ),
  );
  @override
  void initState() {
    super.initState();
    for (final g in widget.initial) {
      sizes[g['dressId'] as String] = g['size'] as String;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select replacement gowns')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Choose $count included gown${count == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the gown and size the customer chose at this visit. Only sizes available for the rental dates can be selected.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search gowns',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) =>
                        setState(() => search = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 16),
                  if (gowns.isEmpty)
                    const Text(
                      'No eligible gowns are available. Keep the outcome as “Needs another gown · not chosen yet”.',
                    ),
                  for (final g in gowns.where(
                    (g) => '${g['name']} ${g['colour']}'.toLowerCase().contains(
                      search,
                    ),
                  ))
                    Card(
                      key: ValueKey(
                        'replacement-card-${g['dressId']}-${sizes[g['dressId']] ?? ''}',
                      ),
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: sizes.containsKey(g['dressId'])
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittingGownPhoto(gown: g),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        g['name'] as String,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text('${g['colour']} · ${g['category']}'),
                                      const Text('Included in this package'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: ValueKey('replacement-size-${g['dressId']}'),
                              initialValue:
                                  available(g).contains(sizes[g['dressId']])
                                  ? sizes[g['dressId']]
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Selected size',
                              ),
                              hint: const Text('Choose a size'),
                              items: [
                                for (final s in g['sizes'] as List)
                                  DropdownMenuItem<String>(
                                    value: s['size'] as String,
                                    enabled: s['status'] == 'Available',
                                    child: Text(
                                      '${s['size']}${s['status'] == 'Available'
                                          ? ''
                                          : s['status'] == 'Unconfirmed'
                                          ? ' · stock not confirmed'
                                          : ' · unavailable'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged:
                                  available(g).isEmpty ||
                                      !sizes.containsKey(g['dressId']) &&
                                          sizes.length >= count
                                  ? null
                                  : (v) => setState(
                                      () => sizes[g['dressId'] as String] = v!,
                                    ),
                            ),
                            if (sizes.containsKey(g['dressId']))
                              TextButton(
                                onPressed: () =>
                                    setState(() => sizes.remove(g['dressId'])),
                                child: const Text('Remove selection'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Saving the fitting outcome updates the proposed selection. The customer must still confirm the proposal before the booking deposit.',
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: chosen.length == count && changed
                        ? () => Navigator.pop(
                            context,
                            FittingGownChangeDraft(widget.options, chosen),
                          )
                        : null,
                    child: Text('Use these gowns (${chosen.length}/$count)'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
