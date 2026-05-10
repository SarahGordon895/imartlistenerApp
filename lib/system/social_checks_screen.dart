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
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
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
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
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
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
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
        title: const Text('${VllBranding.appTitle} · Audience'),
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
                    'APIs-only mode — your Laravel admin configures provider keys and URLs.',
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.black45),
            ),
          ),
          const SizedBox(height: 10),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Results', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(status),
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

