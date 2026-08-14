import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../packages/http_requests.dart';
import '../services/listening_notification.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../widgets/toast.dart';

/// Lookup a customer / sender phone on Instagram, Facebook, WhatsApp, etc.
class SocialChecksScreen extends StatefulWidget {
  const SocialChecksScreen({super.key, this.isActive = false});

  final bool isActive;

  /// Prefill from Inbox / Home when user taps “Find on social”.
  static final ValueNotifier<String?> prefillPhone = ValueNotifier<String?>(null);

  static void requestPrefillPhone(String phone) {
    prefillPhone.value = phone;
  }

  @override
  State<SocialChecksScreen> createState() => _SocialChecksScreenState();
}

class _SocialChecksScreenState extends State<SocialChecksScreen> {
  final _phone = TextEditingController();
  final _batch = TextEditingController();
  final Set<String> _platforms = {
    'facebook',
    'instagram',
    'whatsapp',
    'google',
  };

  bool _busy = false;
  List<Map<String, dynamic>> _results = [];
  VoidCallback? _prefillListener;

  @override
  void initState() {
    super.initState();
    _prefillListener = () {
      final p = SocialChecksScreen.prefillPhone.value;
      if (p == null || p.isEmpty) return;
      final normalized = _normalizePhone(p);
      _phone.text = normalized.isNotEmpty ? normalized : p.trim();
      SocialChecksScreen.prefillPhone.value = null;
      if (widget.isActive || mounted) {
        _runSingle();
      }
    };
    SocialChecksScreen.prefillPhone.addListener(_prefillListener!);
    if (widget.isActive) {
      _consumePrefill();
      _loadRecent();
    }
  }

  @override
  void didUpdateWidget(covariant SocialChecksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _consumePrefill();
      _loadRecent();
    }
  }

  void _consumePrefill() {
    final p = SocialChecksScreen.prefillPhone.value;
    if (p == null || p.isEmpty) return;
    final normalized = _normalizePhone(p);
    _phone.text = normalized.isNotEmpty ? normalized : p.trim();
    SocialChecksScreen.prefillPhone.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runSingle();
    });
  }

  @override
  void dispose() {
    if (_prefillListener != null) {
      SocialChecksScreen.prefillPhone.removeListener(_prefillListener!);
    }
    _phone.dispose();
    _batch.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final query = <String, String>{'limit': '100'};
      final phone = _normalizePhone(_phone.text);
      if (phone.isNotEmpty) {
        query['phone'] = phone;
      }
      final res = await ApiClient.instance.get(ApiConstants.socialRecentPath, query: query);
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Could not load social checks');
      final data = ApiClient.responseData(res);
      if (data is List) {
        if (!mounted) return;
        setState(() {
          _results = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        showToast('Failed to load recent checks: $e', error: true);
      }
    }
  }

  List<String> _selectedPlatforms() => _platforms.toList()..sort();

  Future<void> _runSingle() async {
    final phone = _normalizePhone(_phone.text);
    if (phone.isEmpty) {
      showToast('Enter a valid phone number from the listened message.', error: true);
      return;
    }
    _phone.text = phone;
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.postJson(ApiConstants.socialCheckPath, {
        'phone_number': phone,
        'platforms': _selectedPlatforms(),
      });
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Social check failed');
      final data = ApiClient.responseData(res);
      if (data is List) {
        final fresh = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _notifyResults(fresh);
        if (!mounted) return;
        setState(() {
          _results = _mergeByPhonePlatform(fresh, _results);
        });
      }
      showToast('Social lookup ready for $phone — open platform links below.');
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Match API MSISDN rules for listened SMS/WhatsApp senders (TZ 07… / 7…).
  String _normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 10 && digits.startsWith('0')) {
      return '255${digits.substring(1)}';
    }
    if (digits.length == 9 && (digits.startsWith('6') || digits.startsWith('7'))) {
      return '255$digits';
    }
    if (RegExp(r'^(255|254|256)').hasMatch(digits) &&
        digits.length >= 12 &&
        digits.length <= 15) {
      return digits;
    }
    if (digits.length >= 10 && digits.length <= 15) return digits;
    return '';
  }

  List<Map<String, dynamic>> _mergeByPhonePlatform(
    List<Map<String, dynamic>> fresh,
    List<Map<String, dynamic>> existing,
  ) {
    final keys = <String>{};
    for (final r in fresh) {
      keys.add('${r['phone_number']}|${r['platform']}');
    }
    final kept = existing.where((r) {
      final k = '${r['phone_number']}|${r['platform']}';
      return !keys.contains(k);
    });
    return [...fresh, ...kept];
  }

  Future<void> _runBatch() async {
    final lines = _batch.text
        .split(RegExp(r'[\n,; ]+'))
        .map((e) => _normalizePhone(e))
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      showToast('Enter valid numbers for batch check.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.postJson(ApiConstants.socialBatchPath, {
        'phone_numbers': lines,
        'platforms': _selectedPlatforms(),
      });
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Batch social check failed');
      final data = ApiClient.responseData(res);
      if (data is List) {
        final fresh = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _notifyResults(fresh);
        if (!mounted) return;
        setState(() {
          _results = _mergeByPhonePlatform(fresh, _results);
        });
      }
      showToast('Batch social lookup submitted.');
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyResults(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final phone = (rows.first['phone_number'] ?? '').toString();
    final platforms = rows.map((r) => (r['platform'] ?? '').toString()).where((p) => p.isNotEmpty).toSet();
    final found = rows.where((r) => (r['status'] ?? '') == 'found').length;
    final ready = rows.where((r) => (r['status'] ?? '') == 'search_ready').length;
    final errors = rows.where((r) => (r['status'] ?? '') == 'provider_error').length;

    String title;
    String body;
    if (found > 0) {
      title = 'Social match detected';
      body = '$phone · $found platform match(es)';
    } else if (errors > 0 && ready == 0) {
      title = 'Social check provider error';
      body = '$phone · $errors error(s)';
    } else {
      title = 'Social lookup ready';
      body = '$phone · open ${platforms.join(', ')}';
    }
    await ListeningNotification.instance.showSocialActivity(
      title: title,
      body: body,
    );
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      showToast('Invalid link.', error: true);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) showToast('Could not open link.', error: true);
  }

  List<Map<String, String>> _linksFromRow(Map<String, dynamic> r) {
    final out = <Map<String, String>>[];
    final meta = r['metadata'];
    if (meta is Map) {
      final urls = meta['search_urls'];
      if (urls is List) {
        for (final item in urls) {
          if (item is Map) {
            final label = (item['label'] ?? 'Open').toString();
            final url = (item['url'] ?? '').toString();
            if (url.isNotEmpty) out.add({'label': label, 'url': url});
          }
        }
      }
    }
    final primary = (r['profile_url'] ?? '').toString();
    if (primary.isNotEmpty && !out.any((e) => e['url'] == primary)) {
      out.insert(0, {'label': 'Open search', 'url': primary});
    }
    return out;
  }

  int? _rowId(Map<String, dynamic> r) {
    final id = r['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  Future<void> _editRow(Map<String, dynamic> r) async {
    final id = _rowId(r);
    if (id == null) return;
    final status = TextEditingController(text: (r['status'] ?? '').toString());
    final name = TextEditingController(text: (r['profile_name'] ?? '').toString());
    final url = TextEditingController(text: (r['profile_url'] ?? '').toString());
    var found = r['is_found'];
    int? foundChoice;
    if (found == null) {
      foundChoice = null;
    } else if (found == true || found == 1 || found == '1') {
      foundChoice = 1;
    } else {
      foundChoice = 0;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Mark social find'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: status,
                  decoration: const InputDecoration(
                    labelText: 'Status (e.g. found / not_found)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  // ignore: deprecated_member_use
                  value: foundChoice,
                  decoration: const InputDecoration(
                    labelText: 'Found on platform?',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('Unknown')),
                    DropdownMenuItem<int?>(value: 1, child: Text('Yes')),
                    DropdownMenuItem<int?>(value: 0, child: Text('No')),
                  ],
                  onChanged: (v) => setLocal(() => foundChoice = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Profile / display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: url,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Profile URL',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      status.dispose();
      name.dispose();
      url.dispose();
      return;
    }

    final st = status.text.trim();
    final nm = name.text.trim();
    final ur = url.text.trim();
    status.dispose();
    name.dispose();
    url.dispose();

    try {
      final body = <String, dynamic>{
        'status': st,
        'profile_name': nm,
        'profile_url': ur,
      };
      if (foundChoice != null) {
        body['is_found'] = foundChoice == 1;
      }
      final res = await ApiClient.instance.putJson(
        ApiConstants.socialCheckByIdPath(id),
        body,
      );
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Update failed');
      showToast('Saved.');
      await _loadRecent();
    } catch (e) {
      showToast(e.toString(), error: true);
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> r) async {
    final id = _rowId(r);
    if (id == null) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this row?'),
        content: const Text('Removes this social lookup result from API storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      final res =
          await ApiClient.instance.delete(ApiConstants.socialCheckByIdPath(id));
      ApiClient.ensureHttpAndEnvelopeSuccess(res,
          fallbackPrefix: 'Delete failed');
      showToast('Deleted.');
      await _loadRecent();
    } catch (e) {
      showToast(e.toString(), error: true);
    }
  }

  Widget _platformChip(String id, String label) {
    final selected = _platforms.contains(id);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _platforms.add(id);
          } else {
            _platforms.remove(id);
          }
        });
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'search_ready':
        return Colors.blue.shade100;
      case 'found':
        return Colors.green.shade100;
      case 'not_found':
        return Colors.orange.shade100;
      case 'provider_error':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '${VllBranding.appTitle} · Social',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _loadRecent,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth > 960 ? 880.0 : c.maxWidth;
          final bottom = MediaQuery.paddingOf(context).bottom;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: ListView(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 16 + bottom),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Social phone lookup',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Paste a number from Inbox (who messaged your business SMS / WhatsApp) '
                            'and search Instagram, Facebook, WhatsApp, Telegram, TikTok, LinkedIn, X, or Google. '
                            'Use this to verify callers and spot phishing / fake social sellers.',
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _platformChip('facebook', 'Facebook'),
                              _platformChip('instagram', 'Instagram'),
                              _platformChip('whatsapp', 'WhatsApp'),
                              _platformChip('telegram', 'Telegram'),
                              _platformChip('tiktok', 'TikTok'),
                              _platformChip('linkedin', 'LinkedIn'),
                              _platformChip('x', 'X'),
                              _platformChip('google', 'Google'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: 'Phone number from message',
                              hintText: '2557xxxxxxx',
                              suffixIcon: IconButton(
                                tooltip: 'Paste',
                                onPressed: () async {
                                  final data =
                                      await Clipboard.getData(Clipboard.kTextPlain);
                                  final t = data?.text?.trim() ?? '';
                                  if (t.isNotEmpty) {
                                    setState(() => _phone.text = t);
                                  }
                                },
                                icon: const Icon(Icons.content_paste),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _runSingle,
                              icon: const Icon(Icons.search),
                              label: const Text('Search platforms'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _batch,
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Batch numbers',
                              hintText: 'One per line, or comma separated',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _busy ? null : _runBatch,
                              child: const Text('Run batch lookup'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(
                      VllBranding.supportFootnoteLine,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.black45),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Results — open links to verify the account',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_results.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No lookups yet. Enter a sender number from Inbox, or tap Social on a message.',
                        ),
                      ),
                    )
                  else
                    ..._results.map((r) {
                      final platform = (r['platform'] ?? '').toString();
                      final phone = (r['phone_number'] ?? '').toString();
                      final status = (r['status'] ?? '').toString();
                      final name = (r['profile_name'] ?? '').toString();
                      final checked = (r['checked_at'] ?? '').toString();
                      final links = _linksFromRow(r);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$platform · $phone',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(status),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _editRow(r);
                                      if (v == 'delete') _deleteRow(r);
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Mark found / edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (name.isNotEmpty) Text(name),
                              if (checked.isNotEmpty)
                                Text(checked,
                                    style: Theme.of(context).textTheme.bodySmall),
                              if (links.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: links
                                      .map(
                                        (l) => ActionChip(
                                          avatar: const Icon(Icons.open_in_new,
                                              size: 16),
                                          label: Text(l['label'] ?? 'Open'),
                                          onPressed: () =>
                                              _openUrl(l['url'] ?? ''),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
