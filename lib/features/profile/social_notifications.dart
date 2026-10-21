import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> notifyNewFollower(String recipientId) async {
  final actor = FirebaseAuth.instance.currentUser;
  if (actor == null || actor.uid == recipientId) return;

  try {
    final firestore = FirebaseFirestore.instance;
    final follow = firestore
        .collection('users')
        .doc(actor.uid)
        .collection('following')
        .doc(recipientId);
    if (!(await follow.get()).exists) return;

    final profile = await firestore
        .collection('publicProfiles')
        .doc(actor.uid)
        .get();
    final data = profile.data() ?? const <String, dynamic>{};
    await firestore
        .collection('users')
        .doc(recipientId)
        .collection('notifications')
        .add({
          'kind': 'social_follow',
          'actorId': actor.uid,
          'actorName': data['displayName'] as String? ?? 'A developer',
          'actorHandle': data['handle'] as String? ?? '@developer',
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
  } catch (_) {
    // The follow action should still succeed if a notification cannot be sent.
  }
}

Future<void> notifyPostReply({
  required String postId,
  required String commentId,
}) async {
  final actor = FirebaseAuth.instance.currentUser;
  if (actor == null) return;

  try {
    final firestore = FirebaseFirestore.instance;
    final post = await firestore.collection('posts').doc(postId).get();
    final recipientId = post.data()?['authorId'] as String?;
    if (!post.exists || recipientId == null || recipientId == actor.uid) return;

    final comment = await firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .get();
    if (!comment.exists) return;

    final profile = await firestore
        .collection('publicProfiles')
        .doc(actor.uid)
        .get();
    final data = profile.data() ?? const <String, dynamic>{};
    await firestore
        .collection('users')
        .doc(recipientId)
        .collection('notifications')
        .add({
          'kind': 'post_reply',
          'actorId': actor.uid,
          'actorName': data['displayName'] as String? ?? 'A developer',
          'actorHandle': data['handle'] as String? ?? '@developer',
          'postId': postId,
          'commentId': commentId,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
  } catch (_) {
    // The reply should still succeed if a notification cannot be sent.
  }
}
