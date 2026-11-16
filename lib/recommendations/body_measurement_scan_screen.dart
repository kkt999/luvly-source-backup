import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../src/model.dart';
import '../support/assistant_launcher.dart';
import 'body_scan.dart';

class BodyMeasurementScanScreen extends StatefulWidget {
  const BodyMeasurementScanScreen({
    super.key,
    required this.scanner,
    required this.initialHeight,
  });

  final BodyScanner scanner;
  final String initialHeight;

  @override
  State<BodyMeasurementScanScreen> createState() => _BodyMeasurementScanState();
}

class _BodyMeasurementScanState extends State<BodyMeasurementScanScreen> {
  static const labels = ['Bust', 'Waist', 'Hips'];
  final form = GlobalKey<FormState>();
  late final height = TextEditingController(text: widget.initialHeight);
  final measurements = {
    for (final label in labels) label: TextEditingController(),
  };
  bool busy = false, hasEstimate = false, checkedWithTape = false;
  bool ownerBound = false;
  String? error, owner;
  int generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = AppScope.maybeOf(context)?.accountId;
    if (ownerBound && owner != current) {
      generation++;
      busy = false;
      hasEstimate = false;
      checkedWithTape = false;
      error = null;
      for (final controller in measurements.values) {
        controller.clear();
      }
      height.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context);
        }
      });
    }
    owner = current;
    ownerBound = true;
  }

  @override
  void dispose() {
    height.dispose();
    for (final controller in measurements.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> scan() async {
    if (busy || !widget.scanner.available) return;
    if (!hasEstimate && !form.currentState!.validate()) return;
    final heightCm = double.tryParse(height.text.trim());
    if (heightCm == null ||
        !heightCm.isFinite ||
        heightCm < 120 ||
        heightCm > 220) {
      return;
    }
    FocusScope.of(context).unfocus();
    final request = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final estimate = await widget.scanner.estimateMeasurements(heightCm);
      if (!mounted || request != generation || estimate == null) return;
      setState(() {
        for (final label in labels) {
          measurements[label]!.text = estimate[label]!.toStringAsFixed(0);
        }
        hasEstimate = true;
        checkedWithTape = false;
      });
    } on PlatformException catch (e) {
      if (mounted && request == generation) {
        setState(
          () => error = e.code == 'AUTH_REQUIRED'
              ? 'Sign in again before starting a scan.'
              : 'The camera scan could not finish. Try again or enter your tape measurements manually.',
        );
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'Could not estimate your measurements. Check the lighting and try again.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  String? validateNumber(String? text, int min, int max) {
    final value = double.tryParse(text?.trim() ?? '');
    return value == null || !value.isFinite || value < min || value > max
        ? 'Enter a value from $min to $max cm.'
        : null;
  }

  void useMeasurements() {
    if (busy || !checkedWithTape || !form.currentState!.validate()) return;
    Navigator.pop(context, {
      for (final label in labels)
        label: double.parse(measurements[label]!.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AssistantExclusion(
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              hasEstimate
                  ? 'Review measurements'
                  : 'Estimate body measurements',
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: form,
                  child: SingleChildScrollView(
                    key: ValueKey(hasEstimate),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          hasEstimate
                              ? 'Estimated measurements'
                              : 'Bust, waist and hips',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 10),
                        if (!hasEstimate) ...[
                          const Text(
                            'Enter your height in centimetres to set the scale. Wear close-fitting clothes and keep the phone upright and fixed at waist height.',
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            key: const ValueKey('girth-height'),
                            controller: height,
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Height',
                              suffixText: 'cm',
                            ),
                            validator: (value) =>
                                validateNumber(value, 120, 220),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '1. Face the camera with your feet close together and arms slightly out. Keep your head and feet visible.',
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '2. Turn sideways on the same spot and reach both arms forward at shoulder height.',
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Camera frames are processed on your phone. The scan gives approximate measurements and may be affected by clothing and posture.',
                          ),
                        ] else ...[
                          const Text(
                            'Compare each estimate with a measuring tape. Correct any values before copying them to Body information.',
                          ),
                          const SizedBox(height: 18),
                          for (final label in labels) ...[
                            TextFormField(
                              key: ValueKey('girth-$label'),
                              controller: measurements[label],
                              enabled: !busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: label,
                                suffixText: 'cm',
                              ),
                              validator: (value) =>
                                  validateNumber(value, 30, 300),
                              onChanged: (_) {
                                if (checkedWithTape) {
                                  setState(() => checkedWithTape = false);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: checkedWithTape,
                            onChanged: busy
                                ? null
                                : (v) => setState(
                                    () => checkedWithTape = v == true,
                                  ),
                            title: const Text(
                              'I checked these measurements with a tape.',
                            ),
                          ),
                        ],
                        if (!widget.scanner.available)
                          const Text(
                            'Camera scanning is available in the Android app.',
                          ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        const SizedBox(height: 18),
                        if (hasEstimate) ...[
                          FilledButton(
                            onPressed: busy || !checkedWithTape
                                ? null
                                : useMeasurements,
                            child: const Text('Use checked measurements'),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : scan,
                            child: Text(busy ? 'Camera open…' : 'Scan again'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Done without copying'),
                          ),
                        ] else
                          FilledButton(
                            onPressed: busy || !widget.scanner.available
                                ? null
                                : scan,
                            child: Text(
                              busy ? 'Camera open…' : 'Start measurement scan',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
