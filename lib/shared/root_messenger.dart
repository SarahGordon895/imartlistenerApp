import 'package:flutter/material.dart';

/// For SnackBar toasts on platforms where `fluttertoast` has no plugin (Windows, etc.).
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
