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

  /// Portal rule: min 8 chars, upper, lower, digit, special.
  static String? password(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter password';
    final s = v;
    if (s.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(s)) return 'Include an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(s)) return 'Include a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(s)) return 'Include a number';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(s)) return 'Include a special character';
    return null;
  }

  static String? matchPassword(String? a, String? b) {
    if (a != b) return 'Enter a matching password.';
    return null;
  }
}
