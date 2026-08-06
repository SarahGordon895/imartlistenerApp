/// Laravel API base URL (no trailing slash).
/// Override: `flutter run --dart-define=API_BASE=https://your-host`
class ApiConstants {
  /// Primary API hostname (Apache vhost). Used as `Host` when base URL is the server IP.
  static const String defaultApiVirtualHost = 'api.imartgroup.co.tz';

  static const String alternateApiVirtualHost = 'sms-api.imartgroup.co.tz';

  /// Fallback reachable base (configure DNS / proxy for production).
  static const String productionApiReachableBase = 'http://162.220.11.235';

  /// HTTPS via iMart SMS portal proxy (`/api/v1` → Laravel).
  static const String productionApiBaseHttpsSms = 'https://sms.imartgroup.co.tz';

  static const String productionApiBaseHttpsCom = 'https://api.imartgroup.co.tz';
  static const String productionApiBaseHttpsTz = 'https://sms-api.imartgroup.co.tz';

  /// Dedicated iMart Listener API domain on LipaPay hosting (production default).
  static const String productionApiBaseLipaPay =
      'https://listenerapi.lipapay.co.tz';

  static const List<String> apiVirtualHosts = [
    defaultApiVirtualHost,
    alternateApiVirtualHost,
  ];

  /// Discovery order: hosted LipaPay first, then legacy, then local for dev.
  static const List<String> productionApiBaseCandidates = [
    productionApiBaseLipaPay,
    localLaravelApiBase,
    productionApiBaseHttpsCom,
    productionApiBaseHttpsTz,
    productionApiBaseHttpsSms,
    productionApiReachableBase,
  ];

  /// Local Laravel (`php artisan serve`) for portal + app login on this machine.
  static const String localLaravelApiBase = 'http://127.0.0.1:8000';

  static const String defaultLaravelApiBase = productionApiBaseLipaPay;

  @Deprecated('Use defaultApiVirtualHost')
  static const String defaultLaravelApiVirtualHost = defaultApiVirtualHost;

  @Deprecated('Use productionApiBaseHttpsTz')
  static const String preferredLaravelApiBaseHttps = productionApiBaseHttpsTz;

  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: defaultLaravelApiBase,
  );

  /// Bump so upgrades clear stale hosts and pick LipaPay listener API quickly.
  static const int apiConfigVersion = 12;

  static const String loginPath = '/api/v1/client/login';
  static const String userPath = '/api/v1/user';
  static const String logoutPath = '/api/v1/logout';

  static const String sendersListPath = '/api/v1/senders/list';
  static const String sendersCreatePath = '/api/v1/senders';
  static String senderByIdPath(int id) => '/api/v1/senders/$id';
  static const String sendersDebugPath = '/api/v1/senders/list/debug';
  static const String senderPointerPath = '/api/v1/sender-pointers';
  static const String senderBindPath = '/api/v1/sender-pointers/bind';
  static const String senderUnbindPath = '/api/v1/sender-pointers/bind';

  /// Multi listen filters (which sender IDs this device services).
  static const String listenFiltersPath = '/api/v1/listen-filters';

  static const String conversationsPath = '/api/v1/conversations';
  static const String conversationThreadPath = '/api/v1/conversations/thread';

  static const String autoReplyListPath = '/api/v1/auto-replies/list';
  static const String autoReplyCreatePath = '/api/v1/auto-replies/create';
  static const String autoReplyUpdatePath = '/api/v1/auto-replies/update';
  static const String autoReplyDeletePath = '/api/v1/auto-replies/delete';

  static const String smsSendSinglePath = '/api/v1/sms';
  static const String smsSendBulkPath = '/api/v1/sms/send';
  static const String smsStatusPath = '/api/v1/sms/status';
  static const String healthPath = '/api/v1/health';

  static const String replyTemplatesPath = '/api/v1/reply-templates';
  static String replyTemplateByIdPath(int id) => '/api/v1/reply-templates/$id';
  static const String replyTemplatesPrefsPath = '/api/v1/reply-templates/prefs';

  static const String interactPath = '/api/v1/interact';
  static const String markReadPath = '/api/v1/read';

  static const String socialCheckPath = '/api/v1/social-checks/check';
  static const String socialBatchPath = '/api/v1/social-checks/batch';
  static const String socialRecentPath = '/api/v1/social-checks/recent';
  static String socialCheckByIdPath(int id) => '/api/v1/social-checks/$id';

  static const String pollsPath = '/api/v1/polls';

  static const String appUpdateManifestUrl = String.fromEnvironment(
    'APP_UPDATE_URL',
    defaultValue: 'https://sms.imartgroup.co.tz/app-update.json',
  );
}
