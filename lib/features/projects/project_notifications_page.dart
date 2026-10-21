import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../feed/comments_page.dart';
import '../profile/public_profile_page.dart';
import 'project_file_proposals_page.dart'
    show openMyProjectFileProposals, openProjectFileProposals;
import 'projects_page.dart' show openProjectActivity;

class ProjectNotificationsButton extends StatelessWidget {
  final String userId;
  final VoidCallback onPressed;

  const ProjectNotificationsButton({
    super.key,
    required this.userId,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final requests = FirebaseFirestore.instance
        .collectionGroup('contributionRequests')
        .where('projectOwnerId', isEqualTo: userId)
        .snapshots();
    final suggestions = FirebaseFirestore.instance
        .collectionGroup('suggestions')
        .where('projectOwnerId', isEqualTo: userId)
        .snapshots();
    final codeChangeRequests = FirebaseFirestore.instance
        .collectionGroup('fileChangeProposals')
        .where('projectOwnerId', isEqualTo: userId)
        .snapshots();
    final reviewResults = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: requests,
      builder: (context, requestSnapshot) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: suggestions,
            builder: (context, suggestionSnapshot) =>
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: codeChangeRequests,
                  builder: (context, proposalSnapshot) =>
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: reviewResults,
                        builder: (context, reviewSnapshot) {
                          final pendingRequests =
                              requestSnapshot.data?.docs
                                  .where(
                                    (doc) => doc.data()['status'] == 'pending',
                                  )
                                  .length ??
                              0;
                          final openSuggestions =
                              suggestionSnapshot.data?.docs
                                  .where(
                                    (doc) => doc.data()['status'] == 'open',
                                  )
                                  .length ??
                              0;
                          final pendingCodeChanges =
                              proposalSnapshot.data?.docs
                                  .where(
                                    (doc) => doc.data()['status'] == 'pending',
                                  )
                                  .length ??
                              0;
                          final unreadReviews =
                              reviewSnapshot.data?.docs
                                  .where(
                                    (doc) =>
                                        (doc.data()['kind'] ==
                                                'code_change_review' ||
                                            doc.data()['kind'] ==
                                                'social_follow' ||
                                            doc.data()['kind'] ==
                                                'post_reply') &&
                                        doc.data()['read'] != true,
                                  )
                                  .length ??
                              0;
                          final count =
                              pendingRequests +
                              openSuggestions +
                              pendingCodeChanges +
                              unreadReviews;
                          return IconButton(
                            tooltip: count == 0
                                ? 'Notifications'
                                : '$count new notifications',
                            onPressed: onPressed,
                            icon: Badge(
                              isLabelVisible: count > 0,
                              label: Text(count > 99 ? '99+' : '$count'),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                              ),
                            ),
                          );
                        },
                      ),
                ),
          ),
    );
  }
}

class ProjectNotificationsPage extends StatefulWidget {
  final String userId;

  const ProjectNotificationsPage({super.key, required this.userId});

  @override
  State<ProjectNotificationsPage> createState() =>
      _ProjectNotificationsPageState();
}

class _ProjectNotificationsPageState extends State<ProjectNotificationsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requests;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _suggestions;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _codeChangeRequests;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviewResults;

  @override
  void initState() {
    super.initState();
    _requests = FirebaseFirestore.instance
        .collectionGroup('contributionRequests')
        .where('projectOwnerId', isEqualTo: widget.userId)
        .snapshots();
    _suggestions = FirebaseFirestore.instance
        .collectionGroup('suggestions')
        .where('projectOwnerId', isEqualTo: widget.userId)
        .snapshots();
    _codeChangeRequests = FirebaseFirestore.instance
        .collectionGroup('fileChangeProposals')
        .where('projectOwnerId', isEqualTo: widget.userId)
        .snapshots();
    _reviewResults = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('notifications')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requests,
      builder: (context, requestSnapshot) {
        if (requestSnapshot.hasError) {
          return _loadError(context, requestSnapshot.error);
        }
        if (!requestSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _suggestions,
          builder: (context, suggestionSnapshot) {
            if (suggestionSnapshot.hasError) {
              return _loadError(context, suggestionSnapshot.error);
            }
            if (!suggestionSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _codeChangeRequests,
              builder: (context, proposalSnapshot) {
                if (proposalSnapshot.hasError) {
                  return _loadError(context, proposalSnapshot.error);
                }
                if (!proposalSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _reviewResults,
                  builder: (context, reviewSnapshot) {
                    if (reviewSnapshot.hasError) {
                      return _loadError(context, reviewSnapshot.error);
                    }
                    if (!reviewSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = <_ProjectActivityItem>[
                      for (final doc in requestSnapshot.data!.docs)
                        if (doc.data()['status'] == 'pending')
                          _ProjectActivityItem.fromRequest(doc),
                      for (final doc in suggestionSnapshot.data!.docs)
                        if (doc.data()['status'] == 'open')
                          _ProjectActivityItem.fromSuggestion(doc),
                      for (final doc in proposalSnapshot.data!.docs)
                        if (doc.data()['status'] == 'pending')
                          _ProjectActivityItem.fromCodeChangeRequest(doc),
                      for (final doc in reviewSnapshot.data!.docs)
                        if (doc.data()['kind'] == 'code_change_review')
                          _ProjectActivityItem.fromReviewResult(doc),
                      for (final doc in reviewSnapshot.data!.docs)
                        if (doc.data()['kind'] == 'social_follow' ||
                            doc.data()['kind'] == 'post_reply')
                          _ProjectActivityItem.fromSocialNotification(doc),
                    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    if (items.isEmpty) return _emptyState(context);
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _notificationCard(context, items[index]),
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
  );

  Widget _loadError(BuildContext context, Object? error) {
    final details = error is FirebaseException
        ? '${error.code}: ${error.message ?? 'No additional details'}'
        : error?.toString() ?? 'Unknown error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load notifications.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText(context)),
            ),
            const SizedBox(height: 8),
            SelectableText(
              details,
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText(context), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          const Text(
            'You’re all caught up',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'New followers, post replies, contribution requests, suggestions, and code change updates will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText(context)),
          ),
        ],
      ),
    ),
  );

  Widget _notificationCard(BuildContext context, _ProjectActivityItem item) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openNotification(context, item),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.isUnread ? colors.primary : outlineColor(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.projectTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: mutedText(context)),
                ],
              ),
              const SizedBox(height: 12),
              Text(item.summary, style: const TextStyle(height: 1.4)),
              if (item.targetLabel != null) ...[
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.targetLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    _ProjectActivityItem item,
  ) async {
    if (item.isSocialNotification) {
      try {
        if (!item.isRead && item.notificationReference != null) {
          await item.notificationReference!.update({'read': true});
        }
        if (!context.mounted) return;
        if (item.isSocialFollow) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => PublicProfilePage(
                userId: item.actorId,
                displayName: item.actorName,
                handle: item.actorHandle,
                initials: item.actorName.trim().isEmpty
                    ? 'D'
                    : item.actorName.trim()[0].toUpperCase(),
              ),
            ),
          );
        } else {
          final post = await FirebaseFirestore.instance
              .collection('posts')
              .doc(item.postId)
              .get();
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => CommentsPage(
                postId: item.postId,
                postAuthorName:
                    post.data()?['authorName'] as String? ?? 'Community member',
                postText: post.data()?['text'] as String? ?? '',
              ),
            ),
          );
        }
      } on FirebaseException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open this update (${error.code}).'),
            ),
          );
        }
      }
      return;
    }
    if (item.isCodeReviewResult) {
      try {
        if (!item.isRead && item.notificationReference != null) {
          await item.notificationReference!.update({'read': true});
        }
        if (!context.mounted) return;
        await openMyProjectFileProposals(
          context,
          projectId: item.projectId,
          projectTitle: item.projectTitle,
          ownerId: item.projectOwnerId,
          focusDocumentId: item.proposalId,
        );
      } on FirebaseException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open this update (${error.code}).'),
            ),
          );
        }
      }
      return;
    }
    if (item.isCodeChangeRequest) {
      await openProjectFileProposals(
        context,
        projectId: item.projectId,
        projectTitle: item.projectTitle,
        ownerId: item.projectOwnerId,
      );
      return;
    }
    await openProjectActivity(
      context,
      projectId: item.projectId,
      activityId: item.id,
      isSuggestion: item.isSuggestion,
    );
  }
}

class _ProjectActivityItem {
  final String id;
  final String projectId;
  final String projectTitle;
  final String title;
  final String summary;
  final String? targetLabel;
  final IconData icon;
  final DateTime createdAt;
  final bool isSuggestion;
  final bool isCodeReviewResult;
  final bool isCodeChangeRequest;
  final bool isRead;
  final bool isSocialNotification;
  final bool isSocialFollow;
  final String projectOwnerId;
  final String proposalId;
  final String actorId;
  final String actorName;
  final String actorHandle;
  final String postId;
  final DocumentReference<Map<String, dynamic>>? notificationReference;

  bool get isUnread => !isRead && (isCodeReviewResult || isSocialNotification);

  const _ProjectActivityItem({
    required this.id,
    required this.projectId,
    required this.projectTitle,
    required this.title,
    required this.summary,
    required this.targetLabel,
    required this.icon,
    required this.createdAt,
    required this.isSuggestion,
    this.isCodeReviewResult = false,
    this.isCodeChangeRequest = false,
    this.isRead = true,
    this.isSocialNotification = false,
    this.isSocialFollow = false,
    this.projectOwnerId = '',
    this.proposalId = '',
    this.actorId = '',
    this.actorName = '',
    this.actorHandle = '',
    this.postId = '',
    this.notificationReference,
  });

  factory _ProjectActivityItem.fromRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final requestedAt = data['requestedAt'];
    return _ProjectActivityItem(
      id: document.id,
      projectId: data['projectId'] as String? ?? '',
      projectTitle: data['projectTitle'] as String? ?? 'Project',
      title:
          '${data['requesterName'] as String? ?? 'Someone'} wants to contribute',
      summary: (data['message'] as String? ?? '').trim().isEmpty
          ? 'They would like to help with this project.'
          : data['message'] as String,
      targetLabel: null,
      icon: Icons.group_add_outlined,
      createdAt: requestedAt is Timestamp ? requestedAt.toDate() : DateTime(0),
      isSuggestion: false,
    );
  }

  factory _ProjectActivityItem.fromSuggestion(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final created = data['createdAt'];
    final scope = data['scope'] as String? ?? 'project';
    final path = data['targetPath'] as String? ?? '';
    final targetLabel = switch (scope) {
      'file' => 'File · $path',
      'folder' => 'Folder · $path',
      _ => null,
    };
    return _ProjectActivityItem(
      id: document.id,
      projectId: data['projectId'] as String? ?? '',
      projectTitle: data['projectTitle'] as String? ?? 'Project',
      title: '${data['authorName'] as String? ?? 'Someone'} sent a suggestion',
      summary: data['message'] as String? ?? '',
      targetLabel: targetLabel,
      icon: Icons.lightbulb_outline_rounded,
      createdAt: created is Timestamp ? created.toDate() : DateTime(0),
      isSuggestion: true,
    );
  }

  factory _ProjectActivityItem.fromReviewResult(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final status = data['proposalStatus'] as String? ?? 'reviewed';
    final path = data['path'] as String? ?? '';
    final created = data['createdAt'];
    return _ProjectActivityItem(
      id: document.id,
      projectId: data['projectId'] as String? ?? '',
      projectTitle: data['projectTitle'] as String? ?? 'Project',
      title: status == 'approved'
          ? 'Your code change was approved'
          : 'Your code change was rejected',
      summary: status == 'approved'
          ? 'The project owner approved your change. It has been applied.'
          : 'The project owner reviewed your change and did not apply it.',
      targetLabel: path.isEmpty ? null : 'File · $path',
      icon: status == 'approved'
          ? Icons.check_circle_outline_rounded
          : Icons.cancel_outlined,
      createdAt: created is Timestamp ? created.toDate() : DateTime(0),
      isSuggestion: false,
      isCodeReviewResult: true,
      isRead: data['read'] == true,
      projectOwnerId: data['projectOwnerId'] as String? ?? '',
      proposalId: data['proposalId'] as String? ?? document.id,
      notificationReference: document.reference,
    );
  }

  factory _ProjectActivityItem.fromSocialNotification(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final isFollow = data['kind'] == 'social_follow';
    final actorName = data['actorName'] as String? ?? 'A developer';
    final created = data['createdAt'];
    return _ProjectActivityItem(
      id: document.id,
      projectId: '',
      projectTitle: isFollow ? 'New follower' : 'Post reply',
      title: isFollow
          ? '$actorName followed you'
          : '$actorName replied to your post',
      summary: isFollow
          ? 'Tap to view their profile.'
          : 'Tap to open the reply thread.',
      targetLabel: null,
      icon: isFollow ? Icons.person_add_alt_1_rounded : Icons.reply_rounded,
      createdAt: created is Timestamp ? created.toDate() : DateTime(0),
      isSuggestion: false,
      isRead: data['read'] == true,
      isSocialNotification: true,
      isSocialFollow: isFollow,
      actorId: data['actorId'] as String? ?? '',
      actorName: actorName,
      actorHandle: data['actorHandle'] as String? ?? '@developer',
      postId: data['postId'] as String? ?? '',
      notificationReference: document.reference,
    );
  }

  factory _ProjectActivityItem.fromCodeChangeRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final created = data['createdAt'];
    final path = data['path'] as String? ?? '';
    final projectId = document.reference.parent.parent?.id ?? '';
    return _ProjectActivityItem(
      id: document.id,
      projectId: projectId,
      projectTitle: data['projectTitle'] as String? ?? 'Project',
      title:
          '${data['submitterName'] as String? ?? 'A contributor'} proposed a code change',
      summary: 'Review this change before it is applied to your project.',
      targetLabel: path.isEmpty ? null : 'File · $path',
      icon: Icons.code_rounded,
      createdAt: created is Timestamp ? created.toDate() : DateTime(0),
      isSuggestion: false,
      isCodeChangeRequest: true,
      projectOwnerId: data['projectOwnerId'] as String? ?? '',
    );
  }
}
