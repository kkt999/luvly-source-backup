import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';

import '../shared/list_controls.dart' show ListSearchField, matchesListSearch;
import '../src/design.dart' show CustomerUi, blush, ink, ivory, line, rose;
import 'support_repository.dart';

class CustomerSupportHub extends StatefulWidget {
  const CustomerSupportHub({
    super.key,
    required this.feed,
    required this.onRetry,
    required this.onAssistant,
    required this.onMessage,
    required this.onOpen,
    this.loadPreview,
    this.active = true,
  });

  final Stream<List<SupportCase>>? feed;
  final VoidCallback onRetry, onAssistant, onMessage;
  final ValueChanged<SupportCase> onOpen;
  final Future<String?> Function(SupportCase ticket)? loadPreview;
  final bool active;

  @override
  State<CustomerSupportHub> createState() => _CustomerSupportHubState();
}

class _CustomerSupportHubState extends State<CustomerSupportHub> {
  static const allTopics = 'All categories';
  String query = '', status = 'Active', topic = allTopics;
  final previews = <(String, String), Future<String?>>{};

  @override
  void didUpdateWidget(CustomerSupportHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed != widget.feed ||
        oldWidget.loadPreview != widget.loadPreview) {
      previews.clear();
    }
  }

  Future<String?>? previewFor(SupportCase ticket) {
    final messageId = ticket.lastMessageId;
    final loadPreview = widget.loadPreview;
    if (messageId == null || loadPreview == null) return null;
    final key = (ticket.id, messageId);
    final existing = previews[key];
    if (existing != null) return existing;
    if (!widget.active) return null;
    // Keep repeated searches and scrolling from re-reading recent previews.
    if (previews.length >= 100) previews.remove(previews.keys.first);
    return previews[key] = loadPreview(ticket);
  }

  void resetFilters() => setState(() {
    query = '';
    status = 'Active';
    topic = allTopics;
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: SafeArea(
        top: false,
        bottom: false,
        child: CustomScrollView(
          key: const Key('customer-support-list'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(child: introduction(context)),
                  StreamBuilder<List<SupportCase>>(
                    stream: widget.feed,
                    builder: (context, snapshot) => conversations(snapshot),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget introduction(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'How can we help?',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 30,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'A little guidance, or a conversation with our team.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _SupportEntry(
          key: const Key('support-assistant-entry'),
          tinted: true,
          icon: Icons.auto_awesome_outlined,
          eyebrow: 'QUICK GUIDANCE',
          title: 'Luvly Assistant',
          detail: 'Automated help with gowns, fittings, packages and rentals.',
          onTap: widget.onAssistant,
        ),
        const SizedBox(height: 8),
        _SupportEntry(
          key: const Key('support-team-entry'),
          icon: Icons.support_agent_outlined,
          eyebrow: 'PERSONAL SUPPORT',
          title: 'Message our team',
          detail: 'Help from our team with your booking, fitting or rental.',
          onTap: widget.onMessage,
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            'Your conversations',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Pick up where you left off.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget conversations(AsyncSnapshot<List<SupportCase>> snapshot) {
    if (widget.feed == null ||
        (snapshot.hasError &&
            snapshot.connectionState != ConnectionState.waiting)) {
      return SliverToBoxAdapter(
        child: _ConversationNotice(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load conversations.',
          detail: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: widget.onRetry,
        ),
      );
    }
    if (!snapshot.hasData) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(
            semanticsLabel: 'Loading conversations',
          ),
        ),
      );
    }

    final all = snapshot.data!;
    if (all.isEmpty) {
      return const SliverToBoxAdapter(
        child: _ConversationNotice(
          icon: Icons.forum_outlined,
          title: 'No conversations yet',
          detail:
              'Start a conversation with our team whenever you need assistance.',
        ),
      );
    }
    final rows = all
        .where(
          (ticket) =>
              (status == 'All' ||
                  (ticket.status == 'Closed') == (status == 'Closed')) &&
              (topic == allTopics || ticket.category == topic) &&
              matchesListSearch(query, [ticket.subject, ticket.category]),
        )
        .toList();
    final indexById = {for (var i = 0; i < rows.length; i++) rows[i].id: i};
    final defaultFilters =
        status == 'Active' && topic == allTopics && query.trim().isEmpty;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: filters(context)),
        if (rows.isEmpty)
          SliverToBoxAdapter(
            child: _ConversationNotice(
              icon: Icons.search_off,
              title: 'No matching conversations',
              detail: 'Try another search term or change your filters.',
              actionLabel: defaultFilters
                  ? 'Show all conversations'
                  : 'Reset filters',
              onAction: defaultFilters
                  ? () => setState(() => status = 'All')
                  : resetFilters,
            ),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            findChildIndexCallback: (key) =>
                indexById[(key as ValueKey<String>).value],
            itemBuilder: (context, index) {
              final ticket = rows[index];
              return Padding(
                key: ValueKey(ticket.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _ConversationCard(
                  ticket: ticket,
                  preview: previewFor(ticket),
                  onTap: () => widget.onOpen(ticket),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget filters(BuildContext context) {
    final theme = Theme.of(context);
    final topicSelected = topic != allTopics;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ListSearchField(
                  value: query,
                  hint: MediaQuery.textScalerOf(context).scale(1) > 1.4
                      ? 'Search'
                      : 'Search conversations',
                  compact: true,
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                key: const Key('support-topic-filter'),
                tooltip: 'Filter by topic',
                icon: Icon(
                  Icons.tune,
                  size: 21,
                  color: topicSelected ? rose : ink,
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  backgroundColor: topicSelected ? blush : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: topicSelected ? rose : line),
                  ),
                ),
                initialValue: topic,
                position: PopupMenuPosition.under,
                popUpAnimationStyle: CustomerUi.popupMotion(context),
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(
                    100,
                    360,
                  ),
                ),
                onSelected: (value) => setState(() => topic = value),
                itemBuilder: (_) => [
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Text(
                      'Topic',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final item in [allTopics, ...supportCategories])
                    CheckedPopupMenuItem<String>(
                      key: ValueKey('support-topic-$item'),
                      value: item,
                      checked: topic == item,
                      child: Text(item),
                    ),
                ],
              ),
            ],
          ),
          if (topicSelected)
            InputChip(
              label: Text(topic),
              deleteButtonTooltipMessage: 'Clear topic filter',
              onDeleted: () => setState(() => topic = allTopics),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final option in ['Active', 'Closed', 'All'])
                ChoiceChip(
                  key: ValueKey('support-status-$option'),
                  showCheckmark: false,
                  label: Text(option),
                  selected: status == option,
                  onSelected: (_) => setState(() => status = option),
                  chipAnimationStyle: CustomerUi.chipMotion(context),
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    color: status == option
                        ? ink
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: status == option
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: status == option ? line : Colors.transparent,
                  ),
                  shape: const StadiumBorder(),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupportEntry extends StatelessWidget {
  const _SupportEntry({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.onTap,
    this.tinted = false,
  });

  final IconData icon;
  final String eyebrow, title, detail;
  final VoidCallback onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.6;
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: tinted ? Colors.white : blush,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, color: rose, size: 22),
      ),
    );
    final label = Text(
      eyebrow,
      style: theme.textTheme.labelSmall?.copyWith(
        color: secondary,
        letterSpacing: .85,
        fontWeight: FontWeight.w700,
      ),
    );
    return Material(
      color: tinted ? blush : CustomerUi.linen,
      shape: const RoundedRectangleBorder(borderRadius: CustomerUi.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (!largeText) ...[badge, const SizedBox(width: 11)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (largeText)
                        Row(
                          children: [
                            badge,
                            const SizedBox(width: 8),
                            Expanded(child: label),
                          ],
                        )
                      else
                        label,
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: secondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.ticket,
    required this.preview,
    required this.onTap,
  });

  final SupportCase ticket;
  final Future<String?>? preview;
  final VoidCallback onTap;

  String? updatedLabel(BuildContext context) {
    final value = ticket.data['updatedAt'];
    if (value is! Timestamp) return null;
    final date = value.toDate().toLocal();
    final locale = MaterialLocalizations.of(context);
    final day = locale.formatShortDate(date);
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return 'Updated $day · $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: secondary,
    );
    final updated = updatedLabel(context);
    final closed = ticket.status == 'Closed';
    return Material(
      key: ValueKey('support-conversation-${ticket.id}'),
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: CustomerUi.buttonRadius,
        side: BorderSide(color: CustomerUi.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(ticket.category, style: secondaryStyle),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: closed ? ivory : blush,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              child: Text(
                                ticket.status == 'In Progress'
                                    ? 'In progress'
                                    : ticket.status,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: secondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (preview != null)
                        FutureBuilder<String?>(
                          future: preview,
                          builder: (context, snapshot) {
                            final message = snapshot.data;
                            if (snapshot.connectionState !=
                                    ConnectionState.done ||
                                message == null ||
                                message.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text(
                                message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: secondaryStyle,
                              ),
                            );
                          },
                        ),
                      if (updated != null) ...[
                        const SizedBox(height: 7),
                        Text(updated, style: secondaryStyle),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationNotice extends StatelessWidget {
  const _ConversationNotice({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title, detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, color: rose, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actionLabel != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
