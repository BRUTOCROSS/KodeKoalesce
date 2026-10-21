import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../profile/social_notifications.dart';

class CommentsPage extends StatefulWidget {
  final String postId;
  final String postAuthorName;
  final String postText;

  const CommentsPage({
    super.key,
    required this.postId,
    required this.postAuthorName,
    required this.postText,
  });

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final _controller = TextEditingController();
  final _composerFocusNode = FocusNode();
  String? _replyingToId;
  String? _replyingToName;
  bool _isSending = false;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _commentStream;

  CollectionReference<Map<String, dynamic>> get _comments => FirebaseFirestore
      .instance
      .collection('posts')
      .doc(widget.postId)
      .collection('comments');

  @override
  void initState() {
    super.initState();
    _commentStream = _comments.snapshots();
  }

  @override
  void dispose() {
    _controller.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Replies')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _commentStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Could not load replies. Check Firestore rules.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allComments = snapshot.data!.docs.toList()
                  ..sort((a, b) => _dateFrom(a).compareTo(_dateFrom(b)));
                final childrenByParent =
                    <
                      String?,
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    >{};
                for (final comment in allComments) {
                  final parentId = comment.data()['parentId'] as String?;
                  childrenByParent.putIfAbsent(parentId, () => []).add(comment);
                }
                final topLevelComments = childrenByParent[null] ?? [];

                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                  children: [
                    _originalPost(),
                    const Divider(height: 28),
                    if (topLevelComments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'No replies yet. Start the conversation.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...topLevelComments.map(
                        (comment) =>
                            _commentThread(context, comment, childrenByParent),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: _replyingToName == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 12, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Replying to $_replyingToName',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _cancelReply,
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Cancel reply',
                              ),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _composerFocusNode,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            hintText: 'Write a reply…',
                            border: OutlineInputBorder(),
                            counterText: '',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) => IconButton.filled(
                          onPressed: _isSending || value.text.trim().isEmpty
                              ? null
                              : _sendComment,
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          tooltip: 'Send reply',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _originalPost() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CircleAvatar(
        radius: 20,
        backgroundColor: Color(0xFFD7E8DC),
        child: Icon(Icons.person_rounded, color: AppColors.ink),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.postAuthorName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(widget.postText),
          ],
        ),
      ),
    ],
  );

  Widget _commentThread(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> comment,
    Map<String?, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    childrenByParent,
  ) {
    final data = comment.data();
    final author = data['authorName'] as String? ?? 'Developer';
    final text = data['text'] as String? ?? '';
    final initial = author.trim().isEmpty
        ? 'D'
        : author.trim()[0].toUpperCase();
    final replies = childrenByParent[comment.id] ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFD7E8DC),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$author  ·  ${_timeAgo(_dateFrom(comment))}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(text),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _replyingToId = comment.id;
                          _replyingToName = author;
                        });
                        FocusScope.of(context).requestFocus(_composerFocusNode);
                      },
                      icon: const Icon(Icons.reply_rounded, size: 17),
                      label: const Text('Reply'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: replies.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(left: 17, top: 2),
                    padding: const EdgeInsets.only(left: 15),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      children: replies
                          .map(
                            (reply) => _commentThread(
                              context,
                              reply,
                              childrenByParent,
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  DateTime _dateFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final created = doc.data()['createdAt'];
    return created is Timestamp ? created.toDate() : DateTime(0);
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
  }

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final storedName = profile.data()?['displayName'] as String?;
      final name = storedName?.trim().isNotEmpty == true
          ? storedName!.trim()
          : user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? 'Developer';
      final comment = await _comments.add({
        'authorId': user.uid,
        'authorName': name,
        'text': text,
        'parentId': _replyingToId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await notifyPostReply(postId: widget.postId, commentId: comment.id);
      if (mounted) {
        _controller.clear();
        setState(() {
          _replyingToId = null;
          _replyingToName = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send reply. Check Firestore rules.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _timeAgo(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}
