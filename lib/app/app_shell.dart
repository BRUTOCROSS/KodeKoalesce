import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/feed/feed_page.dart';
import '../features/feed/saved_posts_page.dart';
import '../features/profile/profile_page.dart';
import '../features/projects/projects_page.dart';
import '../features/projects/project_notifications_page.dart';
import '../features/rooms/rooms_page.dart';
import '../core/widgets/collapsible_chrome.dart';
import '../core/widgets/kode_bottom_navigation_bar.dart';
import '../screens/settings_screen.dart';
import 'kodekoalesce_drawer.dart';

class AppShell extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String displayName;
  final String email;
  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.displayName,
    required this.email,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late String _displayName;
  int selectedIndex = 0;
  bool _chromeVisible = true;
  final labels = const ['Feed', 'Projects', 'Rooms', 'You'];
  final icons = const [
    Icons.dynamic_feed_rounded,
    Icons.grid_view_rounded,
    Icons.graphic_eq_rounded,
    Icons.person_outline_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: KodeKoalesceDrawer(
        onNavigate: _navigateTo,
        onComingSoon: _showComingSoon,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        displayName: _displayName,
        email: widget.email,
        onSignOut: () async {
          Navigator.of(context).pop();
          await FirebaseAuth.instance.signOut();
        },
      ),
      body: SafeArea(
        child: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis != Axis.vertical) return false;
            if (notification.direction == ScrollDirection.reverse &&
                _chromeVisible) {
              setState(() => _chromeVisible = false);
            } else if (notification.direction == ScrollDirection.forward &&
                !_chromeVisible) {
              setState(() => _chromeVisible = true);
            }
            return false;
          },
          child: _buildPage(),
        ),
      ),
      bottomNavigationBar: CollapsibleChrome(
        visible: _chromeVisible,
        alignment: Alignment.bottomCenter,
        child: KodeBottomNavigationBar(
          selectedIndex: selectedIndex,
          labels: labels,
          icons: icons,
          onDestinationSelected: (value) => setState(() {
            selectedIndex = value;
            _chromeVisible = true;
          }),
        ),
      ),
      floatingActionButton: selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () => _showCompose(context),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              child: const Icon(Icons.edit_rounded),
            )
          : null,
    );
  }

  Widget _buildPage() {
    void openDrawer() => _scaffoldKey.currentState?.openDrawer();
    return IndexedStack(
      index: selectedIndex,
      children: [
        FeedPage(
          onOpenDrawer: openDrawer,
          onOpenNotifications: _openNotifications,
          chromeVisible: _chromeVisible,
        ),
        ProjectsPage(onOpenDrawer: openDrawer, chromeVisible: _chromeVisible),
        RoomsPage(onOpenDrawer: openDrawer, chromeVisible: _chromeVisible),
        ProfilePage(
          onOpenDrawer: openDrawer,
          chromeVisible: _chromeVisible,
          displayName: _displayName,
          email: widget.email,
          onDisplayNameChanged: (name) => setState(() => _displayName = name),
        ),
      ],
    );
  }

  void _navigateTo(int index) {
    Navigator.of(context).pop();
    setState(() {
      selectedIndex = index;
      _chromeVisible = true;
    });
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProjectNotificationsPage(
          userId: FirebaseAuth.instance.currentUser!.uid,
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    Navigator.of(context).pop();
    if (feature == 'Settings & privacy') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      );
      return;
    }
    if (feature == 'Saved posts') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SavedPostsPage()),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature will be available as we build it.')),
    );
  }

  void _showCompose(BuildContext context) {
    final controller = TextEditingController();
    bool isSaving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Share with the community',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 500,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'What’s on your mind? Share a thought, a laugh, or some news…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        setSheetState(() => isSaving = true);
                        try {
                          final user = FirebaseAuth.instance.currentUser!;
                          await FirebaseFirestore.instance.collection('posts').add({
                            'authorId': user.uid,
                            'authorName': _displayName,
                            'authorHandle':
                                '@${_displayName.toLowerCase().replaceAll(' ', '')}',
                            'text': text,
                            'topic': 'community',
                            'category': 'community',
                            'replyCount': 0,
                            'viewCount': 0,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        } catch (_) {
                          if (sheetContext.mounted) {
                            setSheetState(() => isSaving = false);
                          }
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not post. Check that the Firestore rules are published.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: Text(isSaving ? 'Posting…' : 'Post to Feed'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
