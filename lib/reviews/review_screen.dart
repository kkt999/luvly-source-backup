import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:video_player/video_player.dart';
import '../src/design.dart' show rose, muted, line, blush;
import '../catalogue/dress_photo_data.dart';
import 'review_api.dart';
import 'review_reports.dart';

String reviewDay(dynamic value) {
  final d = DateTime.fromMillisecondsSinceEpoch(
    value as int,
  ).toUtc().add(const Duration(hours: 8));
  return '${d.day}/${d.month}/${d.year}';
}

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({
    super.key,
    this.api,
    this.mine = false,
    this.manage = false,
    this.preview = false,
    this.dressId,
    this.dressName,
  });
  final ReviewApi? api;
  final bool mine, manage, preview;
  final String? dressId, dressName;
  @override
  State<ReviewsScreen> createState() => _ReviewsState();
}

class _ReviewsState extends State<ReviewsScreen> {
  late final api = widget.api ?? ReviewApi();
  late String scope = widget.manage
      ? 'manage'
      : widget.mine
      ? 'mine'
      : 'all';
  Map<String, dynamic>? feed;
  String? error;
  bool loading = false;
  String managerFilter = 'All';
  @override
  void initState() {
    super.initState();
    if (!widget.preview) load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final query = Uri(
        queryParameters: {
          'scope': scope,
          if (widget.dressId != null) 'dressId': widget.dressId!,
        },
      ).query;
      final r = await api.call('/v1/reviews?$query');
      if (mounted) setState(() => feed = r);
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([String? rentalId]) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReviewEditor(api: api, rentalId: rentalId, dressId: widget.dressId),
      ),
    );
    if (mounted) await load();
  }

  Future<void> action(Map<String, dynamic> row, String kind) async {
    if (loading) return;
    if (kind == 'report') {
      final result = await reviewReportDialog(
        context,
        initial: row['draft-report'] as Map<String, dynamic>?,
      );
      if (result != null) row['draft-report'] = result;
      if (result != null && mounted) await mutate(row, kind, result);
      return;
    }
    if (kind == 'approve') {
      final reason = await reviewDecisionNote(
        context,
        title: 'Approve the safety check?',
        explanation:
            'Read the complete review and check its photos/video. Approve only if it meets the content policy; low ratings are allowed. A separate policy hide or withdrawal will remain in effect.',
      );
      if (reason != null && mounted) {
        await mutate(row, kind, {'reason': reason});
      }
      return;
    }
    if (kind == 'withdraw') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Withdraw this review?'),
          content: const Text(
            'It will no longer appear to other customers. You can edit and publish it again from My reviews. This does not cancel your rental or refund a payment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep review'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Withdraw'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      await mutate(row, kind, {});
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ManagerReviewDialog(row: row, reply: kind == 'reply'),
    );
    if (result != null && mounted) {
      if (kind == 'reply') row['draft-reply'] = result['text'];
      await mutate(row, kind, result);
    }
  }

  Future<void> mutate(
    Map<String, dynamic> row,
    String action,
    Map<String, dynamic> body,
  ) async {
    setState(() {
      loading = true;
      error = null;
    });
    // A failed moderation/reply never replaces the existing saved review.
    final fingerprint = jsonEncode(body);
    if (row['pending-$action-body'] != fingerprint) {
      row['pending-$action-body'] = fingerprint;
      row['pending-$action'] = api.requestId();
    }
    final request = row['pending-$action'];
    try {
      final result = await api.call(
        '/v1/reviews/${row['id']}/$action',
        body: {'revision': row['revision'], 'requestId': request, ...body},
      );
      if (action == 'report' && result['reported'] != true) {
        throw const FormatException();
      }
      if (action == 'report' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report sent. The Luvly team will review it; reporting does not automatically remove the review.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted) await load();
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final rows = (feed?['reviews'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .where(
              (r) =>
                  !widget.manage ||
                  managerFilter == 'All' ||
                  managerFilter == 'Pending' &&
                      r['safety']?['state'] == 'Pending' ||
                  managerFilter == 'Reported' &&
                      (r['openReports'] as int? ?? 0) > 0,
            )
            .toList(),
        summary = feed?['summary'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.dressId != null
              ? 'Gown reviews'
              : widget.manage
              ? 'Customer reviews'
              : 'Reviews',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh reviews',
            onPressed: loading || widget.preview ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.dressName ??
                    (widget.manage
                        ? 'Listen to your customers'
                        : 'Real experiences, beautiful moments'),
                style: Theme.of(c).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                widget.dressId == null
                    ? 'Reviews are linked to completed, returned rentals. Photos and videos are optional.'
                    : 'Experiences from completed rentals including this gown. A review may cover the whole package, including other items and service.',
              ),
              if (widget.preview)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Sign in to read and share customer reviews.',
                  ),
                ),
              if (!widget.preview) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (widget.manage) ...[
                      for (final filter in ['All', 'Pending', 'Reported'])
                        ChoiceChip(
                          label: Text(
                            filter == 'All'
                                ? 'All reviews'
                                : filter == 'Pending'
                                ? 'Pending approval (${feed?['pendingCount'] ?? 0})'
                                : 'Reported (${feed?['openReports'] ?? 0})',
                          ),
                          selected: managerFilter == filter,
                          onSelected: loading
                              ? null
                              : (_) => setState(() => managerFilter = filter),
                        ),
                      OutlinedButton.icon(
                        onPressed: loading
                            ? null
                            : () async {
                                await Navigator.push<void>(
                                  c,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ReviewReportsScreen(api: api),
                                  ),
                                );
                                if (mounted) await load();
                              },
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Report queue'),
                      ),
                    ],
                    if (!widget.manage)
                      for (final s in ['all', 'mine'])
                        ChoiceChip(
                          label: Text(
                            s == 'all' ? 'Customer reviews' : 'My reviews',
                          ),
                          selected: scope == s,
                          onSelected: loading
                              ? null
                              : (_) {
                                  setState(() {
                                    scope = s;
                                    feed = null;
                                  });
                                  load();
                                },
                        ),
                    if (!widget.manage)
                      FilledButton.icon(
                        onPressed: loading ? null : () => edit(),
                        icon: const Icon(Icons.rate_review_outlined),
                        label: const Text('Write a review'),
                      ),
                  ],
                ),
                if (widget.manage && feed != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      feed?['textModeration']?['configured'] == true
                          ? 'Google AI checks text only. Uncertain or unavailable checks wait for manual approval. Photos and videos are not automatically safety-checked.'
                          : 'Automated text checking is unavailable. New reviews wait for manual approval; check the pending queue.',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if (summary != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    summary['count'] == 0
                        ? 'No published ratings yet'
                        : '${(summary['average'] as num).toStringAsFixed(1)} / 5 · ${summary['count']} published reviews',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  const Text(
                    'Overall rating includes published reviews only.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(c).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: loading ? null : load,
                          child: const Text('Retry reviews'),
                        ),
                      ],
                    ),
                  ),
                if (feed != null && rows.isEmpty && !loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      scope == 'mine'
                          ? 'You haven’t reviewed a rental yet. Completed rentals will be available under Write a review.'
                          : 'No reviews to show yet.',
                    ),
                  ),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: line),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  r['author'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Completed rental · ${reviewDay(r['createdAt'])}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              label: '${r['stars']} out of 5 stars',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 1; i <= 5; i++)
                                    Icon(
                                      i <= r['stars']
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: rose,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              r['title'],
                              style: Theme.of(c).textTheme.titleSmall,
                            ),
                            if ((r['text'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(r['text']),
                            ],
                            if (r['hidden'] == true ||
                                r['withdrawn'] == true) ...[
                              const SizedBox(height: 10),
                              Text(
                                r['hidden'] == true
                                    ? 'Hidden — ${r['moderationReason']}'
                                    : 'Withdrawn from customer view',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                            if (r['safety']?['state'] == 'Pending') ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Pending safety approval · not visible to other customers',
                                style: TextStyle(
                                  color: rose,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (widget.manage &&
                                (r['openReports'] as int? ?? 0) > 0)
                              Text(
                                '${r['openReports']} open report(s) · see Report queue',
                                style: const TextStyle(color: rose),
                              ),
                            if ((r['media'] as List).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final m in r['media'] as List)
                                    OutlinedButton.icon(
                                      onPressed: () => Navigator.push(
                                        c,
                                        MaterialPageRoute(
                                          builder: (_) => ReviewMediaViewer(
                                            api: api,
                                            reviewId: r['id'],
                                            media: Map<String, dynamic>.from(m),
                                          ),
                                        ),
                                      ),
                                      icon: Icon(
                                        m['mime'] == 'video/mp4'
                                            ? Icons.play_circle_outline
                                            : Icons.photo_outlined,
                                      ),
                                      label: Text(
                                        m['mime'] == 'video/mp4'
                                            ? 'Watch video'
                                            : 'View photo',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (r['reply'] != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: blush,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Luvly replied',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(r['reply']['text']),
                                  ],
                                ),
                              ),
                            ],
                            if (r['reported'] == true)
                              const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: Text(
                                  'You reported this version',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ),
                            if (r['owner'] == true ||
                                r['canManage'] == true ||
                                r['canReport'] == true)
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (r['canReport'] == true)
                                    TextButton.icon(
                                      onPressed: loading
                                          ? null
                                          : () => action(r, 'report'),
                                      icon: const Icon(
                                        Icons.flag_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Report review'),
                                    ),
                                  if (r['owner'] == true)
                                    TextButton(
                                      onPressed: loading
                                          ? null
                                          : () => edit(r['rentalId']),
                                      child: const Text('Edit review'),
                                    ),
                                  if (r['owner'] == true &&
                                      r['withdrawn'] != true)
                                    TextButton(
                                      onPressed: loading
                                          ? null
                                          : () => action(r, 'withdraw'),
                                      child: const Text('Withdraw'),
                                    ),
                                  if (widget.manage &&
                                      r['canManage'] == true) ...[
                                    if (r['safety']?['state'] == 'Pending')
                                      TextButton(
                                        onPressed: loading
                                            ? null
                                            : () => action(r, 'approve'),
                                        child: const Text(
                                          'Approve safety check',
                                        ),
                                      ),
                                    TextButton(
                                      onPressed: loading
                                          ? null
                                          : () => action(r, 'reply'),
                                      child: const Text('Reply'),
                                    ),
                                    TextButton(
                                      onPressed: loading
                                          ? null
                                          : () => action(r, 'moderate'),
                                      child: Text(
                                        r['hidden'] == true
                                            ? 'Restore review'
                                            : 'Moderate',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagerReviewDialog extends StatefulWidget {
  const _ManagerReviewDialog({required this.row, required this.reply});
  final Map<String, dynamic> row;
  final bool reply;
  @override
  State<_ManagerReviewDialog> createState() => _ManagerDialogState();
}

class _ManagerDialogState extends State<_ManagerReviewDialog> {
  final form = GlobalKey<FormState>();
  late final controller = TextEditingController(
    text: widget.reply
        ? (widget.row['draft-reply'] ?? widget.row['reply']?['text'] ?? '')
        : '',
  );
  String category = 'Privacy';
  bool consent = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(
      widget.reply
          ? 'Reply as Luvly'
          : widget.row['hidden'] == true
          ? 'Restore this review'
          : 'Moderate content',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.reply) ...[
              const Text(
                'Use moderation only for a content-policy issue, not because a customer gave a low rating. The customer’s stars and words cannot be changed.',
              ),
              const SizedBox(height: 14),
              if (widget.row['hidden'] != true)
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Content-policy category',
                  ),
                  items: [
                    for (final s in ['Privacy', 'Spam', 'Unrelated', 'Abusive'])
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => category = v!),
                ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: controller,
              maxLength: widget.reply ? 1000 : 300,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: widget.reply
                    ? 'Your reply'
                    : 'Reason visible to the customer',
              ),
              validator: (s) =>
                  s == null || s.trim().length < (widget.reply ? 1 : 5)
                  ? 'Please enter ${widget.reply ? 'a reply' : 'a clear reason'}.'
                  : null,
            ),
            if (widget.reply)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: (v) => setState(() => consent = v!),
                title: const Text(
                  'I agree to send this reply text to Google Gemini for a safety check before publication.',
                ),
                subtitle: const Text(
                  'Do not include private customer or account information. API failures leave the reply unpublished.',
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate() || widget.reply && !consent) {
            return;
          }
          Navigator.pop(
            c,
            widget.reply
                ? {
                    'text': controller.text.trim(),
                    'consent': true,
                    'policyVersion': 2,
                  }
                : {
                    'hidden': widget.row['hidden'] != true,
                    'category': widget.row['hidden'] == true
                        ? 'Restored'
                        : category,
                    'reason': controller.text.trim(),
                  },
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _DraftMedia {
  _DraftMedia(this.id, this.mime, {this.bytes, this.saved, this.name = ''});
  final String id, mime, name;
  Uint8List? bytes;
  Map<String, dynamic>? saved;
}

class ReviewEditor extends StatefulWidget {
  const ReviewEditor({
    super.key,
    required this.api,
    this.rentalId,
    this.dressId,
    this.pickPhotos,
    this.pickVideo,
  });
  final ReviewApi api;
  final String? rentalId, dressId;
  final Future<List<XFile>> Function()? pickPhotos;
  final Future<XFile?> Function()? pickVideo;
  @override
  State<ReviewEditor> createState() => _EditorState();
}

class _EditorState extends State<ReviewEditor> {
  final text = TextEditingController();
  List<Map<String, dynamic>> options = [];
  final media = <_DraftMedia>[];
  String? rentalId, error, requestId;
  int stars = 0, revision = 0;
  bool loading = true,
      busy = false,
      consent = false,
      dirty = false,
      closing = false;
  String progress = '';
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
      final suffix = widget.dressId == null
          ? ''
          : '?${Uri(queryParameters: {'dressId': widget.dressId!}).query}';
      final r = await widget.api.call('/v1/reviews/eligible$suffix');
      if (!mounted) return;
      options = (r['rentals'] as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      if (widget.rentalId != null &&
          !options.any((r) => r['rentalId'] == widget.rentalId)) {
        options = [];
        throw const FormatException();
      }
      if (widget.rentalId != null) {
        select(widget.rentalId!);
      } else if (options.length == 1) {
        select(options.single['rentalId']);
      }
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void select(String id) {
    final row = options.singleWhere((v) => v['rentalId'] == id),
        review = row['review'] as Map?;
    setState(() {
      rentalId = id;
      stars = review?['stars'] ?? 0;
      revision = review?['revision'] ?? 0;
      text.text = review?['text'] ?? '';
      media.clear();
      for (final m in review?['media'] as List? ?? []) {
        media.add(
          _DraftMedia(m['id'], m['mime'], saved: Map<String, dynamic>.from(m)),
        );
      }
      consent = false;
      dirty = false;
      requestId = null;
    });
  }

  void changed() {
    setState(() {
      dirty = true;
      requestId = null;
    });
  }

  Future<void> pick(bool video) async {
    if (busy || rentalId == null) return;
    final count = media
        .where((m) => m.mime == (video ? 'video/mp4' : 'image/jpeg'))
        .length;
    if (count >= (video ? 1 : 5)) {
      setState(
        () => error = video
            ? 'Attach one video per review.'
            : 'Attach up to five photos.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      progress = 'Preparing media…';
    });
    try {
      if (video) {
        final f =
            await (widget.pickVideo?.call() ??
                openFile(
                  acceptedTypeGroups: const [
                    XTypeGroup(
                      label: 'MP4 video',
                      extensions: ['mp4'],
                      mimeTypes: ['video/mp4'],
                    ),
                  ],
                ));
        if (f == null) return;
        if (!f.name.toLowerCase().endsWith('.mp4') ||
            await f.length() > 20 * 1024 * 1024) {
          throw const FormatException(
            'Choose an MP4 video no larger than 20 MB.',
          );
        }
        final bytes = await f.readAsBytes();
        if (!mounted) return;
        media.add(
          _DraftMedia(
            widget.api.requestId(),
            'video/mp4',
            bytes: bytes,
            name: f.name,
          ),
        );
      } else {
        final files =
            await (widget.pickPhotos?.call() ??
                openFiles(
                  acceptedTypeGroups: const [
                    XTypeGroup(
                      label: 'Photos',
                      extensions: ['jpg', 'jpeg', 'png'],
                      mimeTypes: ['image/jpeg', 'image/png'],
                    ),
                  ],
                ));
        if (files.length + count > 5) {
          throw const FormatException('Select up to five photos in total.');
        }
        final prepared = <_DraftMedia>[];
        for (final f in files) {
          final p = await prepareDressPhoto(f);
          prepared.add(
            _DraftMedia(
              widget.api.requestId(),
              'image/jpeg',
              bytes: p.imageBytes,
              name: f.name,
            ),
          );
        }
        if (!mounted) return;
        media.addAll(prepared);
      }
      if (mounted) changed();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : reviewError(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || rentalId == null) return;
    if (stars < 1 || !consent) {
      setState(
        () =>
            error = 'Choose your stars and confirm sharing before submitting.',
      );
      return;
    }
    requestId ??= widget.api.requestId();
    setState(() {
      busy = true;
      error = null;
      progress = 'Checking attachments…';
    });
    try {
      for (var i = 0; i < media.length; i++) {
        final m = media[i];
        if (m.saved != null) continue;
        setState(
          () => progress = 'Uploading attachment ${i + 1} of ${media.length}…',
        );
        m.saved = await widget.api.upload(rentalId!, m.id, m.bytes!, m.mime);
      }
      if (!mounted) return;
      setState(() => progress = 'Checking review text and saving…');
      final r = await widget.api.call(
        '/v1/reviews/$rentalId',
        body: {
          'requestId': requestId,
          'revision': revision,
          'stars': stars,
          'text': text.text.trim(),
          'mediaIds': media.map((m) => m.id).toList(),
          'consent': true,
          'policyVersion': 2,
        },
      );
      if (r['review']?['owner'] != true ||
          r['review']?['rentalId'] != rentalId ||
          r['review']?['revision'] is! int ||
          (r['review']['revision'] as int) <= revision) {
        throw const FormatException();
      }
      if (!mounted) return;
      setState(() {
        dirty = false;
        closing = true;
        busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context, true);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                r['review']?['safety']?['state'] == 'Pending'
                    ? 'Review saved for staff approval. It is not public yet.'
                    : 'Your review was saved.',
              ),
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy && (!dirty || closing),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || busy || !dirty) return;
      final yes = await showDialog<bool>(
        context: c,
        builder: (d) => AlertDialog(
          title: const Text('Discard review changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (yes == true && mounted) {
        setState(() => closing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(c);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Share your experience')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'A little feedback, a lot of meaning',
                style: TextStyle(fontSize: 24, fontFamily: 'LuvlySerif'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Rate your overall rental experience. Photos and a short video are optional.',
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: LinearProgressIndicator(),
                ),
              if (error != null && options.isEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
                if (options.isEmpty)
                  TextButton(
                    onPressed: loading ? null : load,
                    child: const Text('Retry rentals'),
                  ),
              ],
              if (!loading && error == null && options.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No eligible rental yet. You can review after Luvly records collection, return and inspection. A booking or deposit alone does not qualify.',
                  ),
                ),
              if (options.isNotEmpty) ...[
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey(rentalId),
                  initialValue: rentalId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Completed rental',
                  ),
                  items: [
                    for (final r in options)
                      DropdownMenuItem(
                        value: r['rentalId'] as String,
                        child: Text(
                          '${r['title']} · ${r['eventDate']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: busy || dirty ? null : (v) => select(v!),
                ),
                if (dirty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Finish or discard these changes before choosing a different rental.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Your rating',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Wrap(
                  spacing: 0,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                        onPressed: busy || rentalId == null
                            ? null
                            : () {
                                stars = i;
                                changed();
                              },
                        icon: Icon(
                          i <= stars ? Icons.star : Icons.star_border,
                          color: rose,
                          size: 30,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: text,
                  enabled: !busy && rentalId != null,
                  onChanged: (_) => changed(),
                  maxLength: 1000,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Your review (optional)',
                    hintText: 'How was the gown, fit and service?',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Photos & video',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Up to 5 JPG/PNG photos (5 MB each) and 1 H.264 MP4 video (30 seconds, 20 MB, up to 1920 pixels per side). Video format and duration are checked by the server.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in media)
                      SizedBox(
                        width: 140,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                if (m.mime == 'image/jpeg' && m.bytes != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      m.bytes!,
                                      height: 90,
                                      width: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Icon(
                                    m.mime == 'video/mp4'
                                        ? Icons.movie_outlined
                                        : Icons.photo_outlined,
                                    size: 36,
                                    color: rose,
                                  ),
                                Text(
                                  m.mime == 'video/mp4' ? 'Video' : 'Photo',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (m.name.isNotEmpty)
                                  Text(
                                    m.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: muted,
                                    ),
                                  ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () {
                                          media.remove(m);
                                          changed();
                                        },
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          busy ||
                              rentalId == null ||
                              media
                                      .where((m) => m.mime == 'image/jpeg')
                                      .length >=
                                  5
                          ? null
                          : () => pick(false),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add photos'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          busy ||
                              rentalId == null ||
                              media.any((m) => m.mime == 'video/mp4')
                          ? null
                          : () => pick(true),
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Add video'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: consent,
                  onChanged: busy || rentalId == null
                      ? null
                      : (v) => setState(() => consent = v!),
                  title: const Text(
                    'I agree to share this review and media, and send the review text to Google Gemini for safety checking.',
                  ),
                  subtitle: const Text(
                    'Only review text is sent to Google AI, not your photos, video, stars or order details. Do not include private information. Share only media you have permission to use; original video metadata may remain. If checking is unavailable or uncertain, the review waits for staff approval. Honest negative reviews are allowed.',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  Text(progress),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy || rentalId == null ? null : save,
                  child: Text(
                    busy
                        ? 'Please wait…'
                        : revision == 0
                        ? 'Publish review'
                        : 'Save review',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your email, phone number and order IDs are not displayed to other customers. Only your first name is shown. A hidden review stays hidden when edited until the Luvly team restores it.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class ReviewMediaViewer extends StatefulWidget {
  const ReviewMediaViewer({
    super.key,
    required this.api,
    required this.reviewId,
    required this.media,
    this.reportId,
  });
  final ReviewApi api;
  final String reviewId;
  final String? reportId;
  final Map<String, dynamic> media;
  @override
  State<ReviewMediaViewer> createState() => _MediaState();
}

class _MediaState extends State<ReviewMediaViewer> {
  VideoPlayerController? video;
  String? url, error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
      url = null;
    });
    final old = video;
    video = null;
    old?.removeListener(playbackChanged);
    await old?.dispose();
    VideoPlayerController? next;
    try {
      final r = await widget.api.call(
        widget.reportId == null
            ? '/v1/reviews/${widget.reviewId}/media/${widget.media['id']}'
            : '/v1/review-reports/${widget.reportId}/media/${widget.media['id']}',
      );
      final uri = Uri.tryParse(r['url']);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'storage.googleapis.com' ||
          !uri.path.startsWith(
            '/luvly-44c77.firebasestorage.app/customer-reviews/',
          )) {
        throw const FormatException();
      }
      if (widget.media['mime'] == 'video/mp4') {
        next = VideoPlayerController.networkUrl(uri);
        await next.initialize();
      }
      if (!mounted) {
        await next?.dispose();
        return;
      }
      setState(() {
        video = next;
        url = uri.toString();
      });
      next?.addListener(playbackChanged);
    } catch (e) {
      await next?.dispose();
      if (mounted) {
        setState(
          () => error =
              'Could not load this media. Retry to get a fresh access link.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    video?.removeListener(playbackChanged);
    video?.dispose();
    super.dispose();
  }

  void playbackChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    Widget body = const SizedBox();
    if (loading) {
      body = const CircularProgressIndicator();
    } else if (error != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error!),
          TextButton(onPressed: load, child: const Text('Retry media')),
        ],
      );
    } else if (video != null) {
      body = LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AspectRatio(
                aspectRatio: video!.value.aspectRatio,
                child: VideoPlayer(video!),
              ),
            ),
            if (video!.value.hasError)
              TextButton(onPressed: load, child: const Text('Retry media')),
            VideoProgressIndicator(video!, allowScrubbing: true),
            IconButton(
              tooltip: video!.value.isPlaying ? 'Pause' : 'Play',
              onPressed: () async {
                if (video!.value.isPlaying) {
                  await video!.pause();
                } else {
                  await video!.play();
                }
                if (mounted) setState(() {});
              },
              icon: Icon(
                video!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
          ],
        ),
      );
    } else if (url != null) {
      body = InteractiveViewer(
        child: Image.network(
          url!,
          errorBuilder: (_, e, s) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Photo unavailable.'),
              TextButton(onPressed: load, child: const Text('Retry media')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.media['mime'] == 'video/mp4' ? 'Review video' : 'Review photo',
        ),
      ),
      body: Center(
        child: Padding(padding: const EdgeInsets.all(20), child: body),
      ),
    );
  }
}
