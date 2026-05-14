import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/auth.dart';
import 'auth/login.dart';
import 'packages/http_requests.dart';
import 'system/main_shell.dart';
import 'widgets/vll_brand_logo.dart';

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> with WidgetsBindingObserver {
  bool _ready = false;
  bool _loggedIn = false;
  late final AuthService _auth = AuthService(ApiClient.instance);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ApiClient.instance.ensureProductionApiBase());
      if (_ready && _loggedIn) {
        _refreshSession();
      }
    }
  }

  /// Re-validate token after backgrounding (server may have revoked / network restored).
  Future<void> _refreshSession() async {
    final ok = await _auth.hasValidSession();
    if (!mounted) return;
    if (!ok) {
      await ApiClient.instance.setToken(null);
      setState(() => _loggedIn = false);
    }
  }

  Future<void> _check() async {
    await ApiClient.instance.ensureProductionApiBase();
    final t = await ApiClient.instance.getToken();
    var sessionOk = false;
    if (t != null && t.isNotEmpty) {
      sessionOk = await _auth.hasValidSession();
      if (!sessionOk) {
        await ApiClient.instance.setToken(null);
      }
    }
    if (!mounted) return;
    setState(() {
      _loggedIn = sessionOk;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (context) {
                      final sw = MediaQuery.sizeOf(context).width;
                      final w = (sw - 40).clamp(200.0, 320.0);
                      return SizedBox(
                        width: w,
                        height: 96,
                        child: const FittedBox(
                          fit: BoxFit.contain,
                          child: VllBrandLogo(
                            tone: VllLogoTone.onLightSurface,
                            height: 88,
                            width: 300,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return _loggedIn ? const MainShell() : const LoginPage();
  }
}
