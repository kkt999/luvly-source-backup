import 'dart:async';
import 'package:flutter/material.dart';
import '../payments/payment_api.dart' show PaymentFailure;
import '../src/design.dart' show CustomerUi;
import 'assistant_history_api.dart';
import 'assistant_strings.dart';

typedef AssistantHistoryChoice = ({bool newChat, String? id});

class AssistantHistoryScreen extends StatefulWidget {
  const AssistantHistoryScreen({
    super.key,
    required this.session,
    required this.strings,
  });

  final AssistantSession session;
  final AssistantStrings strings;

  @override
  State<AssistantHistoryScreen> createState() => _AssistantHistoryScreenState();
}

class _AssistantHistoryScreenState extends State<AssistantHistoryScreen> {
  final search = TextEditingController();
  final rows = <AssistantConversation>[];
  Timer? debounce;
  String? cursor;
  bool archived = false, loading = true, failed = false, mutating = false;
  int revision = 0;

  AssistantHistoryApi get api => widget.session.history;
  AssistantStrings get strings => widget.strings;

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    final current = ++revision;
    setState(() {
      loading = true;
      failed = false;
      if (reset) {
        rows.clear();
        cursor = null;
      }
    });
    try {
      final page = await api.list(
        archived: archived,
        query: search.text.trim(),
        cursor: cursor,
      );
      if (!mounted || current != revision) return;
      setState(() {
        final seen = rows.map((row) => row.id).toSet();
        rows.addAll(page.records.where((row) => seen.add(row.id)));
        cursor = page.nextCursor;
      });
    } catch (_) {
      if (mounted && current == revision) setState(() => failed = true);
    } finally {
      if (mounted && current == revision) setState(() => loading = false);
    }
  }

  void onSearch(String value) {
    debounce?.cancel();
    revision++;
    setState(() {
      rows.clear();
      cursor = null;
      loading = true;
      failed = false;
    });
    debounce = Timer(
      const Duration(milliseconds: 300),
      () => load(reset: true),
    );
  }

  Future<String?> promptTitle(AssistantConversation row) => showDialog<String>(
    context: context,
    barrierLabel: strings[AssistantText.dismiss],
    builder: (_) =>
        _RenameConversationDialog(title: row.title, strings: strings),
  );

  Future<bool> confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        barrierLabel: strings[AssistantText.dismiss],
        builder: (dialog) => AlertDialog(
          title: Text(strings[AssistantText.deleteTitle]),
          content: Text(strings[AssistantText.deleteBody]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(strings[AssistantText.cancel]),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialog).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(strings[AssistantText.deleteForever]),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> change(AssistantConversation row, String action) async {
    final title = action == 'rename' ? await promptTitle(row) : null;
    if (action == 'rename' && title == null) return;
    if (action == 'delete' && !row.deleting && !await confirmDelete()) return;
    if (!mounted || mutating) return;
    setState(() => mutating = true);
    var feedback = strings[AssistantText.updated];
    try {
      switch (action) {
        case 'rename':
          await api.rename(row.id, title!);
          feedback = strings[AssistantText.renamed];
        case 'archive':
          await api.setArchived(row.id, !row.archived);
          feedback = row.archived
              ? strings[AssistantText.restored]
              : strings[AssistantText.archived];
        case 'delete':
          await api.delete(row.id);
          widget.session.forget(row.id);
          feedback = strings[AssistantText.deleted];
      }
      if (mounted) await load(reset: true);
    } catch (error) {
      feedback =
          error is PaymentFailure && error.code == 'INVALID_ASSISTANT_TITLE'
          ? strings[AssistantText.unsafeTitle]
          : strings[AssistantText.updateFailed];
      if (mounted && action == 'delete') {
        debounce?.cancel();
        search.clear();
        await load(reset: true);
      }
    } finally {
      widget.session.historyRevision++;
      if (mounted) {
        setState(() => mutating = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(feedback)));
      }
    }
  }

  String rowTitle(AssistantConversation row) =>
      row.deleting ? strings[AssistantText.deletionPending] : row.title;

  String label(BuildContext context, DateTime date) {
    if (strings.language == 'en') {
      final localizations = MaterialLocalizations.of(context);
      return '${localizations.formatShortDate(date)} · '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
    }
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final day = strings.language == 'zh'
        ? '${date.year}年${date.month}月${date.day}日'
        : '${date.day}/${date.month}/${date.year}';
    return '$day · $time';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CustomerUi.canvas,
    appBar: AppBar(
      title: Text(strings[AssistantText.yourChats]),
      leading: IconButton(
        tooltip: strings[AssistantText.back],
        onPressed: () => Navigator.maybePop(context),
        icon: const BackButtonIcon(),
      ),
      actions: [
        IconButton(
          tooltip: strings[AssistantText.newChat],
          icon: const Icon(Icons.edit_square),
          onPressed: mutating
              ? null
              : () => Navigator.pop(context, (newChat: true, id: null)),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: TextField(
                  controller: search,
                  onChanged: onSearch,
                  maxLength: 32,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    debounce?.cancel();
                    load(reset: true);
                  },
                  decoration: InputDecoration(
                    labelText: strings[AssistantText.search],
                    counterText: '',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings[AssistantText.clearSearch],
                            onPressed: () {
                              search.clear();
                              debounce?.cancel();
                              load(reset: true);
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(strings[AssistantText.recent]),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(strings[AssistantText.archiveTab]),
                    ),
                  ],
                  selected: {archived},
                  onSelectionChanged: mutating
                      ? null
                      : (value) {
                          if (archived == value.single) return;
                          archived = value.single;
                          debounce?.cancel();
                          load(reset: true);
                        },
                ),
              ),
              if (loading || mutating)
                LinearProgressIndicator(
                  minHeight: 2,
                  semanticsLabel:
                      strings[mutating
                          ? AssistantText.savingChanges
                          : AssistantText.loadingHistory],
                ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: loading
                              ? const SizedBox.shrink()
                              : failed
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(strings[AssistantText.historyFailed]),
                                    TextButton(
                                      onPressed: () => load(reset: true),
                                      child: Text(strings[AssistantText.retry]),
                                    ),
                                  ],
                                )
                              : Text(
                                  search.text.trim().isNotEmpty
                                      ? strings[AssistantText.noMatches]
                                      : archived
                                      ? strings[AssistantText.noArchived]
                                      : strings[AssistantText.noHistory],
                                  textAlign: TextAlign.center,
                                ),
                        ),
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount:
                            rows.length + (cursor != null || failed ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == rows.length) {
                            return TextButton(
                              onPressed: loading || mutating
                                  ? null
                                  : () => load(),
                              child: Text(
                                failed
                                    ? strings[AssistantText.retryLoad]
                                    : strings[AssistantText.loadMore],
                              ),
                            );
                          }
                          final row = rows[index];
                          return ListTile(
                            enabled: !mutating,
                            onTap: mutating || row.deleting
                                ? null
                                : () => Navigator.pop(context, (
                                    newChat: false,
                                    id: row.id,
                                  )),
                            title: Text(
                              rowTitle(row),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              row.preview == null || row.preview == row.title
                                  ? label(context, row.updatedAt)
                                  : '${row.preview}\n${label(context, row.updatedAt)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            leading: Icon(
                              row.archived
                                  ? Icons.archive_outlined
                                  : Icons.chat_bubble_outline,
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: strings.format(
                                AssistantText.rowOptions,
                                rowTitle(row),
                              ),
                              enabled: !mutating,
                              popUpAnimationStyle: CustomerUi.popupMotion(
                                context,
                              ),
                              onSelected: (action) => change(row, action),
                              itemBuilder: (_) => [
                                if (!row.deleting) ...[
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text(strings[AssistantText.rename]),
                                  ),
                                  PopupMenuItem(
                                    value: 'archive',
                                    child: Text(
                                      row.archived
                                          ? strings[AssistantText.restore]
                                          : strings[AssistantText.archive],
                                    ),
                                  ),
                                ],
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    row.deleting
                                        ? strings[AssistantText.retryDelete]
                                        : strings[AssistantText.delete],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({required this.title, required this.strings});
  final String title;
  final AssistantStrings strings;

  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final input = TextEditingController(text: widget.title);
  AssistantStrings get strings => widget.strings;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(strings[AssistantText.renameTitle]),
    content: TextField(
      controller: input,
      autofocus: true,
      maxLength: 64,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: strings[AssistantText.titleField]),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(strings[AssistantText.cancel]),
      ),
      FilledButton(
        onPressed: input.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, input.text),
        child: Text(strings[AssistantText.saveTitle]),
      ),
    ],
  );
}
