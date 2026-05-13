class Validators {
  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email address is required.';
    if (!s.contains('@')) return "Email must have '@'.";
    if (!s.contains('.')) return "Email must have '.'.";
    return null;
  }

  static String? required(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required.';
    return null;
  }

  /// Portal uses MD5 passwords; many legacy accounts are shorter than six characters.
  static String? password(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter password';
    return null;
  }

  static String? matchPassword(String? a, String? b) {
    if (a != b) return 'Enter a matching password.';
    return null;
  }
}
