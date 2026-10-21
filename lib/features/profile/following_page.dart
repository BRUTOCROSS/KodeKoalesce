import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'public_profile_page.dart';

class FollowingPage extends StatefulWidget {
  final String userId;

  const FollowingPage({super.key, required this.userId});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _followingStream;

  @override
  void initState() {
    super.initState();
    _followingStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('following')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Following')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _followingStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load the people you follow. Check your Firestore rules.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText(context)),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final people = snapshot.data!.docs;
        if (people.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_search_rounded,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You’re not following anyone yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Follow someone from a post to find them here.',
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
          itemCount: people.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) =>
              _FollowingPersonTile(followingDocument: people[index]),
        );
      },
    ),
  );
}

class _FollowingPersonTile extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> followingDocument;

  const _FollowingPersonTile({required this.followingDocument});

  @override
  State<_FollowingPersonTile> createState() => _FollowingPersonTileState();
}

class _FollowingPersonTileState extends State<_FollowingPersonTile> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;

  String get _personId =>
      widget.followingDocument.data()['userId'] as String? ??
      widget.followingDocument.id;

  @override
  void initState() {
    super.initState();
    _profileStream = FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(_personId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profileStream,
        builder: (context, snapshot) {
          final profile = snapshot.data?.data();
          final savedData = widget.followingDocument.data();
          final name =
              profile?['displayName'] as String? ??
              savedData['displayName'] as String? ??
              'Community member';
          final handle =
              profile?['handle'] as String? ??
              savedData['handle'] as String? ??
              '@developer';
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
                  name.isEmpty ? '…' : name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: handle.isEmpty ? null : Text(handle),
              trailing: IconButton(
                tooltip: 'Unfollow',
                onPressed: () => _unfollow(context),
                icon: Icon(
                  Icons.person_remove_alt_1_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PublicProfilePage(
                    userId: _personId,
                    displayName: name,
                    handle: handle,
                    initials: name.isEmpty
                        ? 'D'
                        : name.substring(0, 1).toUpperCase(),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Future<void> _unfollow(BuildContext context) async {
    try {
      await widget.followingDocument.reference.delete();
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unfollow (${error.code}).')),
        );
      }
    }
  }
}
