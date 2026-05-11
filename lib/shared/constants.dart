/// Laravel API base URL (no trailing slash), e.g. `https://api.example.com` or `http://10.0.2.2:8000`.
/// Paths below include the `/api` prefix.
/// Override at compile time:
/// `flutter run --dart-define=API_BASE=https://your-domain.com`
class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://sms.victorialush.co.tz',
  );

  /// SMSver1 users authenticate via Laravel `client/login` (same DB as portal).
  static const String loginPath = '/api/v1/client/login';
  static const String userPath = '/api/v1/user';
  static const String logoutPath = '/api/v1/logout';

  /// Same sender rules as SmSver1 (`senders` Active + your `user_id` | Public | Global).
  static const String sendersListPath = '/api/v1/senders/list';
  static const String sendersDebugPath = '/api/v1/senders/list/debug';
  static const String senderBindPath = '/api/v1/sender-pointers/bind';
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
}
