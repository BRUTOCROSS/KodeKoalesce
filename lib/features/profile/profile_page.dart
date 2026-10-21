import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/section_page.dart';
import 'followers_page.dart';
import 'following_page.dart';
import 'profile_utils.dart';
import 'profile_external_link.dart';
import 'builder_name_heading.dart';
import '../projects/projects_page.dart' show openProjectWorkspace;

class ProfilePage extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final bool chromeVisible;
  final String displayName;
  final String email;
  final ValueChanged<String> onDisplayNameChanged;

  const ProfilePage({
    super.key,
    required this.onOpenDrawer,
    required this.chromeVisible,
    required this.displayName,
    required this.email,
    required this.onDisplayNameChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final String _userId;
  late final DocumentReference<Map<String, dynamic>> _profile;
  late final DocumentReference<Map<String, dynamic>> _publicProfile;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _projectsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _followingStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _followersStream;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;
    _profile = firestore.collection('users').doc(_userId);
    _publicProfile = firestore.collection('publicProfiles').doc(_userId);
    _profileStream = _profile.snapshots();
    _postsStream = firestore
        .collection('posts')
        .where('authorId', isEqualTo: _userId)
        .limit(30)
        .snapshots();
    _projectsStream = firestore
        .collection('projects')
        .where('ownerId', isEqualTo: _userId)
        .limit(30)
        .snapshots();
    _followingStream = _profile.collection('following').snapshots();
    _followersStream = firestore
        .collectionGroup('following')
        .where('userId', isEqualTo: _userId)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) => SectionPage(
    onOpenDrawer: widget.onOpenDrawer,
    chromeVisible: widget.chromeVisible,
    eyebrow: 'YOUR CORNER',
    title: 'Your profile',
    subtitle: 'Your projects and posts, all in one place.',
    action: 'Edit profile',
    icon: Icons.edit_outlined,
    onAction: _editProfile,
    child: _buildContent(context),
  );

  Widget _buildContent(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _profileStream,
    builder: (context, profileSnapshot) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _postsStream,
          builder: (context, postsSnapshot) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _projectsStream,
                builder: (context, projectsSnapshot) =>
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _followingStream,
                      builder: (context, followingSnapshot) {
                        final error =
                            profileSnapshot.error ??
                            postsSnapshot.error ??
                            projectsSnapshot.error ??
                            followingSnapshot.error;
                        if (error != null) {
                          return Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              'Could not load your profile. Check your connection and Firestore rules.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: mutedText(context)),
                            ),
                          );
                        }
                        if (!profileSnapshot.hasData ||
                            !postsSnapshot.hasData ||
                            !projectsSnapshot.hasData ||
                            !followingSnapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final profile =
                            profileSnapshot.data!.data() ?? const {};
                        final name =
                            profile['displayName'] as String? ??
                            widget.displayName;
                        final bio = profile['bio'] as String? ?? '';
                        final headline = profile['headline'] as String? ?? '';
                        final location = profile['location'] as String? ?? '';
                        final skills = _stringList(profile['skills']);
                        final interests = _stringList(profile['interests']);
                        final githubUrl = profile['githubUrl'] as String? ?? '';
                        final websiteUrl =
                            profile['websiteUrl'] as String? ?? '';
                        final posts = postsSnapshot.data!.docs.toList()
                          ..sort(
                            (a, b) =>
                                _dateOf(b.data()['createdAt'])
                                    .compareTo(_dateOf(a.data()['createdAt'])),
                          );
                        final projects = projectsSnapshot.data!.docs.toList()
                          ..sort(
                            (a, b) =>
                                _dateOf(b.data()['createdAt'])
                                    .compareTo(_dateOf(a.data()['createdAt'])),
                          );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _profileCard(
                              context,
                              name: name,
                              bio: bio,
                              headline: headline,
                              location: location,
                              skills: skills,
                              interests: interests,
                              githubUrl: githubUrl,
                              websiteUrl: websiteUrl,
                              postCount: posts.length,
                              projectCount: projects.length,
                              followingCount:
                                  followingSnapshot.data!.docs.length,
                            ),
                            const SizedBox(height: 22),
                            _sectionTitle(
                              context,
                              'Your projects',
                              Icons.folder_outlined,
                            ),
                            const SizedBox(height: 9),
                            if (projects.isEmpty)
                              _emptyText(
                                context,
                                'You haven’t created a project yet.',
                              )
                            else
                              for (final project in projects)
                                _projectCard(context, project),
                            const SizedBox(height: 20),
                            _sectionTitle(
                              context,
                              'Your posts',
                              Icons.chat_bubble_outline,
                            ),
                            const SizedBox(height: 9),
                            if (posts.isEmpty)
                              _emptyText(
                                context,
                                'You haven’t shared a post yet.',
                              )
                            else
                              for (final post in posts)
                                _postCard(context, post),
                          ],
                        );
                      },
                    ),
              ),
        ),
  );

  Widget _profileCard(
    BuildContext context, {
    required String name,
    required String bio,
    required String headline,
    required String location,
    required List<String> skills,
    required List<String> interests,
    required String githubUrl,
    required String websiteUrl,
    required int postCount,
    required int projectCount,
    required int followingCount,
  }) {
    final safeName = name.trim().isEmpty ? 'Developer' : name.trim();
    final initials = safeName.substring(0, 1).toUpperCase();
    final handle = profileHandleForName(safeName);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: const Color(0xFFD7E8DC),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 13),
          BuilderNameHeading(name: safeName, fontSize: 25),
          Text(
            '@$handle',
            style: TextStyle(color: mutedText(context), fontSize: 13),
          ),
          if (headline.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(headline, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (location.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _ProfileDetailLine(
              icon: Icons.location_on_outlined,
              text: location,
            ),
          ],
          if (bio.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              bio,
              style: TextStyle(height: 1.45, color: mutedText(context)),
            ),
          ],
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 12),
            _detailChips(context, 'Skills', skills),
          ],
          if (interests.isNotEmpty) ...[
            const SizedBox(height: 8),
            _detailChips(context, 'Interested in', interests),
          ],
          if (githubUrl.trim().isNotEmpty || websiteUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                if (githubUrl.trim().isNotEmpty)
                  ProfileExternalLink(
                    icon: Icons.code_rounded,
                    label: 'GitHub',
                    url: githubUrl,
                  ),
                if (websiteUrl.trim().isNotEmpty)
                  ProfileExternalLink(
                    icon: Icons.link_rounded,
                    label: 'Portfolio',
                    url: websiteUrl,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _ProfileStat(value: '$postCount', label: 'Posts'),
              _ProfileStat(value: '$projectCount', label: 'Projects'),
              _ProfileStat(
                value: '$followingCount',
                label: 'Following',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => FollowingPage(userId: _userId),
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _followersStream,
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
                        builder: (_) => FollowersPage(userId: _userId),
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
  }

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

  Widget _emptyText(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(text, style: TextStyle(color: mutedText(context))),
  );

  Widget _projectCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> project,
  ) {
    final data = project.data();
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
            child: Row(
              children: [
                Icon(Icons.folder_rounded, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['title'] as String? ?? 'Untitled project',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if ((data['description'] as String? ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          data['description'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mutedText(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: mutedText(context)),
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
            ),
          ),
        ],
      ),
    );
  }

  DateTime _dateOf(Object? value) =>
      value is Timestamp ? value.toDate() : DateTime(0);

  Future<void> _editProfile() async {
    final profileData = (await _profile.get()).data() ?? const {};
    if (!mounted) return;
    final result = await showDialog<_ProfileDraft>(
      context: context,
      builder: (_) => _EditProfileDialog(
        initialName:
            profileData['displayName'] as String? ?? widget.displayName,
        initialBio: profileData['bio'] as String? ?? '',
        initialHeadline: profileData['headline'] as String? ?? '',
        initialLocation: profileData['location'] as String? ?? '',
        initialSkills: _stringList(profileData['skills']),
        initialInterests: _stringList(profileData['interests']),
        initialGithubUrl: profileData['githubUrl'] as String? ?? '',
        initialWebsiteUrl: profileData['websiteUrl'] as String? ?? '',
      ),
    );
    if (result == null || !mounted) return;

    try {
      final handle = profileHandleForName(result.name);
      final batch = FirebaseFirestore.instance.batch();
      batch.set(_profile, {
        'displayName': result.name,
        'bio': result.bio,
        'headline': result.headline,
        'location': result.location,
        'skills': result.skills,
        'interests': result.interests,
        'githubUrl': result.githubUrl,
        'websiteUrl': result.websiteUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_publicProfile, {
        'uid': _userId,
        'displayName': result.name,
        'handle': handle,
        'bio': result.bio,
        'headline': result.headline,
        'location': result.location,
        'skills': result.skills,
        'interests': result.interests,
        'githubUrl': result.githubUrl,
        'websiteUrl': result.websiteUrl,
        'searchPrefixes': profileSearchPrefixes(result.name, handle, [
          result.headline,
          result.location,
          ...result.skills,
          ...result.interests,
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      widget.onDisplayNameChanged(result.name);
      // The Firestore profile is the source of truth for the app. Keep the
      // Firebase Auth display name in sync when possible, but don't treat a
      // metadata update failure as a failed profile save.
      try {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(result.name);
      } catch (_) {
        // Firestore already saved the profile successfully.
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save profile (${error.code}).')),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your profile. Try again.'),
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }
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
              fontSize: 11,
              color: onTap == null
                  ? mutedText(context)
                  : Theme.of(context).colorScheme.primary,
              fontWeight: onTap == null ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileDraft {
  final String name;
  final String bio;
  final String headline;
  final String location;
  final List<String> skills;
  final List<String> interests;
  final String githubUrl;
  final String websiteUrl;

  const _ProfileDraft({
    required this.name,
    required this.bio,
    required this.headline,
    required this.location,
    required this.skills,
    required this.interests,
    required this.githubUrl,
    required this.websiteUrl,
  });
}

class _EditProfileDialog extends StatefulWidget {
  final String initialName;
  final String initialBio;
  final String initialHeadline;
  final String initialLocation;
  final List<String> initialSkills;
  final List<String> initialInterests;
  final String initialGithubUrl;
  final String initialWebsiteUrl;

  const _EditProfileDialog({
    required this.initialName,
    required this.initialBio,
    required this.initialHeadline,
    required this.initialLocation,
    required this.initialSkills,
    required this.initialInterests,
    required this.initialGithubUrl,
    required this.initialWebsiteUrl,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _headlineController;
  late final TextEditingController _locationController;
  late final TextEditingController _skillsController;
  late final TextEditingController _interestsController;
  late final TextEditingController _githubController;
  late final TextEditingController _websiteController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _bioController = TextEditingController(text: widget.initialBio);
    _headlineController = TextEditingController(text: widget.initialHeadline);
    _locationController = TextEditingController(text: widget.initialLocation);
    _skillsController = TextEditingController(
      text: widget.initialSkills.join(', '),
    );
    _interestsController = TextEditingController(
      text: widget.initialInterests.join(', '),
    );
    _githubController = TextEditingController(text: widget.initialGithubUrl);
    _websiteController = TextEditingController(text: widget.initialWebsiteUrl);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _headlineController.dispose();
    _locationController.dispose();
    _skillsController.dispose();
    _interestsController.dispose();
    _githubController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit profile'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLength: 250,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'About you',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _headlineController,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Builder headline',
              hintText: 'Flutter developer · Open-source contributor',
            ),
          ),
          TextField(
            controller: _locationController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              hintText: 'City or timezone',
            ),
          ),
          TextField(
            controller: _skillsController,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Skills',
              hintText: 'Flutter, Firebase, UI design',
            ),
          ),
          TextField(
            controller: _interestsController,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Interested in',
              hintText: 'Open source, accessibility',
            ),
          ),
          TextField(
            controller: _githubController,
            maxLength: 200,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'GitHub URL (optional)',
            ),
          ),
          TextField(
            controller: _websiteController,
            maxLength: 200,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Portfolio URL (optional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _nameController.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(
            context,
            _ProfileDraft(
              name: name,
              bio: _bioController.text.trim(),
              headline: _headlineController.text.trim(),
              location: _locationController.text.trim(),
              skills: _parseProfileTags(_skillsController.text),
              interests: _parseProfileTags(_interestsController.text),
              githubUrl: _normalizeProfileUrl(_githubController.text),
              websiteUrl: _normalizeProfileUrl(_websiteController.text),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

List<String> _stringList(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];

List<String> _parseProfileTags(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .take(8)
    .toSet()
    .toList();

String _normalizeProfileUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';
}

Widget _detailChips(BuildContext context, String label, List<String> values) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: mutedText(context), fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
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

class _ProfileDetailLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ProfileDetailLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: mutedText(context)),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: mutedText(context), fontSize: 12)),
    ],
  );
}
