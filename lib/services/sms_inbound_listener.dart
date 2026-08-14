import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:readsms/readsms.dart';

import 'inbound_sync_service.dart';
import 'listening_notification.dart';

/// Keeps SMS listening active for the whole logged-in session (not only the Inbox tab).
class SmsInboundListener {
  SmsInboundListener._();

  static final SmsInboundListener instance = SmsInboundListener._();

  final StreamController<void> _messageEvents = StreamController<void>.broadcast();
  final StreamController<String?> _errorEvents = StreamController<String?>.broadcast();

  Readsms? _readsms;
  bool _starting = false;
  bool _started = false;
  String? _lastError;

  Stream<void> get onMessage => _messageEvents.stream;
  Stream<String?> get onError => _errorEvents.stream;
  String? get lastError => _lastError;
  bool get isStarted => _started;

  Future<void> ensureStarted({bool force = false}) async {
    if ((_started && !force) || _starting) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    if (force && _started) {
      _readsms?.dispose();
      _readsms = null;
      _started = false;
    }

    _starting = true;
    try {
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        _lastError = 'SMS permission denied. Allow SMS access for listener sync.';
        _errorEvents.add(_lastError);
        return;
      }

      await ListeningNotification.instance.showListening();
      _readsms = Readsms();
      _readsms!.read();
      _readsms!.smsStream.listen(
        (sms) async {
          final accepted = await InboundSyncService.instance.onSmsReceived(
            sender: sms.sender,
            body: sms.body,
            timeReceived: sms.timeReceived,
          );
          if (accepted) {
            await ListeningNotification.instance.showListenerIncomingSms(
              from: sms.sender,
              bodyPreview: sms.body,
            );
            if (!_messageEvents.isClosed) {
              _messageEvents.add(null);
            }
          }
        },
        onError: (e) {
          _lastError = e.toString();
          _errorEvents.add(_lastError);
        },
      );
      _started = true;
      _lastError = null;
      _errorEvents.add(null);
    } catch (e) {
      _lastError = e.toString();
      _errorEvents.add(_lastError);
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _readsms?.dispose();
    _readsms = null;
    _started = false;
    _starting = false;
    await ListeningNotification.instance.dismiss();
  }
}
