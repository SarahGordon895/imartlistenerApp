import 'package:flutter/material.dart';

import '../services/inbound_sync_service.dart';
import '../services/sms_inbound_listener.dart';
import 'compose_screen.dart';
import 'dashboard_tab.dart';
import 'incoming_messages_screen.dart';
import 'polls_screen.dart';
import 'social_checks_screen.dart';

/// Bottom navigation on phones; side rail on tablets/desktop for space and clarity.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Width at or above this uses [NavigationRail] instead of bottom bar.
  static const double railBreakpoint = 720;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InboundSyncService.instance.startPeriodicRetry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InboundSyncService.instance.flushPending();
      SmsInboundListener.instance.ensureStarted();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    InboundSyncService.instance.stopPeriodicRetry();
    SmsInboundListener.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      InboundSyncService.instance.flushPending();
    }
  }

  static const _labels = ['Home', 'Compose', 'Inbox', 'Polls', 'Audience'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardTab(),
      ComposeScreen(onOpenTab: (i) => setState(() => _index = i)),
      IncomingMessagesScreen(isActive: _index == 2),
      PollsScreen(isActive: _index == 3),
      SocialChecksScreen(isActive: _index == 4),
    ];

    final useRail = MediaQuery.sizeOf(context).width >= MainShell.railBreakpoint;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              minWidth: 88,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: Text(_labels[0]),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.radio_outlined),
                  selectedIcon: const Icon(Icons.radio),
                  label: Text(_labels[1]),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.inbox_outlined),
                  selectedIcon: const Icon(Icons.inbox),
                  label: Text(_labels[2]),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.how_to_vote_outlined),
                  selectedIcon: const Icon(Icons.how_to_vote),
                  label: Text(_labels[3]),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.manage_search_outlined),
                  selectedIcon: const Icon(Icons.manage_search),
                  label: Text(_labels[4]),
                ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: pages,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: _labels[0],
          ),
          NavigationDestination(
            icon: const Icon(Icons.radio_outlined),
            selectedIcon: const Icon(Icons.radio),
            label: _labels[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.inbox_outlined),
            selectedIcon: const Icon(Icons.inbox),
            label: _labels[2],
          ),
          NavigationDestination(
            icon: const Icon(Icons.how_to_vote_outlined),
            selectedIcon: const Icon(Icons.how_to_vote),
            label: _labels[3],
          ),
          NavigationDestination(
            icon: const Icon(Icons.manage_search_outlined),
            selectedIcon: const Icon(Icons.manage_search),
            label: _labels[4],
          ),
        ],
      ),
    );
  }
}
