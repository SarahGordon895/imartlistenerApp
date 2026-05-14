/// Laravel API base URL (no trailing slash), e.g. `https://api.example.com` or `http://10.0.2.2:8000`.
/// Paths below include the `/api` prefix.
/// Override at compile time:
/// `flutter run --dart-define=API_BASE=https://your-laravel-host.com`
class ApiConstants {
  /// Production Laravel JSON host (NOT `sms.*` — that is SmSver1 PHP and has no `/api/v1/…`).
  static const String defaultLaravelApiBase = 'https://api.victorialush.co.tz';

  /// Laravel JSON host only (no `/api` or `/api/v1`). Must serve `/api/v1/...` as JSON.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: defaultLaravelApiBase,
  );

  /// SMSver1 users authenticate via Laravel `client/login` (same DB as portal).
  static const String loginPath = '/api/v1/client/login';
  static const String userPath = '/api/v1/user';
  static const String logoutPath = '/api/v1/logout';

  /// Same sender rules as SmSver1 (`senders` Active + your `user_id` | Public | Global).
  static const String sendersListPath = '/api/v1/senders/list';
  static const String sendersDebugPath = '/api/v1/senders/list/debug';
  /// Current bound sender for the logged-in bind phone (GET).
  static const String senderPointerPath = '/api/v1/sender-pointers';
  static const String senderBindPath = '/api/v1/sender-pointers/bind';
  /// Same URL as [senderBindPath]; use HTTP DELETE to clear the pointer for the logged-in bind phone.
  static const String senderUnbindPath = '/api/v1/sender-pointers/bind';
  /// Victoria Lush **VLL SMS** Flutter client (`vll_sms`); bulk campaigns stay on SMSver1.
  static const String autoReplyListPath = '/api/v1/auto-replies/list';
  static const String autoReplyCreatePath = '/api/v1/auto-replies/create';
  static const String autoReplyUpdatePath = '/api/v1/auto-replies/update';
  static const String autoReplyDeletePath = '/api/v1/auto-replies/delete';

  /// Single SMS (JSON: `from`, `message`, `to`).
  static const String smsSendSinglePath = '/api/v1/sms';
  /// Bulk SMS (JSON: `from`, `message`, `recipients`).
  static const String smsSendBulkPath = '/api/v1/sms/send';

  /// Inbound sync from device listener (JSON: `sender`, `sms`, `time`).
  static const String interactPath = '/api/v1/interact';
  static const String markReadPath = '/api/v1/read';

  /// Social registration check (APIs-only mode).
  static const String socialCheckPath = '/api/v1/social-checks/check';
  static const String socialBatchPath = '/api/v1/social-checks/batch';
  static const String socialRecentPath = '/api/v1/social-checks/recent';
  static String socialCheckByIdPath(int id) => '/api/v1/social-checks/$id';

  /// Live polls mirrored to Laravel / SMSver1 (`audience_polls`).
  static const String pollsPath = '/api/v1/polls';

  /// Public JSON probe (no auth); confirms this host is Laravel API, not SMS portal HTML.
  static const String healthPath = '/api/v1/health';
}
