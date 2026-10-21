import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class KodeKoalesceDrawer extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final ValueChanged<String> onComingSoon;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String displayName;
  final String email;
  final Future<void> Function() onSignOut;
  const KodeKoalesceDrawer({
    super.key,
    required this.onNavigate,
    required this.onComingSoon,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.displayName,
    required this.email,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Column(
        children: [
          InkWell(
            onTap: () => onNavigate(3),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Color(0xFFD7E8DC),
                    child: Icon(
                      Icons.person_rounded,
                      color: AppColors.ink,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${email.split('@').first}',
                    style: TextStyle(color: mutedText(context), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('0 following', style: _drawerCountStyle(context)),
                      SizedBox(width: 14),
                      Text('0 followers', style: _drawerCountStyle(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerItem(
                  icon: Icons.person_outline_rounded,
                  title: 'Profile',
                  onTap: () => onNavigate(3),
                ),
                _DrawerItem(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Saved posts',
                  onTap: () => onComingSoon('Saved posts'),
                ),
                _DrawerItem(
                  icon: Icons.grid_view_rounded,
                  title: 'Projects',
                  onTap: () => onNavigate(1),
                ),
                _DrawerItem(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Rooms',
                  onTap: () => onNavigate(2),
                ),
                _DrawerItem(
                  icon: Icons.interests_outlined,
                  title: 'Your interests',
                  onTap: () => onComingSoon('Interests'),
                ),
                const Divider(indent: 16, endIndent: 16, height: 18),
                _DrawerItem(
                  icon: Icons.tune_rounded,
                  title: 'Settings & privacy',
                  onTap: () => onComingSoon('Settings & privacy'),
                ),
                _DrawerItem(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & feedback',
                  onTap: () => onComingSoon('Help & feedback'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            onTap: onSignOut,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: themeMode == ThemeMode.dark
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                onPressed: () => onThemeModeChanged(
                  themeMode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  TextStyle _drawerCountStyle(BuildContext context) => TextStyle(
    color: Theme.of(context).colorScheme.onSurface,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      icon,
      color: Theme.of(context).colorScheme.onSurface,
      size: 21,
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    minLeadingWidth: 28,
    dense: true,
    onTap: onTap,
  );
}
