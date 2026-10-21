import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_menu_button.dart';
import '../../core/widgets/collapsible_chrome.dart';
import '../projects/project_notifications_page.dart';
import 'comments_page.dart';
import '../profile/discover_people_page.dart';
import '../profile/public_profile_page.dart';
import '../profile/social_notifications.dart';

class FeedPage extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenNotifications;
  final bool chromeVisible;
  const FeedPage({
    super.key,
    required this.onOpenDrawer,
    required this.onOpenNotifications,
    required this.chromeVisible,
  });

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  bool following = true;
  final PageController _feedPageController = PageController();
  final GlobalKey _feedViewportKey = GlobalKey();
  final ValueNotifier<int> _visibilityRevision = ValueNotifier<int>(0);
  late Stream<QuerySnapshot<Map<String, dynamic>>> _followingStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _exploreStream;
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _followingPostStreams = {};

  @override
  void initState() {
    super.initState();
    _feedPageController.addListener(_notifyVisibilityChanged);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;
    _followingStream = _createFollowingStream(firestore, uid);
    _exploreStream = _createExploreStream(firestore);
  }

  @override
  void dispose() {
    _feedPageController.removeListener(_notifyVisibilityChanged);
    _feedPageController.dispose();
    _visibilityRevision.dispose();
    super.dispose();
  }

  void _notifyVisibilityChanged() {
    _visibilityRevision.value++;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _createFollowingStream(
    FirebaseFirestore firestore,
    String uid,
  ) => firestore
      .collection('users')
      .doc(uid)
      .collection('following')
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> _createExploreStream(
    FirebaseFirestore firestore,
  ) => firestore.collection('posts').limit(50).snapshots();

  void _selectFeed(int page) {
    if (_feedPageController.hasClients) {
      _feedPageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
    if (following != (page == 0)) {
      setState(() => following = page == 0);
    }
  }

  void _onFeedPageChanged(int page) {
    final showFollowing = page == 0;
    if (following != showFollowing) {
      setState(() => following = showFollowing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CollapsibleChrome(
          visible: widget.chromeVisible,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
                child: Row(
                  children: [
                    AvatarMenuButton(onPressed: widget.onOpenDrawer),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KodeKoalesce',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const DiscoverPeoplePage(),
                        ),
                      ),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    ProjectNotificationsButton(
                      userId: FirebaseAuth.instance.currentUser!.uid,
                      onPressed: widget.onOpenNotifications,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: softSurface(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: AnimatedBuilder(
                    animation: _feedPageController,
                    builder: (context, _) => LayoutBuilder(
                      builder: (context, constraints) {
                        final page =
                            (_feedPageController.hasClients
                                    ? (_feedPageController.page ??
                                          (following ? 0.0 : 1.0))
                                    : (following ? 0.0 : 1.0))
                                .clamp(0.0, 1.0)
                                .toDouble();
                        final tabWidth = constraints.maxWidth / 2;
                        return Stack(
                          children: [
                            Positioned(
                              left: page * tabWidth,
                              top: 0,
                              bottom: 0,
                              width: tabWidth,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                _feedTab(
                                  'Following',
                                  1 - page,
                                  () => _selectFeed(0),
                                ),
                                _feedTab('Explore', page, () => _selectFeed(1)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView(
            key: _feedViewportKey,
            controller: _feedPageController,
            onPageChanged: _onFeedPageChanged,
            children: [_buildFollowingPostList(), _buildExplorePostList()],
          ),
        ),
      ],
    );
  }

  Widget _buildFollowingPostList() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _followingStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusList(
            _FeedStatus(
              icon: Icons.cloud_off_rounded,
              title: 'Following isn’t available right now',
              message: 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: _retryFeed,
            ),
          );
        }
        if (!snapshot.hasData) {
          return _refreshable(const _FeedLoadingState());
        }
        // Firestore accepts up to 30 values in a whereIn query. Include the
        // current user so their own posts remain in Following too.
        final authorIds = <String>{
          uid,
          ...snapshot.data!.docs.map((doc) => doc.id),
        }.take(30).toList();
        final key = authorIds.join('|');
        final stream = _followingPostStreams.putIfAbsent(
          key,
          () => FirebaseFirestore.instance
              .collection('posts')
              .where('authorId', whereIn: authorIds)
              .limit(50)
              .snapshots(),
        );
        return _buildPostStream(
          stream,
          emptyMessage:
              'Follow people from Explore and their posts will appear here.',
        );
      },
    );
  }

  Widget _buildExplorePostList() => _buildPostStream(
    _exploreStream,
    emptyMessage: 'No community posts yet. Be the first to share something!',
  );

  Widget _buildPostStream(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream, {
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusList(
            _FeedStatus(
              icon: Icons.cloud_off_rounded,
              title: 'Feed didn’t load',
              message: 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: _retryFeed,
            ),
          );
        }
        if (!snapshot.hasData) {
          return _refreshable(const _FeedLoadingState());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            final aDate = aTime is Timestamp ? aTime.toDate() : DateTime(0);
            final bDate = bTime is Timestamp ? bTime.toDate() : DateTime(0);
            return bDate.compareTo(aDate);
          });
        if (docs.isEmpty) {
          return _statusList(
            _FeedStatus(
              icon: Icons.forum_outlined,
              title: 'Nothing here yet',
              message: emptyMessage,
            ),
          );
        }
        return _refreshable(
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.vertical) {
                _notifyVisibilityChanged();
              }
              return false;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final post = FeedPost.fromDocument(doc);
                return PostCard(
                  key: ValueKey(doc.id),
                  post: post,
                  viewportKey: _feedViewportKey,
                  visibilityRevision: _visibilityRevision,
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _retryFeed() => unawaited(_refreshFeed());

  Widget _refreshable(Widget child) =>
      RefreshIndicator(onRefresh: _refreshFeed, child: child);

  Widget _statusList(_FeedStatus status) => _refreshable(
    LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(child: status),
          ),
        ],
      ),
    ),
  );

  Future<void> _refreshFeed() async {
    if (!mounted) return;
    final firestore = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() {
      _followingStream = _createFollowingStream(firestore, uid);
      _exploreStream = _createExploreStream(firestore);
      _followingPostStreams.clear();
    });
    // Changing the stream restarts its listener while StreamBuilder keeps its
    // last snapshot on screen until the replacement listener emits.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Widget _feedTab(String title, double selectedProgress, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: selectedProgress >= 0.5
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: Color.lerp(
                  mutedText(context),
                  Theme.of(context).colorScheme.onSurface,
                  selectedProgress,
                ),
              ),
            ),
          ),
        ),
      );
}

class _FeedLoadingState extends StatelessWidget {
  const _FeedLoadingState();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 88),
    children: [
      Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Loading posts…', style: TextStyle(color: mutedText(context))),
        ],
      ),
      const SizedBox(height: 14),
      for (var index = 0; index < 4; index++) ...[
        const _FeedSkeletonCard(),
        if (index < 3) const Divider(height: 1, indent: 76),
      ],
    ],
  );
}

class _FeedSkeletonCard extends StatelessWidget {
  const _FeedSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: shade,
        borderRadius: BorderRadius.circular(height),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 21, backgroundColor: shade),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(116, 12), const SizedBox(height: 7), bar(78, 9)],
              ),
            ],
          ),
          const SizedBox(height: 18),
          bar(double.infinity, 10),
          const SizedBox(height: 9),
          FractionallySizedBox(
            widthFactor: 0.72,
            child: bar(double.infinity, 10),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [bar(38, 10), bar(38, 10), bar(38, 10), bar(38, 10)],
          ),
        ],
      ),
    );
  }
}

class _FeedStatus extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FeedStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 38, color: mutedText(context)),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedText(context)),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class FeedPost {
  final String id;
  final String authorId;
  final String name, handle, initials, time, text, topic;
  final Color tint;
  final int replies;
  final int views;
  const FeedPost({
    this.id = '',
    required this.authorId,
    required this.name,
    required this.handle,
    required this.initials,
    required this.tint,
    required this.time,
    required this.text,
    required this.topic,
    required this.replies,
    required this.views,
  });

  factory FeedPost.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final created = data['createdAt'];
    final createdAt = created is Timestamp ? created.toDate() : null;
    final name = data['authorName'] as String? ?? 'Developer';
    final handle = data['authorHandle'] as String? ?? '@developer';
    final time = createdAt == null ? 'now' : _timeAgo(createdAt);
    return FeedPost(
      id: doc.id,
      authorId: data['authorId'] as String? ?? '',
      name: name,
      handle: handle,
      initials: name.trim().isEmpty
          ? 'D'
          : name.trim().substring(0, 1).toUpperCase(),
      tint: const Color(0xFFD7E8DC),
      time: time,
      text: data['text'] as String? ?? '',
      topic: data['topic'] as String? ?? 'community',
      replies: data['replyCount'] as int? ?? 0,
      views: (data['viewCount'] as num?)?.toInt() ?? 0,
    );
  }

  static String _timeAgo(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}

class PostCard extends StatefulWidget {
  final FeedPost post;
  final GlobalKey viewportKey;
  final ValueNotifier<int> visibilityRevision;
  const PostCard({
    super.key,
    required this.post,
    required this.viewportKey,
    required this.visibilityRevision,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Timer? _viewTimer;
  bool _viewRecorded = false;
  bool _expandedText = false;
  late String _userId;
  late CollectionReference<Map<String, dynamic>> _likes;
  late CollectionReference<Map<String, dynamic>> _comments;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _likesStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _commentsStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _followStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _authorProfileStream;
  late DocumentReference<Map<String, dynamic>> _savedPost;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _savedPostStream;

  FeedPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    _bindStreams();
    widget.visibilityRevision.addListener(_scheduleVisibilityCheck);
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibilityRevision != widget.visibilityRevision) {
      oldWidget.visibilityRevision.removeListener(_scheduleVisibilityCheck);
      widget.visibilityRevision.addListener(_scheduleVisibilityCheck);
    }
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.authorId != widget.post.authorId) {
      _expandedText = false;
      _viewTimer?.cancel();
      _viewRecorded = false;
      _bindStreams();
    }
    _scheduleVisibilityCheck();
  }

  @override
  void dispose() {
    widget.visibilityRevision.removeListener(_scheduleVisibilityCheck);
    _viewTimer?.cancel();
    super.dispose();
  }

  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibilityTimer();
    });
  }

  void _updateVisibilityTimer() {
    if (_viewRecorded || post.id.isEmpty || post.authorId == _userId) return;
    final card = context.findRenderObject();
    final viewport = widget.viewportKey.currentContext?.findRenderObject();
    if (card is! RenderBox ||
        viewport is! RenderBox ||
        !card.hasSize ||
        !viewport.hasSize) {
      _viewTimer?.cancel();
      _viewTimer = null;
      return;
    }

    final cardRect = card.localToGlobal(Offset.zero) & card.size;
    final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
    var isVisible = false;
    if (cardRect.overlaps(viewportRect)) {
      final visibleRect = cardRect.intersect(viewportRect);
      final cardArea = cardRect.width * cardRect.height;
      final visibleArea = visibleRect.width * visibleRect.height;
      isVisible = cardArea > 0 && visibleArea / cardArea >= 0.5;
    }

    if (isVisible) {
      _viewTimer ??= Timer(const Duration(seconds: 1), _recordView);
    } else {
      _viewTimer?.cancel();
      _viewTimer = null;
    }
  }

  Future<void> _recordView() async {
    _viewTimer = null;
    if (!mounted ||
        _viewRecorded ||
        post.id.isEmpty ||
        post.authorId == _userId) {
      return;
    }
    _viewRecorded = true;
    final firestore = FirebaseFirestore.instance;
    final postReference = firestore.collection('posts').doc(post.id);
    final viewReference = postReference.collection('views').doc(_userId);
    try {
      await firestore.runTransaction((transaction) async {
        final previousView = await transaction.get(viewReference);
        if (previousView.exists) return;
        final postSnapshot = await transaction.get(postReference);
        if (!postSnapshot.exists) return;
        final currentCount =
            (postSnapshot.data()?['viewCount'] as num?)?.toInt() ?? 0;
        transaction.set(viewReference, {
          'viewerId': _userId,
          'viewedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postReference, {'viewCount': currentCount + 1});
      });
    } catch (_) {
      // A view-count write must not disrupt reading the feed.
    }
  }

  void _bindStreams() {
    _userId = FirebaseAuth.instance.currentUser!.uid;
    final postRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post.id);
    _likes = postRef.collection('likes');
    _comments = postRef.collection('comments');
    _likesStream = _likes.snapshots();
    _commentsStream = _comments.snapshots();
    _savedPost = FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('savedPosts')
        .doc(widget.post.id);
    _savedPostStream = _savedPost.snapshots();
    _followStream = FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('following')
        .doc(widget.post.authorId)
        .snapshots();
    _authorProfileStream = FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(widget.post.authorId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleVisibilityCheck();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _authorProfileStream,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final authorName = profile?['displayName'] as String? ?? post.name;
        final authorHandle = profile?['handle'] as String? ?? post.handle;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _likesStream,
          builder: (context, likeSnapshot) {
            final likedByUsers = likeSnapshot.data?.docs ?? const [];
            final isLiked = likedByUsers.any((like) => like.id == _userId);
            final likeCount = likedByUsers.length;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _commentsStream,
              builder: (context, commentSnapshot) =>
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _savedPostStream,
                    builder: (context, savedSnapshot) => _buildCard(
                      context,
                      _likes,
                      _userId,
                      isLiked,
                      likeCount,
                      commentSnapshot.data?.docs.length ?? post.replies,
                      authorName,
                      authorHandle,
                      savedSnapshot.data?.exists ?? false,
                    ),
                  ),
            );
          },
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    CollectionReference<Map<String, dynamic>> likes,
    String userId,
    bool isLiked,
    int likeCount,
    int commentCount,
    String authorName,
    String authorHandle,
    bool isSaved,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openAuthorProfile(context, authorName, authorHandle),
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 21,
            backgroundColor: post.tint,
            child: Text(
              authorName.trim().isEmpty
                  ? 'D'
                  : authorName.trim().substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => _openAuthorProfile(
                            context,
                            authorName,
                            authorHandle,
                          ),
                          child: Text(
                            authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                authorHandle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: mutedText(context),
                                ),
                              ),
                            ),
                            Text(
                              ' · ${post.time}',
                              style: TextStyle(
                                fontSize: 12,
                                color: mutedText(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (post.authorId == userId)
                    _postMenu(
                      context,
                      isOwner: true,
                      onSelected: (action) {
                        if (action == 'edit') _editPost(context);
                        if (action == 'delete') _deletePost(context);
                      },
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _followStream,
                          builder: (context, followSnapshot) {
                            final isFollowing =
                                followSnapshot.data?.exists ?? false;
                            return IconButton(
                              tooltip: isFollowing ? 'Unfollow' : 'Follow',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              onPressed: () => _toggleFollow(
                                context,
                                userId,
                                post.authorId,
                                isFollowing,
                                authorName,
                                authorHandle,
                              ),
                              icon: Icon(
                                isFollowing
                                    ? Icons.person_remove_alt_1_rounded
                                    : Icons.person_add_alt_1_rounded,
                                size: 18,
                                color: isFollowing
                                    ? Theme.of(context).colorScheme.primary
                                    : mutedText(context),
                              ),
                            );
                          },
                        ),
                        _postMenu(
                          context,
                          isOwner: false,
                          onSelected: (_) => _reportPost(context),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const style = TextStyle(fontSize: 14, height: 1.5);
                  final painter = TextPainter(
                    text: TextSpan(text: post.text, style: style),
                    maxLines: 5,
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  final isLong = painter.didExceedMaxLines;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.text,
                        maxLines: _expandedText ? null : 5,
                        overflow: _expandedText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: style,
                      ),
                      if (isLong)
                        InkWell(
                          onTap: () =>
                              setState(() => _expandedText = !_expandedText),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 5,
                              right: 8,
                              bottom: 4,
                            ),
                            child: Text(
                              _expandedText ? 'Show less' : 'Read more',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: softSurface(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '# ${post.topic}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _action(
                    context,
                    Icons.chat_bubble_outline_rounded,
                    '$commentCount',
                    () => _openComments(context, authorName),
                  ),
                  _action(
                    context,
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    '$likeCount',
                    () {
                      HapticFeedback.lightImpact();
                      _toggleLike(context, likes, userId, isLiked);
                    },
                    color: isLiked ? const Color(0xFFCC5B66) : null,
                  ),
                  _viewCount(context, post.views),
                  IconButton(
                    tooltip: 'Share post',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: () => _sharePost(context, authorName),
                    icon: Icon(
                      Icons.share_outlined,
                      size: 17,
                      color: mutedText(context),
                    ),
                  ),
                  IconButton(
                    tooltip: isSaved ? 'Remove saved post' : 'Save post',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: () => _toggleSavedPost(
                      context,
                      isSaved,
                      authorName,
                      authorHandle,
                    ),
                    icon: Icon(
                      isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 19,
                      color: isSaved
                          ? Theme.of(context).colorScheme.primary
                          : mutedText(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _toggleLike(
    BuildContext context,
    CollectionReference<Map<String, dynamic>> likes,
    String userId,
    bool isLiked,
  ) async {
    final like = likes.doc(userId);
    try {
      if (isLiked) {
        await like.delete();
      } else {
        await like.set({
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your like. Check Firestore rules.'),
          ),
        );
      }
    }
  }

  Future<void> _sharePost(BuildContext context, String authorName) async {
    final content = post.text.trim();
    if (content.isEmpty) return;
    final shareText = '$content\n\n— $authorName on KodeKoalesce';
    try {
      await const MethodChannel('com.kodekoalesce.app/share')
          .invokeMethod<void>('shareText', {
            'text': shareText,
            'title': 'Share post',
          });
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the share menu.')),
        );
      }
    } on MissingPluginException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sharing is available on Android for now.'),
          ),
        );
      }
    }
  }

  Future<void> _toggleSavedPost(
    BuildContext context,
    bool isSaved,
    String authorName,
    String authorHandle,
  ) async {
    try {
      if (isSaved) {
        await _savedPost.delete();
      } else {
        await _savedPost.set({
          'postId': post.id,
          'authorId': post.authorId,
          'authorName': authorName,
          'authorHandle': authorHandle,
          'initials': post.initials,
          'text': post.text,
          'topic': post.topic,
          'time': post.time,
          'replyCount': post.replies,
          'viewCount': post.views,
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update saved posts (${error.code}).'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update saved posts.')),
        );
      }
    }
  }

  Widget _postMenu(
    BuildContext context, {
    required bool isOwner,
    required ValueChanged<String> onSelected,
  }) => PopupMenuButton<String>(
    tooltip: 'Post options',
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 144),
    iconSize: 19,
    icon: Icon(Icons.more_horiz_rounded, color: mutedText(context)),
    onSelected: onSelected,
    itemBuilder: (context) => isOwner
        ? const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ]
        : const [PopupMenuItem(value: 'report', child: Text('Report'))],
  );

  Future<void> _editPost(BuildContext context) async {
    final updatedText = await showDialog<String>(
      context: context,
      builder: (_) => _EditPostDialog(initialText: post.text),
    );
    if (updatedText == null || updatedText == post.text.trim()) return;
    try {
      await FirebaseFirestore.instance.collection('posts').doc(post.id).update({
        'text': updatedText,
      });
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not edit post (${error.code}).')),
        );
      }
    }
  }

  Future<void> _deletePost(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('This will remove the post from the feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(post.id)
          .delete();
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete post (${error.code}).')),
        );
      }
    }
  }

  Future<void> _reportPost(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Why are you reporting this post?'),
            ),
            const SizedBox(height: 8),
            for (final option in const [
              ('spam', 'Spam'),
              ('harassment', 'Harassment or abuse'),
              ('misinformation', 'Misinformation'),
              ('other', 'Something else'),
            ])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(option.$2),
                onTap: () => Navigator.pop(dialogContext, option.$1),
              ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(post.id)
          .collection('reports')
          .doc(_userId)
          .set({
            'reporterId': _userId,
            'reason': reason,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks. Your report was submitted.')),
        );
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report (${error.code}).')),
        );
      }
    }
  }

  void _openAuthorProfile(
    BuildContext context,
    String authorName,
    String authorHandle,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(
          userId: post.authorId,
          displayName: authorName,
          handle: authorHandle,
          initials: authorName.trim().isEmpty
              ? 'D'
              : authorName.trim().substring(0, 1).toUpperCase(),
        ),
      ),
    );
  }

  void _openComments(BuildContext context, String authorName) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommentsPage(
          postId: post.id,
          postAuthorName: authorName,
          postText: post.text,
        ),
      ),
    );
  }

  Future<void> _toggleFollow(
    BuildContext context,
    String currentUserId,
    String targetUserId,
    bool isFollowing,
    String authorName,
    String authorHandle,
  ) async {
    final follow = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(targetUserId);
    try {
      if (isFollowing) {
        await follow.delete();
      } else {
        await follow.set({
          'userId': targetUserId,
          'displayName': authorName,
          'handle': authorHandle,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await notifyNewFollower(targetUserId);
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

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                icon,
                key: ValueKey(icon.codePoint),
                size: 17,
                color: color ?? mutedText(context),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                label,
                key: ValueKey(label),
                style: TextStyle(
                  fontSize: 11,
                  color: color ?? mutedText(context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _viewCount(BuildContext context, int count) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 17, color: mutedText(context)),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(fontSize: 11, color: mutedText(context)),
          ),
        ],
      ),
    ),
  );
}

class _EditPostDialog extends StatefulWidget {
  final String initialText;

  const _EditPostDialog({required this.initialText});

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit post'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 500,
      maxLines: 5,
      decoration: const InputDecoration(
        hintText: 'Write your post',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
