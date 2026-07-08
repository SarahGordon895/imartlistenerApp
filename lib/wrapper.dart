import 'dart:async';

import 'package:flutter/foundation.dart';
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

  Future<void> _refreshSession() async {
    final ok = await _auth.hasValidSession();
    if (!mounted) return;
    if (!ok) {
      await ApiClient.instance.setToken(null);
      setState(() => _loggedIn = false);
    }
  }

  Future<void> _check() async {
    // Non-blocking local pin when possible; show UI quickly.
    unawaited(ApiClient.instance.ensureProductionApiBase());
    final t = await ApiClient.instance.getToken();
    var sessionOk = false;
    if (t != null && t.isNotEmpty) {
      // Don't block splash on /user if network is slow — treat timeout as still logged in.
      sessionOk = await _auth.hasValidSession().timeout(
        const Duration(seconds: 4),
        onTimeout: () => true,
      );
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
                  const VllBrandLogo(
                    tone: VllLogoTone.onLightSurface,
                    height: 88,
                    maxWidth: 220,
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFFE31C23),
                    ),
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Loading imartListener…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                  ],
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
