import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../src/design.dart';
import '../src/model.dart';
import '../src/live_catalogue.dart' show LiveDressDetailScreen;
import '../workspace/workspace_api.dart' show workspaceError;
import 'recommendation_api.dart';
import 'recommendation_engine.dart';
import 'body_scan.dart';
import 'measurement_provenance.dart';
import 'body_measurement_scan_screen.dart';
import 'body_scan_screen.dart';

class PersonalizedGownsScreen extends StatefulWidget {
  const PersonalizedGownsScreen({super.key, this.api, this.onOpenDress});
  final RecommendationApi? api;
  final ValueChanged<String>? onOpenDress;
  @override
  State<PersonalizedGownsScreen> createState() => _PersonalizedGownsState();
}

class _PersonalizedGownsState extends State<PersonalizedGownsScreen>
    with WidgetsBindingObserver {
  StreamSubscription<({String uid, int revision})>? profileChanges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    profileChanges = RecommendationProfileChanges.changes.listen((event) {
      if (mounted &&
          event.uid == uid &&
          (record == null || event.revision > record!.revision)) {
        load();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && uid != null) load();
  }

  late final api = widget.api ?? RecommendationApi();
  PreferenceRecord? record;
  String? uid, error;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppScope.maybeOf(context)?.accountId;
    if (next != uid) {
      uid = next;
      record = null;
      error = null;
      generation++;
      if (next != null) load();
    }
  }

  Future<void> load() async {
    final g = ++generation;
    setState(() {
      error = null;
      record = null;
    });
    try {
      final value = await api.load();
      if (mounted && g == generation) setState(() => record = value);
    } catch (e) {
      if (mounted && g == generation) setState(() => error = workspaceError(e));
    }
  }

  Future<void> edit({bool measurementsOnly = false}) async {
    final current = uid;
    final result = await Navigator.push<PreferenceRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => BridalPreferencesEditor(
          api: api,
          measurementsOnly: measurementsOnly,
        ),
      ),
    );
    if (mounted && current == uid && result != null) {
      generation++;
      setState(() {
        record = result;
        error = null;
      });
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    profileChanges?.cancel();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Chosen for you',
    child: uid == null
        ? const Center(
            child: Text(
              'Sign in to save your preferences and find your gowns.',
            ),
          )
        : error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!, textAlign: TextAlign.center),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              ),
            ),
          )
        : record == null
        ? const Center(child: CircularProgressIndicator())
        : CatalogueFeed(inventory: false, builder: (c, s) => results(c, s)),
  );
  Widget results(BuildContext context, CatalogueSnapshot snapshot) {
    final p = record!.preferences,
        guide = proportionGuide(p),
        matches = recommendGowns(snapshot.dresses, p);
    final inputLabels = [
      if (p.styles.isNotEmpty) 'Style preferences',
      if (guide != null) 'Body proportions',
      if (guide == null && p.useScanProportions) 'Camera proportion ideas',
      if (p.colours.isNotEmpty) 'Colour preferences',
    ];
    final personalized =
        p.styles.isNotEmpty ||
        p.colours.isNotEmpty ||
        p.useProportions ||
        p.useScanProportions;
    return PageList(
      children: [
        const Text(
          'A little closer to your dress.',
          style: TextStyle(
            fontFamily: 'LuvlySerif',
            fontSize: 30,
            height: 1.15,
          ),
        ),
        gap(8),
        const Text(
          'Your taste comes first. Explore gowns with clear reasons behind each suggestion.',
          style: TextStyle(color: muted),
        ),
        gap(20),
        Surface(
          color: blush,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                personalized
                    ? 'Your bridal preferences'
                    : 'Let’s find what feels like you',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              gap(8),
              if (!personalized)
                const Text(
                  'Choose a silhouette or colour you love. Measurements are optional.',
                ),
              if (p.styles.isNotEmpty) Text('Styles · ${p.styles.join(', ')}'),
              if (p.colours.isNotEmpty)
                Text('Colours · ${p.colours.join(', ')}'),
              if (p.maxPriceCents != null)
                Text(
                  'Gown budget · up to RM ${(p.maxPriceCents! / 100).toStringAsFixed(2)}',
                ),
              if (guide != null) ...[
                Text('Optional proportion guide · ${guide.label}'),
                gap(6),
                Text(guide.description),
                gap(6),
                Text(
                  guide.explanation,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                gap(6),
                Text(
                  p.measurementProvenance.summary,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const Text(
                  'An approximate styling guide from your chosen measurements.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ] else ...[
                const Text('Body type unavailable'),
                Text(
                  circumferenceLabels.every(p.measurements.containsKey)
                      ? 'Your measurements are saved. Body-based styling is turned off.'
                      : 'Add bust, waist and hip measurements to include a body proportion guide.',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                TextButton(
                  onPressed: () => edit(measurementsOnly: true),
                  child: Text(
                    circumferenceLabels.every(p.measurements.containsKey)
                        ? 'Use my body measurements for recommendations'
                        : 'Complete body profile',
                  ),
                ),
              ],
              if (p.useScanProportions && p.bodyScan != null)
                Text(
                  guide == null
                      ? 'Camera proportion ideas · enabled'
                      : 'Camera scan saved · manual guide takes priority',
                ),
              gap(12),
              Text(
                inputLabels.isEmpty
                    ? 'Choose preferences to calculate a style score.'
                    : 'Scoring inputs · ${inputLabels.join(' · ')}',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              OutlinedButton.icon(
                key: const Key('edit-bridal-preferences'),
                onPressed: edit,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  personalized ? 'Edit preferences' : 'Find my style',
                ),
              ),
            ],
          ),
        ),
        gap(16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'How your matches work',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 16),
          children: const [
            Text(
              'Style match is a rule-based score out of 100. Your silhouette preferences carry 60 parts, the optional manual proportion guide 30, and colour 10. If you enable camera proportion ideas without the manual guide, they carry 15 parts instead. Camera rules use joint spans, not a body-shape diagnosis. Only the criteria you choose are counted. Your budget is a limit, not extra points. Ties show the lower-priced gown first. These are styling suggestions; a fitting confirms size and alterations.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
        if (snapshot.fromCache)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Showing cached gowns. Reconnect to confirm current listings.',
            ),
          ),
        Text(
          '${matches.length} ${matches.length == 1 ? 'gown' : 'gowns'} to explore',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        gap(6),
        const Text(
          'Rental-date availability is checked when you plan your booking.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        gap(16),
        if (matches.isEmpty)
          Surface(
            child: Column(
              children: [
                const Icon(Icons.checkroom_outlined, size: 32),
                gap(12),
                Text(
                  p.maxPriceCents == null
                      ? 'No gowns are listed as available right now.'
                      : 'No available gowns match your budget right now.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: edit,
                  child: const Text('Adjust preferences'),
                ),
              ],
            ),
          ),
        for (final match in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _RecommendationCard(
              match: match,
              onOpen: () {
                if (widget.onOpenDress != null) {
                  widget.onOpenDress!(match.dress.id);
                  return;
                }
                go(context, LiveDressDetailScreen(id: match.dress.id));
              },
            ),
          ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.match, required this.onOpen});
  final GownRecommendation match;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final d = match.dress;
    return Container(
      key: ValueKey('recommendation-${d.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: CatalogueDressPhoto(dress: d, height: 235, compact: true),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      d.category,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    if (match.validScore != null)
                      Text(
                        'Style match ${match.validScore}/100',
                        style: const TextStyle(
                          color: rose,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      )
                    else
                      const Text(
                        'Score unavailable',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                  ],
                ),
                gap(8),
                Text(
                  d.name,
                  style: const TextStyle(
                    fontFamily: 'LuvlySerif',
                    fontSize: 25,
                  ),
                ),
                gap(4),
                Text(
                  '${d.priceLabel} · ${d.colour}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                gap(12),
                if (match.components.isNotEmpty)
                  Text(
                    match.components.first.reason,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                if (match.budgetReason != null)
                  Text(
                    match.budgetReason!,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                if (match.components.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    title: const Text(
                      'Why this gown?',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      for (final part in match.components)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${part.label} · ${part.value}/100 (${part.weight} parts)\n${part.reason}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      const Text(
                        'Score = sum of points × parts ÷ total active parts. Styling rules are a starting point; you can choose any gown.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                gap(10),
                FilledButton(
                  onPressed: onOpen,
                  child: const Text('Explore gown'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One persisted source for Profile body information and recommendation inputs.
class BridalPreferencesEditor extends StatefulWidget {
  const BridalPreferencesEditor({
    super.key,
    this.api,
    this.measurementsOnly = false,
    this.scanner = const BodyScanner(),
  });
  final RecommendationApi? api;
  final bool measurementsOnly;
  final BodyScanner scanner;
  @override
  State<BridalPreferencesEditor> createState() =>
      _BridalPreferencesEditorState();
}

class _BridalPreferencesEditorState extends State<BridalPreferencesEditor> {
  late final api = widget.api ?? RecommendationApi();
  final form = GlobalKey<FormState>(), budget = TextEditingController();
  final fields = {
    for (final key in measurementLimits.keys) key: TextEditingController(),
  };
  PreferenceRecord? record;
  final styles = <String>{}, colours = <String>{};
  String? uid, error, pendingJson, pendingId;
  bool useProportions = false, shareProportionStats = false, busy = false;
  BodyScan? bodyScan;
  bool useScanProportions = false;
  MeasurementProvenance provenance = const MeasurementProvenance();
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppScope.maybeOf(context)?.accountId;
    if (next != uid) {
      uid = next;
      generation++;
      record = null;
      error = null;
      if (next != null) load();
    }
  }

  Future<void> load() async {
    final g = ++generation;
    setState(() => busy = true);
    try {
      final result = await api.load();
      if (!mounted || g != generation) return;
      setState(() {
        record = result;
        error = null;
        final p = result.preferences;
        for (final e in fields.entries) {
          final n = p.measurements[e.key];
          e.value.text = n == null
              ? ''
              : n.toString().replaceFirst(RegExp(r'\.0$'), '');
        }
        styles
          ..clear()
          ..addAll(p.styles);
        colours
          ..clear()
          ..addAll(p.colours);
        useProportions = p.useProportions;
        provenance = p.measurementProvenance;
        shareProportionStats = p.shareProportionStats;
        bodyScan = p.bodyScan;
        useScanProportions = p.useScanProportions;
        budget.text = p.maxPriceCents == null
            ? ''
            : (p.maxPriceCents! / 100).toStringAsFixed(2);
        pendingJson = null;
        pendingId = null;
      });
    } catch (e) {
      if (mounted && g == generation) setState(() => error = workspaceError(e));
    } finally {
      if (mounted && g == generation) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || record == null || !form.currentState!.validate()) return;
    final measurements = <String, double>{
      for (final e in fields.entries)
        if (e.value.text.trim().isNotEmpty)
          e.key: double.parse(e.value.text.trim()),
    };
    if (useProportions &&
        !['Bust', 'Waist', 'Hips'].every(measurements.containsKey)) {
      setState(
        () => error =
            'Add bust, waist and hips, or switch off the proportion guide.',
      );
      return;
    }
    final complete = circumferenceLabels.every(measurements.containsKey);
    final next = BridalPreferences(
      measurements: measurements,
      measurementProvenance: provenance.retained(measurements.keys.toSet()),
      styles: styles.toList(),
      colours: colours.toList(),
      useProportions: useProportions && complete,
      shareProportionStats: useProportions && complete && shareProportionStats,
      maxPriceCents: budget.text.trim().isEmpty
          ? null
          : parsePriceCents(budget.text.trim()),
      bodyScan: bodyScan,
      useScanProportions: useScanProportions,
    );
    final encoded = jsonEncode(next.toJson());
    if (encoded != pendingJson) {
      pendingJson = encoded;
      pendingId = api.requestId();
    }
    final g = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.save(record!, next, pendingId!);
      if (!mounted || g != generation) return;
      final model = AppScope.maybeOf(context);
      if (model?.accountId == uid) {
        for (final k in model!.measurements.keys) {
          model.measurements[k] = result.preferences.measurements[k] ?? 0;
        }
        model.changed();
      }
      RecommendationProfileChanges.saved(uid!, result.revision);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.measurementsOnly
                  ? 'Body information updated.'
                  : 'Preferences updated.',
            ),
          ),
        );
        Navigator.pop(context, result);
      }
    } on PreferenceSaveFailure catch (e) {
      if (mounted && g == generation) {
        record = e.saved;
        pendingJson = null;
        pendingId = null;
        setState(
          () => error =
              'The server did not retain measurement sources. Ask Luvly to update the body-profile service, then save again.',
        );
      }
    } catch (e) {
      if (mounted && g == generation) setState(() => error = workspaceError(e));
    } finally {
      if (mounted && g == generation) setState(() => busy = false);
    }
  }

  Future<void> scanBody() async {
    if (busy || record == null) return;
    final g = generation;
    setState(() => busy = true);
    final reviewed = await Navigator.push<ReviewedBodyScan>(
      context,
      MaterialPageRoute(
        builder: (_) => BodyScanScreen(scanner: widget.scanner),
      ),
    );
    if (!mounted || g != generation) return;
    setState(() {
      busy = false;
      if (reviewed != null) {
        bodyScan = reviewed.scan;
        useScanProportions = reviewed.useForSuggestions;
        error = null;
      }
    });
  }

  Future<void> scanMeasurements() async {
    if (busy || record == null) return;
    final request = generation;
    setState(() => busy = true);
    final checked = await Navigator.push<ReviewedMeasurements>(
      context,
      MaterialPageRoute(
        builder: (_) => BodyMeasurementScanScreen(
          scanner: widget.scanner,
          initialHeight: fields['Height']!.text,
          existingMeasurements: {
            for (final label in circumferenceLabels)
              if (double.tryParse(fields[label]!.text) case final double value)
                label: value,
          },
        ),
      ),
    );
    if (!mounted || request != generation) return;
    setState(() {
      busy = false;
      if (checked != null) {
        provenance = checked.provenance;
        for (final entry in checked.measurements.entries) {
          fields[entry.key]!.text = entry.value.toString().replaceFirst(
            RegExp(r'\.0$'),
            '',
          );
        }
        error = null;
      }
    });
  }

  @override
  void dispose() {
    generation++;
    budget.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.measurementsOnly ? 'Body information' : 'Preferences'),
    ),
    bottomNavigationBar: record == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: busy ? null : load,
                      child: const Text('Reload saved details'),
                    ),
                  ],
                  FilledButton(
                    key: const Key('save-bridal-preferences'),
                    onPressed: busy ? null : save,
                    child: Text(
                      busy
                          ? 'Saving…'
                          : widget.measurementsOnly
                          ? 'Save body information'
                          : 'Save & show my gowns',
                    ),
                  ),
                ],
              ),
            ),
          ),
    body: uid == null
        ? const Center(child: Text('Sign in to save your bridal preferences.'))
        : record == null
        ? Center(
            child: busy
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(error ?? 'Could not load preferences.'),
                      ),
                      TextButton(onPressed: load, child: const Text('Retry')),
                    ],
                  ),
          )
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.measurementsOnly
                      ? 'Your measurements, your choice.'
                      : 'Let your taste lead.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                gap(8),
                Text(
                  widget.measurementsOnly
                      ? 'Enter measurements you know. Leave anything unmeasured blank.'
                      : 'Choose as many styles and colours as you like. You can change them anytime.',
                  style: const TextStyle(color: muted),
                ),
                gap(22),
                if (widget.measurementsOnly || bodyScan != null) ...[
                  if (bodyScan != null) ...[
                    BodyScanSummary(scan: bodyScan!),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use scan for styling suggestions'),
                      subtitle: const Text(
                        'Optional. The manual proportion guide takes priority. Camera estimates are not included in boutique statistics.',
                      ),
                      value: useScanProportions,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => useScanProportions = v),
                    ),
                  ],
                  OutlinedButton.icon(
                    key: const Key('scan-body-proportions'),
                    onPressed: busy ? null : scanBody,
                    icon: const Icon(Icons.accessibility_new_rounded),
                    label: Text(
                      bodyScan == null ? 'Scan body proportions' : 'Scan again',
                    ),
                  ),
                  if (bodyScan != null)
                    TextButton(
                      key: const Key('remove-body-scan'),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              bodyScan = null;
                              useScanProportions = false;
                            }),
                      child: const Text('Remove scan'),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 16),
                    child: Text(
                      'Camera estimates are separate from your measurements below. Review changes, then save.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
                if (!widget.measurementsOnly) ...[
                  const Text(
                    'Silhouettes you love',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in dressCategories)
                        FilterChip(
                          key: ValueKey('prefer-style-$s'),
                          label: Text(s),
                          selected: styles.contains(s),
                          onSelected: busy
                              ? null
                              : (v) => setState(
                                  () => v ? styles.add(s) : styles.remove(s),
                                ),
                        ),
                    ],
                  ),
                  gap(22),
                  const Text(
                    'Colours you’re drawn to',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in dressColours)
                        FilterChip(
                          key: ValueKey('prefer-colour-$s'),
                          label: Text(s),
                          selected: colours.contains(s),
                          onSelected: busy
                              ? null
                              : (v) => setState(
                                  () => v ? colours.add(s) : colours.remove(s),
                                ),
                        ),
                    ],
                  ),
                  gap(22),
                  TextFormField(
                    controller: budget,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Maximum gown rental price',
                      prefixText: 'RM ',
                      helperText:
                          'Optional · gown price, separate from a package total',
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty || parsePriceCents(v.trim()) != null
                        ? null
                        : 'Enter a valid amount above RM 0.',
                  ),
                  gap(18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include a proportion guide'),
                    subtitle: const Text(
                      'Optional styling ideas from bust, waist and hip measurements.',
                    ),
                    value: useProportions,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            useProportions = v;
                            if (!v) shareProportionStats = false;
                          }),
                  ),
                  if (useProportions)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Include my guide in boutique statistics',
                      ),
                      subtitle: const Text(
                        'Optional. The manager sees category totals, not your name or measurements. Switch off and save to withdraw.',
                      ),
                      value: shareProportionStats,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => shareProportionStats = v),
                    ),
                ],
                if (widget.measurementsOnly) ...[
                  Text(
                    provenance.summary,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Use my body measurements for recommendations',
                    ),
                    subtitle: const Text(
                      'Choose whether your saved bust, waist and hips contribute to styling suggestions.',
                    ),
                    value: useProportions,
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            useProportions = value;
                            if (!value) shareProportionStats = false;
                          }),
                  ),
                ],
                if (widget.measurementsOnly || useProportions) ...[
                  gap(8),
                  const Text(
                    'Measurements in cm',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(8),
                  const Text(
                    'Measure around the fullest bust and hips, and your natural waist. These are body measurements, not garment measurements.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  gap(16),
                  if (widget.measurementsOnly && widget.scanner.available) ...[
                    OutlinedButton.icon(
                      onPressed: busy ? null : scanMeasurements,
                      icon: const Icon(Icons.straighten),
                      label: const Text('Estimate bust, waist & hips'),
                    ),
                    gap(14),
                  ],
                  for (final key
                      in widget.measurementsOnly
                          ? fields.keys
                          : ['Bust', 'Waist', 'Hips']) ...[
                    TextFormField(
                      key: ValueKey('body-$key'),
                      controller: fields[key],
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: key == 'Shoulder' ? 'Shoulder width' : key,
                        suffixText: key == 'Weight' ? 'kg' : 'cm',
                      ),
                      onChanged: (value) {
                        if (circumferenceLabels.contains(key)) {
                          setState(() {
                            provenance = provenance.manual(
                              key,
                              present: value.trim().isNotEmpty,
                              at: DateTime.now().millisecondsSinceEpoch,
                            );
                            if (value.trim().isEmpty &&
                                widget.measurementsOnly) {
                              useProportions = false;
                              shareProportionStats = false;
                            }
                          });
                        }
                      },
                      validator: (v) {
                        if (v!.trim().isEmpty) return null;
                        final n = double.tryParse(v.trim()),
                            range = measurementLimits[key]!;
                        return n == null ||
                                !n.isFinite ||
                                n < range.$1 ||
                                n > range.$2
                            ? 'Enter ${range.$1.toInt()}–${range.$2.toInt()} ${key == 'Weight' ? 'kg' : 'cm'}.'
                            : null;
                      },
                    ),
                    gap(14),
                  ],
                ],
                if (!widget.measurementsOnly && useProportions)
                  const Text(
                    'This simplified styling guide is optional and approximate. Your preferences matter more than a body-shape label.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                gap(12),
                const Text(
                  'Saved privately to your Luvly account. A fitting confirms your size and alterations.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                gap(16),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (widget.measurementsOnly) {
                            for (final c in fields.values) {
                              c.clear();
                            }
                          } else {
                            styles.clear();
                            colours.clear();
                            budget.clear();
                            useProportions = false;
                            useScanProportions = false;
                            shareProportionStats = false;
                          }
                        }),
                  child: Text(
                    widget.measurementsOnly
                        ? 'Clear measurements'
                        : 'Reset style preferences',
                  ),
                ),
              ],
            ),
          ),
  );
}
