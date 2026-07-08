import 'package:shared_preferences/shared_preferences.dart';

import '../shared/portal_sender.dart';

/// Client-side: which portal sender ID(s) this device listens / records under.
/// Empty set = listen for all (use default bind on server).
class ListenFilterService {
  ListenFilterService._();
  static final ListenFilterService instance = ListenFilterService._();

  static const _prefsKey = 'imart_listen_sender_ids';

  Future<Set<String>> getSelected() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_prefsKey) ?? const <String>[];
    return raw.map(normalizeOutgoingSenderId).where((s) => s.isNotEmpty).toSet();
  }

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

  Future<void> toggle(String senderId) async {
    final id = normalizeOutgoingSenderId(senderId);
    if (id.isEmpty) return;
    final cur = await getSelected();
    if (cur.contains(id)) {
      cur.remove(id);
    } else {
      cur.add(id);
    }
    await setSelected(cur);
  }

  Future<bool> isListeningFor(String senderId) async {
    final cur = await getSelected();
    if (cur.isEmpty) return true;
    return cur.contains(normalizeOutgoingSenderId(senderId));
  }

  /// Prefer first selected filter; null when unrestricted (server uses bind).
  Future<String?> primaryListenSenderId() async {
    final cur = await getSelected();
    if (cur.isEmpty) return null;
    return cur.first;
  }
}
