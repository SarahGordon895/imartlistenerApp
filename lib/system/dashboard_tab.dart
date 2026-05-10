import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth.dart';
import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../services/listening_notification.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/flyer_copy.dart';
import '../shared/portal_sender.dart';
import '../shared/sender_api_payload.dart';
import '../shared/themes.dart';
import 'compose_screen.dart';
import 'incoming_messages_screen.dart';
import '../widgets/loading.dart';
import '../widgets/toast.dart';
import '../widgets/vll_brand_logo.dart';
import '../auth/login.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _working = false;
  bool _senderLoading = true;
  List<_SenderOption> _senders = [];
  _SenderOption? _selected;

  String? _portalPhone;

  Map<String, int> _kpis = {};
  List<Map<String, Object?>> _segmentRows = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadUserProfile();
    await _loadSenders();
    await _loadEngagementKpis();
  }

  Future<void> _loadEngagementKpis() async {
    try {
      final k = await LocalDatabase.instance.inboundKpis();
      final s = await LocalDatabase.instance.inboundSegmentBreakdown();
      if (!mounted) return;
      setState(() {
        _kpis = k;
        _segmentRows = s;
      });
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final res = await ApiClient.instance.get(ApiConstants.userPath);
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final data = ApiClient.responseData(res);
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        final phone = m['contact_phone']?.toString();
        if (!mounted) return;
        setState(() => _portalPhone = phone);
      }
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _loadSenders() async {
    if (mounted) setState(() => _senderLoading = true);
    try {
      final res = await ApiClient.instance.get(ApiConstants.sendersListPath);
      ApiClient.ensureHttpAndEnvelopeSuccess(
        res,
        fallbackPrefix: 'Failed to load sender IDs',
      );
      final data = ApiClient.responseData(res);
      final list = SenderApiPayload.extractSendersList(data);
      final currentSender = SenderApiPayload.extractCurrentSenderId(data);
      await LocalDatabase.instance.replacePortalSendersFromApi(list);
      _commitSenderOptions(list, currentSender);
      if (mounted && _senders.isEmpty) {
        showToast(
          'No Active sender IDs from SMSver1 for this account. Add or approve them in the portal.',
          error: true,
        );
      }
    } on TimeoutException {
      final rows = await LocalDatabase.instance.listPortalSenders();
      _commitSenderOptions(rows, null);
      if (mounted && _senders.isEmpty) {
        showToast('Loading sender IDs timed out. Check connection and retry.', error: true);
      } else if (mounted) {
        showToast('Timeout — showing last synced sender IDs from SMSver1.', error: true);
      }
    } catch (e) {
      final rows = await LocalDatabase.instance.listPortalSenders();
      _commitSenderOptions(rows, null);
      if (mounted) {
        if (_senders.isEmpty) {
          showToast('Could not load sender IDs: $e', error: true);
        } else {
          showToast('Using last synced sender IDs from SMSver1 (API unavailable).', error: false);
        }
      }
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
      showToast('Please select sender ID.', error: true);
      return;
    }
    setState(() => _working = true);
    try {
      final res = await ApiClient.instance.postJson(ApiConstants.senderBindPath, {
        'sender_id': normalizeOutgoingSenderId(sel.senderId),
      });
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          ApiClient.errorMessageFromResponse(
            res,
            fallbackPrefix: 'Bind failed',
          ),
        );
      }
      final decoded = ApiClient.decodeBody(res);
      if (decoded is Map && decoded['success'] == false) {
        throw Exception(decoded['message']?.toString() ?? 'Bind rejected');
      }
      showToast('Sender ID attached to portal phone.');
    } on TimeoutException {
      showToast('Bind request timed out. Please try again.', error: true);
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _working = true);
    var logoutErr = '';
    try {
      // Some desktop targets may not have notification plugin channels; don't block logout.
      try {
        await ListeningNotification.instance.dismiss();
      } catch (_) {}

      await AuthService(ApiClient.instance).logout();
    } catch (e) {
      logoutErr = e.toString();
    } finally {
      await ApiClient.instance.setToken(null);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginPage()),
          (_) => false,
        );
        if (logoutErr.isNotEmpty) {
          showToast(logoutErr, error: true);
        }
        setState(() => _working = false);
      }
    }
  }

  void _openCompose() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
    );
  }

  void _openInbox() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const IncomingMessagesScreen(isActive: true),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(VllBranding.appTitle),
        actions: [
          IconButton(
            onPressed: _working ? null : _loadEngagementKpis,
            tooltip: 'Refresh engagement stats',
            icon: const Icon(Icons.analytics_outlined),
          ),
          TextButton(
            onPressed: _working ? null : _logout,
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: LoadingOverlay(
        show: _working,
        child: LayoutBuilder(
          builder: (context, c) {
            final maxW = c.maxWidth > 1100 ? 980.0 : c.maxWidth;
            final isNarrow = c.maxWidth < 420;
            final hPad = isNarrow ? 12.0 : (c.maxWidth > 800 ? 24.0 : 16.0);
            final bottomInset = MediaQuery.paddingOf(context).bottom;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 16 + bottomInset),
                  children: [
                    _buildHeroCard(context, isNarrow),
                    const SizedBox(height: 12),
                    _buildKpiCard(context, isNarrow),
                    const SizedBox(height: 12),
                    _buildSenderCard(isNarrow),
                    const SizedBox(height: 12),
                    _buildQuickActionsCard(isNarrow),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, bool isNarrow) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 14 : 18,
        isNarrow ? 16 : 20,
        isNarrow ? 14 : 18,
        isNarrow ? 14 : 18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.lushRed,
            AppTheme.lushRed.withValues(alpha: 0.88),
            AppTheme.lushDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: VllBrandLogo(
              tone: VllLogoTone.onBrandField,
              height: isNarrow ? 64 : 72,
              width: isNarrow ? 260 : 300,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            VllBranding.appTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            VllBranding.homeHeroSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            '${VllBranding.supportTz} · ${VllBranding.supportKe}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.lushGold,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(BuildContext context, bool isNarrow) {
    final total = _kpis['total'] ?? 0;
    final today = _kpis['today'] ?? 0;
    final pending = _kpis['pending'] ?? 0;
    final synced = _kpis['synced'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: AppTheme.lushRed, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Audience KPIs (this device)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Counts from this device’s Inbox (synced to SMSver1). Full-station KPIs stay in your broadcast tools.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _kpiChip(context, 'All messages', '$total', isNarrow),
                _kpiChip(context, 'Today', '$today', isNarrow),
                _kpiChip(context, 'Synced', '$synced', isNarrow),
                _kpiChip(context, 'Pending sync', '$pending', isNarrow),
              ],
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Key features (implemented)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  _featureLine(context, 'SMS listening & forwarding: real-time capture, authenticated portal sync, background notification (Android).'),
                  _featureLine(context, 'Social registration check: multi-platform batch checks via API (keys configured server-side).'),
                  _featureLine(context, 'Portal integration: SMSver1 users & sender IDs, login, inbox sync, configurable API URL.'),
                  _featureLine(context, 'UI: login, dashboard, compose (auto-reply), inbox, polls, audience tools — responsive layouts.'),
                  _featureLine(context, 'Local DB: SQLite for inbox, polls, outbound log, cached sender IDs from portal.'),
                ],
              ),
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Station KPI reference',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  SelectableText(
                    FlyerCopy.stationKpiReference,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87, height: 1.4),
                  ),
                ],
              ),
            ),
            if (_segmentRows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'By show segment (after portal sync)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _segmentRows.take(6).map((r) {
                  final seg = r['seg']?.toString() ?? '';
                  final c = r['c'];
                  final n = c is int ? c : int.tryParse(c.toString()) ?? 0;
                  return Chip(
                    avatar: CircleAvatar(
                      backgroundColor: AppTheme.lushGold.withValues(alpha: 0.4),
                      child: Text('$n', style: const TextStyle(fontSize: 11)),
                    ),
                    label: Text(seg, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _featureLine(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chevron_right, size: 18, color: AppTheme.lushRed),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiChip(BuildContext context, String label, String value, bool isNarrow) {
    return Container(
      width: isNarrow ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E8ED)),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildSenderCard(bool isNarrow) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Sender ID', style: TextStyle(fontSize: 16)),
              ),
              IconButton(
                onPressed: _senderLoading ? null : _loadSenders,
                tooltip: 'Refresh sender IDs',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_portalPhone != null && _portalPhone!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Bind phone: ${_portalPhone!}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ),
          Text(
            VllBranding.senderListPortalHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          if (_senderLoading)
            const Center(child: CircularProgressIndicator())
          else if (_senders.isEmpty)
            const Text('No sender IDs available for this account.')
          else ...[
            DropdownButtonFormField<_SenderOption>(
              // ignore: deprecated_member_use
              value: _selected,
              items: _senders
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.label, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selected = v),
              decoration: const InputDecoration(
                labelText: 'On-air sender ID',
                helperText: VllBranding.senderListPortalHint,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: isNarrow ? double.infinity : 220,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.lushRed,
                ),
                onPressed: _working ? null : _bindSender,
                child: const Text('Bind sender ID'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(bool isNarrow) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: isNarrow ? double.infinity : 220,
                  child: FilledButton.icon(
                    onPressed: _openInbox,
                    icon: const Icon(Icons.inbox),
                    label: const Text('Open Inbox'),
                  ),
                ),
                SizedBox(
                  width: isNarrow ? double.infinity : 220,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
                    onPressed: _openCompose,
                    icon: const Icon(Icons.edit),
                    label: const Text('Open Compose'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _senders.isEmpty
                  ? 'No sender IDs loaded from SMSver1 yet. Tap refresh on Sender ID card.'
                  : 'Loaded ${_senders.length} sender ID(s) from SMSver1.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
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
      var label = (m['sender_id'] ?? m['name'] ?? m['label'] ?? sid).toString();
      label = normalizeOutgoingSenderId(label);
      final idType = m['id_type']?.toString().trim();
      if (idType != null && idType.isNotEmpty) {
        label = '$label · $idType';
      }
      return _SenderOption(senderId: sid, label: label);
    }
    return null;
  }
}
