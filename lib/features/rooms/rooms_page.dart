import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/section_page.dart';
import 'agora_voice_dialog.dart';

class RoomsPage extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final bool chromeVisible;

  const RoomsPage({
    super.key,
    required this.onOpenDrawer,
    required this.chromeVisible,
  });

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final _rooms = FirebaseFirestore.instance.collection('rooms');
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _roomsStream;
  bool _creatingRoom = false;

  String get _userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _roomsStream = _rooms.where('status', isEqualTo: 'open').snapshots();
  }

  @override
  Widget build(BuildContext context) => SectionPage(
    onOpenDrawer: widget.onOpenDrawer,
    chromeVisible: widget.chromeVisible,
    eyebrow: 'COMMUNITY CONVERSATIONS',
    title: 'Rooms',
    subtitle: 'Create a room or join a conversation with other builders.',
    action: _creatingRoom ? 'Creating room…' : 'Start a Room',
    icon: Icons.mic_none_rounded,
    onAction: _creatingRoom ? null : _startRoom,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _voiceNotice(context),
        const SizedBox(height: 22),
        const Text(
          'OPEN ROOMS',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            color: Color(0xFF77827A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _roomsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _RoomsMessage(
                icon: Icons.cloud_off_rounded,
                title: 'Rooms could not load',
                message: 'Check your connection and make sure the latest Firestore rules are published.',
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final rooms = snapshot.data!.docs.toList()
              ..sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
            if (rooms.isEmpty) {
              return const _RoomsMessage(
                icon: Icons.forum_outlined,
                title: 'No open rooms yet',
                message: 'Start one and invite the community to join.',
              );
            }

            return Column(
              children: [
                for (final room in rooms)
                  _RoomCard(
                    key: ValueKey(room.id),
                    roomId: room.id,
                    data: room.data(),
                    userId: _userId,
                    onJoin: () => _joinRoom(
                      room.id,
                      room.data()['title'] as String? ?? 'Room',
                      isHost: room.data()['hostId'] == _userId,
                      hostId: room.data()['hostId'] as String? ?? '',
                    ),
                    onEnd: () => _endRoom(room.id),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _voiceNotice(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: softSurface(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: outlineColor(context)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Live voice rooms need the secure voice service to be available.',
            style: TextStyle(fontSize: 12, color: mutedText(context)),
          ),
        ),
      ],
    ),
  );

  Future<void> _startRoom() async {
    final draft = await showModalBottomSheet<_RoomDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CreateRoomSheet(),
    );

    if (draft == null || !mounted) return;

    setState(() => _creatingRoom = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final profile = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(user.uid)
          .get();
      final displayName =
          (profile.data()?['displayName'] as String?)?.trim().isNotEmpty == true
          ? (profile.data()!['displayName'] as String).trim()
          : (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'Developer');

      final roomRef = _rooms.doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(roomRef, {
        'title': draft.title,
        'description': draft.description,
        'hostId': user.uid,
        'hostName': displayName,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) _showMessage('Room created. You are now its host.');
    } on FirebaseException catch (error) {
      if (mounted) {
        _showMessage(
          error.code == 'permission-denied'
              ? 'Firebase denied this action. Publish the updated Firestore rules, then try again.'
              : 'Could not create the room. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) _showMessage('Could not create the room. Please try again.');
    } finally {
      if (mounted) setState(() => _creatingRoom = false);
    }
  }

  Future<void> _joinRoom(
    String roomId,
    String roomTitle, {
    required bool isHost,
    required String hostId,
  }) async {
    final participantRef = _rooms
        .doc(roomId)
        .collection('participants')
        .doc(_userId);
    final requestRef = _rooms
        .doc(roomId)
        .collection('joinRequests')
        .doc(_userId);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final profile = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(user.uid)
          .get();
      final displayName =
          (profile.data()?['displayName'] as String?)?.trim().isNotEmpty == true
          ? (profile.data()!['displayName'] as String).trim()
          : (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'Developer');
      if (!isHost) {
        final approved = await _requestRoomAccess(
          requestRef,
          displayName: displayName,
        );
        if (!approved) return;
      }
      await participantRef.set({
        'uid': _userId,
        'displayName': displayName,
        'joinedAt': FieldValue.serverTimestamp(),
        'mutedByHost': false,
      });
      if (!isHost) await requestRef.delete();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AgoraVoiceDialog(
          roomId: roomId,
          roomTitle: roomTitle,
          isHost: isHost,
          hostId: hostId,
          displayName: displayName,
          onEndRoom: () => _endRoom(roomId),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) _showRoomActionError(error, 'join');
    } catch (_) {
      if (mounted) _showMessage('Could not join this room. Please try again.');
    } finally {
      try {
        await participantRef.delete();
      } on FirebaseException catch (error) {
        if (mounted) _showRoomActionError(error, 'leave');
      }
    }
  }

  Future<bool> _requestRoomAccess(
    DocumentReference<Map<String, dynamic>> requestRef, {
    required String displayName,
  }) async {
    final currentRequest = await requestRef.get();
    final status = currentRequest.data()?['status'];
    if (status == 'approved') return true;
    if (status == 'pending') {
      // Reuse the pending request if this screen was reopened.
    } else if (currentRequest.exists) {
      await requestRef.update({
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await requestRef.set({
        'uid': _userId,
        'displayName': displayName,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JoinRequestDialog(requestStream: requestRef.snapshots()),
    );
    if (approved != true) {
      try {
        final latest = await requestRef.get();
        if (latest.data()?['status'] == 'pending') await requestRef.delete();
      } on FirebaseException {
        // A host decision may have raced with cancellation; the next request can reuse it.
      }
      if (approved == false && mounted) {
        _showMessage('The host did not approve this request.');
      }
    }
    return approved == true;
  }

  Future<void> _endRoom(String roomId) async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this room?'),
        content: const Text(
          'Everyone in the voice room will be disconnected, and the room will disappear from the open rooms list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep open'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End room'),
          ),
        ],
      ),
    );
    if (shouldEnd != true) return;
    try {
      await _rooms.doc(roomId).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showMessage('Room ended.');
    } on FirebaseException catch (error) {
      if (mounted) _showRoomActionError(error, 'end');
    } catch (_) {
      if (mounted) _showMessage('Could not end this room. Please try again.');
    }
  }

  void _showRoomActionError(FirebaseException error, String action) {
    _showMessage(
      error.code == 'permission-denied'
          ? 'Firebase denied this action. Publish the updated Firestore rules, then try again.'
          : 'Could not $action this room. Please try again.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

DateTime _createdAt(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final value = doc.data()['createdAt'];
  return value is Timestamp
      ? value.toDate()
      : DateTime.fromMillisecondsSinceEpoch(0);
}

class _RoomCard extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> data;
  final String userId;
  final VoidCallback onJoin;
  final VoidCallback onEnd;

  const _RoomCard({
    super.key,
    required this.roomId,
    required this.data,
    required this.userId,
    required this.onJoin,
    required this.onEnd,
  });

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _participantsStream;

  @override
  void initState() {
    super.initState();
    _participantsStream = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('participants')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final userId = widget.userId;
    final hostId = data['hostId'] as String? ?? '';
    final hostName = data['hostName'] as String? ?? 'Developer';
    final title = data['title'] as String? ?? 'Untitled room';
    final description = data['description'] as String? ?? '';
    final isHost = hostId == userId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: outlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.circle, color: Color(0xFF79D39E), size: 9),
              const SizedBox(width: 7),
              const Text(
                'OPEN NOW',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (isHost)
                TextButton.icon(
                  onPressed: widget.onEnd,
                  icon: const Icon(Icons.stop_circle_outlined, size: 17),
                  label: const Text('End'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(description, style: TextStyle(color: mutedText(context))),
          ],
          const SizedBox(height: 8),
          Text(
            'Hosted by $hostName',
            style: TextStyle(fontSize: 12, color: mutedText(context)),
          ),
          const SizedBox(height: 13),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _participantsStream,
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? const [];
              final joined = docs.any((doc) => doc.id == userId);
              final countLabel = snapshot.hasError
                  ? 'Participants'
                  : '${docs.length} ${docs.length == 1 ? 'person' : 'people'} joined';
              return Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: snapshot.hasError
                          ? null
                          : () => _showParticipants(context, docs),
                      icon: const Icon(Icons.people_outline_rounded, size: 18),
                      label: Text(
                        snapshot.hasError ? 'Participants' : countLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.centerLeft,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (joined && !isHost)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.check_circle,
                        size: 15,
                        color: AppColors.green,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: widget.onJoin,
                    icon: const Icon(Icons.mic_rounded, size: 17),
                    label: const Text('Join voice'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showParticipants(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> participants,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ParticipantsSheet(
        roomTitle: widget.data['title'] as String? ?? 'Room',
        hostId: widget.data['hostId'] as String? ?? '',
        participants: participants,
      ),
    );
  }
}

class _ParticipantsSheet extends StatelessWidget {
  final String roomTitle;
  final String hostId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> participants;

  const _ParticipantsSheet({
    required this.roomTitle,
    required this.hostId,
    required this.participants,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(roomTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${participants.length} ${participants.length == 1 ? 'person' : 'people'} in this room',
          style: TextStyle(color: mutedText(context)),
        ),
        const SizedBox(height: 14),
        if (participants.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No one is in the room yet.')),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .55,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: participants.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final participant = participants[index];
                final name = (participant.data()['displayName'] as String?)
                    ?.trim();
                final displayName = name == null || name.isEmpty
                    ? 'Developer'
                    : name;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(displayName.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(displayName),
                  trailing: participant.id == hostId
                      ? const Chip(label: Text('Host'))
                      : null,
                );
              },
            ),
          ),
      ],
    ),
  );
}

class _RoomsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _RoomsMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 22),
    child: Column(
      children: [
        Icon(icon, size: 36, color: mutedText(context)),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedText(context)),
        ),
      ],
    ),
  );
}

class _RoomDraft {
  final String title;
  final String description;

  const _RoomDraft({required this.title, required this.description});
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start a room',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Give your conversation a name so people know what it is about.',
                style: TextStyle(color: mutedText(context)),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _titleController,
                maxLength: 80,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                  hintText: 'e.g. Flutter beginners meetup',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final title = value?.trim() ?? '';
                  if (title.length < 3) return 'Enter at least 3 characters.';
                  return null;
                },
              ),
              TextFormField(
                controller: _descriptionController,
                maxLength: 240,
                maxLines: 3,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What will you talk about? (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create room'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _RoomDraft(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
  }
}

class _JoinRequestDialog extends StatefulWidget {
  final Stream<DocumentSnapshot<Map<String, dynamic>>> requestStream;

  const _JoinRequestDialog({required this.requestStream});

  @override
  State<_JoinRequestDialog> createState() => _JoinRequestDialogState();
}

class _JoinRequestDialogState extends State<_JoinRequestDialog> {
  bool _closing = false;

  void _closeWithApproval(bool approved) {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(approved);
    });
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: widget.requestStream,
        builder: (context, snapshot) {
          final status = snapshot.data?.data()?['status'];
          if (status == 'approved') _closeWithApproval(true);
          if (status == 'declined') _closeWithApproval(false);

          final isApproved = status == 'approved';
          return AlertDialog(
            title: const Text('Request to join'),
            content: Row(
              children: [
                if (snapshot.hasError)
                  const Icon(Icons.cloud_off_rounded)
                else
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    snapshot.hasError
                        ? 'Could not check your request. Try again.'
                        : isApproved
                        ? 'You’re in. Joining the voice room…'
                        : status == 'declined'
                        ? 'The host did not approve this request.'
                        : 'Waiting for the host to let you in…',
                  ),
                ),
              ],
            ),
            actions: [
              if (status == 'declined')
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close'),
                )
              else if (!isApproved)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel request'),
                ),
            ],
          );
        },
      );
}
