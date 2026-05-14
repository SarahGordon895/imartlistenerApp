import 'dart:async';

import 'package:flutter/material.dart';

import '../packages/http_requests.dart';
import '../services/listening_notification.dart';
import '../shared/branding.dart';
import '../shared/constants.dart';
import '../widgets/toast.dart';

class SocialChecksScreen extends StatefulWidget {
  const SocialChecksScreen({super.key, this.isActive = false});

  final bool isActive;

  @override
  State<SocialChecksScreen> createState() => _SocialChecksScreenState();
}

class _SocialChecksScreenState extends State<SocialChecksScreen> {
  final _phone = TextEditingController();
  final _batch = TextEditingController();
  final Set<String> _platforms = {'facebook', 'instagram', 'whatsapp'};

  bool _busy = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _loadRecent();
    }
  }

  @override
  void didUpdateWidget(covariant SocialChecksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadRecent();
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _batch.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final res = await ApiClient.instance.get(ApiConstants.socialRecentPath, query: {
        'limit': '100',
      });
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
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      showToast('Enter a phone number.', error: true);
      return;
    }
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
          _results = [...fresh, ..._results];
        });
      }
      showToast('Social check submitted.');
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBatch() async {
    final lines = _batch.text
        .split(RegExp(r'[\n,; ]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      showToast('Enter numbers for batch check.', error: true);
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
          _results = [...fresh, ..._results];
        });
      }
      showToast('Batch social check submitted.');
    } catch (e) {
      showToast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyResults(List<Map<String, dynamic>> rows) async {
    for (final r in rows) {
      final status = (r['status'] ?? '').toString();
      if (status == 'found' || status == 'provider_error') {
        final platform = (r['platform'] ?? '').toString();
        final phone = (r['phone_number'] ?? '').toString();
        final title = status == 'found'
            ? 'Social match detected'
            : 'Social check provider error';
        final body = '$platform • $phone • $status';
        await ListeningNotification.instance.showSocialActivity(
          title: title,
          body: body,
        );
      }
    }
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
          title: const Text('Edit social check'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  // ignore: deprecated_member_use
                  value: foundChoice,
                  decoration: const InputDecoration(
                    labelText: 'Found',
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
                    labelText: 'Profile name',
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
      showToast('Social check updated.');
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
        content: const Text(
            'Removes the record from SMSver1 / API storage (same as portal delete).'),
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
      case 'queued_api_check':
        return Colors.blue.shade100;
      case 'found':
        return Colors.green.shade100;
      case 'not_found':
        return Colors.orange.shade100;
      default:
        return Colors.grey.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '${VllBranding.appTitle} · Audience',
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
                          const Text(
                            'Listener / audience analytics: probe social presence by phone (multi-platform). '
                            'Results are stored on the Victoria Lush API — use Refresh after checks. '
                            'Edit or delete rows below (CRUD) to tidy the list.',
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
                              _platformChip('x', 'X'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phone,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Single phone number',
                              hintText: '2557xxxxxxx',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _runSingle,
                              child: const Text('Check Number'),
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
                              child: const Text('Run Batch Check'),
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
                    'Results (tap ⋮ to edit or delete)',
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
                        child: Text('No social check results yet.'),
                      ),
                    )
                  else
                    ..._results.map((r) {
                      final platform = (r['platform'] ?? '').toString();
                      final phone = (r['phone_number'] ?? '').toString();
                      final status = (r['status'] ?? '').toString();
                      final url = (r['profile_url'] ?? '').toString();
                      final checked = (r['checked_at'] ?? '').toString();
                      return Card(
                        child: ListTile(
                          title: Text('$platform • $phone'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (url.isNotEmpty) Text(url),
                              if (checked.isNotEmpty) Text(checked),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
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
