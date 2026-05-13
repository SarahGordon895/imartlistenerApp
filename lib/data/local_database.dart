import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../shared/portal_sender.dart';

/// Local inbox cache + outbound compose audit trail (minimal Phase 1).
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'vll_sms.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE inbound_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sender TEXT NOT NULL,
  body TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0,
  sync_attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  server_message TEXT,
  portal_sender_id TEXT,
  segment TEXT,
  auto_reply_status TEXT,
  server_incoming_id INTEGER
);
''');
        await db.execute('''
CREATE TABLE outbound_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  api_success INTEGER NOT NULL DEFAULT 0,
  api_message TEXT
);
''');
        await db.execute(
          'CREATE INDEX idx_inbound_sync ON inbound_messages(synced, received_at DESC);',
        );
        await db.execute('''
CREATE TABLE audience_polls (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  opt1 TEXT NOT NULL,
  opt2 TEXT NOT NULL,
  opt3 TEXT NOT NULL DEFAULT '',
  opt4 TEXT NOT NULL DEFAULT '',
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  active INTEGER NOT NULL DEFAULT 1,
  server_poll_id INTEGER,
  sync_error TEXT
);
''');
        await db.execute('''
CREATE TABLE portal_senders (
  sender_id TEXT PRIMARY KEY NOT NULL,
  id_type TEXT,
  id_status TEXT,
  synced_at INTEGER NOT NULL
);
''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE inbound_messages ADD COLUMN portal_sender_id TEXT');
          await db.execute('ALTER TABLE inbound_messages ADD COLUMN segment TEXT');
          await db.execute('ALTER TABLE inbound_messages ADD COLUMN auto_reply_status TEXT');
          await db.execute('ALTER TABLE inbound_messages ADD COLUMN server_incoming_id INTEGER');
        }
        if (oldVersion < 3) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS audience_polls (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  opt1 TEXT NOT NULL,
  opt2 TEXT NOT NULL,
  opt3 TEXT NOT NULL DEFAULT '',
  opt4 TEXT NOT NULL DEFAULT '',
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  active INTEGER NOT NULL DEFAULT 1
);
''');
        }
        if (oldVersion < 4) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS portal_senders (
  sender_id TEXT PRIMARY KEY NOT NULL,
  id_type TEXT,
  id_status TEXT,
  synced_at INTEGER NOT NULL
);
''');
        }
        if (oldVersion < 5) {
          try {
            await db.execute(
                'ALTER TABLE audience_polls ADD COLUMN server_poll_id INTEGER');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE audience_polls ADD COLUMN sync_error TEXT');
          } catch (_) {}
        }
      },
    );
  }

  /// Last successful `/senders/list` snapshot (SMSver1 rules) for offline / fallback UI.
  Future<void> replacePortalSendersFromApi(List<dynamic> apiSenders) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('portal_senders');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final raw in apiSenders) {
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        final sid = normalizeOutgoingSenderId(m['sender_id']?.toString() ?? '');
        if (sid.isEmpty) continue;
        batch.insert('portal_senders', {
          'sender_id': sid,
          'id_type': m['id_type']?.toString(),
          'id_status': m['id_status']?.toString(),
          'synced_at': now,
        });
      } else if (raw is String) {
        final sid = normalizeOutgoingSenderId(raw);
        if (sid.isEmpty) continue;
        batch.insert('portal_senders', {
          'sender_id': sid,
          'id_type': null,
          'id_status': null,
          'synced_at': now,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> listPortalSenders() async {
    final db = await database;
    return db.query('portal_senders', orderBy: 'sender_id ASC');
  }

  Future<int> insertInbound({
    required String sender,
    required String body,
    required int receivedAtMs,
  }) async {
    final db = await database;
    return db.insert('inbound_messages', {
      'sender': sender,
      'body': body,
      'received_at': receivedAtMs,
      'synced': 0,
      'sync_attempts': 0,
    });
  }

  Future<List<Map<String, Object?>>> listInboundRecent({int limit = 200}) async {
    final db = await database;
    return db.query(
      'inbound_messages',
      orderBy: 'received_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> pendingInboundSync({int limit = 50}) async {
    final db = await database;
    return db.query(
      'inbound_messages',
      where: 'synced = 0',
      orderBy: 'received_at ASC',
      limit: limit,
    );
  }

  Future<void> markInboundSynced(
    int id, {
    String? serverMessage,
    Map<String, dynamic>? portalPayload,
  }) async {
    final db = await database;
    String? portalSender;
    String? segment;
    String? autoReply;
    int? serverIncomingId;
    if (portalPayload != null) {
      portalSender = portalPayload['portal_sender_id']?.toString();
      segment = portalPayload['segment']?.toString();
      autoReply = portalPayload['auto_reply_status']?.toString();
      final sid = portalPayload['incoming_id'];
      if (sid is int) {
        serverIncomingId = sid;
      } else if (sid is num) {
        serverIncomingId = sid.toInt();
      }
    }
    await db.update(
      'inbound_messages',
      {
        'synced': 1,
        'last_error': null,
        'server_message': serverMessage,
        if (portalSender != null) 'portal_sender_id': portalSender,
        if (segment != null) 'segment': segment,
        if (autoReply != null) 'auto_reply_status': autoReply,
        if (serverIncomingId != null) 'server_incoming_id': serverIncomingId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markInboundSyncFailed(int id, String error) async {
    final db = await database;
    await db.rawUpdate(
      '''
UPDATE inbound_messages
SET sync_attempts = sync_attempts + 1,
    last_error = ?
WHERE id = ?
''',
      [error, id],
    );
  }

  Future<int> insertOutbound({
    required String recipient,
    required String senderId,
    required String body,
    required bool apiSuccess,
    String? apiMessage,
  }) async {
    final db = await database;
    return db.insert('outbound_messages', {
      'recipient': recipient,
      'sender_id': senderId,
      'body': body,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'api_success': apiSuccess ? 1 : 0,
      'api_message': apiMessage,
    });
  }

  Future<List<Map<String, Object?>>> listOutboundRecent({int limit = 100}) async {
    final db = await database;
    return db.query(
      'outbound_messages',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// KPIs for dashboard (local handset inbox cache).
  Future<Map<String, int>> inboundKpis() async {
    final db = await database;
    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM inbound_messages'),
        ) ??
        0;
    final synced = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM inbound_messages WHERE synced = 1'),
        ) ??
        0;
    final pending = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM inbound_messages WHERE synced = 0'),
        ) ??
        0;
    final startDay = DateTime.now();
    final dayStart = DateTime(startDay.year, startDay.month, startDay.day).millisecondsSinceEpoch;
    final today = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) AS c FROM inbound_messages WHERE received_at >= ?',
            [dayStart],
          ),
        ) ??
        0;
    return {
      'total': total,
      'synced': synced,
      'pending': pending,
      'today': today,
    };
  }

  /// Show-segment breakdown for audience analytics (portal-synced segment labels).
  Future<List<Map<String, Object?>>> inboundSegmentBreakdown() async {
    final db = await database;
    return db.rawQuery(
      'SELECT COALESCE(NULLIF(TRIM(segment), ""), "(no segment)") AS seg, COUNT(*) AS c '
      'FROM inbound_messages GROUP BY seg ORDER BY c DESC LIMIT 12',
    );
  }

  Future<List<Map<String, Object?>>> listPolls() async {
    final db = await database;
    return db.query(
      'audience_polls',
      orderBy: 'started_at DESC',
    );
  }

  Future<Map<String, Object?>?> getPoll(int id) async {
    final db = await database;
    final rows = await db.query(
      'audience_polls',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, Object?>?> getActivePoll() async {
    final db = await database;
    final rows = await db.query(
      'audience_polls',
      where: 'active = 1',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<int> insertPoll({
    required String title,
    required String opt1,
    required String opt2,
    String opt3 = '',
    String opt4 = '',
  }) async {
    final db = await database;
    await db.update('audience_polls', {'active': 0});
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('audience_polls', {
      'title': title,
      'opt1': opt1,
      'opt2': opt2,
      'opt3': opt3,
      'opt4': opt4,
      'started_at': now,
      'ended_at': null,
      'active': 1,
    });
  }

  Future<void> endPoll(int id) async {
    final db = await database;
    await db.update(
      'audience_polls',
      {
        'active': 0,
        'ended_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int?> getPollServerId(int localId) async {
    final row = await getPoll(localId);
    if (row == null) return null;
    final v = row['server_poll_id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Future<void> setPollServerSync(int localId,
      {int? serverId, String? syncError}) async {
    final db = await database;
    final existing = await getPoll(localId);
    if (existing == null) return;
    await db.update(
      'audience_polls',
      {
        'server_poll_id': serverId ?? existing['server_poll_id'],
        'sync_error': syncError,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updatePollContent({
    required int id,
    required String title,
    required String opt1,
    required String opt2,
    String opt3 = '',
    String opt4 = '',
  }) async {
    final db = await database;
    await db.update(
      'audience_polls',
      {
        'title': title,
        'opt1': opt1,
        'opt2': opt2,
        'opt3': opt3,
        'opt4': opt4,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePoll(int id) async {
    final db = await database;
    await db.delete('audience_polls', where: 'id = ?', whereArgs: [id]);
  }

  /// Tallies votes from [inbound_messages] during poll window. Listeners text `1`–`4` or `vote 1`.
  Future<Map<int, int>> tallyPoll(int pollId) async {
    final poll = await getPoll(pollId);
    if (poll == null) return {};

    final start = poll['started_at'] as int? ?? 0;
    final end = poll['ended_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final opt3 = (poll['opt3'] as String? ?? '').trim();
    final opt4 = (poll['opt4'] as String? ?? '').trim();
    final maxChoice = opt4.isNotEmpty ? 4 : (opt3.isNotEmpty ? 3 : 2);

    final db = await database;
    final rows = await db.query(
      'inbound_messages',
      columns: ['body'],
      where: 'received_at >= ? AND received_at <= ?',
      whereArgs: [start, end],
    );

    final counts = <int, int>{for (var i = 1; i <= maxChoice; i++) i: 0};
    for (final r in rows) {
      final choice = _parseVoteChoice(r['body'] as String? ?? '');
      if (choice != null && choice >= 1 && choice <= maxChoice) {
        counts[choice] = (counts[choice] ?? 0) + 1;
      }
    }
    return counts;
  }

  static int? _parseVoteChoice(String raw) {
    final b = raw.trim().toLowerCase();
    if (b.isEmpty) return null;
    final m = RegExp(r'^vote\s*(\d)\s*$').firstMatch(b);
    if (m != null) return int.tryParse(m.group(1)!);
    if (RegExp(r'^\d$').hasMatch(b)) return int.tryParse(b);
    return null;
  }
}
