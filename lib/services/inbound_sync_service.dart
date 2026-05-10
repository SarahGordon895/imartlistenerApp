import 'dart:async';

import 'package:http/http.dart' as http;

import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../shared/constants.dart';

/// Posts device-received SMS to Laravel `/api/interact` with retry + local queue.
class InboundSyncService {
  InboundSyncService._();
  static final InboundSyncService instance = InboundSyncService._();

  Timer? _timer;

  void startPeriodicRetry() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      flushPending();
    });
  }

  void stopPeriodicRetry() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> onSmsReceived({
    required String sender,
    required String body,
    required DateTime timeReceived,
  }) async {
    final rowId = await LocalDatabase.instance.insertInbound(
      sender: sender,
      body: body,
      receivedAtMs: timeReceived.millisecondsSinceEpoch,
    );
    await _syncRow(rowId);
  }

  Future<void> flushPending() async {
    final pending = await LocalDatabase.instance.pendingInboundSync(limit: 100);
    for (final row in pending) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final stopBatch = await _syncRow(id);
      if (stopBatch) {
        break;
      }
    }
  }

  /// Returns `true` if the server is rate limiting and remaining rows should wait for the next flush.
  Future<bool> _syncRow(int localId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'inbound_messages',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    if ((row['synced'] as int? ?? 0) != 0) return false;

    final sender = row['sender'] as String? ?? '';
    final body = row['body'] as String? ?? '';
    final receivedAt = row['received_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final dt = DateTime.fromMillisecondsSinceEpoch(receivedAt).toUtc();

    final token = await ApiClient.instance.getToken();
    if (token == null || token.isEmpty) {
      await LocalDatabase.instance.markInboundSyncFailed(localId, 'Not authenticated');
      return false;
    }

    try {
      Future<http.Response> postInteract() {
        return ApiClient.instance.postJson(ApiConstants.interactPath, {
          'sender': sender,
          'sms': body,
          'time': dt.toIso8601String(),
        });
      }

      var res = await postInteract();
      if (res.statusCode == 429) {
        final wait = ApiClient.parseRetryAfterSeconds(res) ?? 3;
        await Future<void>.delayed(Duration(seconds: wait));
        res = await postInteract();
      }

      if (res.statusCode == 429) {
        await LocalDatabase.instance.markInboundSyncFailed(
          localId,
          ApiClient.errorMessageFromResponse(res),
        );
        return true;
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = ApiClient.decodeBody(res);
        String? srvMsg;
        Map<String, dynamic>? portalPayload;
        if (decoded is Map) {
          final m = Map<String, dynamic>.from(decoded);
          if (m['success'] == false) {
            final msg = m['message']?.toString() ?? 'Sync rejected';
            await LocalDatabase.instance.markInboundSyncFailed(localId, msg);
            return false;
          }
          srvMsg = m['message']?.toString();
          final d = m['data'];
          if (d is Map) {
            portalPayload = Map<String, dynamic>.from(d);
          }
        }
        await LocalDatabase.instance.markInboundSynced(
          localId,
          serverMessage: srvMsg,
          portalPayload: portalPayload,
        );
        return false;
      } else {
        await LocalDatabase.instance.markInboundSyncFailed(
          localId,
          ApiClient.errorMessageFromResponse(res),
        );
        return false;
      }
    } on TimeoutException {
      await LocalDatabase.instance.markInboundSyncFailed(localId, 'Timeout');
      return false;
    } on http.ClientException catch (e) {
      await LocalDatabase.instance.markInboundSyncFailed(localId, e.message);
      return false;
    } catch (e) {
      await LocalDatabase.instance.markInboundSyncFailed(localId, e.toString());
      return false;
    }
  }
}
