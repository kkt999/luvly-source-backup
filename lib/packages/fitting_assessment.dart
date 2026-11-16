import 'package:flutter/material.dart';

const fittingParts = {
  'bust': 'Bust',
  'waist': 'Waist',
  'hips': 'Hips',
  'length': 'Length',
};
const fitLabels = {
  'NotAssessed': 'Not assessed',
  'Tight': 'Too tight',
  'Good': 'Fits well',
  'Loose': 'Too loose',
};
const lengthLabels = {
  'NotAssessed': 'Not assessed',
  'Long': 'Too long',
  'Good': 'Suitable length',
  'Short': 'Too short',
};
const followUpLabels = {
  'NotDecided': 'Not decided',
  'Required': 'Another fitting needed',
  'NotRequired': 'No further fitting needed',
};

DateTime fittingToday() {
  final myt = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(myt.year, myt.month, myt.day);
}

String fittingDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class FittingGownDraft {
  FittingGownDraft(Map<String, dynamic> g)
    : id = g['dressId'],
      size = g['size'],
      name = g['name'] ?? 'Gown';
  final String id, size, name;
  final fit = {for (final key in fittingParts.keys) key: 'NotAssessed'};
  final notes = TextEditingController();
  void dispose() => notes.dispose();
}

/// Local form state, never a body-profile update or a size/price recommendation.
class FittingAssessmentDraft {
  FittingAssessmentDraft(List<Map<String, dynamic>> selected)
    : gowns = selected.map(FittingGownDraft.new).toList();
  final body = {
    for (final key in ['bust', 'waist', 'hips']) key: TextEditingController(),
  };
  final bodyCm = <String, double>{};
  final List<FittingGownDraft> gowns;
  bool inches = false;
  String followUp = 'NotDecided';
  DateTime? targetDate;
  void changed(String key) {
    final text = body[key]!.text.trim();
    final parsed = RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)
        ? double.tryParse(text)
        : null;
    final cm = parsed == null ? null : parsed * (inches ? 2.54 : 1);
    if (cm == null || cm < 20 || cm > 300) {
      bodyCm.remove(key);
    } else {
      bodyCm[key] = (cm * 10000).round() / 10000;
    }
  }

  String? get measurementError =>
      body.entries.any(
        (e) => e.value.text.trim().isNotEmpty && !bodyCm.containsKey(e.key),
      )
      ? 'Enter valid measured values, or leave them blank. Use cm 20–300 or the equivalent in inches.'
      : null;
  bool switchUnit(bool value) {
    if (measurementError != null) return false;
    inches = value;
    for (final e in body.entries) {
      final cm = bodyCm[e.key];
      e.value.text = cm == null
          ? ''
          : (cm / (inches ? 2.54 : 1))
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return true;
  }

  String? validate({required bool adjustments, required String? pickup}) {
    if (measurementError != null) return measurementError;
    if (adjustments &&
        gowns.any(
          (g) =>
              g.notes.text.trim().isNotEmpty && g.notes.text.trim().length < 3,
        )) {
      return 'Enter clear adjustment instructions, or leave an unaffected gown blank.';
    }
    if (adjustments && !gowns.any((g) => g.notes.text.trim().length >= 3)) {
      return 'Describe the adjustment needed for at least one gown.';
    }
    if (adjustments &&
        targetDate != null &&
        (targetDate!.isBefore(fittingToday()) ||
            pickup == null ||
            fittingDay(targetDate!).compareTo(pickup) > 0)) {
      return 'Choose a completion date between today and pickup.';
    }
    return null;
  }

  Map<String, dynamic> toJson({required bool adjustments}) => {
    'schemaVersion': 1,
    'bodyCm': {...bodyCm},
    'gowns': [
      for (final g in gowns)
        {
          'dressId': g.id,
          'size': g.size,
          'fit': {...g.fit},
          'adjustmentNotes': adjustments ? g.notes.text.trim() : '',
        },
    ],
    'followUp': adjustments ? followUp : 'NotDecided',
    'targetDate': adjustments && targetDate != null
        ? fittingDay(targetDate!)
        : null,
  };
  void dispose() {
    for (final c in body.values) {
      c.dispose();
    }
    for (final g in gowns) {
      g.dispose();
    }
  }
}

class FittingAssessmentEditor extends StatefulWidget {
  const FittingAssessmentEditor({
    super.key,
    required this.draft,
    required this.adjustments,
    required this.enabled,
    this.pickup,
    this.workbench = false,
  });
  final FittingAssessmentDraft draft;
  final bool adjustments, enabled;
  final String? pickup;
  final bool workbench;
  @override
  State<FittingAssessmentEditor> createState() =>
      _FittingAssessmentEditorState();
}

class _FittingAssessmentEditorState extends State<FittingAssessmentEditor> {
  Future<void> date() async {
    final first = fittingToday(), last = DateTime.tryParse(widget.pickup ?? '');
    if (last == null || last.isBefore(first)) return;
    final previous = widget.draft.targetDate;
    final initial =
        previous != null && !previous.isBefore(first) && !previous.isAfter(last)
        ? previous
        : first;
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Target alteration completion',
    );
    if (result != null && mounted) {
      setState(() => widget.draft.targetDate = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final bodyFields = <Widget>[
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Actual body measurements',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Record measurements taken during this visit. Leave anything unmeasured blank. These are not garment measurements.',
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children: [
          for (final inches in [false, true])
            ChoiceChip(
              label: Text(inches ? 'inches' : 'cm'),
              selected: d.inches == inches,
              onSelected: widget.enabled
                  ? (_) => setState(() {
                      d.switchUnit(inches);
                    })
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final key in d.body.keys)
              SizedBox(
                width: c.maxWidth >= 560 ? (c.maxWidth - 24) / 3 : c.maxWidth,
                child: TextField(
                  key: ValueKey('body-$key'),
                  controller: d.body[key],
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '${fittingParts[key]} (${d.inches ? 'in' : 'cm'})',
                    hintText: 'Optional',
                  ),
                  onChanged: (_) => setState(() => d.changed(key)),
                ),
              ),
          ],
        ),
      ),
      if (d.measurementError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            d.measurementError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ];
    final fitFields = <Widget>[
      for (final g in d.gowns) ...[
        const Divider(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${g.name} · ${g.size}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in fittingParts.entries)
                SizedBox(
                  width: c.maxWidth >= 560 ? (c.maxWidth - 12) / 2 : c.maxWidth,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('fit-${g.id}-${e.key}'),
                    initialValue: g.fit[e.key],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: '${e.value} fit'),
                    items: (e.key == 'length' ? lengthLabels : fitLabels)
                        .entries
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.key,
                            child: Text(
                              v.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: widget.enabled
                        ? (v) => setState(() => g.fit[e.key] = v!)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (widget.adjustments) ...[
          const SizedBox(height: 16),
          TextField(
            key: ValueKey('adjustment-${g.id}'),
            controller: g.notes,
            enabled: widget.enabled,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Adjustment instructions for this gown',
              hintText:
                  'For example: take in the waist by 2 cm. Confirm feasibility with the alteration team.',
            ),
          ),
        ],
      ],
      if (widget.adjustments) ...[
        const Divider(height: 32),
        DropdownButtonFormField<String>(
          key: const ValueKey('fitting-follow-up'),
          initialValue: d.followUp,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Follow-up fitting'),
          items: followUpLabels.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: widget.enabled
              ? (v) => setState(() => d.followUp = v!)
              : null,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: widget.enabled ? date : null,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                d.targetDate == null
                    ? 'Set completion target (optional)'
                    : 'Completion target: ${fittingDay(d.targetDate!)}',
              ),
            ),
            if (d.targetDate != null)
              TextButton(
                onPressed: widget.enabled
                    ? () => setState(() => d.targetDate = null)
                    : null,
                child: const Text('Clear date'),
              ),
          ],
        ),
        const Text(
          'The target must be no later than pickup. A follow-up visit is arranged separately; this record does not create an appointment or a fee.',
        ),
      ],
    ];
    Widget fold(
      String title,
      String subtitle,
      List<Widget> fields, {
      bool open = false,
      Key? key,
    }) {
      final tile = ExpansionTile(
        key: key,
        initiallyExpanded: open,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(title),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: fields,
      );
      if (widget.workbench) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEAD7DD)),
          ),
          clipBehavior: Clip.antiAlias,
          child: tile,
        );
      }
      return Card(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFEAD7DD)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 16),
        child: tile,
      );
    }

    if (widget.workbench) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.adjustments) ...[
            const SizedBox(height: 12),
            const Text(
              'Required: describe the adjustment for at least one gown. Record the follow-up fitting decision below.',
            ),
            ...fitFields,
          ] else
            fold(
              'Gown fit assessment',
              'Optional · assess each gown separately',
              fitFields,
            ),
          fold(
            'Body measurements',
            'Optional · measurements taken at this visit',
            bodyFields,
            key: const ValueKey('fitting-body-measurements'),
          ),
        ],
      );
    }
    return fold(
      'Measurements & fit assessment',
      'Optional measurements · assess each gown separately',
      [...bodyFields, ...fitFields],
      open: widget.adjustments,
      key: ValueKey('fitting-assessment-${widget.adjustments}'),
    );
  }
}

class FittingAssessmentSummary extends StatelessWidget {
  const FittingAssessmentSummary({
    super.key,
    required this.assessment,
    required this.gowns,
  });
  final Map assessment;
  final List<Map<String, dynamic>> gowns;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    shape: const Border(),
    collapsedShape: const Border(),
    tilePadding: EdgeInsets.zero,
    title: const Text('Measurements & fit record'),
    childrenPadding: const EdgeInsets.only(bottom: 12),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Body measurements · cm',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if ((assessment['bodyCm'] as Map).isEmpty)
            const Text('No body measurements recorded.'),
          for (final e in (assessment['bodyCm'] as Map).entries)
            Text('${fittingParts[e.key]}: ${e.value} cm'),
          for (final g in assessment['gowns'] as List) ...[
            const SizedBox(height: 12),
            Text(
              '${gowns.where((s) => s['dressId'] == g['dressId']).map((s) => s['name']).firstOrNull ?? 'Gown'} · ${g['size']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final e in fittingParts.entries)
              Text(
                '${e.value}: ${(e.key == 'length' ? lengthLabels : fitLabels)[g['fit'][e.key]] ?? 'Not assessed'}',
              ),
            if ((g['adjustmentNotes'] as String).isNotEmpty)
              Text(g['adjustmentNotes']),
          ],
          if (assessment['followUp'] != 'NotDecided')
            Text(followUpLabels[assessment['followUp']] ?? 'Not decided'),
          if (assessment['targetDate'] != null)
            Text('Completion target: ${assessment['targetDate']}'),
        ],
      ),
    ],
  );
}

class FittingAdjustmentPlan extends StatelessWidget {
  const FittingAdjustmentPlan({super.key, required this.plan});
  final Map plan;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      const Text(
        'Alteration plan',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      for (final g in plan['gowns'] as List)
        Text('${g['name']} · ${g['size']}: ${g['instructions']}'),
      if (plan['followUp'] != 'NotDecided')
        Text(followUpLabels[plan['followUp']] ?? 'Not decided'),
      if (plan['targetDate'] != null)
        Text('Completion target: ${plan['targetDate']}'),
      if (plan['followUp'] == 'Required')
        const Text('Arrange the follow-up appointment with Luvly.'),
    ],
  );
}
