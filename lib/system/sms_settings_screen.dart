import 'package:flutter/material.dart';

import '../packages/http_requests.dart';
import '../services/listen_keyword_service.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../shared/portal_sender.dart';
import '../shared/sender_api_payload.dart';
import '../shared/themes.dart';
import '../widgets/toast.dart';

/// Client SMS desk toggles + gateway status (credentials stay in API .env).
class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _manual = true;
  bool _bulk = true;
  bool _portal = true;
  bool _auto = false;
  bool _keywordEnabled = true;
  String? _preferredSender;
  int? _autoTplId;
  Map<String, dynamic> _gateway = {};
  List<String> _senders = [];
  Set<String> _listenSenderIds = {};
  List<Map<String, dynamic>> _templates = [];
  final _newSender = TextEditingController();
  final _newSenderNote = TextEditingController();
  final _listenKeyword = TextEditingController();
  final _fromNumbers = TextEditingController();
  final _preferredCustom = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newSender.dispose();
    _newSenderNote.dispose();
    _listenKeyword.dispose();
    _fromNumbers.dispose();
    _preferredCustom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefsRes =
          await ApiClient.instance.get(ApiConstants.replyTemplatesPrefsPath);
      ApiClient.ensureHttpAndEnvelopeSuccess(prefsRes);
      final prefs = ApiClient.responseData(prefsRes);
      if (prefs is Map) {
        final m = Map<String, dynamic>.from(prefs);
        _manual = m['manual_reply_enabled'] != false;
        _bulk = m['bulk_send_enabled'] != false;
        _portal = m['portal_reply_enabled'] != false;
        _auto = m['auto_reply_enabled'] == true;
        _keywordEnabled = m['listen_keyword_enabled'] == true ||
            m['listen_keyword_enabled'] == 1 ||
            m['listen_keyword_enabled'] == '1';
        final kwList = m['listen_keywords'];
        if (kwList is List && kwList.isNotEmpty) {
          _listenKeyword.text =
              kwList.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join('\n');
        } else {
          _listenKeyword.text = (m['listen_keyword']?.toString() ?? '').trim();
        }
        _keywordEnabled =
            _keywordEnabled && _listenKeyword.text.trim().isNotEmpty;
        final from = m['listen_from_numbers'];
        if (from is List) {
          _fromNumbers.text = from.map((e) => e.toString()).join('\n');
        } else {
          _fromNumbers.text = (from?.toString() ?? '').trim();
        }
        final lids = m['listen_sender_ids'];
        _listenSenderIds = {
          if (lids is List)
            ...lids
                .map((e) => normalizeOutgoingSenderId(e.toString()))
                .where((e) => e.isNotEmpty),
        };
        _preferredSender = m['preferred_sender_id']?.toString();
        final tid = m['auto_reply_template_id'];
        _autoTplId = tid is int ? tid : int.tryParse(tid?.toString() ?? '');
        final g = m['gateway'];
        if (g is Map) _gateway = Map<String, dynamic>.from(g);
        await ListenKeywordService.instance.cacheFromPrefsMap(m);
      }
      final sendRes = await ApiClient.instance.get(ApiConstants.sendersListPath);
      ApiClient.ensureHttpAndEnvelopeSuccess(sendRes);
      final sdata = ApiClient.responseData(sendRes);
      final list = SenderApiPayload.extractSendersList(sdata);
      _senders = list
          .map((e) => normalizeOutgoingSenderId(
              (e is Map ? (e['sender_id'] ?? '') : e).toString()))
          .where((e) => e.isNotEmpty)
          .toList();
      final prefNorm = normalizeOutgoingSenderId(_preferredSender ?? '');
      if (prefNorm.isNotEmpty && !_senders.contains(prefNorm)) {
        _preferredCustom.text = prefNorm;
        _preferredSender = null;
      } else {
        _preferredCustom.clear();
        _preferredSender = prefNorm.isEmpty ? null : prefNorm;
      }
      final tplRes = await ApiClient.instance.get(ApiConstants.replyTemplatesPath);
      ApiClient.ensureHttpAndEnvelopeSuccess(tplRes);
      final tdata = ApiClient.responseData(tplRes);
      if (tdata is List) {
        _templates = tdata.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      if (mounted) showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final custom = normalizeOutgoingSenderId(_preferredCustom.text.trim());
      final preferred = custom.isNotEmpty
          ? custom
          : (_preferredSender == null || _preferredSender!.isEmpty
              ? null
              : normalizeOutgoingSenderId(_preferredSender!));
      // Do not POST listen_* here — portal SMS settings owns those fields.
      final res = await ApiClient.instance.postJson(
        ApiConstants.replyTemplatesPrefsPath,
        {
          'preferred_sender_id': preferred,
          'manual_reply_enabled': _manual,
          'bulk_send_enabled': _bulk,
          'portal_reply_enabled': _portal,
          'auto_reply_enabled': _auto,
          'auto_reply_template_id': _autoTplId,
        },
      );
      ApiClient.ensureHttpAndEnvelopeSuccess(res, fallbackPrefix: 'Save failed');
      showToast('Desk settings saved.');
      await _load();
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addSender() async {
    final sid = normalizeOutgoingSenderId(_newSender.text.trim());
    if (sid.isEmpty) {
      showToast('Enter Sender ID name.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await ApiClient.instance.postJson(
        ApiConstants.sendersCreatePath,
        {'sender_id': sid, 'message': _newSenderNote.text.trim()},
      );
      ApiClient.ensureHttpAndEnvelopeSuccess(res, fallbackPrefix: 'Add failed');
      _newSender.clear();
      _newSenderNote.clear();
      showToast('Sender ID registered.');
      await _load();
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('${VllBranding.appTitle} · SMS settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) {
                final maxW = c.maxWidth > 720 ? 640.0 : c.maxWidth;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
                      children: [
                        const Text(
                          'Listen filters (unique words, From numbers, filing Sender IDs) are managed in '
                          'imartPortal → SMS settings. This app syncs and applies them automatically. '
                          'Only matching SMS/WhatsApp appear in Inbox.',
                          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        _gatewayCard(),
                        const SizedBox(height: 16),
                        _keywordCard(),
                        const SizedBox(height: 16),
                        _senderCard(),
                        const SizedBox(height: 16),
                        _togglesCard(),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.lushRed),
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? 'Saving…' : 'Save desk settings'),
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

  Widget _keywordCard() {
    final keywords = _listenKeyword.text
        .split(RegExp(r'[\n\r,;|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Portal listen filters (read-only)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Change these in imartPortal → SMS settings. App applies them to every SMS/WhatsApp.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Text(
              !_keywordEnabled || keywords.isEmpty
                  ? 'Unique words: off'
                  : 'Unique words (${keywords.length}): ${keywords.join(' · ')}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              _fromNumbers.text.trim().isEmpty
                  ? 'Allowed From numbers: (none)'
                  : 'Allowed From:\n${_fromNumbers.text.trim()}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text('Filing Sender IDs',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            if (_listenSenderIds.isEmpty)
              const Text('None — using bound Sender ID',
                  style: TextStyle(fontSize: 13, color: Colors.black54))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _listenSenderIds
                    .map((s) => Chip(label: Text(s)))
                    .toList(),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading || _saving
                  ? null
                  : () async {
                      await ListenKeywordService.instance
                          .refreshFromApi(force: true);
                      await _load();
                    },
              icon: const Icon(Icons.sync),
              label: const Text('Refresh filters from portal'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gatewayCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gateway status',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_gateway.isEmpty)
              const Text('Unavailable')
            else
              ..._gateway.entries.map((e) {
                final v = e.value;
                final display = v is bool ? (v ? 'yes' : 'no') : v.toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${e.key}: $display',
                      style: const TextStyle(fontSize: 13)),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _senderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sender ID (manual)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _newSender,
              decoration: const InputDecoration(
                labelText: 'New Sender ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newSenderNote,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _saving ? null : _addSender, child: const Text('Add Sender ID')),
            if (_senders.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: _senders.map((s) => Chip(label: Text(s))).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _togglesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Manual SMS reply'),
              value: _manual,
              onChanged: (v) => setState(() => _manual = v),
            ),
            SwitchListTile(
              title: const Text('Bulk SMS'),
              value: _bulk,
              onChanged: (v) => setState(() => _bulk = v),
            ),
            SwitchListTile(
              title: const Text('Portal reply'),
              value: _portal,
              onChanged: (v) => setState(() => _portal = v),
            ),
            SwitchListTile(
              title: const Text('Auto-reply on capture'),
              value: _auto,
              onChanged: (v) => setState(() => _auto = v),
            ),
            DropdownButtonFormField<String?>(
              // ignore: deprecated_member_use
              value: _preferredSender,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Preferred Sender ID',
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— select —')),
                ..._senders.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() {
                _preferredSender = v;
                if (v != null) _preferredCustom.clear();
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _preferredCustom,
              decoration: const InputDecoration(
                labelText: 'Or type Preferred Sender ID',
                hintText: 'e.g. College',
              ),
              onChanged: (v) {
                if (v.trim().isNotEmpty) {
                  setState(() => _preferredSender = null);
                }
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              // ignore: deprecated_member_use
              value: _autoTplId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Auto-reply template',
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('—')),
                ..._templates.map((t) {
                  final id = int.tryParse((t['id'] ?? '').toString());
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text((t['title'] ?? 'Template').toString()),
                  );
                }),
              ],
              onChanged: (v) => setState(() => _autoTplId = v),
            ),
          ],
        ),
      ),
    );
  }
}
