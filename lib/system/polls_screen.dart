import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../services/polls_portal_sync.dart';
import '../shared/branding.dart';
import '../shared/themes.dart';

/// Live audience polls: tallies SMS replies `1`–`4` or `vote N` from the local Inbox during the poll window.
/// Created/updated polls sync to Laravel (`audience_polls`) for SMSver1 reporting.
class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key, this.isActive = false});

  final bool isActive;

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  List<Map<String, Object?>> _polls = [];
  bool _loading = true;
  Map<int, Map<int, int>> _tallies = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(PollsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final list = await LocalDatabase.instance.listPolls();
      final tallies = <int, Map<int, int>>{};
      for (final p in list) {
        final id = p['id'] as int?;
        if (id != null) {
          tallies[id] = await LocalDatabase.instance.tallyPoll(id);
        }
      }
      if (!mounted) return;
      setState(() {
        _polls = list;
        _tallies = tallies;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPoll() async {
    final title = TextEditingController();
    final o1 = TextEditingController();
    final o2 = TextEditingController();
    final o3 = TextEditingController();
    final o4 = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New live poll'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Listeners reply with 1, 2, 3, or 4 (or "vote 2"). '
                'Votes are counted from Inbox SMS on this device during the poll window. '
                'Each new poll is stored on SMSver1 when you are online.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Poll title / on-air script',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o1,
                decoration: const InputDecoration(
                    labelText: 'Option 1', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o2,
                decoration: const InputDecoration(
                    labelText: 'Option 2', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o3,
                decoration: const InputDecoration(
                  labelText: 'Option 3 (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o4,
                decoration: const InputDecoration(
                  labelText: 'Option 4 (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start poll'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      title.dispose();
      o1.dispose();
      o2.dispose();
      o3.dispose();
      o4.dispose();
      return;
    }

    final t = title.text.trim();
    final a = o1.text.trim();
    final b = o2.text.trim();
    final c3 = o3.text.trim();
    final c4 = o4.text.trim();
    title.dispose();
    o1.dispose();
    o2.dispose();
    o3.dispose();
    o4.dispose();

    if (t.isEmpty || a.isEmpty || b.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and first two options are required.')),
      );
      return;
    }

    final newId = await LocalDatabase.instance.insertPoll(
      title: t,
      opt1: a,
      opt2: b,
      opt3: c3,
      opt4: c4,
    );
    PollsPortalSync.syncAfterCreate(newId);
    if (mounted) await _reload();
  }

  Future<void> _editPoll(Map<String, Object?> p) async {
    final id = p['id'] as int?;
    if (id == null) return;
    final title = TextEditingController(text: p['title']?.toString() ?? '');
    final o1 = TextEditingController(text: p['opt1']?.toString() ?? '');
    final o2 = TextEditingController(text: p['opt2']?.toString() ?? '');
    final o3 = TextEditingController(text: (p['opt3'] as String? ?? '').trim());
    final o4 = TextEditingController(text: (p['opt4'] as String? ?? '').trim());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit poll'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o1,
                decoration: const InputDecoration(
                  labelText: 'Option 1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o2,
                decoration: const InputDecoration(
                  labelText: 'Option 2',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o3,
                decoration: const InputDecoration(
                  labelText: 'Option 3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: o4,
                decoration: const InputDecoration(
                  labelText: 'Option 4',
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
    );

    if (ok != true || !mounted) {
      title.dispose();
      o1.dispose();
      o2.dispose();
      o3.dispose();
      o4.dispose();
      return;
    }

    final tt = title.text.trim();
    final a1 = o1.text.trim();
    final a2 = o2.text.trim();
    final a3 = o3.text.trim();
    final a4 = o4.text.trim();
    title.dispose();
    o1.dispose();
    o2.dispose();
    o3.dispose();
    o4.dispose();

    if (tt.isEmpty || a1.isEmpty || a2.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and first two options are required.')),
      );
      return;
    }

    await LocalDatabase.instance.updatePollContent(
      id: id,
      title: tt,
      opt1: a1,
      opt2: a2,
      opt3: a3,
      opt4: a4,
    );
    PollsPortalSync.syncAfterUpdate(id);
    if (mounted) await _reload();
  }

  Future<void> _deletePoll(int id) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete poll?'),
        content: const Text(
            'Removes this poll from the device and from SMSver1 if it was synced.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.lushRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final sid = await LocalDatabase.instance.getPollServerId(id);
    await PollsPortalSync.syncDeleteOnServer(sid);
    await LocalDatabase.instance.deletePoll(id);
    if (mounted) await _reload();
  }

  Future<void> _endPoll(int id) async {
    final tallies = await LocalDatabase.instance.tallyPoll(id);
    await LocalDatabase.instance.endPoll(id);
    await PollsPortalSync.syncAfterEnd(id, tallies: tallies);
    if (mounted) await _reload();
  }

  int _maxVotes(Map<int, int> counts) {
    var m = 0;
    for (final v in counts.values) {
      if (v > m) m = v;
    }
    return m == 0 ? 1 : m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${VllBranding.appTitle} · Polls'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPoll,
        backgroundColor: AppTheme.lushGold,
        foregroundColor: Colors.black87,
        icon: const Icon(Icons.how_to_vote),
        label: const Text('New poll'),
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth > 960 ? 880.0 : c.maxWidth;
          final bottom = MediaQuery.paddingOf(context).bottom;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 88 + bottom),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live polls & voting',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.lushDark,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Counts use Inbox SMS on this device. '
                                  'New and ended polls sync to the Victoria Lush API (SMSver1 database) for reports.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  VllBranding.supportFootnoteLine,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: Colors.black45),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_polls.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child: Text(
                                    'No polls yet. Start one for your show block.')),
                          )
                        else
                          ..._polls.map((p) {
                            final id = p['id'] as int?;
                            if (id == null) return const SizedBox.shrink();
                            final active = (p['active'] as int? ?? 0) == 1;
                            final counts = _tallies[id] ?? {};
                            final maxV = _maxVotes(counts);
                            final syncErr = (p['sync_error'] as String?)?.trim();
                            final opts = [
                              p['opt1']?.toString() ?? '',
                              p['opt2']?.toString() ?? '',
                              (p['opt3'] as String? ?? '').trim(),
                              (p['opt4'] as String? ?? '').trim(),
                            ];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p['title']?.toString() ?? 'Poll',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        if (active)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.lushGold
                                                  .withValues(alpha: 0.35),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text('LIVE',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) async {
                                            if (v == 'edit') await _editPoll(p);
                                            if (v == 'delete') await _deletePoll(id);
                                          },
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit')),
                                            const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete')),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (syncErr != null && syncErr.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Sync: $syncErr',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    for (var i = 0; i < opts.length; i++) ...[
                                      if (opts[i].isNotEmpty) ...[
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 22,
                                              child: Text(
                                                '${i + 1}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.lushRed,
                                                ),
                                              ),
                                            ),
                                            Expanded(child: Text(opts[i])),
                                            Text(
                                              '${counts[i + 1] ?? 0}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value: ((counts[i + 1] ?? 0) / maxV)
                                              .clamp(0.0, 1.0),
                                          backgroundColor: Colors.black12,
                                          color: AppTheme.lushRed,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                    ],
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      children: [
                                        if (active)
                                          TextButton(
                                            onPressed: () => _endPoll(id),
                                            child: const Text('End poll'),
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
