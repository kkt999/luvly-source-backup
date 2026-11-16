import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'body_scan.dart';
import '../src/model.dart';

class ReviewedBodyScan {
  const ReviewedBodyScan(this.scan, this.useForSuggestions);
  final BodyScan scan;
  final bool useForSuggestions;
}

class BodyScanScreen extends StatefulWidget {
  const BodyScanScreen({super.key, this.scanner = const BodyScanner()});
  final BodyScanner scanner;
  @override
  State<BodyScanScreen> createState() => _BodyScanScreenState();
}

class _BodyScanScreenState extends State<BodyScanScreen> {
  BodyScan? result;
  BodyScan? previous;
  final scroll = ScrollController();
  bool busy = false, useForSuggestions = false;
  String? error;
  String? owner;
  bool ownerBound = false;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = AppScope.maybeOf(context)?.accountId;
    if (ownerBound && current != owner) {
      generation++;
      result = null;
      previous = null;
      busy = false;
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
    scroll.dispose();
    super.dispose();
  }

  Future<void> scan({bool compare = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final g = generation;
    try {
      final next = await widget.scanner.scan();
      if (!mounted || g != generation) return;
      if (next != null) {
        if (!next.valid) throw const FormatException('Unstable scan');
        setState(() {
          previous = compare ? result : null;
          result = next;
          if (!compare) useForSuggestions = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) scroll.jumpTo(0);
        });
      }
    } on PlatformException catch (e) {
      if (mounted && g == generation) {
        setState(
          () => error = e.code == 'AUTH_REQUIRED'
              ? 'Sign in again before scanning.'
              : e.code == 'SCAN_INTERRUPTED'
              ? 'The scan was interrupted. Your saved details have not changed.'
              : 'Could not start the scan. Check camera access or enter measurements manually.',
        );
      }
    } catch (_) {
      if (mounted && g == generation) {
        setState(
          () => error =
              'We could not use that scan. Try again in even lighting with the phone fixed.',
        );
      }
    } finally {
      if (mounted && g == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(result == null ? 'Scan proportions' : 'Review your scan'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (result != null) ...[
                FilledButton(
                  key: const Key('accept-body-scan'),
                  onPressed: busy
                      ? null
                      : () => Navigator.pop(
                          context,
                          ReviewedBodyScan(result!, useForSuggestions),
                        ),
                  child: const Text('Use this scan'),
                ),
                TextButton(
                  onPressed: busy ? null : () => scan(),
                  child: const Text('Scan again'),
                ),
              ] else
                FilledButton(
                  key: const Key('start-body-scan'),
                  onPressed: busy || !widget.scanner.available
                      ? null
                      : () => scan(),
                  child: Text(busy ? 'Camera open…' : 'Start scan'),
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            result == null
                ? Icons.accessibility_new_rounded
                : Icons.check_circle_outline_rounded,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            result == null
                ? 'A little insight into your proportions.'
                : 'Your scan is ready.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'Optional camera estimates for styling ideas. This does not measure bust, waist or hip circumference, or determine your clothing size.',
          ),
          const SizedBox(height: 24),
          if (result == null) ...[
            const _ScanStep(
              '1',
              'Set up your phone',
              'Keep it fixed and upright at about chest height, facing you. Use even lighting. Avoid pointing it up at the ceiling.',
            ),
            const _ScanStep(
              '2',
              'Stand naturally',
              'Use the on-screen outline to frame your head, shoulders and hips. Keep mirrors and other people out of view. Your knees and feet do not need to be visible. Wear clothing that leaves your outline clear.',
            ),
            const _ScanStep(
              '3',
              'Hold still briefly',
              'Face forward with arms relaxed slightly away from your sides. Hold still for a few seconds and follow the on-screen guidance.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Frames are processed on your phone. No scan photo or video is saved or uploaded. Only proportion estimates can be saved after your review.',
            ),
            if (!widget.scanner.available)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Camera scanning is available in the Android app. You can still enter measurements manually on this device.',
                ),
              ),
          ] else ...[
            BodyScanSummary(scan: result!),
            const SizedBox(height: 12),
            if (previous != null)
              _ComparisonCard(
                comparison: BodyScanComparison(previous!, result!),
                onKeepPrevious: busy
                    ? null
                    : () => setState(() {
                        result = previous;
                        previous = null;
                      }),
              ),
            OutlinedButton.icon(
              key: const Key('compare-body-scan'),
              onPressed: busy ? null : () => scan(compare: true),
              icon: const Icon(Icons.compare_arrows_rounded),
              label: const Text('Check with a second scan'),
            ),
            const Text(
              'Scan the same person again with the same clothing, distance and phone position. Compare consistency before choosing a scan. Nothing is saved automatically.',
            ),
            const SizedBox(height: 12),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('What these ratios mean'),
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'These compare detected shoulder and hip joint spans, and the distance between their midpoints. They are not the widths around your body. Camera angle and clothing can affect the estimate.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: const Key('use-scan-suggestions'),
              title: const Text('Use for styling suggestions'),
              subtitle: const Text(
                'Your style preferences come first. The manual proportion guide takes priority when enabled.',
              ),
              value: useForSuggestions,
              onChanged: busy
                  ? null
                  : (v) => setState(() => useForSuggestions = v),
            ),
            const Text(
              'Save body information on the next screen to keep this scan privately. Your manual measurements stay unchanged.',
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.comparison, this.onKeepPrevious});
  final BodyScanComparison comparison;
  final VoidCallback? onKeepPrevious;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        key: const Key('body-scan-comparison'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compared with your previous scan',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Shoulder / hip ratio difference · ${comparison.shoulderHipDifference.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 8),
          Text(
            'Torso / shoulder ratio difference · ${comparison.torsoShoulderDifference.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 12),
          const Text(
            'These differences describe repeatability, not accuracy. Similar results can share the same camera or tracking bias. If the results differ, check your setup and rescan.',
          ),
          const SizedBox(height: 8),
          const Text(
            'The latest scan is selected. Use this scan keeps only that scan; the comparison is not saved.',
          ),
          TextButton(
            key: const Key('keep-previous-body-scan'),
            onPressed: onKeepPrevious,
            child: const Text('Keep previous scan instead'),
          ),
        ],
      ),
    ),
  );
}

class _ScanStep extends StatelessWidget {
  const _ScanStep(this.number, this.title, this.text);
  final String number, title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 16, child: Text(number)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(text),
            ],
          ),
        ),
      ],
    ),
  );
}

class BodyScanSummary extends StatelessWidget {
  const BodyScanSummary({super.key, required this.scan});
  final BodyScan scan;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Camera proportion estimates',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Shoulder / hip joint span · ${scan.shoulderHipRatio.toStringAsFixed(2)} : 1',
          ),
          const SizedBox(height: 10),
          Text(
            'Torso / shoulder joint span · ${scan.torsoShoulderRatio.toStringAsFixed(2)} : 1',
          ),
          const SizedBox(height: 12),
          Text(
            '${scan.sampleCount} stable samples · ${(scan.durationMs / 1000).toStringAsFixed(1)} seconds',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Stable tracking does not guarantee measurement accuracy.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
