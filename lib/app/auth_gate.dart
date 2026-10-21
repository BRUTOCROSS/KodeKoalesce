import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../features/auth/auth_page.dart';
import '../features/profile/profile_utils.dart';
import 'app_shell.dart';

class AuthGate extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const AuthGate({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _authStateChanges;

  @override
  void initState() {
    super.initState();
    // Keep the stream instance stable when the app rebuilds for a theme change.
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthPage();
        }

        return _ProfileSetupGate(
          user: user,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        );
      },
    );
  }
}

class _ProfileSetupGate extends StatefulWidget {
  final User user;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const _ProfileSetupGate({
    required this.user,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<_ProfileSetupGate> createState() => _ProfileSetupGateState();
}

class _ProfileSetupGateState extends State<_ProfileSetupGate> {
  late Future<void> _profileSetup;

  @override
  void initState() {
    super.initState();
    _profileSetup = _ensureProfile();
  }

  Future<void> _ensureProfile() async {
    final user = widget.user;
    final firestore = FirebaseFirestore.instance;
    final profile = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final snapshot = await profile.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final storedName = data['displayName'] as String?;
    final displayName = storedName?.trim().isNotEmpty == true
        ? storedName!.trim()
        : user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'Developer';
    if (!snapshot.exists) {
      await profile.set({
        'uid': user.uid,
        'displayName': displayName,
        'email': user.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final handle = profileHandleForName(displayName);
    final publicProfile = firestore.collection('publicProfiles').doc(user.uid);
    final publicSnapshot = await publicProfile.get();
    if (!publicSnapshot.exists) {
      await publicProfile.set({
        'uid': user.uid,
        'displayName': displayName,
        'handle': handle,
        'bio': data['bio'] as String? ?? '',
        'searchPrefixes': profileSearchPrefixes(displayName, handle),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _retry() => setState(() => _profileSetup = _ensureProfile());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _profileSetup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 42),
                    const SizedBox(height: 14),
                    const Text(
                      'We couldn’t set up your profile yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Check that Firestore rules have been published, then try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final user = widget.user;
        return AppShell(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          displayName: user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : user.email?.split('@').first ?? 'Developer',
          email: user.email ?? '',
        );
      },
    );
  }
}
