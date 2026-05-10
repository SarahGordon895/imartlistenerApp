import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../shared/branding.dart';

/// Keeps a visible foreground-style notification while inbox listening is active (Android).
class ListeningNotification {
  ListeningNotification._();
  static final ListeningNotification instance = ListeningNotification._();

  static const _channelId = 'vll_sms_listen';
  static const _listenerChannelId = 'vll_listener_sms';
  static const _notificationId = 91001;
  static const _socialActivityNotificationId = 91002;

  /// Rotating ids so each listener SMS can surface during a live show.
  int _listenerNotifySeq = 91020;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);
      _initialized = true;
    } on MissingPluginException {
      _initialized = false;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> ensureAndroidPostPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await Permission.notification.request();
  }

  Future<void> showListening() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await init();
    await ensureAndroidPostPermission();

    const android = AndroidNotificationDetails(
      _channelId,
      'Inbox sync',
      channelDescription:
          'Shows when ${VllBranding.appTitle} is listening for SMS to sync with your portal.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(
      _notificationId,
      '${VllBranding.appTitle} listener',
      'Listening for incoming SMS (portal sync)',
      details,
    );
  }

  Future<void> dismiss() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!_initialized) return;
    try {
      await _plugin.cancel(_notificationId);
    } on MissingPluginException {
      // No-op on platforms/channels where plugin is not wired.
    } catch (_) {
      // Keep app flow stable even if notification channel fails.
    }
  }

  /// Heads-up when a listener texts the on-air / feedback line (radio KPI: SMS participation).
  Future<void> showListenerIncomingSms({
    required String from,
    String? bodyPreview,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await init();
    await ensureAndroidPostPermission();

    final id = _listenerNotifySeq;
    _listenerNotifySeq = _listenerNotifySeq >= 91120 ? 91020 : _listenerNotifySeq + 1;

    var body = bodyPreview?.trim() ?? '';
    if (body.length > 100) {
      body = '${body.substring(0, 100)}…';
    }
    final line = body.isEmpty ? from : '$from · $body';

    const android = AndroidNotificationDetails(
      _listenerChannelId,
      'Listener SMS',
      channelDescription:
          'Alerts for incoming SMS during live segments (syncs to ${VllBranding.appTitle}).',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(
      id,
      'New listener SMS',
      line,
      details,
    );
  }

  Future<void> showSocialActivity({
    required String title,
    required String body,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await init();
    await ensureAndroidPostPermission();
    const android = AndroidNotificationDetails(
      _channelId,
      'Inbox sync',
      channelDescription:
          'Shows when ${VllBranding.appTitle} is listening for SMS to sync with your portal.',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(
      _socialActivityNotificationId,
      title,
      body,
      details,
    );
  }
}
