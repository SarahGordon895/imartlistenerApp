/// Victoria Lush Limited — marketing / support contacts (flyer).
class VllBranding {
  VllBranding._();

  static const String appTitle = 'VLL SMS Feedback';
  /// Shown on the login card under the title.
  static const String loginSubtitle =
      'Sign in with your SMSver1 portal credentials (same account as the web SMS portal).';
  /// Full-width Victoria Lush wordmark (transparent) — light surfaces & login.
  static const String logoAsset = 'assets/vll-logo.png';
  /// White / light-glyph treatment for crimson or dark hero backgrounds.
  static const String logoWhiteAsset = 'assets/vll-logo-white.png';

  static const String homeHeroSubtitle =
      'Live SMS feedback, inbox sync, and portal tools — aligned with your SMSver1 account.';

  /// Shown next to sender pickers: same rules as SMSver1 compose/incoming.
  static const String senderListPortalHint =
      'Same Active sender IDs as SMSver1: your account, plus Public and Global IDs.';
  static const String company = 'Victoria Lush Limited';
  static const String tagline = 'Exceeding expectations.';

  static const String supportTz = '+255 742 200 333';
  static const String supportKe = '+254 111 25 25 21';
  static const String supportEmail = 'Support@victorialush.co.tz';

  /// Compact footer for tab screens (matches Polls / Audience pattern).
  static String get supportFootnoteLine => '$appTitle · $supportTz · $supportKe';
}
