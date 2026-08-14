import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/auth.dart';
import '../auth/login.dart';
import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../services/listen_filter_service.dart';
import '../services/listen_keyword_service.dart';
import '../services/listening_notification.dart';
import '../services/notification_capture_service.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/portal_sender.dart';
import '../shared/sender_api_payload.dart';
import '../shared/themes.dart';
import '../widgets/loading.dart';
import '../widgets/toast.dart';
import '../widgets/vll_brand_logo.dart';
import 'sms_settings_screen.dart';

/// Business desk home: bind sender, enable capture, open Inbox / Reply / Social.
class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    this.onOpenTab,
    this.onOpenSocialLookup,
    this.onOpenReply,
  });

  /// 0 Home, 1 Inbox, 2 Reply, 3 Social
  final void Function(int index)? onOpenTab;
  final void Function({String? phone})? onOpenSocialLookup;
  final VoidCallback? onOpenReply;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _working = false;
  bool _senderLoading = true;
  List<_SenderOption> _senders = [];
  _SenderOption? _selected;
  Set<String> _listenFilters = {};
  String _listenKeyword = '';
  bool _listenKeywordEnabled = true;
  List<String> _listenFromNumbers = [];
  bool _notifCaptureEnabled = true;
  String? _portalPhone;
  Map<String, int> _kpis = {};
  String _smsDriverLabel = '…';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _safe(Future<void> f) =>
      f.timeout(const Duration(seconds: 8), onTimeout: () {});

  Future<void> _bootstrap() async {
    await Future.wait([
      _safe(_loadUserProfile()),
      _loadSenders(),
      _safe(_loadListenFilters()),
      _safe(_loadKpis()),
      _safe(_refreshNotifCapture()),
      _safe(_loadSmsStatus()),
    ]);
  }

  Future<void> _loadSmsStatus() async {
    try {
      final res = await ApiClient.instance.get(ApiConstants.smsStatusPath);
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final data = ApiClient.responseData(res);
      if (data is! Map) return;
      final m = Map<String, dynamic>.from(data);
      final driver = (m['driver'] ?? 'unknown').toString();
      final manual = m['manual_reply_enabled'] == true;
      if (!mounted) return;
      setState(() {
        _smsDriverLabel = manual ? 'Manual · $driver' : 'Driver · $driver';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _smsDriverLabel = 'SMS offline');
    }
  }

  Future<void> _refreshNotifCapture() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _notifCaptureEnabled = true);
      return;
    }
    final ok = await NotificationCaptureService.instance.isEnabled();
    if (!mounted) return;
    setState(() => _notifCaptureEnabled = ok);
    if (ok) await NotificationCaptureService.instance.ensureStarted();
  }

  Future<void> _loadListenFilters() async {
    // Portal / API is source of truth — display only in the app.
    await ListenKeywordService.instance.refreshFromApi();
    final selected = await ListenFilterService.instance.getSelected();
    final cur = await ListenKeywordService.instance.current();
    if (!mounted) return;
    setState(() {
      _listenFilters = selected;
      _listenKeyword = cur.keywords.join(', ');
      _listenKeywordEnabled = cur.enabled;
      _listenFromNumbers = List<String>.from(cur.fromNumbers);
    });
  }

  Future<void> _loadKpis() async {
    try {
      final k = await LocalDatabase.instance.inboundKpis();
      if (!mounted) return;
      setState(() => _kpis = k);
    } catch (_) {}
  }

  Future<void> _loadUserProfile() async {
    try {
      final res = await ApiClient.instance.get(ApiConstants.userPath);
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final data = ApiClient.responseData(res);
      if (data is Map) {
        final phone = Map<String, dynamic>.from(data)['contact_phone']?.toString();
        if (!mounted) return;
        setState(() => _portalPhone = phone);
      }
    } catch (_) {}
  }

  Future<void> _loadSenders() async {
    if (mounted) setState(() => _senderLoading = true);
    try {
      final res = await ApiClient.instance
          .get(ApiConstants.sendersListPath)
          .timeout(const Duration(seconds: 8));
      ApiClient.ensureHttpAndEnvelopeSuccess(res, fallbackPrefix: 'Sender load failed');
      final data = ApiClient.responseData(res);
      final list = SenderApiPayload.extractSendersList(data);
      final current = SenderApiPayload.extractCurrentSenderId(data);
      try {
        await LocalDatabase.instance
            .replacePortalSendersFromApi(list)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      _commitSenderOptions(list, current);
    } catch (_) {
      try {
        final rows = await LocalDatabase.instance
            .listPortalSenders()
            .timeout(const Duration(seconds: 3));
        _commitSenderOptions(rows, null);
      } catch (_) {
        _commitSenderOptions([], null);
      }
    } finally {
      if (mounted) setState(() => _senderLoading = false);
    }
  }

  void _commitSenderOptions(List<dynamic> list, String? currentSender) {
    final options =
        list.map(_SenderOption.fromDynamic).whereType<_SenderOption>().toList();
    _SenderOption? selected;
    if (currentSender != null) {
      for (final o in options) {
        if (o.senderId == currentSender) {
          selected = o;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _senders = options;
      _selected = selected ?? (options.isNotEmpty ? options.first : null);
      _senderLoading = false;
    });
  }

  Future<void> _bindSender() async {
    final sel = _selected;
    if (sel == null) {
      showToast('Select a sender ID first.', error: true);
      return;
    }
    setState(() => _working = true);
    try {
      final res = await ApiClient.instance.postJson(ApiConstants.senderBindPath, {
        'sender_id': normalizeOutgoingSenderId(sel.senderId),
      });
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
      showToast('Sender ID bound for SMS replies.');
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _working = true);
    try {
      try {
        await ListeningNotification.instance.dismiss();
      } catch (_) {}
      await AuthService(ApiClient.instance).logout();
    } catch (_) {
    } finally {
      await ApiClient.instance.setToken(null);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginPage()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text(VllBranding.appTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _working ? null : _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _working ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LoadingOverlay(
        show: _working,
        child: RefreshIndicator(
          onRefresh: _bootstrap,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottom),
            children: [
              _hero(),
              const SizedBox(height: 14),
              _deskStats(),
              const SizedBox(height: 14),
              _setupCard(),
              const SizedBox(height: 14),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionShell({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lushNavy,
                  )),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.inkMuted,
                      height: 1.35,
                    )),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.lushNavy,
            AppTheme.lushNavy.withValues(alpha: 0.92),
            AppTheme.lushRed.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VllBrandLogo(tone: VllLogoTone.onBrandField, height: 44, maxWidth: 160),
          const SizedBox(height: 14),
          Text(
            VllBranding.appTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            VllBranding.homeHeroSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.35,
                ),
          ),
          if (_portalPhone != null && _portalPhone!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Business phone · ${_portalPhone!}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deskStats() {
    final awaiting = _kpis['awaiting'] ?? 0;
    final today = _kpis['today'] ?? 0;
    final sms = _kpis['sms'] ?? 0;
    final wa = _kpis['whatsapp'] ?? 0;
    final items = [
      ('Needs reply', '$awaiting', const Color(0xFFFFF4E5)),
      ('Today', '$today', const Color(0xFFEAF2FF)),
      ('SMS', '$sms', const Color(0xFFF2F4F7)),
      ('WhatsApp', '$wa', const Color(0xFFE8F8EF)),
    ];
    return _sectionShell(
      title: 'Desk today',
      subtitle: _smsDriverLabel,
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 4 : 2;
          const gap = 10.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items
                .map((e) => SizedBox(
                      width: w,
                      child: _stat(e.$1, e.$2, e.$3),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.lushNavy)),
        ],
      ),
    );
  }

  Widget _setupCard() {
    return _sectionShell(
      title: 'Capture setup',
      subtitle:
          'Bind a Sender ID for SMS replies. Allow SMS permission and Notification access so WhatsApp chats sync to Inbox.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_notifCaptureEnabled &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD8A8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('WhatsApp capture is off',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Turn on Notification access for imartListener to capture WhatsApp business chats.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: () async {
                      await NotificationCaptureService.instance.openSettings();
                      await Future<void>.delayed(const Duration(seconds: 1));
                      await _refreshNotifCapture();
                    },
                    child: const Text('Enable notification access'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_senderLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_senders.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'No Sender IDs yet. Add one in the portal SMS settings (type or select) or below.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SmsSettingsScreen(),
                          ),
                        )
                        .then((_) => _loadSenders());
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Sender ID'),
                ),
              ],
            )
          else ...[
            DropdownButtonFormField<_SenderOption>(
              // ignore: deprecated_member_use
              value: _selected,
              isExpanded: true,
              items: _senders
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.label, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selected = v),
              decoration: const InputDecoration(
                labelText: 'SMS reply Sender ID',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _working ? null : _bindSender,
              child: const Text('Bind Sender ID'),
            ),
            const SizedBox(height: 14),
            Text('Portal listen filters',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.lushNavy,
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 6),
            Text(
              _listenKeywordEnabled
                  ? 'Unique words · $_listenKeyword'
                  : 'Unique words · off (accept all / From rules)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _listenFromNumbers.isEmpty
                  ? 'Allowed From · none'
                  : 'Allowed From · ${_listenFromNumbers.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_listenFilters.isEmpty)
              Text(
                'Filing Sender IDs · bound Sender ID',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.inkMuted),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _listenFilters.map((id) => Chip(label: Text(id))).toList(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    return _sectionShell(
      title: 'Work the desk',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => widget.onOpenTab?.call(1),
            icon: const Icon(Icons.inbox),
            label: const Text('Inbox · SMS + WhatsApp'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onOpenReply ?? () => widget.onOpenTab?.call(2),
            icon: const Icon(Icons.reply),
            label: const Text('Reply · template or compose'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => widget.onOpenSocialLookup?.call(),
            icon: const Icon(Icons.travel_explore),
            label: const Text('Social lookup'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SmsSettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('SMS settings'),
          ),
        ],
      ),
    );
  }
}

class _SenderOption {
  _SenderOption({required this.senderId, required this.label});
  final String senderId;
  final String label;

  static _SenderOption? fromDynamic(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final n = normalizeOutgoingSenderId(raw);
      return _SenderOption(senderId: n, label: n);
    }
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final rawSid = (m['sender_id'] ?? m['id'])?.toString();
      if (rawSid == null || rawSid.isEmpty) return null;
      final sid = normalizeOutgoingSenderId(rawSid);
      var label = normalizeOutgoingSenderId(
          (m['sender_id'] ?? m['name'] ?? m['label'] ?? sid).toString());
      final idType = m['id_type']?.toString().trim();
      if (idType != null && idType.isNotEmpty) label = '$label · $idType';
      final cfg = m['sms_config'];
      if (cfg is Map) {
        final driver = (cfg['driver'] ?? 'inherit').toString().toLowerCase();
        final usesGlobal = cfg['uses_global_env'] == true || driver == 'inherit';
        final gate = usesGlobal ? 'env' : driver;
        label = '$label · SMS:$gate';
      }
      return _SenderOption(senderId: sid, label: label);
    }
    return null;
  }
}
