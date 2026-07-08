import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'inbound_sync_service.dart';
import 'listening_notification.dart';

/// Android notification listener bridge for WhatsApp (+ some SMS apps).
class NotificationCaptureService {
  NotificationCaptureService._();
  static final NotificationCaptureService instance = NotificationCaptureService._();

  static const _methods = MethodChannel('imart/notification_capture');
  static const _events = EventChannel('imart/notification_events');

  StreamSubscription<dynamic>? _sub;
  final StreamController<void> _messageEvents = StreamController<void>.broadcast();
  bool _started = false;
  String? _lastError;

  Stream<void> get onMessage => _messageEvents.stream;
  String? get lastError => _lastError;
  bool get isStarted => _started;

  Future<bool> isEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final v = await _methods.invokeMethod<bool>('isEnabled');
      return v ?? false;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> openSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _methods.invokeMethod<void>('openSettings');
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final enabled = await isEnabled();
    if (!enabled) {
      _lastError =
          'Enable Notification access for iMart SMS Listener to capture WhatsApp messages.';
      return;
    }

    _sub?.cancel();
    _sub = _events.receiveBroadcastStream().listen(
      (event) async {
        try {
          final map = event is String
              ? Map<String, dynamic>.from(jsonDecode(event) as Map)
              : Map<String, dynamic>.from(event as Map);
          final channel = (map['channel']?.toString() ?? 'sms').toLowerCase();
          final sender = map['sender']?.toString() ?? '';
          final body = map['body']?.toString() ?? '';
          final name = map['contact_name']?.toString();
          final timeMs = map['time_ms'];
          final dt = timeMs is int
              ? DateTime.fromMillisecondsSinceEpoch(timeMs)
              : DateTime.now();
          if (body.trim().isEmpty) return;

          // SMS is already captured via readsms; avoid double posts from SMS apps.
          if (channel == 'sms') return;

          await InboundSyncService.instance.onMessageReceived(
            sender: sender.isNotEmpty ? sender : (name ?? 'whatsapp'),
            body: body,
            timeReceived: dt,
            channel: 'whatsapp',
            contactName: name,
          );
          await ListeningNotification.instance.showListenerIncomingSms(
            from: name?.isNotEmpty == true ? name! : sender,
            bodyPreview: body,
          );
          if (!_messageEvents.isClosed) {
            _messageEvents.add(null);
          }
        } catch (e) {
          _lastError = e.toString();
        }
      },
      onError: (e) {
        _lastError = e.toString();
      },
    );
    _started = true;
    _lastError = null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
