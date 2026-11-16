import 'package:flutter/material.dart';
import 'catalogue_repository.dart';
import 'dress_photo_data.dart';

class CatalogueDressPhoto extends StatefulWidget {
  const CatalogueDressPhoto({
    super.key,
    required this.dress,
    this.repository,
    this.height = 240,
    this.compact = false,
    this.placeholder,
  });
  final CatalogueDress dress;
  final CatalogueRepository? repository;
  final double height;
  final bool compact;
  final Widget? placeholder;
  @override
  State<CatalogueDressPhoto> createState() => _CatalogueDressPhotoState();
}

class _CatalogueDressPhotoState extends State<CatalogueDressPhoto> {
  CatalogueRepository? repository;
  Stream<DressPhotoData?>? stream;
  void subscribe() {
    stream = widget.dress.photoRevision > 0
        ? repository!.watchPhoto(widget.dress)
        : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = widget.repository ?? CatalogueScope.of(context);
    if (next != repository) {
      repository = next;
      subscribe();
    }
  }

  @override
  void didUpdateWidget(CatalogueDressPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.repository ?? CatalogueScope.of(context);
    if (next != repository ||
        widget.dress.id != oldWidget.dress.id ||
        widget.dress.photoRevision != oldWidget.dress.photoRevision) {
      repository = next;
      subscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dress.photoRevision == 0) {
      return DressPhoto(
        url: widget.dress.imageUrl,
        height: widget.height,
        compact: widget.compact,
        fallback: widget.placeholder,
      );
    }
    return StreamBuilder<DressPhotoData?>(
      key: ValueKey('${widget.dress.id}:${widget.dress.photoRevision}'),
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasError &&
            snapshot.hasData &&
            snapshot.connectionState != ConnectionState.waiting) {
          return Image.memory(
            snapshot.data!.imageBytes,
            height: widget.height,
            width: double.infinity,
            fit: BoxFit.contain,
            semanticLabel: 'Dress photograph',
            errorBuilder: (_, _, _) =>
                widget.placeholder ??
                SizedBox(
                  height: widget.height,
                  child: const Center(child: Text('Photo unavailable')),
                ),
          );
        }
        if (widget.placeholder case final placeholder?) return placeholder;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        if (widget.compact) {
          return _CompactPhotoPlaceholder(
            height: widget.height,
            label: loading ? 'Loading photo…' : 'Photo unavailable',
            retry: loading ? null : () => setState(subscribe),
          );
        }
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.image_outlined, size: 36),
              Text(
                loading
                    ? 'Loading photo…'
                    : 'Photo unavailable. Check your connection.',
              ),
              if (!loading)
                TextButton(
                  onPressed: () => setState(subscribe),
                  child: const Text('Retry photo'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class DressPhoto extends StatelessWidget {
  const DressPhoto({
    super.key,
    required this.url,
    this.height = 240,
    this.compact = false,
    this.fallback,
  });
  final String url;
  final double height;
  final bool compact;
  final Widget? fallback;
  @override
  Widget build(BuildContext context) {
    Widget placeholder(String label) =>
        fallback ??
        (compact
            ? _CompactPhotoPlaceholder(height: height, label: label)
            : Container(
                height: height,
                width: double.infinity,
                color: const Color(0xFFF4E5E6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.checkroom_outlined, size: 38),
                    const SizedBox(height: 12),
                    Text(label),
                  ],
                ),
              ));
    if (url.isEmpty) return placeholder('Photo not added');
    return Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: 'Dress photograph',
      errorBuilder: (_, _, _) => placeholder('Photo unavailable'),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder('Loading photo…'),
    );
  }
}

class _CompactPhotoPlaceholder extends StatelessWidget {
  const _CompactPhotoPlaceholder({
    required this.height,
    required this.label,
    this.retry,
  });
  final double height;
  final String label;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (retry == null)
            const Icon(Icons.image_outlined, size: 24)
          else
            IconButton(
              tooltip: 'Retry photo',
              onPressed: retry,
              icon: const Icon(Icons.refresh),
            ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

/// Owns one subscription, recreates it only for retry/repository changes.
class CatalogueFeed extends StatefulWidget {
  const CatalogueFeed({
    super.key,
    required this.inventory,
    required this.builder,
    this.fallbackBuilder,
  });
  final bool inventory;
  final Widget Function(BuildContext, CatalogueSnapshot) builder;
  final Widget Function(BuildContext, bool loading, VoidCallback retry)?
  fallbackBuilder;
  @override
  State<CatalogueFeed> createState() => _CatalogueFeedState();
}

class _CatalogueFeedState extends State<CatalogueFeed> {
  CatalogueRepository? repository;
  Stream<CatalogueSnapshot>? stream;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CatalogueScope.of(context);
    if (repository != next) {
      repository = next;
      _subscribe();
    }
  }

  void _subscribe() {
    stream = repository!.watch(inventory: widget.inventory);
  }

  @override
  void didUpdateWidget(CatalogueFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inventory != oldWidget.inventory) _subscribe();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<CatalogueSnapshot>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        if (widget.fallbackBuilder != null) {
          return widget.fallbackBuilder!(
            context,
            false,
            () => setState(_subscribe),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 36),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load dresses. Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => setState(_subscribe),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData ||
          snapshot.connectionState == ConnectionState.waiting) {
        if (widget.fallbackBuilder != null) {
          return widget.fallbackBuilder!(
            context,
            true,
            () => setState(_subscribe),
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      }
      return widget.builder(context, snapshot.data!);
    },
  );
}
