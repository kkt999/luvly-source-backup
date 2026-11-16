import 'package:flutter/material.dart';

const rose = Color(0xFFA65360),
    ink = Color(0xFF332A2B),
    muted = Color(0xFF827579),
    blush = Color(0xFFF4E5E6),
    ivory = Color(0xFFFFFCF9),
    line = Color(0xFFEBDDDD);

abstract final class CustomerUi {
  static const canvas = Color(0xFFFCF9F6);
  static const paper = Colors.white;
  static const linen = Color(0xFFF6F0EB);
  static const outline = Color(0xFFDED4D1);
  static const fieldOutline = Color(0xFF97868A);
  static const divider = Color(0xFFEAE1DC);
  static const secondaryText = Color(0xFF685A5E);
  static const activeText = Color(0xFF783A4C);
  static const success = Color(0xFF386953);
  static const warning = Color(0xFF78521F);
  static const information = Color(0xFF435F88);
  static const error = Color(0xFFA3283D);

  static const controlRadius = BorderRadius.all(Radius.circular(12));
  static const buttonRadius = BorderRadius.all(Radius.circular(15));
  static const cardRadius = BorderRadius.all(Radius.circular(20));
  static const featureRadius = BorderRadius.all(Radius.circular(24));
  static const sheetRadius = BorderRadius.vertical(top: Radius.circular(24));
  static const sectionSpacing = 24.0;
  static const pageInset = 20.0;
  static const feedback = Duration(milliseconds: 140);
  static const selection = Duration(milliseconds: 180);
  static const expansion = Duration(milliseconds: 220);

  static const softCard = BoxDecoration(
    color: paper,
    borderRadius: cardRadius,
    boxShadow: [
      BoxShadow(color: Color(0x10382E31), blurRadius: 14, offset: Offset(0, 4)),
    ],
  );
  static const tintedCard = BoxDecoration(
    color: linen,
    borderRadius: cardRadius,
  );

  static Duration motion(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  static AnimationStyle popupMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: selection,
          reverseDuration: feedback,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn,
        );

  static AnimationStyle expansionMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(duration: expansion, curve: Curves.easeInOutCubic);

  static ChipAnimationStyle chipMotion(BuildContext context) =>
      ChipAnimationStyle(
        selectAnimation: AnimationStyle(duration: motion(context, selection)),
      );
}

const _customerInputBorder = OutlineInputBorder(
  borderRadius: CustomerUi.controlRadius,
  borderSide: BorderSide(color: CustomerUi.fieldOutline),
);
const _customerButtonShape = RoundedRectangleBorder(
  borderRadius: CustomerUi.buttonRadius,
);
const _customerMenuShape = RoundedRectangleBorder(
  borderRadius: CustomerUi.cardRadius,
);

final luvlyTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'LuvlySans',
  colorScheme: ColorScheme.fromSeed(
    seedColor: rose,
    primary: rose,
    onPrimary: Colors.white,
    primaryContainer: blush,
    onPrimaryContainer: CustomerUi.activeText,
    secondaryContainer: CustomerUi.linen,
    onSecondaryContainer: ink,
    surface: CustomerUi.canvas,
    surfaceContainer: CustomerUi.linen,
    surfaceContainerLowest: CustomerUi.paper,
    onSurface: ink,
    onSurfaceVariant: CustomerUi.secondaryText,
    outline: CustomerUi.secondaryText,
    outlineVariant: CustomerUi.outline,
    error: CustomerUi.error,
  ),
  scaffoldBackgroundColor: CustomerUi.canvas,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontFamily: 'LuvlySerif',
      fontSize: 34,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'LuvlySerif',
      fontSize: 27,
      fontWeight: FontWeight.w500,
      height: 1.25,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: ink),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: ink),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.4,
      color: CustomerUi.secondaryText,
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: CustomerUi.canvas,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontFamily: 'LuvlySans',
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 17,
    ),
    iconTheme: IconThemeData(color: ink),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: true,
    fillColor: CustomerUi.paper,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: _customerInputBorder,
    enabledBorder: _customerInputBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: CustomerUi.controlRadius,
      borderSide: BorderSide(color: rose, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: CustomerUi.controlRadius,
      borderSide: BorderSide(color: CustomerUi.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: CustomerUi.controlRadius,
      borderSide: BorderSide(color: CustomerUi.error, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: CustomerUi.controlRadius,
      borderSide: BorderSide(color: CustomerUi.divider),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: rose,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 50),
      elevation: 0,
      shape: _customerButtonShape,
      animationDuration: CustomerUi.feedback,
      textStyle: const TextStyle(
        fontFamily: 'LuvlySans',
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style:
        OutlinedButton.styleFrom(
          foregroundColor: CustomerUi.activeText,
          backgroundColor: CustomerUi.paper,
          minimumSize: const Size(0, 48),
          shape: _customerButtonShape,
          animationDuration: CustomerUi.feedback,
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const BorderSide(color: CustomerUi.divider);
            }
            return BorderSide(
              color: states.contains(WidgetState.focused)
                  ? rose
                  : CustomerUi.outline,
            );
          }),
        ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: CustomerUi.activeText,
      shape: _customerButtonShape,
      animationDuration: CustomerUi.feedback,
    ),
  ),
  popupMenuTheme: const PopupMenuThemeData(
    color: CustomerUi.paper,
    surfaceTintColor: Colors.transparent,
    shadowColor: Color(0x33382E31),
    elevation: 4,
    shape: _customerMenuShape,
    menuPadding: EdgeInsets.symmetric(vertical: 6),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: CustomerUi.paper,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: CustomerUi.featureRadius),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: CustomerUi.paper,
    modalBackgroundColor: CustomerUi.paper,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: CustomerUi.sheetRadius),
  ),
  cardTheme: const CardThemeData(
    color: CustomerUi.paper,
    surfaceTintColor: Colors.transparent,
    shadowColor: Color(0x19382E31),
    elevation: 0,
    shape: _customerMenuShape,
  ),
  chipTheme: const ChipThemeData(
    backgroundColor: CustomerUi.paper,
    selectedColor: blush,
    secondarySelectedColor: blush,
    side: BorderSide(color: CustomerUi.outline),
    shape: StadiumBorder(),
  ),
  dividerTheme: const DividerThemeData(color: CustomerUi.divider, space: 24),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: CustomerUi.canvas,
    surfaceTintColor: Colors.transparent,
    indicatorColor: blush,
    height: 74,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: 'LuvlySans',
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
);
void go(BuildContext c, Widget screen) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen));
void toast(BuildContext c, String message) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
Future<bool> confirm(
  BuildContext c,
  String title,
  String message, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep current'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottom,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(top: false, child: child),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: bottom,
            ),
          ),
  );
}

class PageList extends StatelessWidget {
  const PageList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
    children: children,
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext c) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(c).textTheme.titleMedium)),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    ),
  );
}

class Primary extends StatelessWidget {
  const Primary(this.label, this.onPressed, {super.key, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext c) => SizedBox(
    width: double.infinity,
    child: icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext c) {
    final good = ['Confirmed', 'Completed', 'Paid', 'Resolved'].contains(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: good ? const Color(0xFFE8F0E9) : blush,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: good ? const Color(0xFF4E7158) : rose,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class MenuTile extends StatelessWidget {
  const MenuTile(this.icon, this.title, this.subtitle, this.onTap, {super.key});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: line),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor: blush,
          foregroundColor: rose,
          child: Icon(icon, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
        trailing: const Icon(Icons.chevron_right, size: 20, color: muted),
        onTap: onTap,
      ),
    ),
  );
}

class DemoNote extends StatelessWidget {
  const DemoNote({
    super.key,
    this.text =
        'UI preview • Demo data only. Changes reset when the app restarts.',
  });
  final String text;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 15, color: muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: muted, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, this.message, {super.key});
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      children: [
        CircleAvatar(
          radius: 35,
          backgroundColor: blush,
          child: Icon(icon, color: rose, size: 32),
        ),
        gap(18),
        Text(title, style: Theme.of(c).textTheme.titleLarge),
        gap(8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );
}

Widget gap([double height = 16]) => SizedBox(height: height);
Widget photo(
  String asset, {
  double? height,
  double? width,
  BoxFit fit = BoxFit.cover,
}) => Image.asset(
  'assets/images/$asset.jpg',
  height: height,
  width: width,
  fit: fit,
  alignment: Alignment.topCenter,
  filterQuality: FilterQuality.high,
);
