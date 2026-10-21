import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const _agoraAppId = String.fromEnvironment(
  'AGORA_APP_ID',
  defaultValue: 'ac8e433e1703464e8787e5d99311201b',
);
const _tokenServerUrl = String.fromEnvironment(
  'AGORA_TOKEN_SERVER_URL',
  defaultValue: 'http://127.0.0.1:3000',
);

class AgoraVoiceDialog extends StatefulWidget {
  final String roomId;
  final String roomTitle;
  final bool isHost;
  final String hostId;
  final String displayName;
  final Future<void> Function() onEndRoom;

  const AgoraVoiceDialog({
    super.key,
    required this.roomId,
    required this.roomTitle,
    required this.isHost,
    required this.hostId,
    required this.displayName,
    required this.onEndRoom,
  });

  @override
  State<AgoraVoiceDialog> createState() => _AgoraVoiceDialogState();
}

class _AgoraVoiceDialogState extends State<AgoraVoiceDialog> {
  RtcEngine? _engine;
  final Set<int> _remoteUsers = {};
  final Set<int> _mutedRemoteUsers = {};
  bool _connecting = true;
  bool _userMuted = false;
  bool _hostMuted = false;
  bool _leaving = false;
  bool _roomEnded = false;
  bool _isConnected = false;
  bool _connectionFailed = false;
  String? _connectionStatus;
  String? _roomStatusError;
  String? _error;
  String _roomEndMessage =
      'The host ended this room. You have been disconnected.';
  Timer? _reactionExpiryTimer;
  final GlobalKey _meetingStackKey = GlobalKey();
  final Map<String, GlobalKey> _reactionButtonKeys = {};
  final Map<String, GlobalKey> _participantTileKeys = {};
  final Map<String, _RoomReaction> _roomReactions = {};
  _FlyingReactionData? _flyingReaction;
  int _reactionAnimationId = 0;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _participantsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _joinRequestsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reactionsStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _participantSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _reactionSubscription;

  bool get _muted => _userMuted || _hostMuted;

  int get _agoraUid =>
      _uidFromFirebaseId(FirebaseAuth.instance.currentUser?.uid ?? 'guest');

  @override
  void initState() {
    super.initState();
    _participantsStream = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('participants')
        .snapshots();
    _joinRequestsStream = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('joinRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots();
    _reactionsStream = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('reactions')
        .snapshots();
    _reactionSubscription = _reactionsStream.listen(
      _onReactionsUpdated,
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _roomEnded || _leaving) return;
        setState(() => _roomStatusError = 'Room reactions could not refresh.');
      },
    );
    _roomSubscription = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen(
          _onRoomUpdated,
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted || _roomEnded || _leaving) return;
            setState(() => _roomStatusError = 'Room status could not refresh.');
          },
        );
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _participantSubscription = FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomId)
          .collection('participants')
          .doc(userId)
          .snapshots()
          .listen(
            _onParticipantUpdated,
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || _roomEnded || _leaving) return;
              setState(
                () =>
                    _roomStatusError = 'Your room controls could not refresh.',
              );
            },
          );
    }
    unawaited(_connect());
  }

  @override
  void dispose() {
    final engine = _engine;
    _engine = null;
    if (engine != null) unawaited(_releaseEngine(engine));
    final roomSubscription = _roomSubscription;
    _roomSubscription = null;
    if (roomSubscription != null) unawaited(roomSubscription.cancel());
    final participantSubscription = _participantSubscription;
    _participantSubscription = null;
    if (participantSubscription != null) {
      unawaited(participantSubscription.cancel());
    }
    final reactionSubscription = _reactionSubscription;
    _reactionSubscription = null;
    if (reactionSubscription != null) {
      unawaited(reactionSubscription.cancel());
    }
    _reactionExpiryTimer?.cancel();
    super.dispose();
  }

  void _onRoomUpdated(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.metadata.isFromCache && !snapshot.exists) return;
    if (!snapshot.exists || snapshot.data()?['status'] != 'open') {
      unawaited(_handleRoomEnded());
    } else if (_roomStatusError != null && mounted) {
      setState(() => _roomStatusError = null);
    }
  }

  void _onParticipantUpdated(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.metadata.isFromCache && !snapshot.exists) return;
    if (!snapshot.exists) {
      unawaited(_handleRoomEnded('The host removed you from this room.'));
      return;
    }
    final hostMuted = snapshot.data()?['mutedByHost'] == true;
    if (_hostMuted == hostMuted) return;
    setState(() => _hostMuted = hostMuted);
    final engine = _engine;
    if (engine != null) unawaited(engine.muteLocalAudioStream(_muted));
  }

  Future<void> _handleRoomEnded([
    String message = 'The host ended this room. You have been disconnected.',
  ]) async {
    if (_roomEnded || _leaving) return;
    _roomEnded = true;
    _roomEndMessage = message;
    _isConnected = false;
    _connectionStatus = null;
    _connectionFailed = false;
    _remoteUsers.clear();
    _mutedRemoteUsers.clear();
    final engine = _engine;
    _engine = null;
    if (mounted) setState(() {});
    if (engine != null) await _releaseEngine(engine);
  }

  Future<void> _connect() async {
    if (_roomEnded || _leaving) return;
    setState(() {
      _connecting = true;
      _error = null;
      _isConnected = false;
      _connectionFailed = false;
      _connectionStatus = null;
    });

    RtcEngine? engine;
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        throw Exception(
          permission.isPermanentlyDenied
              ? 'Microphone access is blocked. Enable it in Android Settings for KodeKoalesce.'
              : 'Allow microphone access to join voice rooms.',
        );
      }

      final tokenUri = Uri.parse('$_tokenServerUrl/rtc').replace(
        queryParameters: {
          'channel': widget.roomId,
          'uid': _agoraUid.toString(),
        },
      );
      final firebaseIdToken = await FirebaseAuth.instance.currentUser
          ?.getIdToken();
      final tokenResponse = await http
          .get(
            tokenUri,
            headers: firebaseIdToken == null
                ? null
                : {'Authorization': 'Bearer $firebaseIdToken'},
          )
          .timeout(const Duration(seconds: 12));
      if (tokenResponse.statusCode != 200) {
        if (tokenResponse.statusCode == 401) {
          throw Exception('Please sign in again, then rejoin the room.');
        }
        if (tokenResponse.statusCode == 403) {
          throw Exception('You are no longer a participant in this open room.');
        }
        throw Exception('The voice service could not issue a room token.');
      }
      if (_roomEnded || !mounted) return;
      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final token = tokenData['token'] as String?;
      final tokenAppId = tokenData['appId'] as String?;
      if (token == null || tokenAppId != _agoraAppId) {
        throw Exception(
          'The token service configuration does not match this app.',
        );
      }

      engine = createAgoraRtcEngine();
      await engine.initialize(
        const RtcEngineContext(
          appId: _agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!mounted || _roomEnded) return;
            setState(() {
              _connecting = false;
              _isConnected = true;
              _connectionFailed = false;
              _connectionStatus = null;
            });
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted || _roomEnded) return;
            setState(() {
              _remoteUsers.add(remoteUid);
              _mutedRemoteUsers.remove(remoteUid);
            });
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (!mounted || _roomEnded) return;
            setState(() {
              _remoteUsers.remove(remoteUid);
              _mutedRemoteUsers.remove(remoteUid);
            });
          },
          onUserMuteAudio: (connection, remoteUid, muted) {
            if (!mounted || _roomEnded) return;
            setState(() {
              if (muted) {
                _mutedRemoteUsers.add(remoteUid);
              } else {
                _mutedRemoteUsers.remove(remoteUid);
              }
            });
          },
          onConnectionStateChanged: (connection, state, _) {
            if (!mounted || _roomEnded || _leaving) return;
            switch (state) {
              case ConnectionStateType.connectionStateReconnecting:
                setState(() {
                  _isConnected = false;
                  _connectionFailed = false;
                  _connectionStatus = 'Connection interrupted. Reconnecting…';
                  _remoteUsers.clear();
                  _mutedRemoteUsers.clear();
                });
                break;
              case ConnectionStateType.connectionStateConnected:
                setState(() {
                  _connecting = false;
                  _isConnected = true;
                  _connectionFailed = false;
                  _connectionStatus = null;
                  _error = null;
                });
                break;
              case ConnectionStateType.connectionStateFailed:
                setState(() {
                  _connecting = false;
                  _isConnected = false;
                  _connectionFailed = true;
                  _connectionStatus = 'Connection lost. Rejoin to continue.';
                  _remoteUsers.clear();
                  _mutedRemoteUsers.clear();
                });
                break;
              case ConnectionStateType.connectionStateConnecting:
                setState(() {
                  _connecting = true;
                  _isConnected = false;
                  _connectionFailed = false;
                  _connectionStatus = 'Connecting to voice…';
                });
                break;
              case ConnectionStateType.connectionStateDisconnected:
                break;
            }
          },
          onError: (errorCode, message) {
            if (!mounted || _roomEnded) return;
            setState(() {
              _connecting = false;
              _error = 'Agora error: $message';
              _isConnected = false;
            });
          },
        ),
      );
      await engine.enableAudio();
      await engine.joinChannel(
        token: token,
        channelId: widget.roomId,
        uid: _agoraUid,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      if (_roomEnded || !mounted) {
        await _releaseEngine(engine);
        return;
      }
      _engine = engine;
      if (_muted) await engine.muteLocalAudioStream(true);
    } catch (error) {
      if (engine != null) await _releaseEngine(engine);
      if (!mounted || _roomEnded) return;
      setState(() {
        _connecting = false;
        _isConnected = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _toggleMute() async {
    final engine = _engine;
    if (engine == null || !_isConnected || _roomEnded || _hostMuted) return;
    final mute = !_userMuted;
    setState(() => _userMuted = mute);
    await engine.muteLocalAudioStream(_muted);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final engine = _engine;
    _engine = null;
    if (engine != null) await _releaseEngine(engine);
    _reactionExpiryTimer?.cancel();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(widget.roomId)
            .collection('reactions')
            .doc(userId)
            .delete();
      } on FirebaseException {
        // The reaction may already have expired or the room may have closed.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _sendReaction(String emoji) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || !_isConnected || _roomEnded) return;
    final ref = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('reactions')
        .doc(userId);
    try {
      await ref.set({
        'uid': userId,
        'displayName': widget.displayName,
        'emoji': emoji,
        'eventId': DateTime.now().microsecondsSinceEpoch.toString(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _reactionExpiryTimer?.cancel();
      _reactionExpiryTimer = Timer(const Duration(seconds: 4), () {
        unawaited(ref.delete().catchError((_) {}));
      });
    } on FirebaseException {
      if (mounted) {
        setState(() => _roomStatusError = 'Could not send that reaction.');
      }
    }
  }

  void _onReactionsUpdated(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final now = DateTime.now();
    final next = <String, _RoomReaction>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      if (createdAt is! Timestamp ||
          now.difference(createdAt.toDate()) > const Duration(seconds: 5)) {
        continue;
      }
      next[doc.id] = _RoomReaction(
        emoji: data['emoji'] as String? ?? '👏',
        eventId:
            data['eventId'] as String? ??
            createdAt.microsecondsSinceEpoch.toString(),
      );
    }
    if (!mounted) return;
    setState(() {
      _roomReactions
        ..clear()
        ..addAll(next);
    });
  }

  void _animateReaction(String emoji) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final root = _meetingStackKey.currentContext?.findRenderObject();
    final source = _reactionButtonKeys[emoji]?.currentContext
        ?.findRenderObject();
    final target = userId == null
        ? null
        : _participantTileKeys[userId]?.currentContext?.findRenderObject();
    if (_isConnected &&
        !_roomEnded &&
        root is RenderBox &&
        source is RenderBox &&
        target is RenderBox) {
      final rootOrigin = root.localToGlobal(Offset.zero);
      final sourceCenter = source.localToGlobal(
        source.size.center(Offset.zero),
      );
      final targetCenter = target.localToGlobal(
        target.size.center(Offset.zero),
      );
      final id = ++_reactionAnimationId;
      setState(() {
        _flyingReaction = _FlyingReactionData(
          id: id,
          emoji: emoji,
          start: sourceCenter - rootOrigin,
          end: targetCenter - rootOrigin,
        );
      });
    }
    unawaited(_sendReaction(emoji));
  }

  void _finishReactionFlight(int id) {
    if (!mounted || _flyingReaction?.id != id) return;
    setState(() => _flyingReaction = null);
  }

  GlobalKey _reactionButtonKey(String emoji) =>
      _reactionButtonKeys.putIfAbsent(emoji, GlobalKey.new);

  GlobalKey _participantTileKey(String userId) =>
      _participantTileKeys.putIfAbsent(userId, GlobalKey.new);

  Future<void> _decideJoinRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> request,
    String decision,
  ) async {
    try {
      await request.reference.update({
        'status': decision,
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      if (mounted) {
        setState(
          () => _roomStatusError = 'Could not update that join request.',
        );
      }
    }
  }

  Future<void> _showParticipantActions(_MeetingPerson person) async {
    if (!widget.isHost || person.isSelf || _roomEnded) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                person.mutedByHost ? Icons.mic_rounded : Icons.mic_off_rounded,
              ),
              title: Text(
                person.mutedByHost ? 'Allow microphone' : 'Mute person',
              ),
              onTap: () => Navigator.pop(
                context,
                person.mutedByHost ? 'unmute' : 'mute',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_alt_1_rounded),
              title: const Text('Remove from room'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () => Navigator.pop(context, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final ref = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('participants')
        .doc(person.id);
    try {
      if (action == 'mute' || action == 'unmute') {
        await ref.update({'mutedByHost': action == 'mute'});
      } else if (action == 'remove') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove ${person.name}?'),
            content: const Text(
              'They will be disconnected from this room and can request to join again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed == true) await ref.delete();
      }
    } on FirebaseException {
      if (mounted) {
        setState(() => _roomStatusError = 'Could not update this participant.');
      }
    }
  }

  Future<void> _reconnect() async {
    if (_connecting || _leaving || _roomEnded) return;
    final engine = _engine;
    _engine = null;
    if (engine != null) await _releaseEngine(engine);
    if (!mounted || _roomEnded) return;
    await _connect();
  }

  Future<void> _releaseEngine(RtcEngine engine) async {
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('SocketException') ||
        message.contains('TimeoutException')) {
      return 'Could not reach the voice service. Check your connection and try again.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_leaving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Dialog.fullscreen(
      backgroundColor: const Color(0xFF101915),
      child: _buildMeetingRoom(context),
    ),
  );

  Widget _buildMeetingRoom(BuildContext context) => Stack(
    key: _meetingStackKey,
    children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF172820), Color(0xFF101915), Color(0xFF0D1411)],
            ),
          ),
        ),
      ),
      Positioned(
        top: -100,
        right: -80,
        child: _GlowOrb(color: const Color(0xFF5ACB91).withValues(alpha: .15)),
      ),
      Positioned(
        bottom: 80,
        left: -130,
        child: _GlowOrb(color: const Color(0xFF4A8B70).withValues(alpha: .12)),
      ),
      SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _participantsStream,
          builder: (context, snapshot) {
            final participants = snapshot.data?.docs ?? const [];
            final roster = _meetingRoster(participants);
            final connectedCount = roster
                .where((person) => person.connected)
                .length;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _roomEnded
                                        ? const Color(0xFFFF8177)
                                        : const Color(0xFF6EE7A8),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6EE7A8)
                                            .withValues(alpha: .45),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _roomEnded
                                      ? (_roomEndMessage.startsWith('The host')
                                            ? 'ROOM ENDED'
                                            : 'REMOVED FROM ROOM')
                                      : 'LIVE VOICE ROOM',
                                  style: const TextStyle(
                                    color: Color(0xFFB6C9BE),
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.roomTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFF1F7F3),
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.isHost && !_roomEnded)
                        IconButton(
                          tooltip: 'End room for everyone',
                          onPressed: widget.onEndRoom,
                          icon: const Icon(Icons.stop_circle_outlined),
                          color: const Color(0xFFFF9187),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: .07,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_roomStatusError != null)
                  _MeetingNotice(
                    icon: Icons.cloud_off_rounded,
                    message: _roomStatusError!,
                  ),
                if (_roomEnded)
                  Expanded(
                    child: Center(
                      child: _MeetingNotice(
                        icon: Icons.call_end_rounded,
                        message: _roomEndMessage,
                      ),
                    ),
                  ),
                if (_roomEnded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _leave,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close room'),
                      ),
                    ),
                  ),
                if (!_roomEnded) ...[
                  if (widget.isHost) _buildJoinRequests(),
                  if (_error != null)
                    _MeetingNotice(
                      icon: Icons.wifi_off_rounded,
                      message: _error!,
                      action: TextButton.icon(
                        onPressed: _reconnect,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    )
                  else if (_connectionStatus != null)
                    _MeetingNotice(
                      icon: _connectionFailed
                          ? Icons.wifi_off_rounded
                          : Icons.sync_rounded,
                      message: _connectionStatus!,
                      action: _connectionFailed
                          ? TextButton.icon(
                              onPressed: _reconnect,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reconnect'),
                            )
                          : null,
                    )
                  else if (_connecting)
                    const _MeetingNotice(
                      icon: Icons.graphic_eq_rounded,
                      message: 'Joining the conversation…',
                      isLoading: true,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
                    child: Row(
                      children: [
                        const Text(
                          'IN THIS ROOM',
                          style: TextStyle(
                            color: Color(0xFF9BAFA4),
                            fontSize: 10,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        _GlassPill(
                          icon: Icons.people_alt_outlined,
                          label:
                              '${roster.length} ${roster.length == 1 ? 'person' : 'people'}',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: roster.isEmpty
                        ? const Center(
                            child: Text(
                              'Waiting for the host to join…',
                              style: TextStyle(color: Color(0xFFAFC0B6)),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth < 440
                                  ? 2
                                  : 3;
                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  18,
                                ),
                                itemCount: roster.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: .88,
                                    ),
                                itemBuilder: (context, index) {
                                  final person = roster[index];
                                  return _ParticipantTile(
                                    key: _participantTileKey(person.id),
                                    person: person,
                                    onModerate: widget.isHost && !person.isSelf
                                        ? () => _showParticipantActions(person)
                                        : null,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                    child: _MeetingControlDock(
                      connected: _isConnected,
                      muted: _muted,
                      mutedByHost: _hostMuted,
                      onToggleMute: _toggleMute,
                      reactionButtonKeys: {
                        for (final emoji in const [
                          '👏',
                          '❤️',
                          '😂',
                          '🔥',
                          '👍',
                          '🎉',
                        ])
                          emoji: _reactionButtonKey(emoji),
                      },
                      onReact: _animateReaction,
                      onLeave: _leave,
                      leaving: _leaving,
                      connectedCount: connectedCount,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      if (_flyingReaction case final flight?)
        TweenAnimationBuilder<Offset>(
          key: ValueKey(flight.id),
          tween: Tween(begin: flight.start, end: flight.end),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
          onEnd: () => _finishReactionFlight(flight.id),
          builder: (context, position, child) => Positioned(
            left: position.dx - 22,
            top: position.dy - 22,
            child: child!,
          ),
          child: _FlyingReactionBubble(emoji: flight.emoji),
        ),
    ],
  );

  Widget
  _buildJoinRequests() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _joinRequestsStream,
    builder: (context, snapshot) {
      final requests = snapshot.data?.docs ?? const [];
      if (requests.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: _GlassPanel(
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${requests.length} JOIN ${requests.length == 1 ? 'REQUEST' : 'REQUESTS'}',
                style: const TextStyle(
                  color: Color(0xFFB6C9BE),
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 116),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: requests.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: .08),
                  ),
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final name =
                        request.data()['displayName'] as String? ?? 'Developer';
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFEAF2ED),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(
                            _decideJoinRequest(request, 'declined'),
                          ),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          onPressed: () => unawaited(
                            _decideJoinRequest(request, 'approved'),
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Allow'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  List<_MeetingPerson> _meetingRoster(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final roster = <_MeetingPerson>[];
    for (final document in documents) {
      final data = document.data();
      final name = (data['displayName'] as String?)?.trim();
      final isSelf = document.id == FirebaseAuth.instance.currentUser?.uid;
      roster.add(
        _MeetingPerson(
          id: document.id,
          name: isSelf
              ? widget.displayName
              : (name == null || name.isEmpty ? 'Developer' : name),
          isSelf: isSelf,
          isHost: document.id == widget.hostId,
          connected: isSelf
              ? _isConnected
              : _remoteUsers.contains(_uidFromFirebaseId(document.id)),
          muted: isSelf
              ? _muted
              : _mutedRemoteUsers.contains(_uidFromFirebaseId(document.id)),
          mutedByHost: data['mutedByHost'] == true,
          reaction: _roomReactions[document.id],
        ),
      );
    }
    if (!roster.any((person) => person.isSelf)) {
      final selfId = FirebaseAuth.instance.currentUser?.uid ?? widget.hostId;
      roster.insert(
        0,
        _MeetingPerson(
          id: selfId,
          name: widget.displayName,
          isSelf: true,
          isHost: widget.isHost,
          connected: _isConnected,
          muted: _muted,
          mutedByHost: _hostMuted,
          reaction: _roomReactions[selfId],
        ),
      );
    }
    return roster;
  }
}

class _MeetingPerson {
  final String id;
  final String name;
  final bool isSelf;
  final bool isHost;
  final bool connected;
  final bool muted;
  final bool mutedByHost;
  final _RoomReaction? reaction;

  const _MeetingPerson({
    required this.id,
    required this.name,
    required this.isSelf,
    required this.isHost,
    required this.connected,
    required this.muted,
    required this.mutedByHost,
    this.reaction,
  });
}

class _RoomReaction {
  final String emoji;
  final String eventId;

  const _RoomReaction({required this.emoji, required this.eventId});
}

class _FlyingReactionData {
  final int id;
  final String emoji;
  final Offset start;
  final Offset end;

  const _FlyingReactionData({
    required this.id,
    required this.emoji,
    required this.start,
    required this.end,
  });
}

class _GlowOrb extends StatelessWidget {
  final Color color;

  const _GlowOrb({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 280,
    height: 280,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 35)],
    ),
  );
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .075),
          borderRadius: borderRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .11)),
        ),
        child: child,
      ),
    ),
  );
}

class _GlassPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _GlassPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => _GlassPanel(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    borderRadius: BorderRadius.circular(30),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFC5D5CC), size: 15),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFEAF2ED),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ParticipantTile extends StatelessWidget {
  final _MeetingPerson person;
  final VoidCallback? onModerate;

  const _ParticipantTile({super.key, required this.person, this.onModerate});

  @override
  Widget build(BuildContext context) {
    final initial = person.name.trim().isEmpty
        ? '?'
        : person.name.trim().substring(0, 1).toUpperCase();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: person.connected
            ? const Color(0xFF24392E).withValues(alpha: .78)
            : Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: person.connected
              ? const Color(0xFF74D6A0).withValues(alpha: .32)
              : Colors.white.withValues(alpha: .08),
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: person.connected
                          ? const [Color(0xFFB6E8C8), Color(0xFF579A73)]
                          : const [Color(0xFF51655A), Color(0xFF34443B)],
                    ),
                    boxShadow: person.connected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF67D493)
                                  .withValues(alpha: .2),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ]
                        : const [],
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Color(0xFF102017),
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    person.isSelf ? '${person.name} (You)' : person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF0F5F1),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  person.mutedByHost
                      ? 'Muted by host'
                      : person.connected
                      ? 'In the conversation'
                      : 'Joining…',
                  style: const TextStyle(
                    color: Color(0xFFA9B9AF),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (person.isHost)
            const Positioned(
              top: 12,
              left: 12,
              child: _TileBadge(icon: Icons.star_rounded, label: 'HOST'),
            ),
          if (person.reaction != null)
            Positioned(
              top: 56,
              right: 20,
              child: _SettledReaction(
                key: ValueKey(person.reaction!.eventId),
                emoji: person.reaction!.emoji,
              ),
            ),
          Positioned(
            top: 10,
            right: 10,
            child: Icon(
              person.muted || person.mutedByHost
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              color: person.muted || person.mutedByHost
                  ? const Color(0xFFFFA9A1)
                  : const Color(0xFFC8D8CE),
              size: 17,
            ),
          ),
          if (onModerate != null)
            Positioned(
              right: 5,
              bottom: 5,
              child: IconButton(
                tooltip: 'Manage ${person.name}',
                onPressed: onModerate,
                icon: const Icon(Icons.more_horiz_rounded),
                color: const Color(0xFFD8E4DC),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: .2),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TileBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TileBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFFE0C98A)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE4EAE6),
              fontSize: 9,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettledReaction extends StatelessWidget {
  final String emoji;

  const _SettledReaction({super.key, required this.emoji});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutBack,
    builder: (context, progress, child) => Opacity(
      opacity: progress.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 14),
        child: Transform.scale(scale: .75 + progress * .25, child: child),
      ),
    ),
    child: Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2B22).withValues(alpha: .94),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF9FE3B8).withValues(alpha: .7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 19)),
    ),
  );
}

class _FlyingReactionBubble extends StatelessWidget {
  final String emoji;

  const _FlyingReactionBubble({required this.emoji});

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF21372A).withValues(alpha: .96),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFA5E9BD).withValues(alpha: .85)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF75DDA0).withValues(alpha: .28),
          blurRadius: 18,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Text(emoji, style: const TextStyle(fontSize: 24)),
  );
}

class _MeetingNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  final bool isLoading;

  const _MeetingNotice({
    required this.icon,
    required this.message,
    this.action,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: _GlassPanel(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (isLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF87D9A7),
              ),
            )
          else
            Icon(icon, color: const Color(0xFFB7D9C4), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFE3ECE6), fontSize: 12),
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}

class _MeetingControlDock extends StatelessWidget {
  final bool connected;
  final bool muted;
  final bool mutedByHost;
  final VoidCallback onToggleMute;
  final ValueChanged<String> onReact;
  final Map<String, GlobalKey> reactionButtonKeys;
  final VoidCallback onLeave;
  final bool leaving;
  final int connectedCount;

  const _MeetingControlDock({
    required this.connected,
    required this.muted,
    required this.mutedByHost,
    required this.onToggleMute,
    required this.onReact,
    required this.reactionButtonKeys,
    required this.onLeave,
    required this.leaving,
    required this.connectedCount,
  });

  @override
  Widget build(BuildContext context) => _GlassPanel(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    borderRadius: BorderRadius.circular(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(
              Icons.graphic_eq_rounded,
              color: Color(0xFF93D9AD),
              size: 17,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                connected
                    ? '$connectedCount ${connectedCount == 1 ? 'person' : 'people'} connected'
                    : 'Voice controls unlock when connected',
                style: const TextStyle(
                  color: Color(0xFFC3D1C8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final emoji in const ['👏', '❤️', '😂', '🔥', '👍', '🎉'])
              InkWell(
                key: reactionButtonKeys[emoji],
                onTap: connected ? () => onReact(emoji) : null,
                borderRadius: BorderRadius.circular(20),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: connected ? 1 : .38,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 21)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: connected && !mutedByHost ? onToggleMute : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 54),
                  backgroundColor: muted
                      ? const Color(0xFF633B39)
                      : Colors.white.withValues(alpha: .12),
                  foregroundColor: const Color(0xFFF2F7F3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: Icon(
                  mutedByHost
                      ? Icons.lock_rounded
                      : muted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                ),
                label: Text(
                  mutedByHost
                      ? 'Muted by host'
                      : muted
                      ? 'Unmute'
                      : 'Mute',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: leaving ? null : onLeave,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 54),
                  backgroundColor: const Color(0xFFD85D56),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: Icon(
                  leaving ? Icons.hourglass_top : Icons.call_end_rounded,
                ),
                label: Text(leaving ? 'Leaving…' : 'Leave room'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

int _uidFromFirebaseId(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
  }
  final uid = hash & 0x7fffffff;
  return uid == 0 ? 1 : uid;
}
