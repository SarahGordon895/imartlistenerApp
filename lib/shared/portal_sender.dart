/// Parity with SmSver1 `phone_lib.php` → `vll_normalize_outgoing_sender_id`.
String normalizeOutgoingSenderId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  if (lower == 'vll-sms' || lower == 'vllsms') {
    return 'VLL SMS';
  }
  return s;
}
