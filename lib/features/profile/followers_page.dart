import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'public_profile_page.dart';

class FollowersPage extends StatefulWidget {
  final String userId;

  const FollowersPage({super.key, required this.userId});

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _followersStream;

  @override
  void initState() {
    super.initState();
    _followersStream = FirebaseFirestore.instance
        .collectionGroup('following')
        .where('userId', isEqualTo: widget.userId)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Followers')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _followersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          final details = error is FirebaseException
              ? '${error.code}: ${error.message ?? 'No details'}'
              : '$error';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load followers.\n$details',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText(context)),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final followers = snapshot.data!.docs;
        if (followers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No followers yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'When people follow this profile, they’ll appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedText(context)),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: followers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) => _FollowerTile(
            key: ValueKey(followers[index].reference.path),
            followerId: followers[index].reference.parent.parent!.id,
          ),
        );
      },
    ),
  );
}

class _FollowerTile extends StatelessWidget {
  final String followerId;

  const _FollowerTile({super.key, required this.followerId});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('publicProfiles')
            .doc(followerId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final name = data?['displayName'] as String? ?? 'Community member';
          final handle = data?['handle'] as String? ?? '@developer';
          final initial = name.trim().isEmpty
              ? 'D'
              : name.trim()[0].toUpperCase();
          return Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: outlineColor(context)),
              ),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFD7E8DC),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: handle.isEmpty ? null : Text(handle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PublicProfilePage(
                    userId: followerId,
                    displayName: name,
                    handle: handle,
                    initials: initial,
                  ),
                ),
              ),
            ),
          );
        },
      );
}
