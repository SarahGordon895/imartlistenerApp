import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/portal_sender.dart';
import '../shared/sender_api_payload.dart';
import '../shared/themes.dart';
import '../widgets/toast.dart';

/// Show block for radio: tags templates for KPIs (SMS participation per segment).
enum RadioShowSegment {
  custom,
  morning,
  afternoon,
  evening,
  night,
}

extension on RadioShowSegment {
  String get menuLabel {
    switch (this) {
      case RadioShowSegment.custom:
        return 'Custom (set times manually)';
      case RadioShowSegment.morning:
        return 'Morning show';
      case RadioShowSegment.afternoon:
        return 'Afternoon show';
      case RadioShowSegment.evening:
        return 'Evening show';
      case RadioShowSegment.night:
        return 'Night show';
    }
  }

  /// Stored on server for reporting; null for custom.
  String? get apiTag {
    switch (this) {
      case RadioShowSegment.custom:
        return null;
      case RadioShowSegment.morning:
        return 'Morning show';
      case RadioShowSegment.afternoon:
        return 'Afternoon show';
      case RadioShowSegment.evening:
        return 'Evening show';
      case RadioShowSegment.night:
        return 'Night show';
    }
  }

  /// Suggested on-air start (EAT); end is set via segment length (e.g. 45 min).
  TimeOfDay get defaultStart {
    switch (this) {
      case RadioShowSegment.custom:
        return const TimeOfDay(hour: 8, minute: 0);
      case RadioShowSegment.morning:
        return const TimeOfDay(hour: 6, minute: 0);
      case RadioShowSegment.afternoon:
        return const TimeOfDay(hour: 12, minute: 0);
      case RadioShowSegment.evening:
        return const TimeOfDay(hour: 18, minute: 0);
      case RadioShowSegment.night:
        return const TimeOfDay(hour: 22, minute: 0);
    }
  }
}

/// **Compose** tab (VLL SMS / `vll_sms`): segment auto-replies (time windows) + optional one-off reply from Inbox.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.prefillRecipient, this.onOpenTab});

  final String? prefillRecipient;

  /// Switch main shell tab: 0 Home, 1 Compose, 2 Inbox, 3 Polls, 4 Audience.
  final void Function(int index)? onOpenTab;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _oneOffMessage = TextEditingController();
  final _templateMessage = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loadingSenders = true;
  bool _submitting = false;
  List<_SenderPick> _senders = [];
  _SenderPick? _selected;

  bool _terms = false;

  String? _replyTo;

  RadioShowSegment _showSegment = RadioShowSegment.custom;
  TimeOfDay _autoStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _autoEnd;
  bool _autoSaving = false;
  bool _autoLoading = true;
  List<Map<String, dynamic>> _autoRows = [];
  int _autoLoadToken = 0;
  int? _editingAutoReplyId;

  @override
  void initState() {
    super.initState();
    _replyTo = widget.prefillRecipient?.trim().isNotEmpty == true
        ? widget.prefillRecipient!.trim()
        : null;
    _loadSenders();
  }

  @override
  void dispose() {
    _oneOffMessage.dispose();
    _templateMessage.dispose();
    super.dispose();
  }

  void _applyEndFromStartMinutes(int minutes) {
    final startM = _autoStart.hour * 60 + _autoStart.minute;
    final endM = startM + minutes;
    final wrapped = endM % (24 * 60);
    _autoEnd = TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }

  void _applyShowSegment(RadioShowSegment seg) {
    setState(() {
      _showSegment = seg;
      if (seg == RadioShowSegment.custom) {
        return;
      }
      _autoStart = seg.defaultStart;
      _applyEndFromStartMinutes(45);
    });
  }

  Future<void> _loadSenders() async {
    setState(() => _loadingSenders = true);
    try {
      final res = await ApiClient.instance.get(ApiConstants.sendersListPath);
      ApiClient.ensureHttpAndEnvelopeSuccess(
        res,
        fallbackPrefix: 'Could not load sender IDs',
      );
      final data = ApiClient.responseData(res);
      final list = SenderApiPayload.extractSendersList(data);
      final currentSender = SenderApiPayload.extractCurrentSenderId(data);
      await LocalDatabase.instance.replacePortalSendersFromApi(list);
      _commitSenderPicks(list, currentSender);
      if (!mounted) return;
      if (_senders.isEmpty) {
        showToast(
          'No Active sender IDs from SMSver1. Add or approve them in the portal.',
          error: true,
        );
      }
      await _loadAutoReplies();
    } catch (e) {
      final rows = await LocalDatabase.instance.listPortalSenders();
      _commitSenderPicks(rows, null);
      if (!mounted) return;
      if (_senders.isEmpty) {
        showToast('Could not load sender IDs: $e', error: true);
      } else {
        showToast('Using last synced sender IDs from SMSver1 (API unavailable).', error: false);
      }
      await _loadAutoReplies();
    }
  }

  void _commitSenderPicks(List<dynamic> list, String? currentSender) {
    final picks =
        list.map(_SenderPick.fromDynamic).whereType<_SenderPick>().toList();
    _SenderPick? selected;
    if (currentSender != null) {
      for (final p in picks) {
        if (p.senderId == currentSender) {
          selected = p;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _senders = picks;
      _selected = selected ?? (picks.isNotEmpty ? picks.first : null);
      _loadingSenders = false;
    });
  }

  String _fmtTimeApi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  TimeOfDay? _parseTimeOfDay(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final p = s.trim().split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  RadioShowSegment _segmentFromStored(String? seg) {
    if (seg == null || seg.isEmpty) return RadioShowSegment.custom;
    for (final v in RadioShowSegment.values) {
      if (v.apiTag != null && v.apiTag == seg) return v;
    }
    return RadioShowSegment.custom;
  }

  void _beginEditAutoRow(Map<String, dynamic> r) {
    final id = r['id'];
    final int? eid = id is int
        ? id
        : (id is num ? id.toInt() : int.tryParse(id?.toString() ?? ''));
    if (eid == null) return;
    final start = _parseTimeOfDay(r['scheduled_time']?.toString());
    final end = _parseTimeOfDay(r['end_schedule']?.toString());
    setState(() {
      _editingAutoReplyId = eid;
      _templateMessage.text = r['reply']?.toString() ?? '';
      if (start != null) _autoStart = start;
      _autoEnd = end;
      _showSegment = _segmentFromStored(r['segment']?.toString());
    });
    showToast('Editing template — save to update.');
  }

  String _fmtUi(String? t) {
    if (t == null || t.isEmpty) return 'All day';
    final p = t.split(':');
    if (p.length < 2) return t;
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }

  Future<void> _loadAutoReplies() async {
    final int token = ++_autoLoadToken;
    final sel = _selected;
    if (sel == null) {
      if (mounted) {
        setState(() {
          _autoRows = [];
          _autoLoading = false;
        });
      }
      return;
    }
    setState(() => _autoLoading = true);
    try {
      final res = await ApiClient.instance.get(
        ApiConstants.autoReplyListPath,
        query: {
          'sender_id': normalizeOutgoingSenderId(sel.senderId),
          'per_page': '200',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
      final raw = ApiClient.responseData(res);
      List<dynamic> list = const [];
      if (raw is List) {
        list = raw;
      } else if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        final inner = m['data'];
        if (inner is List) {
          list = inner;
        } else if (inner is Map) {
          final d = Map<String, dynamic>.from(inner);
          final maybe = d['data'];
          if (maybe is List) list = maybe;
        }
      }
      if (!mounted || token != _autoLoadToken) return;
      setState(() {
        _autoRows =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      if (!mounted || token != _autoLoadToken) return;
      setState(() => _autoRows = []);
      showToast('Could not load saved templates: $e', error: true);
    } finally {
      if (mounted && token == _autoLoadToken) {
        setState(() => _autoLoading = false);
      }
    }
  }

  Future<void> _pickAutoStart() async {
    final picked =
        await showTimePicker(context: context, initialTime: _autoStart);
    if (picked != null) {
      setState(() {
        _autoStart = picked;
        _showSegment = RadioShowSegment.custom;
      });
    }
  }

  Future<void> _pickAutoEnd() async {
    final current = _autoEnd ?? _autoStart;
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked != null) {
      setState(() {
        _autoEnd = picked;
        _showSegment = RadioShowSegment.custom;
      });
    }
  }

  Future<void> _saveTemplate() async {
    if (!_terms) {
      showToast('Accept the terms to save an auto-reply template.',
          error: true);
      return;
    }
    if (_showSegment.apiTag != null && _autoEnd == null) {
      showToast(
        'Named show segments need an end time (e.g. 09:00–10:00) so auto-reply stops when the block ends — same rules as SMSver1.',
        error: true,
      );
      return;
    }
    final msg = _templateMessage.text.trim();
    if (msg.isEmpty) {
      showToast('Enter the template message.', error: true);
      return;
    }
    final sel = _selected;
    if (sel == null) {
      showToast('Select a sender ID first.', error: true);
      return;
    }
    setState(() => _autoSaving = true);
    try {
      final body = <String, dynamic>{
        'sender_id': normalizeOutgoingSenderId(sel.senderId),
        'reply': msg,
        'time_schedule': _fmtTimeApi(_autoStart),
      };
      if (_autoEnd != null) body['end_schedule'] = _fmtTimeApi(_autoEnd!);
      body['segment'] = _showSegment.apiTag;

      final editId = _editingAutoReplyId;
      final res = editId != null
          ? await ApiClient.instance
              .putJson('${ApiConstants.autoReplyUpdatePath}/$editId', body)
          : await ApiClient.instance
              .postJson(ApiConstants.autoReplyCreatePath, body);
      if (res.statusCode < 200 ||
          res.statusCode >= 300 ||
          !ApiClient.isSuccess(res)) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
      if (!mounted) return;
      _templateMessage.clear();
      setState(() {
        _autoEnd = null;
        _editingAutoReplyId = null;
      });
      showToast(editId != null ? 'Template updated.' : 'Template saved.');
      await _loadAutoReplies();
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _autoSaving = false);
    }
  }

  Future<void> _deleteAuto(dynamic id) async {
    if (id == null) return;
    final int? did =
        id is int ? id : (id is num ? id.toInt() : int.tryParse(id.toString()));
    try {
      final res = await ApiClient.instance
          .delete('${ApiConstants.autoReplyDeletePath}/$id');
      if (res.statusCode < 200 ||
          res.statusCode >= 300 ||
          !ApiClient.isSuccess(res)) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
      if (!mounted) return;
      if (did != null && did == _editingAutoReplyId) {
        setState(() {
          _editingAutoReplyId = null;
          _templateMessage.clear();
        });
      }
      final hint = ApiClient.successMessageFromResponse(res);
      showToast(
        hint ??
            'Template removed here. It stays archived on SMSver1 until an admin purges it.',
      );
      await _loadAutoReplies();
    } catch (e) {
      showToast(e.toString(), error: true);
    }
  }

  Future<void> _submitOneOffSend() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_terms) {
      showToast('Accept the terms to send.', error: true);
      return;
    }
    final sel = _selected;
    if (sel == null) {
      showToast('Select a sender ID.', error: true);
      return;
    }
    final to = _replyTo;
    if (to == null || to.isEmpty) {
      showToast('Open Inbox and tap a message to reply.', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final res =
          await ApiClient.instance.postJson(ApiConstants.smsSendSinglePath, {
        'from': normalizeOutgoingSenderId(sel.senderId),
        'message': _oneOffMessage.text.trim(),
        'to': to,
      });

      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final decoded = ApiClient.decodeBody(res);
      var success = ok;
      String? srvMsg;
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        if (m['success'] == false) success = false;
        srvMsg = m['message']?.toString();
      }

      await LocalDatabase.instance.insertOutbound(
        recipient: to,
        senderId: normalizeOutgoingSenderId(sel.senderId),
        body: _oneOffMessage.text.trim(),
        apiSuccess: success,
        apiMessage: srvMsg ?? ApiClient.errorMessageFromResponse(res),
      );

      if (!mounted) return;
      if (success) {
        showToast(srvMsg ?? 'Message queued.');
        _oneOffMessage.clear();
      } else {
        showToast(srvMsg ?? ApiClient.errorMessageFromResponse(res),
            error: true);
      }
    } on TimeoutException {
      showToast('Send timed out. Try again.', error: true);
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tplChars = _templateMessage.text.length;
    final tplParts = (tplChars / 160).ceil();
    final oneOffChars = _oneOffMessage.text.length;
    final oneOffParts = (oneOffChars / 160).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '${VllBranding.appTitle} · Compose',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth > 960 ? 880.0 : c.maxWidth;
          final narrow = c.maxWidth < 420;
          final hPad = narrow ? 14.0 : (c.maxWidth > 800 ? 28.0 : 20.0);
          final bottomPad = MediaQuery.paddingOf(context).bottom;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24 + bottomPad),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_loadingSenders)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else
                        DropdownButtonFormField<_SenderPick>(
                          // ignore: deprecated_member_use
                          value: _selected,
                          items: _senders
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e.label,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selected = v);
                            _loadAutoReplies();
                          },
                          decoration: const InputDecoration(
                            labelText: 'On-air sender ID',
                            border: OutlineInputBorder(),
                            helperText: VllBranding.senderListPortalHint,
                          ),
                          validator: (v) =>
                              v == null ? 'Select sender ID' : null,
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _loadingSenders ? null : _loadSenders,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh sender IDs'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE6E8ED)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'On-air auto-reply (incoming)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.lushDark,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Set time windows and automatic SMS replies when listeners text your '
                                'on-air sender ID (SMSver1 auto-reply flow). '
                                'Mass / bulk SMS campaigns belong in the SMSver1 portal — not here.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.black87,
                                      height: 1.35,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<RadioShowSegment>(
                        // ignore: deprecated_member_use
                        value: _showSegment,
                        decoration: const InputDecoration(
                          labelText: 'Show segment',
                          border: OutlineInputBorder(),
                          helperText:
                              'Pick a block to apply typical start time + 45 min window (EAT). Choose Custom to edit times only.',
                        ),
                        items: RadioShowSegment.values
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.menuLabel),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) _applyShowSegment(v);
                        },
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _terms,
                        onChanged: (v) => setState(() => _terms = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'I agree to use SMS responsibly and comply with applicable laws and the portal terms.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Segment auto-reply',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _templateMessage,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText:
                              'Message listeners receive automatically during the window',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$tplChars characters · ~$tplParts SMS part(s)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickAutoStart,
                              child: Text(
                                  'Active from ${_fmtUi(_fmtTimeApi(_autoStart))}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickAutoEnd,
                              child: Text(
                                  'Until ${_fmtUi(_autoEnd == null ? null : _fmtTimeApi(_autoEnd!))}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Segment length from start (typical live block)',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [15, 30, 45, 60].map((m) {
                          return ActionChip(
                            label: Text('$m min'),
                            onPressed: () {
                              setState(() {
                                _showSegment = RadioShowSegment.custom;
                                _applyEndFromStartMinutes(m);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _autoEnd = null;
                          _showSegment = RadioShowSegment.custom;
                        }),
                        child: const Text(
                            'No end time (all day from start — use with care)'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Africa/Nairobi (EAT), 24-hour times — same as SMSver1. '
                        'The incoming message time must fall inside your start–end window and match the show segment label for this reply to send.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      if (widget.onOpenTab != null) ...[
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE6E8ED)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Audience tools',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Open Polls or Audience (social checks) from here.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          widget.onOpenTab?.call(3),
                                      icon: const Icon(Icons.how_to_vote_outlined,
                                          size: 18),
                                      label: const Text('Polls'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          widget.onOpenTab?.call(4),
                                      icon: const Icon(Icons.manage_search_outlined,
                                          size: 18),
                                      label: const Text('Audience'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_editingAutoReplyId != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _autoSaving
                                ? null
                                : () {
                                    setState(() {
                                      _editingAutoReplyId = null;
                                      _templateMessage.clear();
                                    });
                                  },
                            child: const Text('Discard edit · new template'),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.lushRed),
                          onPressed: _autoSaving ? null : _saveTemplate,
                          child: _autoSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_editingAutoReplyId != null
                                  ? 'Update segment template'
                                  : 'Save segment template'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Text(
                            'Saved templates (this sender ID)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _loadAutoReplies,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh list',
                          ),
                        ],
                      ),
                      if (_autoLoading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_autoRows.isEmpty)
                        Text(
                          _selected == null
                              ? 'Select a sender ID to load templates.'
                              : 'No segment templates yet.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else ...[
                        Text(
                          'Tap a row to edit; trash removes it from the app and archives it on SMSver1.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        ..._autoRows.map(
                          (r) {
                            final seg = r['segment']?.toString();
                            final timeLine =
                                '${_fmtUi(r['scheduled_time']?.toString())} – ${_fmtUi(r['end_schedule']?.toString())}';
                            return Card(
                              child: ListTile(
                                title: Text(r['reply']?.toString() ?? ''),
                                subtitle: Text(
                                  seg != null && seg.isNotEmpty
                                      ? '$seg · $timeLine'
                                      : timeLine,
                                ),
                                onTap: () => _beginEditAutoRow(
                                    Map<String, dynamic>.from(r)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteAuto(r['id']),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      if (_replyTo != null) ...[
                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Text(
                          'One-off reply (this Inbox thread)',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Same sender ID and terms as above. Does not replace segment auto-reply.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _oneOffMessage,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Reply message',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Enter the reply message';
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$oneOffChars characters · ~$oneOffParts SMS part(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _submitting ? null : _submitOneOffSend,
                            child: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Send reply now'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        VllBranding.supportFootnoteLine,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SenderPick {
  _SenderPick({required this.senderId, required this.label});

  final String senderId;
  final String label;

  static _SenderPick? fromDynamic(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final sid = normalizeOutgoingSenderId(raw);
      if (sid.isEmpty) return null;
      return _SenderPick(senderId: sid, label: sid);
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
      return _SenderPick(senderId: sid, label: label);
    }
    return null;
  }
}
