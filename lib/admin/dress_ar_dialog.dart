import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../catalogue/dress_ar_api.dart';
import '../payments/payment_api.dart';

Future<bool> confirmDressArGeneration(
  BuildContext context, {
  required int credits,
  bool saveFirst = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate AR try-on?'),
        content: Text(
          saveFirst
              ? 'Luvly will save this dress, then send its photo to Tripo to generate a 3D model. This uses about $credits Tripo API credits.'
              : 'Luvly will send the saved dress photo to Tripo to generate a 3D model. This uses about $credits Tripo API credits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(saveFirst ? 'Save & generate' : 'Generate model'),
          ),
        ],
      ),
    ) ??
    false;

class DressArDialog extends StatefulWidget {
  const DressArDialog({
    super.key,
    required this.uid,
    required this.dressId,
    required this.photoRevision,
    this.generateOnOpen = false,
  });

  final String uid, dressId;
  final int photoRevision;
  final bool generateOnOpen;

  @override
  State<DressArDialog> createState() => _DressArDialogState();
}

class _DressArDialogState extends State<DressArDialog> {
  late final api = DressArApi(widget.uid, widget.dressId, widget.photoRevision);
  DressArStatus? status;
  Uint8List? preview;
  String? error;
  String front = '+Z';
  bool busy = false;
  Timer? poll;

  @override
  void initState() {
    super.initState();
    if (widget.generateOnOpen) {
      run(api.generate, updateOrientation: true);
    } else {
      refresh();
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    api.close();
    super.dispose();
  }

  Future<void> refresh() => run(api.status, updateOrientation: status == null);

  Future<void> run(
    Future<DressArStatus> Function() load, {
    bool updateOrientation = false,
  }) async {
    if (busy) return;
    poll?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await load();
      if (!mounted) return;
      setState(() {
        status = next;
        if (updateOrientation) front = next.front;
      });
      if (next.hasPreview && preview == null) {
        try {
          final image = await api.preview();
          if (mounted) setState(() => preview = image);
        } catch (_) {
          if (mounted) {
            setState(() => error = 'Could not load the preview image.');
          }
        }
      }
      if (mounted && next.inProgress && next.configured) {
        poll = Timer(const Duration(seconds: 6), refresh);
      }
    } on PaymentFailure catch (e) {
      if (mounted) setState(() => error = dressArError(e.code));
    } catch (_) {
      if (mounted) setState(() => error = dressArError(null));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> generate(int credits) async {
    if (await confirmDressArGeneration(context, credits: credits) && mounted) {
      await run(api.generate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = status;
    final ready = current?.state == 'ready';
    final description = switch (current?.state) {
      'preparing' || 'submitting' => 'Submitting the saved photo to Tripo…',
      'running' =>
        'Generating the 3D model. You can close this and check again from Edit Dress.',
      'ready' when current!.approved =>
        'Try-on is enabled when this dress is published.',
      'ready' => 'Review the generated model before enabling try-on.',
      'failed' => dressArError(current?.error),
      'submission_unknown' =>
        'Tripo may have received the request. Check Tripo task history before attempting another generation.',
      _ =>
        busy && current == null
            ? (widget.generateOnOpen
                  ? 'Submitting the saved photo to Tripo…'
                  : 'Checking 3D try-on…')
            : current?.configured == false
            ? 'Tripo is not configured on the Luvly server.'
            : 'Generate an optional 3D try-on model from the saved dress photo.',
    };
    return AlertDialog(
      title: const Text('3D try-on'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy || current?.inProgress == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: LinearProgressIndicator(
                    value: (current?.progress ?? 0) > 0
                        ? current!.progress / 100
                        : null,
                  ),
                ),
              Text(description),
              if (current?.spent case final spent?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Tripo credits used · $spent'),
                ),
              if (preview case final bytes?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Image.memory(
                    bytes,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.contain,
                    semanticLabel: 'Tripo-generated dress preview',
                  ),
                ),
              if (ready) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: front,
                  decoration: const InputDecoration(
                    labelText: 'Front alignment',
                  ),
                  items: const [
                    DropdownMenuItem(value: '+Z', child: Text('Default')),
                    DropdownMenuItem(value: '+X', child: Text('Turn 90°')),
                    DropdownMenuItem(value: '-Z', child: Text('Turn 180°')),
                    DropdownMenuItem(value: '-X', child: Text('Turn 270°')),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => front = value!),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can adjust the front after checking it on Android. Rotation uses no Tripo credits.',
                ),
              ],
              if (error case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        if (!busy && (error != null || current?.inProgress == true || !ready))
          TextButton(onPressed: refresh, child: const Text('Check status')),
        if (current?.canGenerate == true)
          FilledButton(
            onPressed: busy ? null : () => generate(current!.credits),
            child: const Text('Generate from photo'),
          ),
        if (current?.approved == true)
          TextButton(
            onPressed: busy
                ? null
                : () => run(() => api.approve(false, current!.front)),
            child: const Text('Disable try-on'),
          ),
        if (ready)
          FilledButton(
            onPressed: busy || (current!.approved && front == current.front)
                ? null
                : () => run(() => api.approve(true, front)),
            child: Text(current!.approved ? 'Save alignment' : 'Enable try-on'),
          ),
      ],
    );
  }
}
