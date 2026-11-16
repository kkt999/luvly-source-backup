import 'package:flutter/material.dart';
import '../src/design.dart';
import 'shortlist_controller.dart';

class ShortlistScope extends InheritedNotifier<ShortlistController> {
  const ShortlistScope({
    super.key,
    required ShortlistController controller,
    required super.child,
  }) : super(notifier: controller);
  static ShortlistController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShortlistScope>()?.notifier;
}

Future<void> changeShortlist(
  BuildContext context,
  ShortlistController controller,
  String id,
  bool saved,
) async {
  final uid = controller.uid;
  try {
    await controller.setSaved(id, saved);
    if (context.mounted && uid == controller.uid) {
      toast(
        context,
        saved ? 'Saved to your shortlist' : 'Removed from your shortlist',
      );
    }
  } catch (_) {
    if (context.mounted && uid == controller.uid) {
      toast(
        context,
        'Could not update your shortlist. Check your connection and try again.',
      );
    }
  }
}

class ShortlistButton extends StatelessWidget {
  const ShortlistButton({
    super.key,
    required this.dressId,
    this.label,
    this.outlined = false,
  });
  final String dressId;
  final String? label;
  final bool outlined;
  @override
  Widget build(BuildContext context) {
    final controller = ShortlistScope.maybeOf(context);
    if (controller?.uid == null) return const SizedBox.shrink();
    final state = controller!;
    final saved = state.contains(dressId), pending = state.pending(dressId);
    final text = saved ? 'Remove from shortlist' : 'Save to shortlist';
    final icon = pending
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(saved ? Icons.favorite : Icons.favorite_border, color: rose);
    final VoidCallback? action = !state.ready || pending
        ? null
        : () => changeShortlist(context, state, dressId, !saved);
    if (outlined) {
      return OutlinedButton.icon(
        key: ValueKey('save-gown-$dressId'),
        onPressed: action,
        icon: icon,
        label: Text(pending ? 'Updating shortlist…' : text),
      );
    }
    return IconButton.filledTonal(
      key: ValueKey('save-gown-$dressId'),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xF7FFFFFF),
        minimumSize: const Size(48, 48),
      ),
      tooltip: pending
          ? 'Updating shortlist'
          : '$text${label == null ? '' : ': $label'}',
      isSelected: saved,
      onPressed: action,
      icon: icon,
    );
  }
}

class ShortlistNotice extends StatelessWidget {
  const ShortlistNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final state = ShortlistScope.maybeOf(context);
    if (state?.error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state!.error!,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            TextButton(
              onPressed: state.retry,
              child: const Text('Retry shortlist'),
            ),
          ],
        ),
      );
    }
    if (state?.fromCache == true) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Offline or reconnecting · Showing your last saved shortlist.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
