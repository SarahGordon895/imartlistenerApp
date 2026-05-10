import 'portal_sender.dart';

/// Parses Laravel [SenderController] JSON `data` for `GET /api/v1/senders/list`.
class SenderApiPayload {
  SenderApiPayload._();

  static List<dynamic> extractSendersList(dynamic data) {
    if (data == null) return const [];
    if (data is List) return data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final s = m['senders'];
      if (s is List) return s;
      // Rare: nested `data.senders` if an upstream proxy double-wraps the envelope.
      final inner = m['data'];
      if (inner is Map) {
        final s2 = Map<String, dynamic>.from(inner)['senders'];
        if (s2 is List) return s2;
      }
    }
    return const [];
  }

  static String? extractCurrentSenderId(dynamic data) {
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    var current = m['current_sender'];
    if (current is! List || current.isEmpty) {
      final inner = m['data'];
      if (inner is Map) {
        current = Map<String, dynamic>.from(inner)['current_sender'];
      }
    }
    if (current is! List || current.isEmpty) return null;
    final first = current.first;
    if (first is! Map) return null;
    final sid = first['sender_id']?.toString();
    if (sid == null || sid.trim().isEmpty) return null;
    return normalizeOutgoingSenderId(sid);
  }
}
