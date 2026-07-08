import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/auth.dart';
import '../auth/login.dart';
import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../services/listen_filter_service.dart';
import '../services/listening_notification.dart';
import '../services/notification_capture_service.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/flyer_copy.dart';
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
    final selected = await ListenFilterService.instance.getSelected();
    if (!mounted) return;
    setState(() => _listenFilters = selected);
  }

  Future<void> _toggleListenFilter(String senderId) async {
    await ListenFilterService.instance.toggle(senderId);
    await _loadListenFilters();
    try {
      await ApiClient.instance.postJson(ApiConstants.listenFiltersPath, {
        'sender_ids': _listenFilters.toList(),
      });
    } catch (_) {}
    if (!mounted) return;
    showToast(_listenFilters.isEmpty
        ? 'Capturing under default bound sender.'
        : 'Sender filters: ${_listenFilters.length}');
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _hero(),
              const SizedBox(height: 12),
              _deskStats(),
              const SizedBox(height: 12),
              _setupCard(),
              const SizedBox(height: 12),
              _actions(),
              const SizedBox(height: 16),
              Text(
                FlyerCopy.headline,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.lushRed, AppTheme.lushNavy.withValues(alpha: 0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const VllBrandLogo(tone: VllLogoTone.onBrandField, height: 72, maxWidth: 200),
          const SizedBox(height: 10),
          Text(
            VllBranding.appTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            VllBranding.homeHeroSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
        ],
      ),
    );
  }

  Widget _deskStats() {
    final awaiting = _kpis['awaiting'] ?? 0;
    final today = _kpis['today'] ?? 0;
    final sms = _kpis['sms'] ?? 0;
    final wa = _kpis['whatsapp'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E8ED)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Desk today',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Needs reply', '$awaiting', Colors.orange.shade50),
              _stat('Today', '$today', Colors.blue.shade50),
              _stat('SMS', '$sms', Colors.grey.shade100),
              _stat('WhatsApp', '$wa', const Color(0xFFE8F8EF)),
              _stat('Gateway', _smsDriverLabel, const Color(0xFFF3F0FF)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color bg) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _setupCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E8ED)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1 · Capture setup',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Bind the Sender ID used for SMS replies. On Android, allow SMS + Notification access so WhatsApp chats to this phone appear in Inbox.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          if (_portalPhone != null && _portalPhone!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Bound phone: ${_portalPhone!}',
                style: Theme.of(context).textTheme.labelMedium),
          ],
          if (!_notifCaptureEnabled &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD8A8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('WhatsApp capture is off',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Enable Notification access for imartListener to capture Instagram / WhatsApp business chats.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
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
          ],
          const SizedBox(height: 12),
          if (_senderLoading)
            const Center(child: CircularProgressIndicator())
          else if (_senders.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'No Sender IDs yet. Add one in SMS settings — gateway credentials stay in API .env.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SmsSettingsScreen(),
                      ),
                    ).then((_) => _loadSenders());
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
              items: _senders
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                  .toList(),
              onChanged: (v) => setState(() => _selected = v),
              decoration: const InputDecoration(
                labelText: 'SMS reply Sender ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
              onPressed: _working ? null : _bindSender,
              child: const Text('Bind Sender ID'),
            ),
            const SizedBox(height: 8),
            Text('Optional: limit which Sender IDs this phone files under',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _senders.map((s) {
                final selected = _listenFilters.contains(s.senderId);
                return FilterChip(
                  selected: selected,
                  label: Text(s.senderId),
                  onSelected: (_) => _toggleListenFilter(s.senderId),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('2 · Work the desk',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => widget.onOpenTab?.call(1),
          icon: const Icon(Icons.inbox),
          label: const Text('Open Inbox (SMS + WhatsApp)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.onOpenReply ?? () => widget.onOpenTab?.call(2),
          icon: const Icon(Icons.reply),
          label: const Text('Manual reply (template / compose)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => widget.onOpenSocialLookup?.call(),
          icon: const Icon(Icons.travel_explore),
          label: const Text('Social lookup (IG / FB / more)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SmsSettingsScreen()),
            );
          },
          icon: const Icon(Icons.settings),
          label: const Text('SMS settings & Sender ID'),
        ),
      ],
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
      return _SenderOption(senderId: sid, label: label);
    }
    return null;
  }
}
