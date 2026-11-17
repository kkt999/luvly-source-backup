import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dress_ar_api.dart';

class GeneratedGownTryOn extends StatefulWidget {
  const GeneratedGownTryOn({
    super.key,
    required this.uid,
    required this.dressId,
    required this.dressName,
    required this.photoRevision,
  });

  final String uid, dressId, dressName;
  final int photoRevision;
  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<GeneratedGownTryOn> createState() => _GeneratedGownTryOnState();
}

class _GeneratedGownTryOnState extends State<GeneratedGownTryOn> {
  late final api = DressArApi(widget.uid, widget.dressId, widget.photoRevision);
  late final Future<bool> available;
  bool opening = false;

  @override
  void initState() {
    super.initState();
    available = api.available().catchError((Object _) => false);
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  Future<void> open() async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final model = await api.model();
      if (!mounted) return;
      await const MethodChannel('luvly/ar').invokeMethod<void>(
        'openGeneratedTryOn',
        {'dressId': widget.dressId, 'label': widget.dressName, 'model': model},
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The 3D model is unavailable. Reopen this dress and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: available,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return OutlinedButton.icon(
        onPressed: opening ? null : open,
        icon: const Icon(Icons.view_in_ar_outlined, size: 18),
        label: Text(opening ? 'Loading 3D model…' : 'AR try-on'),
      );
    },
  );
}
