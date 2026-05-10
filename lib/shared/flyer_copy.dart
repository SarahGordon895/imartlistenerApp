import 'package:flutter/material.dart';

/// Marketing / KPI reference aligned with the VLL SMS Feedback flyer and radio operations.
class FlyerCopy {
  FlyerCopy._();

  static const String headline =
      'The smart audience engagement solution for modern radio stations.';

  static const List<String> perfectFor = [
    'FM Radio Stations',
    'Talk Shows',
    'Live Broadcast Programs',
    'Online Radio Platforms',
  ];

  static List<({IconData icon, String label})> get valueProps => [
        (icon: Icons.podcasts_outlined, label: 'Increase listener interaction'),
        (icon: Icons.bar_chart_outlined, label: 'Track real-time feedback'),
        (icon: Icons.sms_outlined, label: 'Receive SMS comments instantly'),
        (icon: Icons.how_to_vote_outlined, label: 'Run live polls & voting'),
        (icon: Icons.trending_up_outlined, label: 'Improve station KPIs'),
        (icon: Icons.attach_money_outlined, label: 'Increase advertiser value'),
      ];

  /// Shown on the dashboard hero; wording matches what the app actually ships today.
  static const List<String> appHighlights = [
    'Live SMS feedback (device → portal sync)',
    'Audience polls & voting (from Inbox on this device)',
    'Participation & KPI slice (counts + segment tags after sync)',
    'Sponsor-ready engagement (listener SMS during shows)',
    'Inbox & sync stats on this device (pair with SMSver1 for full analytics)',
  ];

  /// Educational: full-station KPIs; this app covers SMS/participation slice + portal.
  static const String stationKpiReference =
      'Radio KPIs cover audience growth, revenue, program performance, and operations. '
      'Examples: grow daily listeners (e.g. +20%), reach monthly SMS interaction targets (e.g. 10,000), '
      'ad revenue goals, high on-air uptime (e.g. 95%), new advertisers per month.\n\n'
      'Typical areas: listeners/viewers, engagement rate, ad revenue, sponsors, social reach, '
      'SMS participation during shows, call-ins, ratings, stream listeners, web/app traffic, '
      'satisfaction, uptime, campaign performance.\n\n'
      'This app: live SMS capture & portal sync, Inbox, polls (device), audience/social checks, '
      'on-air sender IDs from SMSver1, and segment auto-replies. Pair with SMSver1 for bulk SMS, '
      'billing, and full station analytics.';
}
