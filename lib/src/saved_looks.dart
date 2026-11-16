import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'model.dart';
import 'dresses.dart';

const _channel = MethodChannel('luvly/ar');

class SavedLook {
  final String id, dressId, path;
  final DateTime savedAt;
  final bool fullBody;
  SavedLook.fromMap(Map m)
    : id = m['id'] as String,
      dressId = m['dressId'] as String,
      path = m['path'] as String,
      savedAt = DateTime.fromMillisecondsSinceEpoch(m['savedAt'] as int),
      fullBody = m['fullBody'] == true;
  int get dressIndex => dresses.indexWhere((d) => d.id == dressId);
  String get name => dressIndex < 0 ? 'Saved dress' : dresses[dressIndex].name;
}

Widget savedLookImage(SavedLook look, {double? height}) => Image.file(
  File(look.path),
  height: height,
  width: double.infinity,
  fit: BoxFit.contain,
  cacheWidth: 1080,
  errorBuilder: (_, _, _) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text('This saved image is unavailable.'),
  ),
);

class TryOnHistoryScreen extends StatefulWidget {
  const TryOnHistoryScreen({super.key});
  @override
  State<TryOnHistoryScreen> createState() => _TryOnHistoryState();
}

class _TryOnHistoryState extends State<TryOnHistoryScreen> {
  List<SavedLook> looks = [];
  final selected = <String>{};
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final rows =
          await _channel
              .invokeListMethod<dynamic>('listLooks')
              .timeout(const Duration(seconds: 8)) ??
          [];
      if (!mounted) return;
      setState(() {
        looks = rows.map((e) => SavedLook.fromMap(Map.from(e as Map))).toList();
        selected.removeWhere((id) => !looks.any((l) => l.id == id));
        error = null;
      });
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => error = 'Saved camera looks are available in the Android app.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load your looks. Please retry.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> remove(SavedLook look) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this look?'),
        content: const Text(
          'This removes the saved photo from this phone. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final deleted = await _channel.invokeMethod<bool>('deleteLook', {
        'id': look.id,
      });
      if (deleted != true) throw StateError('delete failed');
      await load();
    } catch (_) {
      if (mounted) toast(context, 'Could not delete this look. Please retry.');
    }
  }

  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'My try-on looks',
    actions: [
      IconButton(
        tooltip: 'Refresh looks',
        onPressed: loading ? null : load,
        icon: const Icon(Icons.refresh),
      ),
    ],
    bottom: selected.length == 2
        ? Primary(
            'Compare two looks',
            () => go(
              c,
              CompareLooksScreen(
                looks: looks.where((l) => selected.contains(l.id)).toList(),
              ),
            ),
          )
        : null,
    child: PageList(
      children: [
        const Text(
          'Only photos you choose to save appear here. Select two to compare styles—not physical fit.',
        ),
        const DemoNote(
          text:
              'Private to your signed-in account on this phone. No cloud backup. Uninstalling removes these photos.',
        ),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Text(error!),
        if (!loading && error == null && looks.isEmpty)
          const EmptyState(
            Icons.camera_alt_outlined,
            'Your looks, all together',
            'Choose a dress, preview it on yourself, then tap Save look.',
          ),
        for (final look in looks)
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: () => go(c, SavedLookScreen(look: look)),
                  child: savedLookImage(look, height: 280),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(look.name),
                  subtitle: Text(
                    '${look.savedAt.toLocal().toString().substring(0, 16)} · ${look.fullBody ? 'Full-body framing' : 'Cropped hem'}',
                  ),
                  value: selected.contains(look.id),
                  onChanged: (value) => setState(() {
                    if (value == true && selected.length < 2) {
                      selected.add(look.id);
                    } else if (value != true) {
                      selected.remove(look.id);
                    } else {
                      toast(c, 'Select no more than two looks.');
                    }
                  }),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => go(c, SavedLookScreen(look: look)),
                      child: const Text('View look'),
                    ),
                    TextButton(
                      onPressed: () => remove(look),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class SavedLookScreen extends StatelessWidget {
  final SavedLook look;
  const SavedLookScreen({super.key, required this.look});
  @override
  Widget build(BuildContext c) => PageFrame(
    title: look.name,
    child: PageList(
      children: [
        SizedBox(
          height: 460,
          child: InteractiveViewer(child: savedLookImage(look)),
        ),
        const Text(
          'Pinch to inspect your saved preview. Appearance only—not a size, beauty or fit score.',
        ),
        if (!look.fullBody)
          const DemoNote(
            text:
                'The hem is outside the camera frame. Dress length cannot be judged from this image.',
          ),
        if (look.dressIndex >= 0)
          Primary(
            'Dress details & favourites',
            () => go(c, DressDetailScreen(index: look.dressIndex)),
          ),
        if (look.dressIndex >= 0)
          OutlinedButton(
            onPressed: () => go(c, TryOnGuideScreen(index: look.dressIndex)),
            child: const Text('Try again'),
          ),
      ],
    ),
  );
}

class CompareLooksScreen extends StatelessWidget {
  final List<SavedLook> looks;
  const CompareLooksScreen({super.key, required this.looks});
  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Compare your looks',
    child: PageList(
      children: [
        const Text(
          'Which neckline, silhouette and details do you prefer? Compare in similar poses and lighting.',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final look in looks.take(2))
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      Text(look.name, textAlign: TextAlign.center),
                      gap(8),
                      GestureDetector(
                        onTap: () => go(c, SavedLookScreen(look: look)),
                        child: savedLookImage(look),
                      ),
                      TextButton(
                        onPressed: () => go(c, SavedLookScreen(look: look)),
                        child: const Text('Inspect look'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const DemoNote(
          text:
              'These are appearance previews. Different camera distances or cropped hems can affect comparisons. Confirm colour, size and comfort during an in-store fitting.',
        ),
      ],
    ),
  );
}
