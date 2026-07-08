import 'package:flutter/foundation.dart';

/// A captured SMS / WhatsApp row chosen in Inbox for Reply desk.
class CapturedMessage {
  CapturedMessage({
    required this.phone,
    required this.body,
    this.channel = 'sms',
    this.incomingId,
    this.localId,
    this.contactName,
  });

  final String phone;
  final String body;
  final String channel;
  final int? incomingId;
  final int? localId;
  final String? contactName;

  String get displayTitle =>
      (contactName != null && contactName!.trim().isNotEmpty)
          ? '${contactName!.trim()} · $phone'
          : phone;
}

/// Shared selection between Inbox and Reply tabs.
class DeskSelection {
  DeskSelection._();
  static final DeskSelection instance = DeskSelection._();

  final ValueNotifier<List<CapturedMessage>> selected =
      ValueNotifier<List<CapturedMessage>>([]);

  /// Bump when Reply tab should reload selection / templates.
  final ValueNotifier<int> replyTick = ValueNotifier<int>(0);

  void set(List<CapturedMessage> items) {
    selected.value = List<CapturedMessage>.from(items);
    replyTick.value++;
  }

  void clear() {
    selected.value = [];
    replyTick.value++;
  }

  void openReplyWith(List<CapturedMessage> items) {
    set(items);
  }
}
