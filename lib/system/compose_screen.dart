import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../services/desk_selection.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/portal_sender.dart';
import '../shared/sender_api_payload.dart';
import '../shared/themes.dart';
import '../widgets/toast.dart';

/// Reply desk: Inbox selection → template or compose → individual / bulk SMS.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    this.prefillRecipient,
    this.prefillChannel,
    this.prefillIncomingId,
    this.onOpenTab,
  });

  final String? prefillRecipient;
  final String? prefillChannel;
  final int? prefillIncomingId;
  final void Function(int index)? onOpenTab;

  @override
  State<ComposeScreen> createState() => ComposeScreenState();
}

class ComposeScreenState extends State<ComposeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _message = TextEditingController();
  final _tplTitle = TextEditingController();
  final _tplBody = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _submitting = false;
  bool _terms = false;
  bool _autoReplyEnabled = false;
  bool _manualReplyEnabled = true;
  bool _bulkSendEnabled = true;
  List<_SenderPick> _senders = [];
  _SenderPick? _selected;
  List<CapturedMessage> _deskPicks = [];
  List<Map<String, dynamic>> _templates = [];
  Map<String, dynamic>? _pickedTemplate;
  Map<String, dynamic>? _gateway;
  String? _preferredSenderId;
  int? _autoTemplateId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _applyPrefillFromWidget();
    _applyDeskSelection();
    DeskSelection.instance.replyTick.addListener(_onDeskTick);
    _bootstrap();
  }

  void _applyPrefillFromWidget() {
    final phone = widget.prefillRecipient?.trim();
    if (phone != null && phone.isNotEmpty) {
      final ch = (widget.prefillChannel ?? 'sms').toLowerCase();
      _deskPicks = [
        CapturedMessage(
          phone: phone,
          body: '',
          channel: ch == 'whatsapp' ? 'whatsapp' : 'sms',
          incomingId: widget.prefillIncomingId,
        ),
      ];
    }
  }

  void _applyDeskSelection() {
    final fromDesk = DeskSelection.instance.selected.value;
    if (fromDesk.isNotEmpty) {
      _deskPicks = List<CapturedMessage>.from(fromDesk);
    }
  }

  void _onDeskTick() {
    if (!mounted) return;
    setState(_applyDeskSelection);
  }

  /// Called from [MainShell] when user navigates from Inbox with a selection.
  void reloadFromDesk() {
    if (!mounted) return;
    setState(_applyDeskSelection);
    _tabs.animateTo(0);
  }

  @override
  void dispose() {
    DeskSelection.instance.replyTick.removeListener(_onDeskTick);
    _tabs.dispose();
    _message.dispose();
    _tplTitle.dispose();
    _tplBody.dispose();
    super.dispose();
  }

  Future<void> _safe(Future<void> f) =>
      f.timeout(const Duration(seconds: 8), onTimeout: () {});

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _safe(_loadSenders()),
        _safe(_loadTemplates()),
        _safe(_loadPrefs()),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSenders() async {
    try {
      final res = await ApiClient.instance
          .get(ApiConstants.sendersListPath)
          .timeout(const Duration(seconds: 8));
      ApiClient.ensureHttpAndEnvelopeSuccess(res);
      final data = ApiClient.responseData(res);
      final list = SenderApiPayload.extractSendersList(data);
      final picks =
          list.map(_SenderPick.fromDynamic).whereType<_SenderPick>().toList();
      if (!mounted) return;
      setState(() {
        _senders = picks;
        _selected = _pickPreferred(picks) ??
            (picks.isNotEmpty ? picks.first : null);
      });
    } catch (e) {
      if (mounted) showToast('Sender list: ${e.toString()}', error: true);
    }
  }

  _SenderPick? _pickPreferred(List<_SenderPick> picks) {
    final pref = _preferredSenderId;
    if (pref == null || pref.isEmpty) return null;
    for (final p in picks) {
      if (p.senderId.toLowerCase() == pref.toLowerCase()) return p;
    }
    return null;
  }

  Future<void> _loadPrefs() async {
    try {
      final res = await ApiClient.instance
          .get(ApiConstants.replyTemplatesPrefsPath)
          .timeout(const Duration(seconds: 8));
      ApiClient.ensureHttpAndEnvelopeSuccess(res);
      final data = ApiClient.responseData(res);
      if (data is! Map) return;
      final m = Map<String, dynamic>.from(data);
      if (!mounted) return;
      setState(() {
        _preferredSenderId = m['preferred_sender_id']?.toString();
        _autoReplyEnabled = m['auto_reply_enabled'] == true;
        _manualReplyEnabled = m['manual_reply_enabled'] != false;
        _bulkSendEnabled = m['bulk_send_enabled'] != false;
        final tid = m['auto_reply_template_id'];
        _autoTemplateId = tid is int
            ? tid
            : int.tryParse(tid?.toString() ?? '');
        final g = m['gateway'];
        _gateway = g is Map ? Map<String, dynamic>.from(g) : null;
        if (_senders.isNotEmpty) {
          _selected = _pickPreferred(_senders) ?? _selected ?? _senders.first;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadTemplates() async {
    try {
      final res = await ApiClient.instance
          .get(ApiConstants.replyTemplatesPath)
          .timeout(const Duration(seconds: 8));
      ApiClient.ensureHttpAndEnvelopeSuccess(res);
      final data = ApiClient.responseData(res);
      if (data is List) {
        if (!mounted) return;
        setState(() {
          _templates =
              data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (_) {}
  }

  void _applyTemplate(Map<String, dynamic> t) {
    final body = (t['body'] ?? '').toString();
    setState(() {
      _pickedTemplate = t;
      _message.text = body;
    });
  }

  void _removePick(CapturedMessage c) {
    setState(() {
      _deskPicks.removeWhere((p) => p.phone == c.phone);
    });
    DeskSelection.instance.set(_deskPicks);
  }

  Future<void> _savePrefs() async {
    final sel = _selected;
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.instance.postJson(
        ApiConstants.replyTemplatesPrefsPath,
        {
          'preferred_sender_id': sel?.senderId,
          'auto_reply_enabled': _autoReplyEnabled,
          'auto_reply_template_id': _autoTemplateId,
        },
      );
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Could not save SMS prefs');
      showToast('SMS integration prefs saved.');
      await _loadPrefs();
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveTemplate({int? id}) async {
    final title = _tplTitle.text.trim();
    final body = _tplBody.text.trim();
    if (title.isEmpty || body.isEmpty) {
      showToast('Title and message body required.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      if (id == null) {
        final res = await ApiClient.instance.postJson(
          ApiConstants.replyTemplatesPath,
          {
            'title': title,
            'body': body,
            'channel': 'any',
            'is_default': true,
            'use_as_auto_reply': _autoReplyEnabled,
          },
        );
        ApiClient.ensureHttpAndEnvelopeSuccess(res);
        showToast('Template saved.');
      } else {
        final res = await ApiClient.instance.putJson(
          ApiConstants.replyTemplateByIdPath(id),
          {
            'title': title,
            'body': body,
            'use_as_auto_reply': _autoReplyEnabled,
          },
        );
        ApiClient.ensureHttpAndEnvelopeSuccess(res);
        showToast('Template updated.');
      }
      _tplTitle.clear();
      _tplBody.clear();
      await _loadTemplates();
      await _loadPrefs();
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteTemplate(int id) async {
    try {
      final res =
          await ApiClient.instance.delete(ApiConstants.replyTemplateByIdPath(id));
      ApiClient.ensureHttpAndEnvelopeSuccess(res);
      showToast('Template deleted.');
      await _loadTemplates();
    } catch (e) {
      showToast(e.toString(), error: true);
    }
  }

  Future<void> _submitIndividual(CapturedMessage target) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_terms) {
      showToast('Accept the terms to send.', error: true);
      return;
    }
    if (!_manualReplyEnabled) {
      showToast('Manual reply is disabled in SMS settings.', error: true);
      return;
    }
    final sel = _selected;
    final to = target.phone.trim();
    if (sel == null) {
      showToast('Select a Sender ID.', error: true);
      return;
    }
    if (to.isEmpty) {
      showToast('No recipient phone.', error: true);
      return;
    }

    final channel = target.channel == 'whatsapp' ? 'whatsapp' : 'sms';
    setState(() => _submitting = true);
    try {
      final tid = _pickedTemplate == null
          ? null
          : int.tryParse((_pickedTemplate!['id'] ?? '').toString());
      final payload = <String, dynamic>{
        'from': normalizeOutgoingSenderId(sel.senderId),
        'message': _message.text.trim(),
        'to': to,
        'channel': channel,
        'reply_mode': tid != null ? 'template' : 'manual',
      };
      if (tid != null) payload['template_id'] = tid;
      if (target.incomingId != null && target.incomingId! > 0) {
        payload['in_reply_to_incoming_id'] = target.incomingId;
      }
      final res = await ApiClient.instance
          .postJson(ApiConstants.smsSendSinglePath, payload);
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
        body: _message.text.trim(),
        apiSuccess: success,
        apiMessage: srvMsg ?? ApiClient.errorMessageFromResponse(res),
        channel: channel,
        inReplyToIncomingId: target.incomingId,
      );
      if (!mounted) return;
      if (success) {
        showToast(srvMsg ??
            (channel == 'whatsapp'
                ? 'WhatsApp reply logged.'
                : 'SMS reply queued.'));
      } else {
        showToast(srvMsg ?? ApiClient.errorMessageFromResponse(res),
            error: true);
      }
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitBulk() async {
    if (!_terms) {
      showToast('Accept the terms to send.', error: true);
      return;
    }
    if (!_bulkSendEnabled) {
      showToast('Bulk send is disabled in SMS settings.', error: true);
      return;
    }
    final sel = _selected;
    final msg = _message.text.trim();
    if (sel == null) {
      showToast('Select a Sender ID.', error: true);
      return;
    }
    if (msg.isEmpty) {
      showToast('Compose a message or pick a template.', error: true);
      return;
    }
    if (_deskPicks.isEmpty) {
      showToast('Select captured messages in Inbox first.', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final tid = _pickedTemplate == null
          ? null
          : int.tryParse((_pickedTemplate!['id'] ?? '').toString());
      final recipients = _deskPicks.map((e) => e.phone).toList();
      final payload = <String, dynamic>{
        'from': normalizeOutgoingSenderId(sel.senderId),
        'message': msg,
        'recipients': recipients,
        'channel': 'sms',
        'reply_mode': tid != null ? 'template_bulk' : 'bulk_manual',
      };
      if (tid != null) payload['template_id'] = tid;
      final res = await ApiClient.instance
          .postJson(ApiConstants.smsSendBulkPath, payload);
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Bulk send failed');
      for (final to in recipients) {
        await LocalDatabase.instance.insertOutbound(
          recipient: to,
          senderId: normalizeOutgoingSenderId(sel.senderId),
          body: msg,
          apiSuccess: true,
          apiMessage: 'bulk',
          channel: 'sms',
        );
      }
      showToast('Bulk SMS queued for ${recipients.length} number(s).');
      DeskSelection.instance.clear();
      setState(() => _deskPicks = []);
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chars = _message.text.length;
    final parts = chars == 0 ? 0 : (chars / 160).ceil();
    final driver = (_gateway?['driver'] ?? '…').toString();
    final pickCount = _deskPicks.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('${VllBranding.appTitle} · Reply'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Send reply'),
            Tab(text: 'Templates'),
          ],
        ),
        actions: [
          if (widget.onOpenTab != null)
            TextButton(
              onPressed: () => widget.onOpenTab!(1),
              child: const Text('Inbox', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _integrationBanner(driver),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _replyTab(chars, parts, pickCount),
                      _templatesTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _integrationBanner(String driver) {
    return Material(
      color: const Color(0xFFF7F8FA),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            const Icon(Icons.sms, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gateway · $driver · Sender: ${_selected?.senderId ?? 'none'}'
                '${_autoReplyEnabled ? ' · auto-template ON' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: _submitting ? null : _savePrefs,
              child: const Text('Save sender'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _senderDropdown() {
    return DropdownButtonFormField<_SenderPick>(
      // ignore: deprecated_member_use
      value: _selected,
      items: _senders
          .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
          .toList(),
      onChanged: (v) => setState(() => _selected = v),
      decoration: const InputDecoration(
        labelText: 'Sender ID (SMS integration)',
        border: OutlineInputBorder(),
        helperText: 'Gateway credentials live in API .env — pick Sender ID here.',
      ),
    );
  }

  Widget _templateChips() {
    if (_templates.isEmpty) {
      return Text(
        'No templates yet — create one in the Templates tab.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _templates.map((t) {
        final title = (t['title'] ?? 'Template').toString();
        final selected = _pickedTemplate != null &&
            (_pickedTemplate!['id']?.toString() == t['id']?.toString());
        return ChoiceChip(
          label: Text(title),
          selected: selected,
          onSelected: (_) => _applyTemplate(t),
        );
      }).toList(),
    );
  }

  Widget _selectedFromInbox(int pickCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Selected from Inbox ($pickCount)',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (pickCount > 0)
              TextButton(
                onPressed: () {
                  DeskSelection.instance.clear();
                  setState(() => _deskPicks = []);
                },
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (pickCount == 0)
          OutlinedButton.icon(
            onPressed: () => widget.onOpenTab?.call(1),
            icon: const Icon(Icons.inbox_outlined),
            label: const Text('Select captured messages in Inbox'),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _deskPicks.map((c) {
              return InputChip(
                label: Text(c.displayTitle, style: const TextStyle(fontSize: 12)),
                onDeleted: () => _removePick(c),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _replyTab(int chars, int parts, int pickCount) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '1 · Pick captured numbers in Inbox. 2 · Tap a template or compose. '
            '3 · Send to one number or bulk to all selected.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _selectedFromInbox(pickCount),
          const SizedBox(height: 12),
          _senderDropdown(),
          const SizedBox(height: 12),
          Text('Reply template',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _templateChips(),
          const SizedBox(height: 12),
          TextFormField(
            controller: _message,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Compose reply (or edit template text)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a reply' : null,
          ),
          Text('$chars characters · ~$parts SMS part(s)'),
          CheckboxListTile(
            value: _terms,
            onChanged: (v) => setState(() => _terms = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I will use messaging responsibly.'),
          ),
          if (pickCount == 1) ...[
            SizedBox(
              height: 48,
              child: FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
                onPressed: _submitting || !_manualReplyEnabled
                    ? null
                    : () => _submitIndividual(_deskPicks.first),
                child: Text(_deskPicks.first.channel == 'whatsapp'
                    ? 'Send individual WhatsApp reply'
                    : 'Send individual SMS reply'),
              ),
            ),
          ],
          if (pickCount > 1) ...[
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
              onPressed: _submitting || !_bulkSendEnabled ? null : _submitBulk,
              child: Text('Send bulk SMS to $pickCount numbers'),
            ),
          ],
          if (pickCount == 0)
            Text(
              'Go to Inbox and select one or more captured messages to enable send.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
            ),
          const SizedBox(height: 16),
          Text(VllBranding.supportFootnoteLine,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.black45)),
        ],
      ),
    );
  }

  Widget _templatesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Create reply templates (CRUD). Use them on the Send reply tab for individual or bulk messages.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-reply captured messages with template'),
          subtitle: const Text(
              'When ON, new captures get this template via your Sender ID + env gateway.'),
          value: _autoReplyEnabled,
          onChanged: (v) => setState(() => _autoReplyEnabled = v),
        ),
        DropdownButtonFormField<int?>(
          // ignore: deprecated_member_use
          value: _autoTemplateId,
          decoration: const InputDecoration(
            labelText: 'Auto-reply template',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('None')),
            ..._templates.map((t) {
              final id = int.tryParse((t['id'] ?? '').toString());
              return DropdownMenuItem<int?>(
                value: id,
                child: Text((t['title'] ?? 'Template').toString()),
              );
            }),
          ],
          onChanged: (v) => setState(() => _autoTemplateId = v),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _submitting ? null : _savePrefs,
          child: const Text('Save auto-reply settings'),
        ),
        const Divider(height: 28),
        Text('New / edit template',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _tplTitle,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tplBody,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Message body',
            border: OutlineInputBorder(),
            hintText: 'Thanks for contacting us…',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submitting ? null : () => _saveTemplate(),
          child: const Text('Save template'),
        ),
        const SizedBox(height: 16),
        ..._templates.map((t) {
          final id = int.tryParse((t['id'] ?? '').toString());
          final title = (t['title'] ?? '').toString();
          final body = (t['body'] ?? '').toString();
          return Card(
            child: ListTile(
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle:
                  Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'use') {
                    _applyTemplate(t);
                    _tabs.animateTo(0);
                  }
                  if (v == 'edit') {
                    setState(() {
                      _tplTitle.text = title;
                      _tplBody.text = body;
                      _autoTemplateId = id;
                    });
                  }
                  if (v == 'delete' && id != null) _deleteTemplate(id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'use', child: Text('Use in reply')),
                  PopupMenuItem(value: 'edit', child: Text('Load to edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
              onTap: () {
                _applyTemplate(t);
                _tabs.animateTo(0);
              },
            ),
          );
        }),
      ],
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
      final sid = normalizeOutgoingSenderId((m['sender_id'] ?? '').toString());
      if (sid.isEmpty) return null;
      return _SenderPick(senderId: sid, label: sid);
    }
    return null;
  }
}
