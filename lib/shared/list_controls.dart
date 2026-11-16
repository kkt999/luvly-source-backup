import 'package:flutter/material.dart';

bool matchesListSearch(String query, Iterable<Object?> fields) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty);
  final haystack = fields.where((s) => s != null).join(' ').toLowerCase();
  return terms.every(haystack.contains);
}

bool matchesMalaysiaDateRange(DateTime instant, DateTimeRange? range) {
  if (range == null) return true;
  int key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  final day = key(instant.toUtc().add(const Duration(hours: 8)));
  return day >= key(range.start) && day <= key(range.end);
}

class ListSearchField extends StatefulWidget {
  const ListSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.hint,
    this.compact = false,
  });
  final String value, hint;
  final bool compact;
  final ValueChanged<String> onChanged;
  @override
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(ListSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.value) {
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      hintText: widget.hint,
      contentPadding: widget.compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : null,
      prefixIcon: Icon(Icons.search, size: widget.compact ? 20 : null),
      suffixIcon: widget.value.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                widget.onChanged('');
              },
              icon: const Icon(Icons.close),
            ),
    ),
  );
}

class ListFilterSelect extends StatelessWidget {
  const ListFilterSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labels = const {},
    this.compact = false,
    this.menuAnimationStyle,
  });
  final String label, value;
  final List<String> options;
  final Map<String, String> labels;
  final bool compact;
  final AnimationStyle? menuAnimationStyle;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = bounds.maxWidth.isFinite ? bounds.maxWidth : 230.0;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.4;
      final controlWidth = width < 400
          ? width
          : large
          ? 300.0
          : 230.0;
      final theme = Theme.of(context);
      return Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: SizedBox(
          width: compact ? null : controlWidth,
          child: PopupMenuButton<String>(
            key: ValueKey('$label-$value'),
            initialValue: value,
            tooltip: '$label: ${labels[value] ?? value}',
            position: PopupMenuPosition.under,
            popUpAnimationStyle: menuAnimationStyle,
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(100, 360),
            ),
            onSelected: onChanged,
            itemBuilder: (_) => {...options, value}
                .map(
                  (s) => CheckedPopupMenuItem<String>(
                    key: ValueKey('list-option-$label-$s'),
                    value: s,
                    checked: s == value,
                    child: Text(labels[s] ?? s),
                  ),
                )
                .toList(),
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 48 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (compact)
                    Flexible(
                      child: Text(
                        '$label · ${labels[value] ?? value}',
                        style: theme.textTheme.labelLarge,
                      ),
                    )
                  else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            labels[value] ?? value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 10),
                  const Icon(Icons.expand_more, size: 19),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ResetListFilters extends StatelessWidget {
  const ResetListFilters({super.key, required this.onReset});
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onReset,
    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
    label: const Text('Reset filters'),
  );
}

class FilteredListEmpty extends StatelessWidget {
  const FilteredListEmpty({
    super.key,
    required this.message,
    required this.onReset,
  });
  final String message;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
    child: Column(
      children: [
        const Icon(Icons.search_off, size: 30),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        ResetListFilters(onReset: onReset),
      ],
    ),
  );
}
