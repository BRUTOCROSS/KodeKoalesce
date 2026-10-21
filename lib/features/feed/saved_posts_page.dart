import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'feed_page.dart';

class SavedPostsPage extends StatefulWidget {
  const SavedPostsPage({super.key});

  @override
  State<SavedPostsPage> createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<SavedPostsPage> {
  final GlobalKey _viewportKey = GlobalKey();
  final ValueNotifier<int> _visibilityRevision = ValueNotifier<int>(0);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _savedPostsStream;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    _savedPostsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('savedPosts')
        .orderBy('savedAt', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  void dispose() {
    _visibilityRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved posts')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _savedPostsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SavedPostsMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load saved posts',
            message:
                'Check your connection and Firestore rules, then try again.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const _SavedPostsMessage(
            icon: Icons.bookmark_border_rounded,
            title: 'No saved posts yet',
            message: 'Tap the bookmark on a post to keep it here for later.',
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              _visibilityRevision.value++;
            }
            return false;
          },
          child: ListView.separated(
            key: _viewportKey,
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = data['authorName'] as String? ?? 'Developer';
              final post = FeedPost(
                id: data['postId'] as String? ?? doc.id,
                authorId: data['authorId'] as String? ?? '',
                name: name,
                handle: data['authorHandle'] as String? ?? '@developer',
                initials:
                    data['initials'] as String? ??
                    (name.isEmpty ? 'D' : name.substring(0, 1).toUpperCase()),
                tint: const Color(0xFFD7E8DC),
                time: data['time'] as String? ?? 'saved',
                text: data['text'] as String? ?? '',
                topic: data['topic'] as String? ?? 'community',
                replies: (data['replyCount'] as num?)?.toInt() ?? 0,
                views: (data['viewCount'] as num?)?.toInt() ?? 0,
              );
              return PostCard(
                key: ValueKey(post.id),
                post: post,
                viewportKey: _viewportKey,
                visibilityRevision: _visibilityRevision,
              );
            },
          ),
        );
      },
    ),
  );
}

class _SavedPostsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SavedPostsMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: mutedText(context)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText(context)),
          ),
        ],
      ),
    ),
  );
}
