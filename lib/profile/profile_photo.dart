import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:file_selector/file_selector.dart';
import '../catalogue/dress_photo_data.dart';
import '../packages/package_api.dart' show packageRequestId;
import '../support/assistant_launcher.dart';
import '../workspace/workspace_api.dart';
import 'profile_photo_data.dart';

final _photoChanges = StreamController<String>.broadcast();

/// No globally cached image bytes: each view is bound to the current owner.
class ProfilePhotoAvatar extends StatefulWidget {
  const ProfilePhotoAvatar({
    super.key,
    this.uid,
    this.radius = 38,
    this.editable = false,
    this.showLabel = false,
    this.fallbackInitial,
    this.backgroundColor,
    this.api,
  });
  final String? uid, fallbackInitial;
  final double radius;
  final bool editable, showLabel;
  final WorkspaceApi? api;
  final Color? backgroundColor;
  @override
  State<ProfilePhotoAvatar> createState() => _PhotoAvatarState();
}

class _PhotoAvatarState extends State<ProfilePhotoAvatar> {
  late final api = widget.api ?? WorkspaceApi();
  StreamSubscription<String>? changes;
  DressPhotoData? photo;
  String? error;
  int epoch = 0;
  bool get connected =>
      widget.uid != null && (widget.api != null || Firebase.apps.isNotEmpty);
  @override
  void initState() {
    super.initState();
    changes = _photoChanges.stream.listen((uid) {
      if (uid == widget.uid) load();
    });
    if (connected) load();
  }

  @override
  void didUpdateWidget(ProfilePhotoAvatar old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) {
      epoch++;
      photo = null;
      error = null;
      if (connected) load();
    }
  }

  Future<void> load() async {
    final request = ++epoch, uid = widget.uid;
    if (uid == null) return;
    try {
      final value = ProfilePhotoRecord.parse(
        await api.request('/v1/my-profile-photo'),
        uid,
      );
      if (mounted && request == epoch) {
        setState(() {
          photo = value.photo;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && request == epoch) {
        setState(() {
          photo = null;
          error = 'Photo unavailable. Tap to retry.';
        });
      }
    }
  }

  Future<void> edit() async {
    if (!connected) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProfilePhotoEditScreen(uid: widget.uid!, api: api),
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'Removed'
                ? 'Profile photo removed.'
                : 'Profile photo updated.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    epoch++;
    changes?.cancel();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    final fallback = widget.fallbackInitial == null
        ? Icon(Icons.person_outline, size: widget.radius * 1.05, color: colour)
        : Text(widget.fallbackInitial!, style: TextStyle(color: colour));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: widget.editable ? 'Edit profile photo' : 'Profile photo',
          button: widget.editable,
          child: Tooltip(
            message:
                error ??
                (widget.editable ? 'Change profile photo' : 'Profile photo'),
            child: InkWell(
              onTap: widget.editable
                  ? edit
                  : error != null
                  ? load
                  : null,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: widget.radius * 2 + (widget.editable ? 8 : 0),
                height: widget.radius * 2 + (widget.editable ? 8 : 0),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: CircleAvatar(
                        radius: widget.radius,
                        backgroundColor:
                            widget.backgroundColor ?? const Color(0xFFF4E5E6),
                        child: photo == null
                            ? fallback
                            : ClipOval(
                                child: Image.memory(
                                  photo!.imageBytes,
                                  width: widget.radius * 2,
                                  height: widget.radius * 2,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, e, s) => fallback,
                                ),
                              ),
                      ),
                    ),
                    if (widget.editable)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colour,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_outlined,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.showLabel)
          TextButton(
            onPressed: connected ? edit : null,
            child: const Text('Change photo'),
          ),
      ],
    );
  }
}

class ProfilePhotoEditScreen extends StatefulWidget {
  const ProfilePhotoEditScreen({
    super.key,
    required this.uid,
    this.api,
    this.pickPhoto,
  });
  final String uid;
  final WorkspaceApi? api;
  final Future<XFile?> Function()? pickPhoto;
  @override
  State<ProfilePhotoEditScreen> createState() => _PhotoEditState();
}

class _PhotoEditState extends State<ProfilePhotoEditScreen> {
  late final api = widget.api ?? WorkspaceApi();
  ProfilePhotoRecord? record;
  DressPhotoData? source;
  ui.Image? image;
  double zoom = 1, x = .5, y = .5;
  bool loading = true, preparing = false, saving = false, discarding = false;
  String? error, requestId;
  bool get busy => loading || preparing || saving;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final row = ProfilePhotoRecord.parse(
        await api.request('/v1/my-profile-photo'),
        widget.uid,
      );
      if (mounted) setState(() => record = row);
    } catch (e) {
      if (mounted) setState(() => error = workspaceError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pick() async {
    setState(() {
      preparing = true;
      error = null;
    });
    ui.Image? decoded;
    try {
      final file =
          await (widget.pickPhoto?.call() ??
              openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'Profile photos',
                    extensions: ['jpg', 'jpeg', 'png'],
                    mimeTypes: ['image/jpeg', 'image/png'],
                    uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
                  ),
                ],
              ));
      if (file == null) return;
      final value = await prepareDressPhoto(file),
          codec = await ui.instantiateImageCodec(value.imageBytes);
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        decoded.dispose();
        return;
      }
      final old = image;
      setState(() {
        source = value;
        image = decoded;
        zoom = 1;
        x = .5;
        y = .5;
        requestId = null;
      });
      old?.dispose();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : workspaceError(e),
        );
      }
    } finally {
      if (mounted) setState(() => preparing = false);
    }
  }

  void cropChanged({double? newZoom, double? newX, double? newY}) {
    setState(() {
      zoom = newZoom ?? zoom;
      x = (newX ?? x).clamp(0, 1);
      y = (newY ?? y).clamp(0, 1);
      requestId = null;
    });
  }

  Future<void> save({bool remove = false}) async {
    if (record == null || busy || (!remove && source == null)) return;
    if (remove) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Remove profile photo?'),
          content: const Text(
            'Your account will use the default avatar. Your profile and rental records are unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep photo'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final photo = remove
          ? null
          : await prepareProfileCrop(
              ProfileCropInput(source!.bytes, zoom, x, y),
            );
      requestId ??= packageRequestId();
      final result = ProfilePhotoRecord.parse(
        await api.request(
          '/v1/my-profile-photo',
          body: {
            'requestId': requestId,
            'revision': record!.revision,
            'photo': photo?.toFields(),
          },
        ),
        widget.uid,
      );
      if (result.revision <= record!.revision ||
          remove && result.photo != null ||
          !remove && result.photo == null) {
        throw const FormatException('Photo was not confirmed saved');
      }
      if (!mounted) return;
      _photoChanges.add(widget.uid);
      setState(() {
        saving = false;
        discarding = true;
      });
      // Rebuild PopScope before closing: its previous frame still blocks
      // navigation while the upload is in progress.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, remove ? 'Removed' : 'Saved');
      });
    } catch (e) {
      if (mounted) setState(() => error = workspaceError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    image?.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving && (source == null || discarding),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || saving || source == null) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard photo changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard == true && context.mounted) {
        setState(() => discarding = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const AssistantExclusion(child: Text('Profile photo')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'A little more you',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a JPG or PNG up to 5 MB. Preview and adjust your photo before saving. Only your compressed crop is uploaded.',
              ),
              const SizedBox(height: 24),
              if (loading || preparing) const LinearProgressIndicator(),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (record == null)
                  TextButton(
                    onPressed: busy ? null : load,
                    child: const Text('Retry photo'),
                  ),
              ],
              const SizedBox(height: 20),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (c, size) => GestureDetector(
                        onPanUpdate: source == null || busy
                            ? null
                            : (d) {
                                final b = profileCropBounds(
                                  source!.width,
                                  source!.height,
                                  zoom,
                                  x,
                                  y,
                                );
                                cropChanged(
                                  newX: source!.width == b.side
                                      ? x
                                      : x -
                                            d.delta.dx *
                                                b.side /
                                                size.maxWidth /
                                                (source!.width - b.side),
                                  newY: source!.height == b.side
                                      ? y
                                      : y -
                                            d.delta.dy *
                                                b.side /
                                                size.maxWidth /
                                                (source!.height - b.side),
                                );
                              },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4E5E8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: image != null
                                ? CustomPaint(
                                    painter: _CropPainter(image!, zoom, x, y),
                                  )
                                : record?.photo != null
                                ? Image.memory(
                                    record!.photo!.imageBytes,
                                    fit: BoxFit.cover,
                                  )
                                : const Center(
                                    child: Icon(
                                      Icons.person_outline,
                                      size: 110,
                                      color: Color(0xFFA95262),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (source != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Drag the photo to reposition. The circle shows your avatar.',
                ),
                Row(
                  children: [
                    const Icon(Icons.zoom_out),
                    Expanded(
                      child: Slider(
                        label: 'Zoom ${zoom.toStringAsFixed(1)}×',
                        value: zoom,
                        min: 1,
                        max: math
                            .min(
                              3,
                              math.min(source!.width, source!.height) / 64,
                            )
                            .toDouble(),
                        onChanged: busy ? null : (v) => cropChanged(newZoom: v),
                      ),
                    ),
                    const Icon(Icons.zoom_in),
                  ],
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => cropChanged(newZoom: 1, newX: .5, newY: .5),
                  child: const Text('Reset crop'),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || record == null ? null : pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      source == null ? 'Choose photo' : 'Choose another',
                    ),
                  ),
                  if (record?.photo != null && source == null)
                    TextButton.icon(
                      onPressed: busy ? null : () => save(remove: true),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy || source == null ? null : () => save(),
                icon: const Icon(Icons.check),
                label: Text(saving ? 'Saving…' : 'Save photo'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Saved securely to your Luvly account so it is available on your other devices. Name and contact changes are saved separately.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.zoom, this.x, this.y);
  final ui.Image image;
  final double zoom, x, y;
  @override
  void paint(Canvas canvas, Size size) {
    final b = profileCropBounds(image.width, image.height, zoom, x, y),
        target = Offset.zero & size;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        b.x.toDouble(),
        b.y.toDouble(),
        b.side.toDouble(),
        b.side.toDouble(),
      ),
      target,
      Paint()..filterQuality = FilterQuality.high,
    );
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(target),
      Path()..addOval(target),
    );
    canvas.drawPath(mask, Paint()..color = const Color(0x77000000));
    canvas.drawOval(
      target.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      image != old.image || zoom != old.zoom || x != old.x || y != old.y;
}
