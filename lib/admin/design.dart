import 'package:flutter/material.dart';
import 'model.dart';

// Document-aligned portal palette. Keep this separate from the bride app theme.
const rose = Color(0xFFA20F3A),
    ink = Color(0xFF30262B),
    muted = Color(0xFF76666D),
    blush = Color(0xFFF7ECF0),
    canvas = Color(0xFFFCF9FA),
    border = Color(0xFFECDDE2),
    sage = Color(0xFF52765C);
final portalTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'LuvlySans',
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: rose,
    primary: rose,
    surface: Colors.white,
    onSurface: ink,
    onPrimary: Colors.white,
    outline: border,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    toolbarHeight: 60,
    titleTextStyle: TextStyle(
      fontFamily: 'LuvlySans',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
  ),
  drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
  cardTheme: CardThemeData(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: border),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: Colors.white,
    selectedColor: blush,
    showCheckmark: true,
    checkmarkColor: rose,
    side: const BorderSide(color: border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    labelStyle: const TextStyle(
      fontFamily: 'LuvlySans',
      fontSize: 12,
      color: ink,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: border),
    ),
  ),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 13, color: ink, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: rose, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: rose,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      side: const BorderSide(color: border),
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: rose,
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  dividerTheme: const DividerThemeData(color: border, space: 28),
  dataTableTheme: const DataTableThemeData(
    headingRowColor: WidgetStatePropertyAll(canvas),
    headingTextStyle: TextStyle(
      fontFamily: 'LuvlySans',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: muted,
    ),
    dataTextStyle: TextStyle(fontFamily: 'LuvlySans', fontSize: 13, color: ink),
  ),
);
Widget gap([double n = 16]) => SizedBox(height: n);
void notice(BuildContext c, String text) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
void perform(BuildContext c, VoidCallback action) {
  try {
    action();
    notice(c, 'Saved in this demo session.');
  } on StateError catch (e) {
    notice(c, e.message);
  }
}

Future<bool> confirm(BuildContext c, String title, String text) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext c) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => ListView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(c).width < 700 ? 18 : 26),
    children: children,
  );
}

class Heading extends StatelessWidget {
  const Heading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: LayoutBuilder(
      builder: (c, b) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(c).textTheme.headlineMedium),
            gap(5),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
          ],
        );
        return b.maxWidth < 600
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  if (action != null) ...[gap(), action!],
                ],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  if (action != null) ...[const SizedBox(width: 20), action!],
                ],
              );
      },
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext c) {
    final good = [
      'Available',
      'Active',
      'Confirmed',
      'Paid',
      'Completed',
      'Resolved',
      'Gold',
    ].contains(text);
    final warn = [
      'Delayed',
      'Pending',
      'Unassigned',
      'High',
      'Waiting for Customer',
    ].contains(text);
    final col = good
        ? sage
        : warn
        ? const Color(0xFFAA7744)
        : rose;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: col.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: col),
      ),
    );
  }
}

class Metric extends StatelessWidget {
  const Metric(
    this.label,
    this.value,
    this.caption,
    this.icon, {
    super.key,
    this.connected = false,
  });
  final String label, value, caption;
  final IconData icon;
  final bool connected;
  @override
  Widget build(BuildContext c) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            Icon(icon, color: rose, size: 20),
          ],
        ),
        gap(12),
        Text(
          !connected && PortalScope.maybeOf(c)?.isLive == true ? '—' : value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        gap(7),
        Text(
          !connected && PortalScope.maybeOf(c)?.isLive == true
              ? 'Not connected yet'
              : caption,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    ),
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minWidth = 240,
  });
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext c) => LayoutBuilder(
    builder: (c, b) {
      if (children.isEmpty) return const SizedBox.shrink();
      final columns = (b.maxWidth / minWidth).floor().clamp(1, children.length);
      final w = (b.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children.map((x) => SizedBox(width: w, child: x)).toList(),
      );
    },
  );
}

class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    required this.onSearch,
    this.hint = 'Search records',
    this.filters = const [],
  });
  final ValueChanged<String> onSearch;
  final String hint;
  final List<Widget> filters;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(c).width < 500 ? 260 : 300,
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search, size: 19),
            ),
          ),
        ),
        ...filters,
      ],
    ),
  );
}

Widget filterSelect(
  String value,
  List<String> options,
  ValueChanged<String> onChanged,
) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: border),
    borderRadius: BorderRadius.circular(8),
  ),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: value,
      items: options
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: (v) => onChanged(v!),
    ),
  ),
);

class RecordTable extends StatelessWidget {
  const RecordTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 850,
    this.empty = 'No matching records.',
    this.connected = false,
  });
  final List<String> columns;
  final List<List<Widget>> rows;
  final double minWidth;
  final String empty;
  final bool connected;
  @override
  Widget build(BuildContext c) => Panel(
    padding: EdgeInsets.zero,
    child: rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                !connected && PortalScope.maybeOf(c)?.isLive == true
                    ? 'Records are unavailable until this section is connected.'
                    : empty,
                style: const TextStyle(color: muted),
              ),
            ),
          )
        : LayoutBuilder(
            builder: (c, b) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: b.maxWidth > minWidth ? b.maxWidth : minWidth,
                  ),
                  child: DataTable(
                    columnSpacing: 24,
                    horizontalMargin: 20,
                    dataRowMinHeight:
                        60 * MediaQuery.textScalerOf(c).scale(13) / 13,
                    dataRowMaxHeight:
                        76 * MediaQuery.textScalerOf(c).scale(13) / 13,
                    headingRowHeight:
                        46 * MediaQuery.textScalerOf(c).scale(12) / 12,
                    columns: columns
                        .map((s) => DataColumn(label: Text(s)))
                        .toList(),
                    rows: rows
                        .map(
                          (r) => DataRow(
                            cells: r.map((w) => DataCell(w)).toList(),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
  );
}

Widget cell(String value, {String? sub}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
    if (sub != null)
      Text(sub, style: const TextStyle(color: muted, fontSize: 11)),
  ],
);

class Info extends StatelessWidget {
  const Info(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({
    super.key,
    this.text =
        'UI preview · Demo data only. Changes reset on refresh. No live messages or payments.',
  });
  final String text;
  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
    color: blush.withValues(alpha: .65),
    child: Text(text, style: const TextStyle(fontSize: 10, color: rose)),
  );
}

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label,
    this.value, {
    this.options,
    this.number = false,
    this.multiline = false,
    this.optional = false,
    this.date = false,
  });
  final String key, label, value;
  final Map<String, String>? options;
  final bool number, multiline, optional, date;
}

Future<void> editForm(
  BuildContext c,
  String title,
  List<FieldSpec> fields,
  void Function(Map<String, String>) submit, {
  String submitLabel = 'Save changes',
}) async {
  if (PortalScope.maybeOf(c)?.isLive == true) {
    notice(c, 'This section is not connected yet. No changes were saved.');
    return;
  }
  await showDialog<void>(
    context: c,
    builder: (_) => _EditForm(
      title: title,
      fields: fields,
      submit: submit,
      submitLabel: submitLabel,
    ),
  );
}

class _EditForm extends StatefulWidget {
  const _EditForm({
    required this.title,
    required this.fields,
    required this.submit,
    required this.submitLabel,
  });
  final String title, submitLabel;
  final List<FieldSpec> fields;
  final void Function(Map<String, String>) submit;
  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  final form = GlobalKey<FormState>();
  final values = <String, String>{};
  final controllers = <String, TextEditingController>{};
  String? error;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      values[f.key] = f.value;
      controllers[f.key] = TextEditingController(text: f.value);
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in widget.fields) ...[
                if (f.options != null)
                  DropdownButtonFormField<String>(
                    initialValue: values[f.key],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: f.label),
                    items: f.options!.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => values[f.key] = v!,
                  )
                else
                  TextFormField(
                    controller: controllers[f.key],
                    maxLines: f.multiline ? 3 : 1,
                    keyboardType: f.number
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: f.label,
                      hintText: f.date ? 'YYYY-MM-DD' : null,
                    ),
                    validator: (v) {
                      if (!f.optional && (v ?? '').trim().isEmpty) {
                        return 'This field is required.';
                      }
                      if (f.number) {
                        final n = double.tryParse(v ?? '');
                        if (n == null || !n.isFinite || n < 0) {
                          return 'Enter a valid non-negative number.';
                        }
                      }
                      if (f.key == 'email' &&
                          !RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(v ?? '')) {
                        return 'Enter a valid email address.';
                      }
                      if (f.date) {
                        final d = DateTime.tryParse(v ?? '');
                        if (d == null ||
                            d.toIso8601String().substring(0, 10) != v) {
                          return 'Use a valid date in YYYY-MM-DD format.';
                        }
                      }
                      return null;
                    },
                  ),
                gap(),
              ],
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
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
          if (!form.currentState!.validate()) return;
          for (final f in widget.fields) {
            if (f.options == null) {
              values[f.key] = controllers[f.key]!.text.trim();
            }
          }
          try {
            widget.submit(values);
            Navigator.pop(c);
          } on StateError catch (e) {
            setState(() => error = e.message);
          }
        },
        child: Text(widget.submitLabel),
      ),
    ],
  );
}

Map<String, String> choices(List<String> options) => {
  for (final x in options) x: x,
};
Map<String, String> staffChoices(PortalModel m) => {
  '': 'Unassigned',
  for (final s in m.team.where((s) => s.active)) s.id: s.name,
};
String dateInput(DateTime d) => d.toIso8601String().substring(0, 10);
