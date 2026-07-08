/// Normalize portal / alphanumeric sender IDs (iMart + legacy aliases).
String normalizeOutgoingSenderId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  if (lower == 'vll-sms' || lower == 'vllsms' || lower == 'vll sms') {
    return 'iMart SMS';
  }
  if (lower == 'imart-sms' || lower == 'imartsms' || lower == 'imart sms') {
    return 'iMart SMS';
  }
  return s;
}
