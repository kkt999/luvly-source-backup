import 'package:flutter/material.dart';
import '../src/design.dart' show rose, muted, line;
import 'review_api.dart';
import 'review_screen.dart' show ReviewMediaViewer, reviewDay;

const reviewReportReasons = {
  'Profanity': 'Profanity / bad language',
  'Harassment': 'Harassment or abuse',
  'Hate': 'Hate or discriminatory language',
  'Threats': 'Threats',
  'Sexual': 'Sexually explicit content',
  'Privacy': 'Private information or media',
  'Spam': 'Spam or advertising',
  'Other': 'Other policy concern',
};

Future<Map<String, dynamic>?> reviewReportDialog(
  BuildContext c, {
  Map<String, dynamic>? initial,
}) => showDialog<Map<String, dynamic>>(
  context: c,
  builder: (_) => _ReportDialog(initial: initial),
);

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final form = GlobalKey<FormState>();
  late final details = TextEditingController(
    text: widget.initial?['details'] ?? '',
  );
  late String category = widget.initial?['category'] ?? 'Harassment';
  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: const Text('Report this review'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tell the Luvly team about a content-policy concern. Disagreeing with a rating is not a reason to remove a review. Reporting does not automatically hide it. Your identity is not shown to the reviewer.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [
                for (final entry in reviewReportReasons.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: details,
              maxLength: 500,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText:
                    'Which words, photo or video should we check? Do not include private account information.',
              ),
              validator: (s) =>
                  category == 'Other' && (s?.trim().length ?? 0) < 5
                  ? 'Please explain the policy concern.'
                  : null,
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
          if (form.currentState!.validate()) {
            Navigator.pop(c, {
              'category': category,
              'details': details.text.trim(),
            });
          }
        },
        child: const Text('Send report'),
      ),
    ],
  );
}

Future<String?> reviewDecisionNote(
  BuildContext c, {
  required String title,
  required String explanation,
}) => showDialog<String>(
  context: c,
  builder: (_) => _DecisionNote(title: title, explanation: explanation),
);

class _DecisionNote extends StatefulWidget {
  const _DecisionNote({required this.title, required this.explanation});
  final String title, explanation;
  @override
  State<_DecisionNote> createState() => _DecisionNoteState();
}

class _DecisionNoteState extends State<_DecisionNote> {
  final form = GlobalKey<FormState>(), note = TextEditingController();
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.explanation),
            const SizedBox(height: 16),
            TextFormField(
              controller: note,
              maxLength: 300,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Decision note'),
              validator: (s) => (s?.trim().length ?? 0) < 5
                  ? 'Please record a clear reason.'
                  : null,
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
          if (form.currentState!.validate()) Navigator.pop(c, note.text.trim());
        },
        child: const Text('Confirm decision'),
      ),
    ],
  );
}

class ReviewReportsScreen extends StatefulWidget {
  const ReviewReportsScreen({super.key, required this.api});
  final ReviewApi api;
  @override
  State<ReviewReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends State<ReviewReportsScreen> {
  List<Map<String, dynamic>>? rows;
  String status = 'Open';
  String? error;
  bool busy = false;
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
      final r = await widget.api.call('/v1/review-reports?status=$status');
      if (mounted) {
        setState(
          () => rows = (r['reports'] as List)
              .map((v) => Map<String, dynamic>.from(v))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resolve(Map<String, dynamic> row, bool hide) async {
    if (busy) return;
    final note = await reviewDecisionNote(
      context,
      title: hide ? 'Hide review and resolve report?' : 'Dismiss this report?',
      explanation: hide
          ? 'Review both the reported version and the current review. Hide only for a genuine policy violation, not a low rating. This reason is visible to the review owner. The rating and text are never edited.'
          : 'Keep the review as it is. Record why this report does not justify removal. The report and decision remain in the audit history.',
    );
    if (note == null || !mounted) return;
    final payload = {
      'revision': row['revision'],
      'reviewRevision': row['current']?['revision'] ?? 0,
      'resolution': hide ? 'HideReview' : 'NoViolation',
      'note': note,
    };
    final signature = payload.toString();
    if (row['pending-body'] != signature) {
      row['pending-body'] = signature;
      row['pending-id'] = widget.api.requestId();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.call(
        '/v1/review-reports/${row['id']}/resolve',
        body: {...payload, 'requestId': row['pending-id']},
      );
      if (r['resolved'] != true) throw const FormatException();
    } catch (e) {
      if (mounted) setState(() => error = reviewError(e));
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) await load();
  }

  Widget evidence(BuildContext c, Map<String, dynamic> row) {
    final snapshot = Map<String, dynamic>.from(row['snapshot']),
        current = row['current'] as Map?,
        changed =
            current != null &&
            current['contentVersion'] != snapshot['contentVersion'];
    return Card(
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
              children: [
                Text(
                  reviewReportReasons[row['category']] ?? row['category'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${row['status']} · ${reviewDay(row['createdAt'])}',
                  style: const TextStyle(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              row['details'].isEmpty
                  ? 'No additional details.'
                  : row['details'],
            ),
            const Divider(height: 28),
            const Text(
              'Reported version',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${snapshot['author']} · ${snapshot['title']} · ${snapshot['stars']} / 5 stars',
            ),
            const SizedBox(height: 6),
            Text(snapshot['text'].isEmpty ? 'Rating only' : snapshot['text']),
            if (snapshot['reply'] != null)
              Text('Luvly reply at the time: ${snapshot['reply']['text']}'),
            if ((snapshot['media'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in snapshot['media'] as List)
                    OutlinedButton.icon(
                      onPressed: row['status'] != 'Open'
                          ? null
                          : () => Navigator.push(
                              c,
                              MaterialPageRoute<void>(
                                builder: (_) => ReviewMediaViewer(
                                  api: widget.api,
                                  reviewId: row['reviewId'],
                                  reportId: row['id'],
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
                            ? 'Reported video'
                            : 'Reported photo',
                      ),
                    ),
                ],
              ),
              if (row['status'] != 'Open')
                const Text(
                  'Historical attachment access ends when the case is closed.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
            ],
            if (changed) ...[
              const Divider(height: 28),
              const Text(
                'The author changed this review after it was reported.',
                style: TextStyle(color: rose, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text('Current review · ${current['stars']} / 5 stars'),
              Text(current['text']),
              const Text(
                'A removal decision applies to the current version shown above.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
            if (row['resolution'] != null) ...[
              const Divider(height: 28),
              Text(
                'Decision: ${row['resolution']['kind'] == 'HideReview' ? 'Review hidden' : 'Report dismissed'}',
              ),
              Text(row['resolution']['note']),
            ],
            if (row['status'] == 'Open') ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => resolve(row, false),
                    child: const Text('Dismiss report'),
                  ),
                  FilledButton(
                    onPressed: busy || current == null
                        ? null
                        : () => resolve(row, true),
                    child: const Text('Hide review & resolve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Reported reviews'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          tooltip: 'Refresh reports',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Review concerns fairly',
              style: Theme.of(c).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the evidence and record a decision. A report alone is not proof of a violation; honest criticism and low ratings are allowed.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final s in ['Open', 'Closed'])
                  ChoiceChip(
                    label: Text(
                      s == 'Open' ? 'Open reports' : 'Resolved history',
                    ),
                    selected: s == status,
                    onSelected: busy
                        ? null
                        : (_) {
                            setState(() {
                              status = s;
                              rows = null;
                            });
                            load();
                          },
                  ),
              ],
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
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
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                    TextButton(
                      onPressed: busy ? null : load,
                      child: const Text('Retry reports'),
                    ),
                  ],
                ),
              ),
            if (rows != null && rows!.isEmpty && !busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text('No reports in this view.'),
              ),
            for (final row in rows ?? <Map<String, dynamic>>[])
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: evidence(c, row),
              ),
          ],
        ),
      ),
    ),
  );
}
