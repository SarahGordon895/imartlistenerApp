import '../data/local_database.dart';
import '../packages/http_requests.dart';
import '../shared/constants.dart';

/// Pushes local poll rows to Laravel so SMSver1 / shared DB keeps an audit trail.
class PollsPortalSync {
  static int? _parseServerId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static Future<void> syncAfterCreate(int localPollId) async {
    final token = await ApiClient.instance.getToken();
    if (token == null || token.isEmpty) {
      await LocalDatabase.instance.setPollServerSync(localPollId,
          syncError: 'Not logged in — poll saved on device only.');
      return;
    }
    final row = await LocalDatabase.instance.getPoll(localPollId);
    if (row == null) return;
    try {
      final res = await ApiClient.instance.postJson(ApiConstants.pollsPath, {
        'title': row['title']?.toString() ?? '',
        'opt1': row['opt1']?.toString() ?? '',
        'opt2': row['opt2']?.toString() ?? '',
        'opt3': row['opt3']?.toString() ?? '',
        'opt4': row['opt4']?.toString() ?? '',
        'started_at_ms': row['started_at'] as int,
        'active': (row['active'] as int? ?? 0) == 1,
      });
      if (!ApiClient.isSuccess(res)) {
        await LocalDatabase.instance.setPollServerSync(localPollId,
            syncError: ApiClient.errorMessageFromResponse(res));
        return;
      }
      final data = ApiClient.responseData(res);
      if (data is Map) {
        final sid = _parseServerId(data['id']);
        await LocalDatabase.instance.setPollServerSync(localPollId,
            serverId: sid, syncError: null);
      } else {
        await LocalDatabase.instance.setPollServerSync(localPollId,
            syncError: 'Unexpected poll response');
      }
    } catch (e) {
      await LocalDatabase.instance.setPollServerSync(localPollId,
          syncError: e.toString());
    }
  }

  static Future<void> syncAfterUpdate(int localPollId) async {
    final sid = await LocalDatabase.instance.getPollServerId(localPollId);
    if (sid == null) return;
    final row = await LocalDatabase.instance.getPoll(localPollId);
    if (row == null) return;
    try {
      final res = await ApiClient.instance.putJson(
          '${ApiConstants.pollsPath}/$sid', {
        'title': row['title']?.toString() ?? '',
        'opt1': row['opt1']?.toString() ?? '',
        'opt2': row['opt2']?.toString() ?? '',
        'opt3': row['opt3']?.toString() ?? '',
        'opt4': row['opt4']?.toString() ?? '',
      });
      if (!ApiClient.isSuccess(res)) {
        await LocalDatabase.instance.setPollServerSync(localPollId,
            syncError: ApiClient.errorMessageFromResponse(res));
        return;
      }
      await LocalDatabase.instance.setPollServerSync(localPollId,
          serverId: sid, syncError: null);
    } catch (e) {
      await LocalDatabase.instance.setPollServerSync(localPollId,
          syncError: e.toString());
    }
  }

  static Future<void> syncAfterEnd(
    int localPollId, {
    required Map<int, int> tallies,
  }) async {
    final sid = await LocalDatabase.instance.getPollServerId(localPollId);
    if (sid == null) return;
    final talliesJson = <String, int>{
      for (final e in tallies.entries) e.key.toString(): e.value,
    };
    try {
      final res = await ApiClient.instance.patchJson(
        '${ApiConstants.pollsPath}/$sid/end',
        {
          'ended_at_ms': DateTime.now().millisecondsSinceEpoch,
          'tallies': talliesJson,
        },
      );
      if (!ApiClient.isSuccess(res)) {
        await LocalDatabase.instance.setPollServerSync(localPollId,
            syncError: ApiClient.errorMessageFromResponse(res));
        return;
      }
      await LocalDatabase.instance.setPollServerSync(localPollId,
          serverId: sid, syncError: null);
    } catch (e) {
      await LocalDatabase.instance.setPollServerSync(localPollId,
          syncError: e.toString());
    }
  }

  static Future<void> syncDeleteOnServer(int? serverPollId) async {
    if (serverPollId == null) return;
    final token = await ApiClient.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      final res =
          await ApiClient.instance.delete('${ApiConstants.pollsPath}/$serverPollId');
      if (!ApiClient.isSuccess(res)) {
        throw Exception(ApiClient.errorMessageFromResponse(res));
      }
    } catch (_) {
      // Local row already removed; ignore server delete failure.
    }
  }
}
