import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../shared/root_messenger.dart';

bool get _useSnackBarInsteadOfPlugin {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

void showToast(String msg, {bool error = false}) {
  if (_useSnackBarInsteadOfPlugin) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: error ? const Color(0xFFB00020) : const Color(0xFF323232),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    debugPrint('[toast${error ? ' ERROR' : ''}] $msg');
    return;
  }

  try {
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor:
          error ? const Color(0xFFB00020) : const Color(0xFF323232),
      textColor: const Color(0xFFFFFFFF),
    );
  } on MissingPluginException {
    debugPrint(msg);
  }
}
