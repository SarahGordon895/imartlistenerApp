import 'package:flutter/material.dart';

import '../services/desk_selection.dart';
import '../services/inbound_sync_service.dart';
import '../services/listen_keyword_service.dart';
import '../services/notification_capture_service.dart';
import '../services/sms_inbound_listener.dart';
import 'compose_screen.dart';
import 'dashboard_tab.dart';
import 'incoming_messages_screen.dart';
import 'social_checks_screen.dart';

/// Business desk: Home · Inbox · Reply · Social
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static const double railBreakpoint = 700;
  static const double wideBreakpoint = 1100;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  final _composeKey = GlobalKey<ComposeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InboundSyncService.instance.startPeriodicRetry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        ListenKeywordService.instance.refreshFromApi();
        InboundSyncService.instance.flushPending();
        SmsInboundListener.instance.ensureStarted();
        NotificationCaptureService.instance.ensureStarted();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    InboundSyncService.instance.stopPeriodicRetry();
    SmsInboundListener.instance.stop();
    NotificationCaptureService.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ListenKeywordService.instance.refreshFromApi();
      InboundSyncService.instance.flushPending();
      SmsInboundListener.instance.ensureStarted();
      NotificationCaptureService.instance.ensureStarted();
    }
  }

  void _openSocial({String? phone}) {
    if (phone != null && phone.trim().isNotEmpty) {
      SocialChecksScreen.requestPrefillPhone(phone.trim());
    }
    setState(() => _index = 3);
  }

  void _openReply(List<CapturedMessage> picks) {
    if (picks.isNotEmpty) {
      DeskSelection.instance.openReplyWith(picks);
    }
    setState(() => _index = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composeKey.currentState?.reloadFromDesk();
    });
  }

  void _openReplyDesk() => _openReply([]);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardTab(
        onOpenTab: (i) => setState(() => _index = i),
        onOpenSocialLookup: _openSocial,
        onOpenReply: _openReplyDesk,
      ),
      IncomingMessagesScreen(
        isActive: _index == 1,
        onOpenSocialLookup: _openSocial,
        onOpenReply: _openReply,
      ),
      ComposeScreen(
        key: _composeKey,
        onOpenTab: (i) => setState(() => _index = i),
      ),
      SocialChecksScreen(isActive: _index == 3),
    ];

    final useRail = MediaQuery.sizeOf(context).width >= MainShell.railBreakpoint;
    final wide = MediaQuery.sizeOf(context).width >= MainShell.wideBreakpoint;

    if (useRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: wide,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: wide
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.inbox_outlined),
                    selectedIcon: Icon(Icons.inbox),
                    label: Text('Inbox'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.reply_outlined),
                    selectedIcon: Icon(Icons.reply),
                    label: Text('Reply'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.travel_explore_outlined),
                    selectedIcon: Icon(Icons.travel_explore),
                    label: Text('Social'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: IndexedStack(index: _index, children: pages),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(Icons.reply_outlined),
            selectedIcon: Icon(Icons.reply),
            label: 'Reply',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: 'Social',
          ),
        ],
      ),
    );
  }
}
