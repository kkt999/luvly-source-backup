import 'package:flutter/material.dart';
import '../admin/design.dart' show blush, border, muted, rose;

class PackageEditorSection extends StatelessWidget {
  const PackageEditorSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: blush,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: rose),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        if (subtitle case final text?) ...[
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: muted)),
        ],
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}
