import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

Future<void> submitProjectFileProposal({
  required String projectId,
  required String fileId,
  required String operation,
  required String path,
  required String content,
  required String baseContent,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('You must be signed in to contribute.');
  final projectRef = FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId);
  final projectSnapshot = await projectRef.get();
  final project = projectSnapshot.data();
  if (project == null) throw StateError('This project is no longer available.');
  final displayName = (user.displayName?.trim().isNotEmpty ?? false)
      ? user.displayName!.trim()
      : 'Community member';

  await projectRef.collection('fileChangeProposals').add({
    'submitterId': user.uid,
    'submitterName': displayName.length > 80
        ? displayName.substring(0, 80)
        : displayName,
    'projectOwnerId': project['ownerId'],
    'projectTitle': project['title'],
    'operation': operation,
    'fileId': fileId,
    'path': path,
    'content': content,
    'baseContent': baseContent,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> openProjectFileProposals(
  BuildContext context, {
  required String projectId,
  required String projectTitle,
  required String ownerId,
}) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return;
  if (userId != ownerId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Only the project owner can review changes.'),
      ),
    );
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProjectFileProposalsPage(
        projectId: projectId,
        projectTitle: projectTitle,
        viewerId: userId,
        ownerId: ownerId,
      ),
    ),
  );
}

Future<void> openMyProjectFileProposals(
  BuildContext context, {
  required String projectId,
  required String projectTitle,
  required String ownerId,
  String? focusDocumentId,
}) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProjectFileProposalsPage(
        projectId: projectId,
        projectTitle: projectTitle,
        viewerId: userId,
        ownerId: ownerId,
        focusDocumentId: focusDocumentId,
      ),
    ),
  );
}

class ProjectFileProposalsPage extends StatefulWidget {
  final String projectId;
  final String projectTitle;
  final String viewerId;
  final String ownerId;
  final String? focusDocumentId;

  const ProjectFileProposalsPage({
    super.key,
    required this.projectId,
    required this.projectTitle,
    required this.viewerId,
    required this.ownerId,
    this.focusDocumentId,
  });

  @override
  State<ProjectFileProposalsPage> createState() =>
      _ProjectFileProposalsPageState();
}

class _ProjectFileProposalsPageState extends State<ProjectFileProposalsPage> {
  final Set<String> _updatingIds = {};

  bool get _canReview => widget.viewerId == widget.ownerId;

  CollectionReference<Map<String, dynamic>> get _proposals => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('fileChangeProposals');

  Future<void> _review(
    QueryDocumentSnapshot<Map<String, dynamic>> proposal,
    String decision,
  ) async {
    setState(() => _updatingIds.add(proposal.id));
    try {
      if (decision == 'approved') {
        final currentProposal = await proposal.reference.get();
        final currentData = currentProposal.data();
        if (currentData?['operation'] == 'create') {
          final existing = await _files
              .where('path', isEqualTo: currentData?['path'])
              .limit(1)
              .get();
          if (existing.docs.isNotEmpty) {
            throw StateError(
              'A file already exists at this path. Reject this proposal or ask the contributor to choose another path.',
            );
          }
        }
      }
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final proposalSnapshot = await transaction.get(proposal.reference);
        final data = proposalSnapshot.data();
        if (data == null || data['status'] != 'pending') {
          throw StateError('This proposal has already been reviewed.');
        }

        DocumentReference<Map<String, dynamic>>? fileReference;
        DocumentSnapshot<Map<String, dynamic>>? fileSnapshot;
        if (decision == 'approved') {
          final operation = data['operation'] as String?;
          if (operation == 'create') {
            fileReference = _files.doc(proposal.id);
            fileSnapshot = await transaction.get(fileReference);
            if (fileSnapshot.exists) {
              throw StateError('A file with this proposal ID already exists.');
            }
          } else if (operation == 'update') {
            final fileId = data['fileId'] as String? ?? '';
            if (fileId.isEmpty) throw StateError('The target file is missing.');
            fileReference = _files.doc(fileId);
            fileSnapshot = await transaction.get(fileReference);
            if (!fileSnapshot.exists) {
              throw StateError('The original file was deleted.');
            }
            if (fileSnapshot.data()?['content'] != data['baseContent']) {
              throw StateError(
                'The file changed after this proposal was submitted. Review the latest file before approving.',
              );
            }
          } else {
            throw StateError('This proposal type is not supported.');
          }

          if (operation == 'create') {
            transaction.set(fileReference, {
              'path': data['path'],
              'content': data['content'],
              'createdBy': widget.viewerId,
              'updatedBy': widget.viewerId,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            transaction.update(fileReference, {
              'content': data['content'],
              'updatedBy': widget.viewerId,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        transaction.update(proposal.reference, {
          'status': decision,
          'reviewedBy': widget.viewerId,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
        final submitterId = data['submitterId'] as String;
        final notificationReference = FirebaseFirestore.instance
            .collection('users')
            .doc(submitterId)
            .collection('notifications')
            .doc(proposal.id);
        transaction.set(notificationReference, {
          'kind': 'code_change_review',
          'projectId': widget.projectId,
          'projectTitle':
              data['projectTitle'] as String? ?? widget.projectTitle,
          'projectOwnerId': widget.ownerId,
          'proposalId': proposal.id,
          'path': data['path'] as String? ?? '',
          'proposalStatus': decision,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage('Could not review change (${error.code}).');
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : 'Could not review this change. Try again.';
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _updatingIds.remove(proposal.id));
    }
  }

  CollectionReference<Map<String, dynamic>> get _files => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('files');

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_canReview ? 'Code change requests' : 'My code changes'),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _canReview
          ? _proposals.snapshots()
          : _proposals
                .where('submitterId', isEqualTo: widget.viewerId)
                .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load code changes. Check your Firestore rules.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText(context)),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final proposals = snapshot.data!.docs.toList()
          ..sort((a, b) {
            if (a.id == widget.focusDocumentId) return -1;
            if (b.id == widget.focusDocumentId) return 1;
            final aData = a.data();
            final bData = b.data();
            final aPending = aData['status'] == 'pending';
            final bPending = bData['status'] == 'pending';
            if (aPending != bPending) return aPending ? -1 : 1;
            final aCreated = aData['createdAt'];
            final bCreated = bData['createdAt'];
            final aDate = aCreated is Timestamp
                ? aCreated.toDate()
                : DateTime(0);
            final bDate = bCreated is Timestamp
                ? bCreated.toDate()
                : DateTime(0);
            return bDate.compareTo(aDate);
          });
        if (proposals.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                _canReview
                    ? 'No code changes waiting for review.'
                    : 'You have not submitted any code changes for ${widget.projectTitle}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText(context)),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: proposals.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _proposalCard(proposals[index]),
        );
      },
    ),
  );

  Widget _proposalCard(QueryDocumentSnapshot<Map<String, dynamic>> proposal) {
    final data = proposal.data();
    final operation = data['operation'] as String? ?? 'update';
    final status = data['status'] as String? ?? 'pending';
    final path = data['path'] as String? ?? 'Unknown file';
    final content = data['content'] as String? ?? '';
    final isUpdating = _updatingIds.contains(proposal.id);
    final colors = Theme.of(context).colorScheme;
    final statusColor = switch (status) {
      'approved' => colors.primary,
      'rejected' => colors.error,
      _ => colors.tertiary,
    };
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: outlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  operation == 'create' ? 'New file' : 'Edit file',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                status[0].toUpperCase() + status.substring(1),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(path, style: TextStyle(color: mutedText(context))),
          const SizedBox(height: 10),
          Text(
            _canReview
                ? 'Proposed by ${data['submitterName'] as String? ?? 'Community member'}'
                : 'Submitted for owner approval',
            style: TextStyle(color: mutedText(context), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          if (_canReview && status == 'pending') ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: isUpdating
                      ? null
                      : () => _review(proposal, 'rejected'),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: isUpdating
                      ? null
                      : () => _review(proposal, 'approved'),
                  child: isUpdating
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve and apply'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
