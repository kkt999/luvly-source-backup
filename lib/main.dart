import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'admin/main.dart';
import 'bride_app.dart';
import 'firebase_options.dart';

export 'bride_app.dart' show LuvlyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(createPlatformApp());
}

/// Platform selection chooses a UI; it is not an authorization boundary.
Widget createPlatformApp({bool isWeb = kIsWeb}) =>
    isWeb ? PortalApp() : LuvlyApp();
