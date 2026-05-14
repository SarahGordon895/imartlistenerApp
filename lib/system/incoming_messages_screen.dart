import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/local_database.dart';
import '../services/sms_inbound_listener.dart';
import '../shared/branding.dart';
import '../shared/show_segment.dart';
import 'compose_screen.dart';

class IncomingMessagesScreen extends StatefulWidget {
  const IncomingMessagesScreen({super.key, this.isActive = false});

  /// When true, the Inbox tab is visible (used for first-open privacy copy).
  final bool isActive;

  @override
  State<IncomingMessagesScreen> createState() => _IncomingMessagesScreenState();
}

class _IncomingMessagesScreenState extends State<IncomingMessagesScreen> {
  Future<List<Map<String, Object?>>>? _future;
  String? _listenError;
  bool _privacyShown = false;
  String? _segmentFilter;
  StreamSubscription<void>? _messageSub;
  StreamSubscription<String?>? _errorSub;

  @override
  void initState() {
    super.initState();
    _reload();
    SmsInboundListener.instance.ensureStarted();
    _listenError = SmsInboundListener.instance.lastError;
    _messageSub = SmsInboundListener.instance.onMessage.listen((_) {
      if (mounted) _reload();
    });
    _errorSub = SmsInboundListener.instance.onError.listen((err) {
      if (!mounted) return;
      setState(() => _listenError = err);
    });
    if (widget.isActive) {
      _maybeShowPrivacy();
    }
  }

  @override
  void didUpdateWidget(IncomingMessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _maybeShowPrivacy();
    }
  }

  Future<void> _maybeShowPrivacy() async {
    if (_privacyShown || !mounted) return;
    _privacyShown = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SMS access'),
        content: const Text(
          'Real-time SMS dashboard: messages on this handset sync to the shared database (SmSver1 / API) '
          'for your station team. Bind your on-air sender on Home. For live polls, ask listeners to reply '
          'with 1–4 or “vote 2” — tallies appear under Polls. Filter by show segment below (EAT).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = LocalDatabase.instance.listInboundRecent(limit: 300);
    });
  }

  /// Tanzania / EAT display: 24-hour clock (device should be set to Africa/Dar or Nairobi).
  String _fmtTime(int? ms) {
    if (ms == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _segmentForRow(Map<String, Object?> r) {
    final stored = r['segment'] as String?;
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final at = r['received_at'] as int?;
    if (at == null) {
      return '';
    }
    return ShowSegmentUtils.labelForLocal(DateTime.fromMillisecondsSinceEpoch(at));
  }

  String _autoReplyLabel(String? code) {
    if (code == null || code.isEmpty) {
      return '';
    }
    switch (code) {
      case 'queued':
        return 'Auto-reply queued';
      case 'skipped_recent':
        return 'Auto-reply skipped (recent)';
      case 'skipped_no_template':
        return 'No template';
      case 'insufficient_balance':
        return 'Balance low';
      case 'failed_sender_row':
        return 'Sender error';
      case 'pending':
        return 'Processing…';
      default:
        return code;
    }
  }

  List<Map<String, Object?>> _applySegment(List<Map<String, Object?>> rows) {
    if (_segmentFilter == null) {
      return rows;
    }
    return rows.where((r) => _segmentForRow(r) == _segmentFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '${VllBranding.appTitle} · Inbox',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth > 900 ? 760.0 : c.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          if (_listenError != null)
            MaterialBanner(
              content: Text(_listenError!),
              actions: [
                TextButton(onPressed: () => setState(() => _listenError = null), child: const Text('Dismiss')),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('All segments'),
                  selected: _segmentFilter == null,
                  onSelected: (_) => setState(() => _segmentFilter = null),
                ),
                for (final label in ShowSegmentUtils.allLabels)
                  FilterChip(
                    label: Text(label.replaceAll(' show', '')),
                    selected: _segmentFilter == label,
                    onSelected: (_) => setState(() => _segmentFilter = label),
                  ),
              ],
            ),
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Messages are read from this phone’s SMS app, validated against your portal sender binding, '
                'and stored in the shared incoming log. Open the Compose tab in VLL SMS to manage segment auto-replies.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final rows = _applySegment(snap.data ?? []);
                if (rows.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _segmentFilter == null
                            ? 'No listener SMS yet.\nOpen this tab during a show so the app can listen and sync to the portal.'
                            : 'No messages in this segment.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final phone = r['sender'] as String? ?? '';
                      final body = r['body'] as String? ?? '';
                      final at = r['received_at'] as int?;
                      final synced = (r['synced'] as int? ?? 0) == 1;
                      final err = r['last_error'] as String?;
                      final portalSid = r['portal_sender_id'] as String?;
                      final seg = _segmentForRow(r);
                      final ar = r['auto_reply_status'] as String?;
                      return ListTile(
                        title: Text(phone, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (portalSid != null && portalSid.isNotEmpty)
                              Text('On-air sender ID: $portalSid', style: Theme.of(context).textTheme.labelSmall),
                            Text(body),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(seg.isEmpty ? 'Segment' : seg),
                                  backgroundColor: Colors.blue.shade50,
                                ),
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(synced ? 'Portal sync OK' : 'Pending sync'),
                                  backgroundColor: synced ? Colors.green.shade50 : Colors.orange.shade50,
                                ),
                                if (synced && ar != null && ar.isNotEmpty)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(_autoReplyLabel(ar)),
                                    backgroundColor: Colors.purple.shade50,
                                  ),
                                if (!synced && err != null && err.isNotEmpty)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(err, overflow: TextOverflow.ellipsis),
                                    backgroundColor: Colors.red.shade50,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Text(_fmtTime(at), style: Theme.of(context).textTheme.bodySmall),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ComposeScreen(prefillRecipient: phone),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
