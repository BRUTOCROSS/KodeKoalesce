import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'public_profile_page.dart';
import 'social_notifications.dart';
import 'builder_name_heading.dart';

class DiscoverPeoplePage extends StatefulWidget {
  const DiscoverPeoplePage({super.key});

  @override
  State<DiscoverPeoplePage> createState() => _DiscoverPeoplePageState();
}

class _DiscoverPeoplePageState extends State<DiscoverPeoplePage> {
  final TextEditingController _searchController = TextEditingController();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  late final CollectionReference<Map<String, dynamic>> _profiles;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _profileStream;
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _myProfileFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _profiles = FirebaseFirestore.instance.collection('publicProfiles');
    _myProfileFuture = _profiles.doc(_currentUserId).get();
    _profileStream = _profiles.orderBy('displayName').limit(50).snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateSearch(String value) {
    final query = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    setState(() {
      _query = query;
      _profileStream = query.isEmpty
          ? _profiles.orderBy('displayName').limit(50).snapshots()
          : _profiles
                .where('searchPrefixes', arrayContains: query)
                .limit(50)
                .snapshots();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Discover people')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _updateSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name or handle',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        _updateSearch('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            children: [
              for (final topic in const [
                'Flutter',
                'Firebase',
                'UI/UX',
                'Open source',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ActionChip(
                    label: Text(topic),
                    onPressed: () {
                      _searchController.text = topic;
                      _updateSearch(topic);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _myProfileFuture,
            builder: (context, myProfileSnapshot) =>
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _profileStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load people. Check your Firestore rules.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: mutedText(context)),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final myProfile =
                        myProfileSnapshot.data?.data() ?? const {};
                    final mySkills = _stringSet(myProfile['skills']);
                    final myInterests = _stringSet(myProfile['interests']);
                    final hasMatchingDetails =
                        mySkills.isNotEmpty || myInterests.isNotEmpty;
                    final people =
                        snapshot.data!.docs
                            .where((document) => document.id != _currentUserId)
                            .map(
                              (document) => _RankedPerson(
                                document,
                                _matchLabels(
                                  document.data(),
                                  mySkills,
                                  myInterests,
                                ),
                                _profileCompleteness(document.data()),
                              ),
                            )
                            .toList()
                          ..sort((a, b) {
                            final matchOrder = b.matches.length.compareTo(
                              a.matches.length,
                            );
                            if (matchOrder != 0) return matchOrder;
                            final completenessOrder = b.completeness.compareTo(
                              a.completeness,
                            );
                            if (completenessOrder != 0) {
                              return completenessOrder;
                            }
                            final aName =
                                a.document.data()['displayName'] as String? ??
                                '';
                            final bName =
                                b.document.data()['displayName'] as String? ??
                                '';
                            return aName.toLowerCase().compareTo(
                              bName.toLowerCase(),
                            );
                          });
                    if (people.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            _query.isEmpty
                                ? 'No other profiles yet. Try again when more people join.'
                                : 'No people found for “${_searchController.text.trim()}”.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: mutedText(context)),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        if (!hasMatchingDetails)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                            child: Material(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.lightbulb_outline_rounded,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Add skills and interests to personalize your builder matches.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: people.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 7),
                            itemBuilder: (context, index) =>
                                _DiscoverPersonTile(
                                  profile: people[index].document,
                                  currentUserId: _currentUserId,
                                  matches: people[index].matches,
                                ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ),
        ),
      ],
    ),
  );
}

class _DiscoverPersonTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> profile;
  final String currentUserId;
  final List<String> matches;

  const _DiscoverPersonTile({
    required this.profile,
    required this.currentUserId,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    final data = profile.data();
    final name = data['displayName'] as String? ?? 'Community member';
    final handle = data['handle'] as String? ?? '@developer';
    final bio = data['bio'] as String? ?? '';
    final headline = data['headline'] as String? ?? '';
    final location = data['location'] as String? ?? '';
    final skills = data['skills'] is List
        ? (data['skills'] as List).whereType<String>().take(3).toList()
        : const <String>[];
    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(profile.id);
    final initial = name.trim().isEmpty ? 'D' : name.trim()[0].toUpperCase();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(15),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: outlineColor(context)),
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFD7E8DC),
          child: Text(
            initial,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: BuilderNameHeading(
                name: name,
                fontSize: 16,
                showAccent: false,
              ),
            ),
            if (matches.isNotEmpty)
              Text(
                '${matches.length} match${matches.length == 1 ? '' : 'es'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(handle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (matches.isNotEmpty)
              Text(
                'You both: ${matches.take(3).join(', ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                ),
              ),
            if (headline.trim().isNotEmpty)
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (bio.trim().isNotEmpty)
              Text(
                bio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedText(context)),
              ),
            if (location.trim().isNotEmpty)
              Text(
                '⌖ $location',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedText(context), fontSize: 12),
              ),
            if (skills.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(
                  spacing: 5,
                  children: [
                    for (final skill in skills) _MiniSkillChip(label: skill),
                  ],
                ),
              ),
          ],
        ),
        isThreeLine:
            bio.trim().isNotEmpty ||
            headline.trim().isNotEmpty ||
            skills.isNotEmpty,
        trailing: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: followingRef.snapshots(),
          builder: (context, snapshot) {
            final isFollowing = snapshot.data?.exists ?? false;
            return IconButton(
              tooltip: isFollowing ? 'Unfollow' : 'Follow',
              onPressed: snapshot.hasError
                  ? null
                  : () =>
                        _toggleFollow(context, followingRef, isFollowing, data),
              icon: Icon(
                isFollowing
                    ? Icons.person_remove_alt_1_rounded
                    : Icons.person_add_alt_1_rounded,
                color: isFollowing
                    ? Theme.of(context).colorScheme.primary
                    : mutedText(context),
              ),
            );
          },
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => PublicProfilePage(
              userId: profile.id,
              displayName: name,
              handle: handle,
              initials: initial,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> reference,
    bool isFollowing,
    Map<String, dynamic> person,
  ) async {
    try {
      if (isFollowing) {
        await reference.delete();
      } else {
        final name = person['displayName'] as String? ?? 'Community member';
        final handle = person['handle'] as String? ?? '@developer';
        await reference.set({
          'userId': profile.id,
          'displayName': name,
          'handle': handle,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await notifyNewFollower(profile.id);
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update following (${error.code}).'),
          ),
        );
      }
    }
  }
}

class _RankedPerson {
  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final List<String> matches;
  final int completeness;
  const _RankedPerson(this.document, this.matches, this.completeness);
}

Set<String> _stringSet(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet()
    : <String>{};

List<String> _matchLabels(
  Map<String, dynamic> profile,
  Set<String> mySkills,
  Set<String> myInterests,
) {
  final theirSkills = _stringSet(profile['skills']);
  final theirInterests = _stringSet(profile['interests']);
  return {
    ...mySkills.intersection(theirSkills),
    ...myInterests.intersection(theirInterests),
  }.toList()..sort();
}

int _profileCompleteness(Map<String, dynamic> profile) {
  var score = 0;
  for (final field in [
    'headline',
    'location',
    'bio',
    'githubUrl',
    'websiteUrl',
  ]) {
    if ((profile[field] as String? ?? '').trim().isNotEmpty) score++;
  }
  score += (profile['skills'] is List ? (profile['skills'] as List).length : 0);
  score += (profile['interests'] is List
      ? (profile['interests'] as List).length
      : 0);
  return score;
}

class _MiniSkillChip extends StatelessWidget {
  final String label;
  const _MiniSkillChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );
}
