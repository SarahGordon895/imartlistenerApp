import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'packages/http_requests.dart';
import 'shared/branding.dart';
import 'shared/root_messenger.dart';
import 'shared/themes.dart';
import 'wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initSqfliteForDesktop();
  await ApiClient.instance.ensureProductionApiBase();
  runApp(const VllSmsApp());
}

/// Windows/Linux/macOS: use FFI sqlite (avoids VM-only `sqflite` default). Android/iOS unchanged.
void _initSqfliteForDesktop() {
  if (kIsWeb) return;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    default:
      break;
  }
}

class VllSmsApp extends StatelessWidget {
  const VllSmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: VllBranding.appTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: AppTheme.light(),
      home: const AppWrapper(),
    );
  }
}
