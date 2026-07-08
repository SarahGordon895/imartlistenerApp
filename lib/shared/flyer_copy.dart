import 'package:flutter/material.dart';

/// Value props for the business SMS + WhatsApp desk (not radio/FM).
class FlyerCopy {
  FlyerCopy._();

  static const String headline =
      'Capture customer SMS and WhatsApp. Reply manually from one desk.';

  static const List<String> perfectFor = [
    'Instagram / social sellers',
    'Small business customer care',
    'WhatsApp business lines',
    'Shared phone + portal teams',
  ];

  static List<({IconData icon, String label})> get valueProps => [
        (icon: Icons.sms_outlined, label: 'Capture normal SMS'),
        (icon: Icons.chat, label: 'Capture WhatsApp notifications'),
        (icon: Icons.reply_all_outlined, label: 'Manual reply (no auto-reply)'),
        (icon: Icons.forum_outlined, label: 'Threads sync to imartPortal'),
        (icon: Icons.filter_alt_outlined, label: 'Filter by channel & status'),
        (icon: Icons.phone_android, label: 'Runs on the business phone'),
      ];

  static const List<String> appHighlights = [
    'SMS + WhatsApp inbound on one Inbox',
    'Manual SMS reply via your Sender ID',
    'WhatsApp replies logged in conversations',
    'No radio polls / no FM auto-reply flow',
    'Same account as imartPortal client desk',
  ];

  static const String stationKpiReference =
      'Desk metrics: messages captured, awaiting reply, SMS vs WhatsApp split, '
      'and portal sync status. Pair with imartPortal Conversations for the full thread history.';
}
