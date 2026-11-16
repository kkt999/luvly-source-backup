import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'shell.dart';

/// Development fixtures only. Never imported by the production entry point.
class PortalPreviewApp extends StatelessWidget {
  const PortalPreviewApp({super.key, required this.model});
  final PortalModel model;
  @override
  Widget build(BuildContext context) => PortalScope(
    model: model,
    child: MaterialApp(
      title: 'Luvly Portal Preview',
      debugShowCheckedModeBanner: false,
      theme: portalTheme,
      home: const PortalRoot(),
    ),
  );
}
