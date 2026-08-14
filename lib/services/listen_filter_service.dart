import 'package:shared_preferences/shared_preferences.dart';

import '../shared/portal_sender.dart';

/// Cache of portal filing Sender IDs (read-only on device).
/// Values come from portal SMS settings via API sync — do not POST from the app.
class ListenFilterService {
  ListenFilterService._();
  static final ListenFilterService instance = ListenFilterService._();

  static const _prefsKey = 'imart_listen_sender_ids';

  Future<Set<String>> getSelected() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_prefsKey) ?? const <String>[];
    return raw.map(normalizeOutgoingSenderId).where((s) => s.isNotEmpty).toSet();
  }

  /// Replace local cache from a portal/API sync payload.
  Future<void> setSelected(Iterable<String> ids) async {
    final p = await SharedPreferences.getInstance();
    final cleaned = ids
        .map(normalizeOutgoingSenderId)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    await p.setStringList(_prefsKey, cleaned);
  }

  Future<bool> isListeningFor(String senderId) async {
    final cur = await getSelected();
    if (cur.isEmpty) return true;
    return cur.contains(normalizeOutgoingSenderId(senderId));
  }

  /// Prefer first portal filing Sender ID; null when unrestricted (server uses bind).
  Future<String?> primaryListenSenderId() async {
    final cur = await getSelected();
    if (cur.isEmpty) return null;
    return cur.first;
  }
}
