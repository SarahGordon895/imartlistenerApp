import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../services/desk_selection.dart';
import '../services/notification_capture_service.dart';
import '../services/sms_inbound_listener.dart';
import '../shared/branding.dart';

/// Business inbox: SMS + WhatsApp captures → select → Reply or Social lookup.
class IncomingMessagesScreen extends StatefulWidget {
  const IncomingMessagesScreen({
    super.key,
    this.isActive = false,
    this.onOpenSocialLookup,
    this.onOpenReply,
  });

  final bool isActive;
  final void Function({String? phone})? onOpenSocialLookup;
  final void Function(List<CapturedMessage> picks)? onOpenReply;

  @override
  State<IncomingMessagesScreen> createState() => _IncomingMessagesScreenState();
}

class _IncomingMessagesScreenState extends State<IncomingMessagesScreen> {
  Future<List<Map<String, Object?>>>? _future;
  String? _listenError;
  String? _channelFilter;
  String? _replyFilter;
  StreamSubscription<void>? _messageSub;
  StreamSubscription<String?>? _errorSub;
  StreamSubscription<void>? _notifSub;
  bool _notifEnabled = true;
  bool _privacyShown = false;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _reload();
    SmsInboundListener.instance.ensureStarted();
    NotificationCaptureService.instance.ensureStarted();
    _listenError = SmsInboundListener.instance.lastError ??
        NotificationCaptureService.instance.lastError;
    _messageSub = SmsInboundListener.instance.onMessage.listen((_) {
      if (mounted) _reload();
    });
    _notifSub = NotificationCaptureService.instance.onMessage.listen((_) {
      if (mounted) _reload();
    });
    _errorSub = SmsInboundListener.instance.onError.listen((err) {
      if (!mounted) return;
      setState(() => _listenError = err);
    });
    _refreshNotifStatus();
    if (widget.isActive) _maybeShowPrivacy();
  }

  @override
  void didUpdateWidget(IncomingMessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _maybeShowPrivacy();
      _refreshNotifStatus();
      _reload();
    }
  }

  Future<void> _refreshNotifStatus() async {
    final ok = await NotificationCaptureService.instance.isEnabled();
    if (!mounted) return;
    setState(() => _notifEnabled = ok);
  }

  Future<void> _maybeShowPrivacy() async {
    if (_privacyShown || !mounted) return;
    _privacyShown = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Business message capture'),
        content: const Text(
          'This phone captures customer SMS and (with Notification access) WhatsApp messages, '
          'then syncs them to imartPortal for manual reply. Select messages → Reply tab → template or compose.',
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
    _notifSub?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = LocalDatabase.instance
          .listInboundRecent(limit: 300)
          .timeout(const Duration(seconds: 6), onTimeout: () => <Map<String, Object?>>[]);
    });
  }

  CapturedMessage _toCaptured(Map<String, Object?> r) {
    return CapturedMessage(
      phone: (r['sender'] as String? ?? '').trim(),
      body: (r['body'] as String? ?? '').trim(),
      channel: (r['channel'] as String? ?? 'sms'),
      incomingId: r['server_incoming_id'] as int?,
      localId: r['id'] as int?,
      contactName: r['contact_name'] as String?,
    );
  }

  List<CapturedMessage> _selectedFromRows(List<Map<String, Object?>> rows) {
    final out = <CapturedMessage>[];
    for (final r in rows) {
      final id = r['id'] as int?;
      if (id != null && _selectedIds.contains(id)) {
        out.add(_toCaptured(r));
      }
    }
    return out;
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(Map<String, Object?> r) {
    final id = r['id'] as int?;
    if (id == null) return;
    setState(() {
      _selectMode = true;
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _openReplyFor(List<CapturedMessage> picks) {
    if (picks.isEmpty) return;
    widget.onOpenReply?.call(picks);
    _exitSelectMode();
  }

  void _openReplySingle(Map<String, Object?> r) {
    _openReplyFor([_toCaptured(r)]);
  }

  String _fmtTime(int? ms) {
    if (ms == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _replyLabel(Map<String, Object?> r) {
    final status = (r['reply_status'] as String?) ?? '';
    final ar = (r['auto_reply_status'] as String?) ?? '';
    if (status == 'replied' || ar == 'manual_replied') return 'Replied';
    return 'Needs reply';
  }

  Widget _metaPill(String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  List<Map<String, Object?>> _applyFilters(List<Map<String, Object?>> rows) {
    var out = rows;
    if (_channelFilter != null) {
      out = out
          .where((r) => (r['channel'] as String? ?? 'sms') == _channelFilter)
          .toList();
    }
    if (_replyFilter != null) {
      out = out.where((r) {
        final label = _replyLabel(r).toLowerCase();
        if (_replyFilter == 'awaiting_reply') return label.contains('needs');
        return label.contains('replied');
      }).toList();
    }
    return out;
  }

  Future<void> _openSenderActions(Map<String, Object?> r) async {
    final phone = (r['sender'] as String? ?? '').trim();
    final name = (r['contact_name'] as String?)?.trim();
    final channel = (r['channel'] as String? ?? 'sms');
    final body = (r['body'] as String? ?? '').trim();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('From phone',
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  phone.isEmpty ? 'Unknown number' : phone,
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                ),
                if (name != null && name.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(name, style: Theme.of(ctx).textTheme.titleMedium),
                ],
                const SizedBox(height: 6),
                Text(
                  '${channel == 'whatsapp' ? 'WhatsApp' : 'SMS'} · captured on this phone',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(body, maxLines: 4, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openReplySingle(r);
                  },
                  icon: const Icon(Icons.reply),
                  label: const Text('Reply (template / compose)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: phone.isEmpty
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          widget.onOpenSocialLookup?.call(phone: phone);
                        },
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Social lookup (IG / FB)'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode
            ? '${VllBranding.appTitle} · ${_selectedIds.length} selected'
            : '${VllBranding.appTitle} · Inbox'),
        actions: [
          if (_selectMode) ...[
            TextButton(
              onPressed: _exitSelectMode,
              child: const Text('Cancel', style: TextStyle(color: Colors.white)),
            ),
            IconButton(
              tooltip: 'Reply to selected',
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () async {
                      final snap = await _future;
                      if (!mounted) return;
                      _openReplyFor(_selectedFromRows(snap ?? []));
                    },
              icon: const Icon(Icons.reply),
            ),
          ] else
            IconButton(
              tooltip: 'Select messages',
              onPressed: () => setState(() => _selectMode = true),
              icon: const Icon(Icons.checklist),
            ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_listenError != null)
            MaterialBanner(
              content: Text(_listenError!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _listenError = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          if (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              !_notifEnabled)
            MaterialBanner(
              content: const Text(
                'Enable Notification access to capture WhatsApp for this business phone.',
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await NotificationCaptureService.instance.openSettings();
                    await Future<void>.delayed(const Duration(seconds: 1));
                    await _refreshNotifStatus();
                    await NotificationCaptureService.instance.ensureStarted();
                  },
                  child: const Text('Enable'),
                ),
              ],
            ),
          if (_selectMode)
            Material(
              color: const Color(0xFFE8F4FF),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Tap messages to select. Then use Reply → pick a template or compose → send individual or bulk.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _channelFilter == null && _replyFilter == null,
                  onSelected: (_) => setState(() {
                    _channelFilter = null;
                    _replyFilter = null;
                  }),
                ),
                FilterChip(
                  label: const Text('SMS'),
                  selected: _channelFilter == 'sms',
                  onSelected: (_) => setState(() => _channelFilter = 'sms'),
                ),
                FilterChip(
                  label: const Text('WhatsApp'),
                  selected: _channelFilter == 'whatsapp',
                  onSelected: (_) => setState(() => _channelFilter = 'whatsapp'),
                ),
                FilterChip(
                  label: const Text('Needs reply'),
                  selected: _replyFilter == 'awaiting_reply',
                  onSelected: (v) =>
                      setState(() => _replyFilter = v ? 'awaiting_reply' : null),
                ),
                FilterChip(
                  label: const Text('Replied'),
                  selected: _replyFilter == 'replied',
                  onSelected: (v) => setState(() => _replyFilter = v ? 'replied' : null),
                ),
              ],
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
                final rows = _applyFilters(snap.data ?? []);
                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No customer messages yet.\nSMS and WhatsApp captures will show here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final id = r['id'] as int?;
                      final phone = r['sender'] as String? ?? '';
                      final name = r['contact_name'] as String?;
                      final body = r['body'] as String? ?? '';
                      final channel = (r['channel'] as String? ?? 'sms');
                      final synced = (r['synced'] as int? ?? 0) == 1;
                      final reply = _replyLabel(r);
                      final selected = id != null && _selectedIds.contains(id);
                      return ListTile(
                        selected: selected,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: _selectMode
                            ? Checkbox(
                                value: selected,
                                onChanged: (_) => _toggleSelect(r),
                              )
                            : CircleAvatar(
                                backgroundColor: channel == 'whatsapp'
                                    ? const Color(0xFF25D366)
                                    : const Color(0xFF0B2C5F),
                                child: Icon(
                                  channel == 'whatsapp' ? Icons.chat : Icons.sms,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                phone.isEmpty
                                    ? (name?.isNotEmpty == true ? name! : 'Unknown sender')
                                    : phone,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            Text(
                              _fmtTime(r['received_at'] as int?),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.black54,
                                  ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (name != null &&
                                name.isNotEmpty &&
                                phone.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(name,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                            const SizedBox(height: 2),
                            Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _metaPill(
                                  channel == 'whatsapp' ? 'WhatsApp' : 'SMS',
                                  channel == 'whatsapp'
                                      ? const Color(0xFFE8F8EF)
                                      : const Color(0xFFEEF2F7),
                                ),
                                const SizedBox(width: 6),
                                _metaPill(
                                  reply,
                                  reply.contains('Needs')
                                      ? const Color(0xFFFFF4E5)
                                      : const Color(0xFFE8F8EF),
                                ),
                                const SizedBox(width: 6),
                                _metaPill(
                                  synced ? 'Synced' : 'Pending',
                                  synced
                                      ? const Color(0xFFEAF2FF)
                                      : const Color(0xFFF2F4F7),
                                ),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: _selectMode
                            ? null
                            : IconButton(
                                tooltip: 'Social lookup',
                                onPressed: phone.isEmpty
                                    ? null
                                    : () => widget.onOpenSocialLookup
                                        ?.call(phone: phone),
                                icon: const Icon(Icons.travel_explore),
                              ),
                        onTap: () {
                          if (_selectMode) {
                            _toggleSelect(r);
                          } else {
                            _openSenderActions(r);
                          }
                        },
                        onLongPress: () {
                          if (!_selectMode) {
                            _toggleSelect(r);
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (_selectMode && _selectedIds.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final snap = await _future;
                    if (!mounted) return;
                    _openReplyFor(_selectedFromRows(snap ?? []));
                  },
                  icon: const Icon(Icons.reply),
                  label: Text(
                    _selectedIds.length == 1
                        ? 'Reply to 1 number'
                        : 'Bulk reply to ${_selectedIds.length} numbers',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
