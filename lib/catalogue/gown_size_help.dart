import 'package:flutter/material.dart';
import '../payments/payment_api.dart';
import 'gown_measurements.dart';
import 'catalogue_repository.dart' show dressSizes;

/// Centimetres are canonical. Units only affect local input and presentation.
double? bodyMeasurementCm(String text, {required bool inches}) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text.trim())) return null;
  final n = double.tryParse(text.trim());
  if (n == null) return null;
  final cm = n * (inches ? 2.54 : 1);
  return cm >= 20 && cm <= 300 ? cm : null;
}

class GownSizeHelp extends StatefulWidget {
  const GownSizeHelp({
    super.key,
    required this.dressId,
    required this.dressName,
    this.api,
    this.selectableSizes,
  });
  final String dressId, dressName;
  final HttpPaymentApi? api;
  final List<String>? selectableSizes;
  @override
  State<GownSizeHelp> createState() => _GownSizeHelpState();
}

class _GownSizeHelpState extends State<GownSizeHelp> {
  late final api = widget.api ?? HttpPaymentApi();
  late Future<dynamic> feed;
  final form = GlobalKey<FormState>();
  final resultKey = GlobalKey();
  final inputs = {
    for (final k in ['bust', 'waist', 'hip']) k: TextEditingController(),
  };
  int tab = 0;
  bool inches = false;
  // Preserve exact cm values when switching units, avoiding repeated rounding.
  final canonical = <String, double>{};
  List<Map<String, dynamic>>? matches;
  void load() {
    feed = api.businessRequest(
      '/v1/rental-variants?dressId=${Uri.encodeQueryComponent(widget.dressId)}',
    );
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    if (widget.api == null) api.close();
    super.dispose();
  }

  void unit(bool next) {
    if (next == inches) return;
    setState(() {
      for (final key in inputs.keys) {
        final value =
            canonical[key] ??
            bodyMeasurementCm(inputs[key]!.text, inches: inches);
        if (value != null) {
          canonical[key] = value;
          inputs[key]!.text = (value / (next ? 2.54 : 1)).toStringAsFixed(2);
        } else if (inputs[key]!.text.isNotEmpty) {
          inputs[key]!.clear();
        }
      }
      inches = next;
      matches = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Size & fit', style: theme.textTheme.headlineMedium),
                    Text(widget.dressName, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close size guide',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in [
                'Size chart',
                'How to measure',
                'Find my size',
              ].asMap().entries)
                ChoiceChip(
                  showCheckmark: false,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  label: Text(entry.value),
                  selected: tab == entry.key,
                  onSelected: (_) => setState(() => tab = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (tab != 1)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Measurements in ${inches ? 'inches' : 'cm'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('cm')),
                    ButtonSegment(value: true, label: Text('inches')),
                  ],
                  selected: {inches},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => unit(v.single),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Expanded(
            child: tab == 1
                ? const _MeasureInstructions()
                : FutureBuilder<dynamic>(
                    future: feed,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Size information could not be loaded.',
                              ),
                              TextButton(
                                onPressed: () => setState(load),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final variants = (snapshot.data['variants'] as List)
                          .map((v) => Map<String, dynamic>.from(v))
                          .where(
                            (v) =>
                                widget.selectableSizes == null ||
                                widget.selectableSizes!.contains(v['size']),
                          )
                          .toList();
                      variants.sort(
                        (a, b) => dressSizes
                            .indexOf('${a['size']}')
                            .compareTo(dressSizes.indexOf('${b['size']}')),
                      );
                      final general = variants.any(
                        (v) => v['measurementSource'] == 'demo-reference',
                      );
                      String range(Map<String, dynamic> v, String k) {
                        final m = v['measurements'];
                        if (m is! Map ||
                            m['${k}Min'] is! num ||
                            m['${k}Max'] is! num) {
                          return '—';
                        }
                        String number(num value) => inches
                            ? (value / 2.54).toStringAsFixed(1)
                            : value.toString().replaceFirst(
                                RegExp(r'\.0$'),
                                '',
                              );
                        return '${number(m['${k}Min'])}–${number(m['${k}Max'])}';
                      }

                      return ListView(
                        children: [
                          Text(
                            general
                                ? 'General size reference · not measured on this gown. Confirm fit in store.'
                                : 'Body measurement ranges · confirm the final fit at your fitting.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          if (tab == 0) ...[
                            Table(
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              columnWidths: const {0: FlexColumnWidth(.7)},
                              children: [
                                TableRow(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF4E5E6),
                                  ),
                                  children: [
                                    for (final label in [
                                      'Size',
                                      'Bust',
                                      'Waist',
                                      'Hip',
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 14,
                                        ),
                                        child: Text(
                                          label,
                                          style: theme.textTheme.labelLarge,
                                        ),
                                      ),
                                  ],
                                ),
                                for (var i = 0; i < variants.length; i++)
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: i.isEven
                                          ? Colors.white
                                          : const Color(0xFFF7F2EF),
                                    ),
                                    children: [
                                      for (final value in [
                                        '${variants[i]['size']}',
                                        range(variants[i], 'bust'),
                                        range(variants[i], 'waist'),
                                        range(variants[i], 'hip'),
                                      ])
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 16,
                                          ),
                                          child: Text(
                                            value,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                            if (variants.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No size chart is available yet.'),
                              ),
                            if (variants.any((v) => v['measurements'] == null))
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  '— Measurements pending. Contact Luvly for guidance.',
                                ),
                              ),
                            const SizedBox(height: 24),
                            Text(
                              'A little help finding your fit',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Compare your three measurements with the listed sizes.',
                            ),
                            TextButton.icon(
                              onPressed: () => setState(() => tab = 2),
                              label: const Text('Find my size'),
                              icon: const Icon(Icons.arrow_forward, size: 16),
                              iconAlignment: IconAlignment.end,
                            ),
                          ] else ...[
                            const Text(
                              'Enter your body measurements. Your entries stay on this screen.',
                            ),
                            const SizedBox(height: 16),
                            Form(
                              key: form,
                              child: Column(
                                children: [
                                  for (final k in inputs.keys)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: TextFormField(
                                        controller: inputs[k],
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText:
                                              '${k[0].toUpperCase()}${k.substring(1)} (${inches ? 'in' : 'cm'})',
                                        ),
                                        validator: (v) =>
                                            (canonical[k] ??
                                                    bodyMeasurementCm(
                                                      v ?? '',
                                                      inches: inches,
                                                    )) ==
                                                null
                                            ? inches
                                                  ? 'Enter 7.88–118.11 inches.'
                                                  : 'Enter 20–300 cm.'
                                            : null,
                                        onChanged: (_) => setState(() {
                                          canonical.remove(k);
                                          matches = null;
                                        }),
                                      ),
                                    ),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () async {
                                        FocusScope.of(context).unfocus();
                                        if (!form.currentState!.validate()) {
                                          return;
                                        }
                                        setState(
                                          () => matches = matchingGownSizes(
                                            variants,
                                            inputs.map(
                                              (k, c) => MapEntry(
                                                k,
                                                canonical[k] ??
                                                    bodyMeasurementCm(
                                                      c.text,
                                                      inches: inches,
                                                    )!,
                                              ),
                                            ),
                                          ),
                                        );
                                        await Future<void>.delayed(
                                          const Duration(milliseconds: 300),
                                        );
                                        if (mounted &&
                                            resultKey.currentContext != null) {
                                          await Scrollable.ensureVisible(
                                            resultKey.currentContext!,
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('Find my size'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (matches != null)
                              Padding(
                                key: resultKey,
                                padding: const EdgeInsets.only(top: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF4E5E6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        matches!.isEmpty
                                            ? 'Let’s confirm your fit'
                                            : 'Reference size: ${matches!.first['size']}',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        matches!.isEmpty
                                            ? 'No listed size matches all three measurements. Contact Luvly for fitting advice.'
                                            : 'Your bust, waist and hip fall within this size’s reference ranges. A fitting confirms the final fit.',
                                      ),
                                      if (matches!.isNotEmpty)
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                            context,
                                            matches!.first['size'] as String,
                                          ),
                                          child: Text(
                                            'Use ${matches!.first['size']}',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MeasureInstructions extends StatelessWidget {
  const _MeasureInstructions();
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Container(
        height: 235,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F2EF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: SizedBox(
            width: 210,
            height: 220,
            child: CustomPaint(painter: _MeasurementPainter()),
          ),
        ),
      ),
      const SizedBox(height: 18),
      for (final item in [
        (
          '1',
          'Bust',
          'Measure around the fullest part of your bust. Keep the tape level.',
        ),
        (
          '2',
          'Waist',
          'Measure around your natural waist, keeping the tape comfortably snug.',
        ),
        (
          '3',
          'Hips',
          'Stand with feet together and measure around the fullest part of your hips.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFF4E5E6),
                child: Text(
                  item.$1,
                  style: const TextStyle(color: Color(0xFF7D3D4E)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(item.$3),
                  ],
                ),
              ),
            ],
          ),
        ),
      const Text(
        'Use a flexible measuring tape. These are body circumferences, not flat garment measurements.',
      ),
    ],
  );
}

class _MeasurementPainter extends CustomPainter {
  const _MeasurementPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = const Color(0xFFAE8D96)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final body = Path()
      ..moveTo(87, 42)
      ..lineTo(70, 49)
      ..quadraticBezierTo(57, 50, 50, 66)
      ..lineTo(33, 132)
      ..quadraticBezierTo(32, 141, 41, 142)
      ..lineTo(68, 81)
      ..quadraticBezierTo(78, 103, 68, 126)
      ..quadraticBezierTo(55, 148, 64, 171)
      ..lineTo(75, 211)
      ..lineTo(93, 211)
      ..lineTo(105, 161)
      ..lineTo(117, 211)
      ..lineTo(135, 211)
      ..lineTo(146, 171)
      ..quadraticBezierTo(155, 148, 142, 126)
      ..quadraticBezierTo(132, 103, 142, 81)
      ..lineTo(169, 142)
      ..quadraticBezierTo(178, 141, 177, 132)
      ..lineTo(160, 66)
      ..quadraticBezierTo(153, 50, 140, 49)
      ..lineTo(123, 42);
    canvas.drawCircle(const Offset(105, 23), 18, outline);
    canvas.drawPath(body, outline);
    final tape = Paint()
      ..color = const Color(0xFFA65360)
      ..strokeWidth = 3;
    for (final item in [
      (1, 76.0, 141.0),
      (2, 107.0, 136.0),
      (3, 143.0, 148.0),
    ]) {
      canvas.drawLine(
        Offset(210 - item.$3, item.$2),
        Offset(item.$3, item.$2),
        tape,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '${item.$1}',
          style: const TextStyle(
            fontFamily: 'LuvlySans',
            color: Color(0xFFA65360),
            fontSize: 13,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(187, item.$2 - 8));
      canvas.drawLine(
        Offset(item.$3 + 3, item.$2),
        Offset(181, item.$2),
        outline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
