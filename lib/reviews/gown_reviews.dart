import 'package:flutter/material.dart';
import 'review_api.dart';
import 'review_screen.dart';

/// A single product query supplies both the heading and the review section.
/// Ratings describe returned rental experiences including this gown.
class GownReviews extends StatefulWidget {
  const GownReviews({
    super.key,
    required this.dressId,
    required this.dressName,
    required this.builder,
    this.api,
    this.enabled = true,
  });
  final String dressId, dressName;
  final ReviewApi? api;
  final bool enabled;
  final Widget Function(Widget summary, Widget section) builder;
  @override
  State<GownReviews> createState() => _GownReviewsState();
}

class _GownReviewsState extends State<GownReviews> {
  late final api = widget.api ?? ReviewApi();
  Map<String, dynamic>? feed;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    if (widget.enabled) load();
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await api.call(
        '/v1/reviews?${Uri(queryParameters: {'scope': 'all', 'dressId': widget.dressId}).query}',
      );
      if (mounted) setState(() => feed = result);
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open({bool write = false}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => write
            ? ReviewEditor(api: api, dressId: widget.dressId)
            : ReviewsScreen(
                api: api,
                dressId: widget.dressId,
                dressName: widget.dressName,
              ),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = feed?['summary'] as Map?;
    final count = summary?['count'] as int? ?? 0;
    final average = (summary?['average'] as num? ?? 0).toDouble();
    final rows = (feed?['reviews'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    final caption = !widget.enabled
        ? 'Sign in to read customer reviews'
        : loading && feed == null
        ? 'Loading customer reviews…'
        : error != null
        ? 'Customer reviews unavailable'
        : count == 0
        ? 'No reviews yet'
        : '${average.toStringAsFixed(1)} · $count ${count == 1 ? 'review' : 'reviews'}';
    final heading = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
        onPressed: widget.enabled && feed != null && error == null
            ? () => open()
            : null,
        icon: Icon(
          count > 0 && error == null
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          size: 19,
        ),
        label: Text(caption),
      ),
    );
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 40),
        Text('Customer reviews', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Ratings and experiences from customers who rented this gown.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        if (!widget.enabled)
          const Text('Sign in to read and share rental experiences.')
        else if (loading && feed == null)
          const LinearProgressIndicator()
        else if (error != null) ...[
          Text(error!),
          TextButton.icon(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry reviews'),
          ),
        ] else if (feed != null) ...[
          if (count == 0) ...[
            Text(
              'Be the first to share your experience',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'After you return a rental including this gown, you can leave a rating, photos and a video.',
            ),
          ] else ...[
            Wrap(
              spacing: 18,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  average.toStringAsFixed(1),
                  style: theme.textTheme.headlineLarge,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReviewStars(value: average),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'published review' : 'published reviews'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final star in [5, 4, 3, 2, 1])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('$star'),
                    const SizedBox(width: 5),
                    const Icon(Icons.star_rounded, size: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        label:
                            '$star stars: ${summary?['distribution']?['$star'] ?? 0} reviews',
                        child: LinearProgressIndicator(
                          value:
                              ((summary?['distribution']?['$star'] as num? ??
                                          0) /
                                      count)
                                  .clamp(0.0, 1.0),
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${summary?['distribution']?['$star'] ?? 0}',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            for (final row in rows.take(2)) ...[
              const Divider(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row['author'] as String,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text('Verified rental', style: theme.textTheme.bodySmall),
                  Text(
                    reviewDay(row['createdAt']),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ReviewStars(value: (row['stars'] as num).toDouble()),
              if ((row['text'] as String).isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  row['text'] as String,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if ((row['media'] as List? ?? []).isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final media in row['media'] as List)
                      TextButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReviewMediaViewer(
                              api: api,
                              reviewId: row['id'] as String,
                              media: Map<String, dynamic>.from(media),
                            ),
                          ),
                        ),
                        icon: Icon(
                          media['mime'] == 'video/mp4'
                              ? Icons.play_circle_outline
                              : Icons.image_outlined,
                        ),
                        label: Text(
                          media['mime'] == 'video/mp4'
                              ? 'Watch video'
                              : 'View photo',
                        ),
                      ),
                  ],
                ),
              if (row['reply'] != null) ...[
                const SizedBox(height: 12),
                Text('Luvly replied', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(row['reply']['text'] as String),
              ],
            ],
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (count > 0)
                OutlinedButton(
                  onPressed: () => open(),
                  child: const Text('Read all reviews'),
                ),
              TextButton.icon(
                onPressed: () => open(write: true),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Write a review'),
              ),
            ],
          ),
        ],
      ],
    );
    return widget.builder(heading, section);
  }
}

class _ReviewStars extends StatelessWidget {
  const _ReviewStars({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${value.toStringAsFixed(1)} out of 5 stars',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            value >= i + 1
                ? Icons.star_rounded
                : value > i
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 19,
          ),
      ],
    ),
  );
}
