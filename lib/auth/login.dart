import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../packages/http_requests.dart';
import '../packages/validators.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/themes.dart';
import '../widgets/loading.dart';
import '../widgets/toast.dart';
import '../widgets/vll_brand_logo.dart';
import 'auth.dart';
import '../system/main_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _adminPin = String.fromEnvironment(
    'ADMIN_PIN',
    defaultValue: '2605',
  );
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _baseUrl;
  int _logoTapCount = 0;

  late final AuthService _auth = AuthService(ApiClient.instance);

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    final url = await ApiClient.instance.getBaseUrl();
    if (!mounted) return;
    setState(() => _baseUrl = url);
  }

  Future<void> _showServerDialog() async {
    final c = TextEditingController(text: _baseUrl ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: c,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://your-laravel-host.com',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Use the Laravel host that returns JSON for /api/v1/… (not a URL that serves only the SMS portal HTML).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    if (!saved.startsWith('http://') && !saved.startsWith('https://')) {
      showToast('URL must start with http:// or https://', error: true);
      return;
    }
    if (ApiClient.isSmsPortalHostMisusedAsApi(saved)) {
      showToast(
        'That host is the SMS web portal, not the Laravel API. Use your JSON API host (e.g. ${ApiConstants.defaultLaravelApiBase}).',
        error: true,
      );
      return;
    }
    await ApiClient.instance.setBaseUrl(saved);
    if (!mounted) return;
    setState(() => _baseUrl = saved);
    showToast('Server updated.');
  }

  void _onLogoTap() {
    _logoTapCount += 1;
    if (_logoTapCount < 5) return;
    _logoTapCount = 0;
    _promptAdminPin();
  }

  Future<void> _promptAdminPin() async {
    final pinController = TextEditingController();
    final enteredPin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Access'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN',
            hintText: 'Enter admin PIN',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, pinController.text.trim()),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (!mounted || enteredPin == null) return;
    if (enteredPin != _adminPin) {
      showToast('Invalid admin PIN.', error: true);
      return;
    }
    _showServerDialog();
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await _auth.login(login: _login.text.trim(), password: _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
      );
    } on AuthException catch (e) {
      showToast(e.message, error: true);
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.lushRed, AppTheme.lushDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: GestureDetector(
                  onTap: _onLogoTap,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final maxLogo = (c.maxWidth - 8).clamp(160.0, 280.0);
                      return SizedBox(
                        width: maxLogo,
                        height: 60,
                        child: const FittedBox(
                          fit: BoxFit.contain,
                          child: VllBrandLogo(
                            tone: VllLogoTone.onBrandField,
                            height: 56,
                            width: 260,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              child: LoadingOverlay(
                show: _busy,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final maxW = c.maxWidth > 700 ? 520.0 : c.maxWidth;
                    final kb = MediaQuery.viewInsetsOf(context).bottom;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 20 + kb),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxW),
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              child: Card(
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        VllBranding.appTitle,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.lushDark,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        VllBranding.loginSubtitle,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.black54,
                                              height: 1.35,
                                            ),
                                      ),
                                      const SizedBox(height: 20),
                                      TextFormField(
                                        controller: _login,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [AutofillHints.username],
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Username, user ID, or email',
                                        ),
                                        validator: (v) => Validators.required(v, 'Username'),
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _password,
                                        obscureText: true,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [AutofillHints.password],
                                        onFieldSubmitted: (_) => _submit(),
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Password',
                                        ),
                                        validator: Validators.password,
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        height: 50,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppTheme.lushRed,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          onPressed: _busy
                                              ? null
                                              : () {
                                                  TextInput.finishAutofillContext();
                                                  _submit();
                                                },
                                          child: const Text(
                                            'Login',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
