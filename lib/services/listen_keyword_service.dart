import 'package:shared_preferences/shared_preferences.dart';

import '../packages/http_requests.dart';
import '../shared/constants.dart';
import '../shared/portal_sender.dart';
import 'listen_filter_service.dart';

/// Portal-managed listen rules cached for on-device filtering (keyword OR from-numbers).
class ListenKeywordService {
  ListenKeywordService._();
  static final ListenKeywordService instance = ListenKeywordService._();

  static const _keyKeyword = 'imart_listen_keyword';
  static const _keyEnabled = 'imart_listen_keyword_enabled';
  static const _keyFromNumbers = 'imart_listen_from_numbers';

  Future<void> cacheFromPrefsMap(Map<String, dynamic> prefs) async {
    final keyword = (prefs['listen_keyword']?.toString() ?? '').trim();
    final enabledRaw = prefs['listen_keyword_enabled'] != false;
    final enabled = enabledRaw && keyword.isNotEmpty;
    final fromRaw = prefs['listen_from_numbers'];
    final fromList = <String>[];
    if (fromRaw is List) {
      for (final e in fromRaw) {
        final d = e.toString().replaceAll(RegExp(r'\D'), '');
        if (d.isNotEmpty) fromList.add(d);
      }
    } else if (fromRaw != null) {
      for (final part in fromRaw.toString().split(RegExp(r'[\s,;]+'))) {
        final d = part.replaceAll(RegExp(r'\D'), '');
        if (d.isNotEmpty) fromList.add(d);
      }
    }

    final p = await SharedPreferences.getInstance();
    await p.setString(_keyKeyword, keyword);
    await p.setBool(_keyEnabled, enabled);
    await p.setStringList(_keyFromNumbers, fromList.toSet().toList());

    final senderIds = prefs['listen_sender_ids'];
    if (senderIds is List) {
      await ListenFilterService.instance.setSelected(
        senderIds.map((e) => normalizeOutgoingSenderId(e.toString())),
      );
    }
  }

  Future<void> refreshFromApi() async {
    try {
      final res =
          await ApiClient.instance.get(ApiConstants.replyTemplatesPrefsPath);
      ApiClient.ensureHttpAndEnvelopeSuccess(res);
      final data = ApiClient.responseData(res);
      if (data is Map) {
        await cacheFromPrefsMap(Map<String, dynamic>.from(data));
      }
      // Also pull dedicated listen-filters endpoint (portal may update only that table).
      final lf = await ApiClient.instance.get(ApiConstants.listenFiltersPath);
      if (lf.statusCode >= 200 && lf.statusCode < 300) {
        final d = ApiClient.responseData(lf);
        if (d is Map) {
          final ids = d['sender_ids'];
          if (ids is List) {
            await ListenFilterService.instance.setSelected(
              ids.map((e) => normalizeOutgoingSenderId(e.toString())),
            );
          }
        }
      }
    } catch (_) {
      // Keep last cached values when offline.
    }
  }

  Future<({String keyword, bool enabled, List<String> fromNumbers})>
      current() async {
    final p = await SharedPreferences.getInstance();
    return (
      keyword: (p.getString(_keyKeyword) ?? '').trim(),
      enabled: p.getBool(_keyEnabled) ?? false,
      fromNumbers: p.getStringList(_keyFromNumbers) ?? const <String>[],
    );
  }

  bool _fromMatches(String sender, List<String> allowed) {
    if (allowed.isEmpty) return false;
    final from = sender.replaceAll(RegExp(r'\D'), '');
    if (from.isEmpty) return false;
    for (final a in allowed) {
      if (from == a) return true;
      if (from.length >= 9 && a.length >= 9 && from.substring(from.length - 9) == a.substring(a.length - 9)) {
        return true;
      }
    }
    return false;
  }

  /// Same rule as API `ClientSmsPref::evaluateListenFilter`.
  Future<bool> messageShouldListen({
    required String body,
    required String sender,
  }) async {
    final cur = await current();
    final hasFrom = cur.fromNumbers.isNotEmpty;
    // Empty keyword must never block all captures.
    final hasKeywordRule = cur.enabled && cur.keyword.isNotEmpty;

    if (!hasKeywordRule && !hasFrom) return true;

    final kwMatch = hasKeywordRule &&
        body.toLowerCase().contains(cur.keyword.toLowerCase());
    final fromMatch = hasFrom && _fromMatches(sender, cur.fromNumbers);

    if (hasKeywordRule && hasFrom) {
      return kwMatch || fromMatch;
    }
    if (hasFrom) return fromMatch;
    return kwMatch;
  }

  /// Back-compat for call sites that only had a body check.
  Future<bool> bodyMatches(String body) async {
    return messageShouldListen(body: body, sender: '');
  }
}
