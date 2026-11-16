import 'package:flutter/material.dart';

class FittingSection extends StatelessWidget {
  const FittingSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFEADDE1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF7C6D73)),
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class FittingOptions extends StatelessWidget {
  const FittingOptions({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.descriptions = const {},
  });
  final String value;
  final Map<String, String> labels, descriptions;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final width =
          c.maxWidth >= 560 && MediaQuery.textScalerOf(context).scale(1) < 1.7
          ? (c.maxWidth - 12) / 2
          : c.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          for (final e in labels.entries)
            SizedBox(
              width: width,
              child: Semantics(
                selected: value == e.key,
                button: true,
                child: Material(
                  color: value == e.key
                      ? const Color(0xFFFBF0F3)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: value == e.key
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFFEADDE1),
                    ),
                  ),
                  child: InkWell(
                    key: ValueKey('fitting-option-${e.key}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: onChanged == null ? null : () => onChanged!(e.key),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            value == e.key
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: value == e.key
                                ? Theme.of(context).colorScheme.primary
                                : const Color(0xFF96868C),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (descriptions[e.key] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    descriptions[e.key]!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

const fittingOutcomeLabels = {
  'Selected': 'Keep current gown selection',
  'SelectedOther': 'Chosen a different gown',
  'Reselect': 'Needs another gown · not chosen yet',
  'Considering': 'Still considering',
  'NotProceeding': 'Not proceeding',
};
const fittingAdjustmentLabels = {
  'None': 'No adjustment',
  'Basic': 'Basic fit adjustments',
  'Assessment': 'Special requests · needs assessment',
};

class FittingSaveBar extends StatelessWidget {
  const FittingSaveBar({
    super.key,
    required this.next,
    required this.caption,
    required this.label,
    required this.onSave,
    this.error,
    this.icon = Icons.save_outlined,
    this.showAction = true,
  });
  final String next, caption, label;
  final String? error;
  final VoidCallback? onSave;
  final IconData icon;
  final bool showAction;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFEADDE1))),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1312),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, c) {
                    final description = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next: $next',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          caption,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                    if (!showAction) {
                      return SizedBox(width: double.infinity, child: description);
                    }
                    final button = FilledButton.icon(
                      onPressed: onSave,
                      icon: Icon(icon, size: 18),
                      label: Text(label),
                    );
                    return c.maxWidth >= 720 &&
                            MediaQuery.textScalerOf(context).scale(1) < 1.7
                        ? Row(
                            children: [
                              Expanded(child: description),
                              const SizedBox(width: 24),
                              button,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              description,
                              const SizedBox(height: 10),
                              button,
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
