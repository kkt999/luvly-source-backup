import 'package:flutter/material.dart';
import '../payments/payment_api.dart';

const measurementKeys = [
  'bustMin',
  'bustMax',
  'waistMin',
  'waistMax',
  'hipMin',
  'hipMax',
  'lengthCm',
];
String measurementSourceLabel(Map<String, dynamic> variant) =>
    variant['measurementSource'] == 'demo-reference'
    ? 'General size reference · not measured on this gown · confirm fit in store'
    : 'Staff-entered ranges · fitting required';
const measurementLabels = [
  'Bust minimum',
  'Bust maximum',
  'Waist minimum',
  'Waist maximum',
  'Hip minimum',
  'Hip maximum',
  'Gown length',
];
double? measurementNumber(String text) {
  if (!RegExp(r'^\d{1,3}(\.\d)?$').hasMatch(text.trim())) return null;
  final value = double.tryParse(text.trim());
  return value != null && value >= 20 && value <= 300 ? value : null;
}

String fitComparison(Map<String, dynamic>? ranges, Map<String, double> body) {
  if (ranges == null) return 'Size measurements not provided';
  if (body.length != 3) return 'Enter bust, waist and hip to compare';
  final outside = ['bust', 'waist', 'hip']
      .where(
        (k) =>
            body[k]! < (ranges['${k}Min'] as num) ||
            body[k]! > (ranges['${k}Max'] as num),
      )
      .toList();
  return outside.isEmpty
      ? 'Within the listed ranges · fitting still required'
      : 'Outside listed range: ${outside.join(', ')}';
}

/// Recommend only variants whose three body ranges contain the user's inputs.
/// Distance to each range's centre ranks overlapping matches, not poor fits.
List<Map<String, dynamic>> matchingGownSizes(
  List<Map<String, dynamic>> variants,
  Map<String, double> body,
) {
  if (!['bust', 'waist', 'hip'].every((k) => body[k]?.isFinite == true)) {
    return [];
  }
  final matches = variants.where((v) {
    final ranges = v['measurements'];
    return ranges is Map &&
        ['bust', 'waist', 'hip'].every((k) {
          final min = ranges['${k}Min'], max = ranges['${k}Max'];
          return min is num &&
              max is num &&
              min.isFinite &&
              max.isFinite &&
              min <= max &&
              body[k]! >= min &&
              body[k]! <= max;
        });
  }).toList();
  double score(Map<String, dynamic> v) {
    final m = v['measurements'] as Map;
    return ['bust', 'waist', 'hip'].fold(0.0, (total, k) {
      final min = (m['${k}Min'] as num).toDouble();
      final max = (m['${k}Max'] as num).toDouble();
      final width = max - min < 1 ? 1.0 : max - min;
      final delta = (body[k]! - (min + max) / 2) / width;
      return total + delta * delta;
    });
  }

  matches.sort((a, b) {
    final order = score(a).compareTo(score(b));
    return order != 0 ? order : '${a['size']}'.compareTo('${b['size']}');
  });
  return matches;
}

class GownFitScreen extends StatefulWidget {
  const GownFitScreen({
    super.key,
    required this.dressId,
    required this.dressName,
    this.api,
    this.returnSize = false,
  });
  final String dressId, dressName;
  final HttpPaymentApi? api;
  final bool returnSize;
  @override
  State<GownFitScreen> createState() => _GownFitState();
}

class _GownFitState extends State<GownFitScreen> {
  late final api = widget.api ?? HttpPaymentApi();
  final form = GlobalKey<FormState>();
  final inputs = {
    for (final k in ['bust', 'waist', 'hip']) k: TextEditingController(),
  };
  Map<String, double> body = {};
  List<Map<String, dynamic>>? variants;
  String? error;
  bool busy = false;
  Future<void> compareSizes() async {
    FocusScope.of(context).unfocus();
    if (!form.currentState!.validate()) return;
    setState(() {
      body = inputs.map((k, c) => MapEntry(k, measurementNumber(c.text)!));
    });
    final sizes = variants ?? <Map<String, dynamic>>[];
    final hasMeasurements = sizes.any((v) => v['measurements'] != null);
    final matches = matchingGownSizes(sizes, body);
    final recommended = matches.isEmpty ? null : matches.first;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          !hasMeasurements
              ? 'Cannot compare yet'
              : recommended == null
              ? 'Staff fitting recommended'
              : 'Your reference size: ${recommended['size']}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hasMeasurements)
                const Text(
                  'This gown has no size measurements yet. Please ask Luvly staff to add them or arrange a fitting. Your measurements cannot be compared until then.',
                )
              else ...[
                if (recommended != null) ...[
                  Text(
                    'Size ${recommended['size']} is the closest matching option for this gown. Your bust, waist and hip are all within its listed ranges.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(measurementSourceLabel(recommended)),
                  if (matches.length > 1)
                    Text(
                      'Also within range: ${matches.skip(1).map((v) => v['size']).join(', ')}. Staff can compare these at your fitting.',
                    ),
                ] else
                  const Text(
                    'None of this gown’s listed sizes matches all three measurements. Check that you entered body circumferences in centimetres, then ask staff for a fitting or try another gown.',
                  ),
                const SizedBox(height: 16),
                for (final v in sizes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Size ${v['size']}\n${fitComparison(v['measurements'] == null ? null : Map<String, dynamic>.from(v['measurements']), body)}\n${measurementSourceLabel(Map<String, dynamic>.from(v))}',
                    ),
                  ),
                const Text(
                  'This is size guidance, not a guaranteed fit or a stock reservation.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (widget.returnSize && recommended != null)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, recommended['size'] as String),
              child: Text('Use ${recommended['size']}'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) Navigator.pop(context, selected);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.businessRequest(
        '/v1/rental-variants?dressId=${Uri.encodeQueryComponent(widget.dressId)}',
      );
      if (mounted) {
        setState(
          () => variants = (result['variants'] as List)
              .map((v) => Map<String, dynamic>.from(v))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PaymentFailure
              ? e.message
              : 'Could not load size information. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Size guide & fit check')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.dressName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Enter your measurements to find a reference size for this gown. We compare bust, waist and hip together; staff will confirm the final fit.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Measure bust, waist and hips around the fullest bust, natural waist and fullest hips. All values are in centimetres. Your entries stay on this screen and are not saved or uploaded.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Form(
              key: form,
              child: Column(
                children: [
                  for (final k in inputs.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: inputs[k],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${k[0].toUpperCase()}${k.substring(1)} (cm)',
                        ),
                        onChanged: (_) {
                          if (body.isNotEmpty) setState(() => body = {});
                        },
                        validator: (v) => measurementNumber(v ?? '') == null
                            ? 'Enter 20–300 cm, with up to 1 decimal.'
                            : null,
                      ),
                    ),
                  FilledButton(
                    onPressed: busy || error != null ? null : compareSizes,
                    child: const Text('Find my size'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (busy) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: busy ? null : load,
                child: const Text('Retry'),
              ),
            ],
            if (variants != null && variants!.isEmpty)
              const Text('No sizes configured. Please contact Luvly.'),
            for (final v in variants ?? <Map<String, dynamic>>[])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Size ${v['size']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (v['measurements'] == null)
                        const Text(
                          'Measurements not provided. Ask staff at your fitting.',
                        )
                      else ...[
                        Text(
                          measurementSourceLabel(v),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        for (final k in ['bust', 'waist', 'hip'])
                          Text(
                            '${k[0].toUpperCase()}${k.substring(1)}: ${v['measurements']['${k}Min']}–${v['measurements']['${k}Max']} cm',
                          ),
                        Text(
                          v['measurementSource'] == 'demo-reference'
                              ? 'Reference hollow-to-hem length: ${v['measurements']['lengthCm']} cm · excludes train; confirm gown length in store'
                              : 'Gown length: ${v['measurements']['lengthCm']} cm · verify measurement point with staff',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          fitComparison(
                            Map<String, dynamic>.from(v['measurements']),
                            body,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Size guidance does not reserve stock. Rental-date availability is checked separately.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
