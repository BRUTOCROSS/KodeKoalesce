import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'followers_page.dart';
import 'social_notifications.dart';
import 'profile_external_link.dart';
import 'builder_name_heading.dart';
import '../projects/projects_page.dart' show openProjectWorkspace;

class PublicProfilePage extends StatelessWidget {
  final String userId;
  final String displayName;
  final String handle;
  final String initials;

  const PublicProfilePage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.handle,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final isOwnProfile = currentUserId == userId;
    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(userId);
    final postsQuery = FirebaseFirestore.instance
        .collection('posts')
        .where('authorId', isEqualTo: userId)
        .limit(50);
    final projectsQuery = FirebaseFirestore.instance
        .collection('projects')
        .where('ownerId', isEqualTo: userId)
        .limit(20);
    final followersStream = FirebaseFirestore.instance
        .collectionGroup('following')
        .where('userId', isEqualTo: userId)
        .limit(50)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: postsQuery.snapshots(),
        builder: (context, postSnapshot) {
          if (postSnapshot.hasError) {
            return _loadError(context, 'Could not load this profile’s posts.');
          }
          if (!postSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: projectsQuery.snapshots(),
            builder: (context, projectSnapshot) {
              if (projectSnapshot.hasError) {
                return _loadError(
                  context,
                  'Could not load this profile’s projects.',
                );
              }
              if (!projectSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final posts = postSnapshot.data!.docs.toList()
                ..sort(
                  (a, b) =>
                      _dateOf(b.data()['createdAt'])
                          .compareTo(_dateOf(a.data()['createdAt'])),
                );
              final projects = projectSnapshot.data!.docs.toList()
                ..sort(
                  (a, b) =>
                      _dateOf(b.data()['createdAt'])
                          .compareTo(_dateOf(a.data()['createdAt'])),
                );

              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                children: [
                  _profileHeader(
                    context,
                    postsCount: posts.length,
                    projectsCount: projects.length,
                    isOwnProfile: isOwnProfile,
                    followingRef: followingRef,
                    followersStream: followersStream,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(context, 'Projects', Icons.folder_outlined),
                  const SizedBox(height: 9),
                  if (projects.isEmpty)
                    _emptySection(context, 'No public projects yet.')
                  else
                    for (final project in projects)
                      _projectCard(context, project),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'Posts', Icons.chat_bubble_outline),
                  const SizedBox(height: 9),
                  if (posts.isEmpty)
                    _emptySection(context, 'No posts yet.')
                  else
                    for (final post in posts) _postCard(context, post),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _profileHeader(
    BuildContext context, {
    required int postsCount,
    required int projectsCount,
    required bool isOwnProfile,
    required DocumentReference<Map<String, dynamic>> followingRef,
    required Stream<QuerySnapshot<Map<String, dynamic>>> followersStream,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: outlineColor(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFD7E8DC),
              child: Text(
                initials,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            if (!isOwnProfile)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: followingRef.snapshots(),
                builder: (context, followSnapshot) {
                  final isFollowing = followSnapshot.data?.exists ?? false;
                  return FilledButton.tonal(
                    onPressed: followSnapshot.hasError
                        ? null
                        : () =>
                              _toggleFollow(context, followingRef, isFollowing),
                    child: Text(isFollowing ? 'Following' : 'Follow'),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        BuilderNameHeading(name: displayName, fontSize: 27),
        const SizedBox(height: 3),
        Text(handle, style: TextStyle(color: mutedText(context))),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('publicProfiles')
              .doc(userId)
              .snapshots(),
          builder: (context, snapshot) {
            final details = snapshot.data?.data();
            if (details == null) return const SizedBox.shrink();
            final headline = details['headline'] as String? ?? '';
            final location = details['location'] as String? ?? '';
            final skills = details['skills'] is List
                ? (details['skills'] as List).whereType<String>().toList()
                : const <String>[];
            final interests = details['interests'] is List
                ? (details['interests'] as List).whereType<String>().toList()
                : const <String>[];
            final bio = details['bio'] as String? ?? '';
            final github = details['githubUrl'] as String? ?? '';
            final website = details['websiteUrl'] as String? ?? '';
            if ([
                  headline,
                  location,
                  bio,
                  github,
                  website,
                ].every((v) => v.trim().isEmpty) &&
                skills.isEmpty &&
                interests.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (headline.trim().isNotEmpty)
                    Text(
                      headline,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if (location.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    _DetailLine(
                      icon: Icons.location_on_outlined,
                      text: location,
                    ),
                  ],
                  if (bio.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      style: TextStyle(color: mutedText(context), height: 1.4),
                    ),
                  ],
                  if (skills.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _detailChips(context, 'Skills', skills),
                  ],
                  if (interests.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _detailChips(context, 'Interested in', interests),
                  ],
                  if (github.trim().isNotEmpty ||
                      website.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (github.trim().isNotEmpty)
                          ProfileExternalLink(
                            icon: Icons.code_rounded,
                            label: 'GitHub',
                            url: github,
                          ),
                        if (website.trim().isNotEmpty)
                          ProfileExternalLink(
                            icon: Icons.link_rounded,
                            label: 'Portfolio',
                            url: website,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _ProfileStat(value: '$postsCount', label: 'Posts'),
            _ProfileStat(value: '$projectsCount', label: 'Projects'),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: followersStream,
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                return _ProfileStat(
                  value: snapshot.hasError
                      ? '!'
                      : !snapshot.hasData
                      ? '…'
                      : count >= 50
                      ? '50+'
                      : '$count',
                  label: 'Followers',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => FollowersPage(userId: userId),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    ),
  );

  Widget _sectionTitle(BuildContext context, String title, IconData icon) =>
      Row(
        children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      );

  Widget _emptySection(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(message, style: TextStyle(color: mutedText(context))),
  );

  Widget _projectCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> project,
  ) {
    final data = project.data();
    final tags = (data['tags'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .take(3)
        .toList();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openProjectWorkspace(context, project.id),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: outlineColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_rounded, color: colors.primary, size: 20),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        data['title'] as String? ?? 'Untitled project',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: mutedText(context),
                    ),
                  ],
                ),
                if ((data['description'] as String? ?? '')
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    data['description'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedText(context), height: 1.35),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in tags)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _postCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> post,
  ) {
    final data = post.data();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['text'] as String? ?? '',
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 9),
          Text(
            '# ${data['topic'] as String? ?? 'community'}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  DateTime _dateOf(Object? value) =>
      value is Timestamp ? value.toDate() : DateTime(0);

  Widget _loadError(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: mutedText(context)),
      ),
    ),
  );

  Future<void> _toggleFollow(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> follow,
    bool isFollowing,
  ) async {
    try {
      if (isFollowing) {
        await follow.delete();
      } else {
        await follow.set({
          'userId': userId,
          'displayName': displayName,
          'handle': handle,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await notifyNewFollower(userId);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update following. Check Firestore rules.'),
          ),
        );
      }
    }
  }
}

Widget _detailChips(BuildContext context, String label, List<String> values) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: mutedText(context), fontSize: 12)),
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final value in values.take(8))
              Chip(
                label: Text(value),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide.none,
              ),
          ],
        ),
      ],
    );

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: mutedText(context)),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          style: TextStyle(color: mutedText(context), fontSize: 12),
        ),
      ),
    ],
  );
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _ProfileStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? mutedText(context)
                  : Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: onTap == null ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
