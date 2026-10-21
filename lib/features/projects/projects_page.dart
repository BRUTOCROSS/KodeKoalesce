import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/section_page.dart';
import 'project_file_proposals_page.dart';

enum _ProjectView { explore, mine, saved }

enum _SuggestionScope { project, file, folder }

class _ProjectSuggestionDraft {
  final _SuggestionScope scope;
  final String targetPath;
  final String message;

  const _ProjectSuggestionDraft({
    required this.scope,
    required this.targetPath,
    required this.message,
  });
}

class _ProjectData {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final List<String> tags;
  final String status;

  const _ProjectData({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.tags,
    required this.status,
  });

  factory _ProjectData.fromMap(String id, Map<String, dynamic> data) =>
      _ProjectData(
        id: id,
        ownerId: data['ownerId'] as String? ?? '',
        title: data['title'] as String? ?? 'Untitled project',
        description: data['description'] as String? ?? '',
        tags: (data['tags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        status: data['status'] as String? ?? 'Open to collaborators',
      );

  Map<String, dynamic> toMap() => {
    'ownerId': ownerId,
    'title': title,
    'description': description,
    'tags': tags,
    'status': status,
  };
}

List<String> _stringValues(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];

Future<void> openProjectWorkspace(
  BuildContext context,
  String projectId,
) async {
  try {
    final projectDocument = await FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .get();
    if (!context.mounted) return;
    final data = projectDocument.data();
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This project is no longer available.')),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProjectWorkspacePage(
          project: _ProjectData.fromMap(projectDocument.id, data),
        ),
      ),
    );
  } on FirebaseException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open project (${error.code}).')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this project. Try again.')),
    );
  }
}

Future<void> openProjectActivity(
  BuildContext context, {
  required String projectId,
  required String activityId,
  required bool isSuggestion,
}) async {
  try {
    final projectDocument = await FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .get();
    if (!context.mounted) return;
    final data = projectDocument.data();
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This project is no longer available.')),
      );
      return;
    }

    final project = _ProjectData.fromMap(projectDocument.id, data);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || project.ownerId != userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the project owner can review this.'),
        ),
      );
      return;
    }

    if (isSuggestion) {
      final suggestions = FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId)
          .collection('suggestions');
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _ProjectSuggestionsPage(
            project: project,
            suggestions: suggestions,
            suggestionStream: suggestions.snapshots(),
            canReview: true,
            userId: userId,
            focusDocumentId: activityId,
          ),
        ),
      );
    } else {
      final requests = FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId)
          .collection('contributionRequests');
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _ContributionRequestsPage(
            project: project,
            requests: requests,
            requestStream: requests.snapshots(),
            ownerId: userId,
            focusDocumentId: activityId,
          ),
        ),
      );
    }
  } on FirebaseException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open review (${error.code}).')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this review. Try again.')),
    );
  }
}

class ProjectsPage extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final bool chromeVisible;
  const ProjectsPage({
    super.key,
    required this.onOpenDrawer,
    required this.chromeVisible,
  });

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  _ProjectView _view = _ProjectView.explore;
  final TextEditingController _projectSearchController =
      TextEditingController();
  final FocusNode _projectSearchFocus = FocusNode();
  String _projectQuery = '';
  String _selectedProjectTag = '';
  bool _projectSearchExpanded = false;
  bool _showOnlyMatches = false;
  List<String> _builderTopics = const [];
  late final String _userId;
  late final CollectionReference<Map<String, dynamic>> _projects;
  late final CollectionReference<Map<String, dynamic>> _savedProjects;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _exploreStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _mineStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _savedStream;
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  _savedSubscription;
  final Set<String> _savedProjectIds = {};
  List<_ProjectData> _savedProjectData = const [];
  bool _savedProjectsLoaded = false;
  bool _savedProjectsFailed = false;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;
    _loadBuilderTopics();
    _projects = firestore.collection('projects');
    _savedProjects = firestore
        .collection('users')
        .doc(_userId)
        .collection('savedProjects');
    _exploreStream = _projects
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
    _mineStream = _projects
        .where('ownerId', isEqualTo: _userId)
        .limit(50)
        .snapshots();
    _savedStream = _savedProjects
        .orderBy('savedAt', descending: true)
        .limit(50)
        .snapshots();
    _savedSubscription = _savedStream.listen(
      (snapshot) {
        if (!mounted) return;
        final latestIds = snapshot.docs.map((doc) => doc.id).toSet();
        setState(() {
          _savedProjectIds
            ..clear()
            ..addAll(latestIds);
          _savedProjectData = snapshot.docs
              .map((doc) => _ProjectData.fromMap(doc.id, doc.data()))
              .toList();
          _savedProjectsLoaded = true;
          _savedProjectsFailed = false;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _savedProjectsLoaded = true;
          _savedProjectsFailed = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _savedSubscription.cancel();
    _projectSearchController.dispose();
    _projectSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadBuilderTopics() async {
    try {
      final profile = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(_userId)
          .get();
      final data = profile.data() ?? const <String, dynamic>{};
      final topics = [
        ..._stringValues(data['skills']),
        ..._stringValues(data['interests']),
      ];
      if (!mounted) return;
      setState(() => _builderTopics = topics.toSet().toList());
    } catch (_) {
      // Project exploration still works when profile matching is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionPage(
      onOpenDrawer: widget.onOpenDrawer,
      chromeVisible: widget.chromeVisible,
      eyebrow: 'BUILD TOGETHER',
      title: 'Projects',
      subtitle:
          'Explore ideas, build your own, and find a place to contribute.',
      action: 'Create project',
      icon: Icons.add_rounded,
      onAction: _createProject,
      onSearch: _expandProjectSearch,
      onSearchClose: _collapseProjectSearch,
      onSearchChanged: (value) =>
          setState(() => _projectQuery = value.trim().toLowerCase()),
      searchController: _projectSearchController,
      searchFocusNode: _projectSearchFocus,
      searchExpanded: _projectSearchExpanded && _view == _ProjectView.explore,
      searchHint: 'Search projects, tech, or ideas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_ProjectView>(
            segments: const [
              ButtonSegment(
                value: _ProjectView.explore,
                label: Text('Explore', maxLines: 1, softWrap: false),
              ),
              ButtonSegment(
                value: _ProjectView.mine,
                label: Text('My Projects', maxLines: 1, softWrap: false),
              ),
              ButtonSegment(
                value: _ProjectView.saved,
                label: Text('Saved', maxLines: 1, softWrap: false),
              ),
            ],
            selected: {_view},
            showSelectedIcon: false,
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              ),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            onSelectionChanged: (selection) {
              final nextView = selection.first;
              if (nextView != _ProjectView.explore) {
                _projectSearchFocus.unfocus();
              }
              setState(() {
                _view = nextView;
                if (nextView != _ProjectView.explore) {
                  _projectSearchExpanded = false;
                }
              });
            },
          ),
          if (_view == _ProjectView.explore) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_projectQuery.isNotEmpty)
                    if (!_projectSearchExpanded)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: InputChip(
                          avatar: const Icon(Icons.search_rounded, size: 16),
                          label: Text(_projectQuery),
                          onDeleted: _clearProjectSearchQuery,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: FilterChip(
                      avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('For you'),
                      selected: _showOnlyMatches,
                      onSelected: (selected) =>
                          setState(() => _showOnlyMatches = selected),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  for (final tag in _projectFilterTags())
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(tag.isEmpty ? 'All' : tag),
                        selected:
                            _selectedProjectTag.toLowerCase() ==
                            tag.toLowerCase(),
                        onSelected: (_) =>
                            setState(() => _selectedProjectTag = tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_view),
              child: _buildProjectContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectContent(BuildContext context) {
    if (_view == _ProjectView.saved) {
      if (!_savedProjectsLoaded) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_savedProjectsFailed) {
        return _projectMessage(
          context,
          icon: Icons.cloud_off_rounded,
          title: 'Could not load saved projects',
          message: 'Check your connection and try again.',
        );
      }
      if (_savedProjectData.isEmpty) return _emptyProjectsMessage(context);
      return _buildProjectTiles(_savedProjectData);
    }

    final stream = _view == _ProjectView.explore ? _exploreStream : _mineStream;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _projectMessage(
            context,
            icon: Icons.cloud_off_rounded,
            title: 'Could not load projects',
            message: 'Check your connection and make sure the updated Firestore rules are published.',
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
        if (docs.isEmpty) return _emptyProjectsMessage(context);
        var projects = docs
            .map((doc) => _ProjectData.fromMap(doc.id, doc.data()))
            .toList();
        if (_view == _ProjectView.explore) {
          final recencyOrder = {
            for (var index = 0; index < projects.length; index++)
              projects[index].id: index,
          };
          projects = projects.where(_matchesProjectFilters).toList();
          projects.sort((a, b) {
            final matchOrder = _matchedProjectTags(b).length
                .compareTo(_matchedProjectTags(a).length);
            if (matchOrder != 0) return matchOrder;
            return recencyOrder[a.id]!.compareTo(recencyOrder[b.id]!);
          });
          if (projects.isEmpty) {
            return _projectMessage(
              context,
              icon: Icons.filter_alt_off_rounded,
              title: 'No projects match those filters',
              message:
                  'Try another search or clear the selected project filters.',
              action: TextButton(
                onPressed: () {
                  setState(() {
                    _projectQuery = '';
                    _selectedProjectTag = '';
                    _showOnlyMatches = false;
                  });
                },
                child: const Text('Clear filters'),
              ),
            );
          }
          final matchCount = projects
              .where((project) => _matchedProjectTags(project).isNotEmpty)
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_builderTopics.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Add skills and interests to your profile for personalized project matches.',
                    style: TextStyle(color: mutedText(context), fontSize: 12),
                  ),
                )
              else if (matchCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$matchCount project${matchCount == 1 ? '' : 's'} match your profile',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              _buildProjectTiles(projects, showSkillMatches: true),
            ],
          );
        }
        return _buildProjectTiles(projects);
      },
    );
  }

  void _expandProjectSearch() {
    setState(() {
      _view = _ProjectView.explore;
      _projectSearchExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _projectSearchFocus.requestFocus();
    });
  }

  void _collapseProjectSearch() {
    _projectSearchFocus.unfocus();
    setState(() => _projectSearchExpanded = false);
  }

  void _clearProjectSearchQuery() {
    _projectSearchController.clear();
    setState(() => _projectQuery = '');
  }

  List<String> _projectFilterTags() {
    final tags = <String, String>{};
    for (final tag in [
      ..._builderTopics,
      'Flutter',
      'Firebase',
      'Web',
      'Open source',
    ]) {
      tags.putIfAbsent(tag.toLowerCase(), () => tag);
    }
    return ['', ...tags.values.take(8)];
  }

  bool _matchesProjectFilters(_ProjectData project) {
    final normalizedQuery = _projectQuery;
    final haystack =
        '${project.title} ${project.description} ${project.tags.join(' ')}'
            .toLowerCase();
    if (normalizedQuery.isNotEmpty && !haystack.contains(normalizedQuery)) {
      return false;
    }
    if (_selectedProjectTag.isNotEmpty &&
        !project.tags.any(
          (tag) => tag.toLowerCase() == _selectedProjectTag.toLowerCase(),
        )) {
      return false;
    }
    if (_showOnlyMatches && _matchedProjectTags(project).isEmpty) {
      return false;
    }
    return true;
  }

  List<String> _matchedProjectTags(_ProjectData project) {
    final topics = _builderTopics.map((item) => item.toLowerCase()).toSet();
    return project.tags
        .where((tag) => topics.contains(tag.toLowerCase()))
        .toList();
  }

  DateTime _createdAt(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final value = doc.data()['createdAt'];
    return value is Timestamp ? value.toDate() : DateTime(0);
  }

  Widget _buildProjectTiles(
    List<_ProjectData> projects, {
    bool showSkillMatches = false,
  }) => Column(
    children: projects.map((project) {
      final isSaved = _savedProjectIds.contains(project.id);
      return _ProjectTile(
        project: project,
        matchedTags: showSkillMatches ? _matchedProjectTags(project) : const [],
        isSaved: isSaved,
        onToggleSaved: () => _toggleSaved(project),
        onOpen: () => _openWorkspace(project),
      );
    }).toList(),
  );

  void _openWorkspace(_ProjectData project) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProjectWorkspacePage(project: project),
      ),
    );
  }

  Widget _emptyProjectsMessage(BuildContext context) {
    final isMine = _view == _ProjectView.mine;
    final isSaved = _view == _ProjectView.saved;
    return _projectMessage(
      context,
      icon: isMine
          ? Icons.rocket_launch_outlined
          : Icons.bookmark_border_rounded,
      title: isMine
          ? 'Your projects start here'
          : isSaved
          ? 'No saved projects yet'
          : 'No projects yet',
      message: isMine
          ? 'Create a project to share your idea and invite people to help.'
          : isSaved
          ? 'Bookmark projects from Explore to keep them here.'
          : 'Be the first to share a project idea with the community.',
      action: isMine
          ? FilledButton.icon(
              onPressed: _createProject,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create project'),
            )
          : null,
    );
  }

  Widget _projectMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
    child: Column(
      children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedText(context), height: 1.4),
        ),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    ),
  );

  Future<void> _toggleSaved(_ProjectData project) async {
    final savedRef = _savedProjects.doc(project.id);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final saved = await transaction.get(savedRef);
        if (saved.exists) {
          transaction.delete(savedRef);
        } else {
          transaction.set(savedRef, {
            ...project.toMap(),
            'savedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update saved projects (${error.code}).'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update saved projects.')),
      );
    }
  }

  Future<void> _createProject() async {
    final details = await showDialog<_NewProjectDetails>(
      context: context,
      builder: (_) => const _CreateProjectDialog(),
    );
    if (!mounted || details == null) return;

    try {
      final projectRef = _projects.doc();
      final readmeRef = projectRef.collection('files').doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(projectRef, {
        'ownerId': _userId,
        ...details.toMap(),
        'status': 'Open to collaborators',
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(readmeRef, {
        'path': 'README.md',
        'content': '# ${details.title}\n\n${details.description}\n',
        'createdBy': _userId,
        'updatedBy': _userId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      setState(() => _view = _ProjectView.mine);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create project. Check that the Firestore rules are published.',
          ),
        ),
      );
    }
  }
}

class _NewProjectDetails {
  final String title;
  final String description;
  final List<String> tags;

  const _NewProjectDetails({
    required this.title,
    required this.description,
    required this.tags,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'tags': tags,
  };
}

class _CreateProjectDialog extends StatefulWidget {
  final _ProjectData? initialProject;

  const _CreateProjectDialog({this.initialProject});

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final project = widget.initialProject;
    if (project != null) {
      _titleController.text = project.title;
      _descriptionController.text = project.description;
      _tagsController.text = project.tags.join(', ');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(8)
        .toList();
    Navigator.of(context).pop(
      _NewProjectDetails(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        tags: tags,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialProject == null
          ? 'Create a project'
          : 'Edit project details',
    ),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Project name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a project name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What are you building?',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a short description'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                hintText: 'Flutter, Open source',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.initialProject == null ? 'Create' : 'Save'),
      ),
    ],
  );
}

class _ProjectFile {
  final String id;
  final String path;
  final String content;

  const _ProjectFile({
    required this.id,
    required this.path,
    required this.content,
  });

  factory _ProjectFile.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => _ProjectFile(
    id: document.id,
    path: document.data()['path'] as String? ?? 'untitled.txt',
    content: document.data()['content'] as String? ?? '',
  );

  String get name => path.split('/').last;
}

class _FileTreeNode {
  final String name;
  final Map<String, _FileTreeNode> children = {};
  _ProjectFile? file;

  _FileTreeNode(this.name);
}

class _RenamePathDialog extends StatefulWidget {
  final String title;
  final String initialPath;
  final String fieldLabel;
  final String hintText;
  final String helperText;

  const _RenamePathDialog({
    required this.title,
    required this.initialPath,
    required this.fieldLabel,
    required this.hintText,
    required this.helperText,
  });

  @override
  State<_RenamePathDialog> createState() => _RenamePathDialogState();
}

class _RenamePathDialogState extends State<_RenamePathDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPath);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      autocorrect: false,
      textCapitalization: TextCapitalization.none,
      decoration: InputDecoration(
        labelText: widget.fieldLabel,
        hintText: widget.hintText,
        helperText: widget.helperText,
        border: const OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Rename'),
      ),
    ],
  );
}

class _ProjectWorkspacePage extends StatefulWidget {
  final _ProjectData project;

  const _ProjectWorkspacePage({required this.project});

  @override
  State<_ProjectWorkspacePage> createState() => _ProjectWorkspacePageState();
}

class _ProjectWorkspacePageState extends State<_ProjectWorkspacePage> {
  late _ProjectData _project;
  late final String _userId;
  late final bool _isOwner;
  late final CollectionReference<Map<String, dynamic>> _files;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _fileStream;
  late final CollectionReference<Map<String, dynamic>> _contributionRequests;
  late final DocumentReference<Map<String, dynamic>> _myContributionRequest;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
  _myContributionRequestStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _contributionRequestsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _pendingFileProposals;
  late final TextEditingController _fileSearchController;
  final Set<String> _collapsedFolders = {};
  bool _isFileSearchOpen = false;
  String _fileSearch = '';

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _fileSearchController = TextEditingController();
    _userId = FirebaseAuth.instance.currentUser!.uid;
    _isOwner = _project.ownerId == _userId;
    _files = FirebaseFirestore.instance
        .collection('projects')
        .doc(_project.id)
        .collection('files');
    _fileStream = _files.orderBy('path').snapshots();
    _contributionRequests = FirebaseFirestore.instance
        .collection('projects')
        .doc(_project.id)
        .collection('contributionRequests');
    _myContributionRequest = _contributionRequests.doc(_userId);
    _myContributionRequestStream = _myContributionRequest.snapshots();
    _contributionRequestsStream = _contributionRequests
        .orderBy('requestedAt', descending: true)
        .snapshots();
    _pendingFileProposals = FirebaseFirestore.instance
        .collection('projects')
        .doc(_project.id)
        .collection('fileChangeProposals')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  @override
  void dispose() {
    _fileSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOwner) {
      return _buildWorkspaceScaffold(
        canEditFiles: true,
        canProposeFiles: false,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _myContributionRequestStream,
      builder: (context, requestSnapshot) {
        final requestStatus =
            requestSnapshot.data?.data()?['status'] as String?;
        return _buildWorkspaceScaffold(
          canEditFiles: false,
          canProposeFiles: requestStatus == 'accepted',
          requestStatus: requestStatus,
          requestLoading: !requestSnapshot.hasData && !requestSnapshot.hasError,
        );
      },
    );
  }

  Widget _buildWorkspaceScaffold({
    required bool canEditFiles,
    required bool canProposeFiles,
    String? requestStatus,
    bool requestLoading = false,
  }) => PopScope<Object?>(
    canPop: !_isFileSearchOpen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _isFileSearchOpen) _closeFileSearch();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(_project.title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _fileStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not load project files. Check your connection and Firestore rules.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data!.docs
              .map(_ProjectFile.fromDocument)
              .toList();
          final searchQuery = _fileSearch.trim().toLowerCase();
          final visibleFiles = searchQuery.isEmpty
              ? files
              : files
                    .where(
                      (file) => file.path.toLowerCase().contains(searchQuery),
                    )
                    .toList();
          final tree = _makeTree(visibleFiles);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: outlineColor(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _project.title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (_isOwner)
                          IconButton(
                            tooltip: 'Edit project details',
                            onPressed: _editProjectDetails,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _project.description,
                      style: TextStyle(color: mutedText(context), height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    if (_isOwner)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _openContributionRequests,
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text('Contribution requests'),
                          ),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _pendingFileProposals,
                            builder: (context, proposalSnapshot) {
                              final count =
                                  proposalSnapshot.data?.docs.length ?? 0;
                              return OutlinedButton.icon(
                                onPressed: () => openProjectFileProposals(
                                  context,
                                  projectId: _project.id,
                                  projectTitle: _project.title,
                                  ownerId: _project.ownerId,
                                ),
                                icon: const Icon(Icons.rate_review_outlined),
                                label: Text(
                                  count == 0
                                      ? 'Code change requests'
                                      : 'Code change requests ($count)',
                                ),
                              );
                            },
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openSuggestions(canReview: true),
                            icon: const Icon(Icons.lightbulb_outline_rounded),
                            label: const Text('Suggestions'),
                          ),
                        ],
                      )
                    else ...[
                      _contributionStatus(
                        requestStatus: requestStatus,
                        loading: requestLoading,
                        canProposeFiles: canProposeFiles,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _submitSuggestion(files),
                            icon: const Icon(Icons.lightbulb_outline_rounded),
                            label: const Text('Suggest an improvement'),
                          ),
                          TextButton.icon(
                            onPressed: () => _openSuggestions(canReview: false),
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('My suggestions'),
                          ),
                          if (canProposeFiles)
                            TextButton.icon(
                              onPressed: () => openMyProjectFileProposals(
                                context,
                                projectId: _project.id,
                                projectTitle: _project.title,
                                ownerId: _project.ownerId,
                              ),
                              icon: const Icon(Icons.history_rounded),
                              label: const Text('My code changes'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Project files',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${visibleFiles.length} ${visibleFiles.length == 1 ? 'file' : 'files'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (files.isNotEmpty)
                    IconButton(
                      tooltip: _isFileSearchOpen
                          ? 'Close file search'
                          : 'Search files',
                      onPressed: _isFileSearchOpen
                          ? _closeFileSearch
                          : () => setState(() => _isFileSearchOpen = true),
                      icon: Icon(
                        _isFileSearchOpen
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                      ),
                    ),
                  if (canEditFiles || canProposeFiles)
                    TextButton.icon(
                      onPressed: () => _addFile(asProposal: canProposeFiles),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        canProposeFiles ? 'Propose file' : 'Add file',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (files.isNotEmpty && _isFileSearchOpen) ...[
                TextField(
                  controller: _fileSearchController,
                  autofocus: true,
                  onChanged: (value) => setState(() => _fileSearch = value),
                  decoration: InputDecoration(
                    hintText: 'Search files and folders',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _fileSearch.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _fileSearchController.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No text files yet.',
                    style: TextStyle(color: mutedText(context)),
                  ),
                )
              else if (visibleFiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No files or folders match “${_fileSearch.trim()}”.',
                    style: TextStyle(color: mutedText(context)),
                  ),
                )
              else
                ..._treeRows(
                  tree,
                  depth: 0,
                  parentPath: '',
                  canEditFiles: canEditFiles,
                  canProposeFiles: canProposeFiles,
                  expandAll: searchQuery.isNotEmpty,
                ),
            ],
          );
        },
      ),
      floatingActionButton: canEditFiles || canProposeFiles
          ? FloatingActionButton.extended(
              onPressed: () => _addFile(asProposal: canProposeFiles),
              icon: const Icon(Icons.note_add_outlined),
              label: Text(
                canProposeFiles ? 'Propose a new file' : 'Add text file',
              ),
            )
          : null,
    ),
  );

  void _closeFileSearch() {
    _fileSearchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _fileSearch = '';
      _isFileSearchOpen = false;
    });
  }

  Widget _contributionStatus({
    required String? requestStatus,
    required bool loading,
    required bool canProposeFiles,
  }) {
    if (loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (canProposeFiles) {
      return const _ContributionStatusMessage(
        icon: Icons.check_circle_outline_rounded,
        message: 'You can propose file changes for the owner to review.',
      );
    }
    if (requestStatus == 'pending') {
      return Row(
        children: [
          const Expanded(
            child: _ContributionStatusMessage(
              icon: Icons.hourglass_top_rounded,
              message: 'Your request is waiting for the owner.',
            ),
          ),
          TextButton(
            onPressed: _cancelContributionRequest,
            child: const Text('Cancel'),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: () =>
            _requestToContribute(isRetry: requestStatus == 'declined'),
        icon: const Icon(Icons.group_add_outlined),
        label: Text(
          requestStatus == 'declined'
              ? 'Request again'
              : 'Request to contribute',
        ),
      ),
    );
  }

  Future<void> _requestToContribute({bool isRetry = false}) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _RequestContributionDialog(projectTitle: _project.title),
    );
    if (!mounted || message == null) return;
    final user = FirebaseAuth.instance.currentUser!;
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'Community member';
    try {
      await _myContributionRequest.set({
        'requesterId': _userId,
        'requesterName': name.length > 80 ? name.substring(0, 80) : name,
        'message': message,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'projectId': _project.id,
        'projectTitle': _project.title,
        'projectOwnerId': _project.ownerId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRetry
                ? 'Your new request has been sent.'
                : 'Request sent to the project owner.',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      _showWorkspaceMessage('Could not send request (${error.code}).');
    } catch (_) {
      _showWorkspaceMessage('Could not send your request. Try again.');
    }
  }

  Future<void> _cancelContributionRequest() async {
    try {
      await _myContributionRequest.delete();
    } on FirebaseException catch (error) {
      _showWorkspaceMessage('Could not cancel request (${error.code}).');
    } catch (_) {
      _showWorkspaceMessage('Could not cancel your request. Try again.');
    }
  }

  void _openContributionRequests() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ContributionRequestsPage(
          project: _project,
          requests: _contributionRequests,
          requestStream: _contributionRequestsStream,
          ownerId: _userId,
        ),
      ),
    );
  }

  void _openSuggestions({required bool canReview}) {
    final suggestions = FirebaseFirestore.instance
        .collection('projects')
        .doc(_project.id)
        .collection('suggestions');
    final stream = canReview
        ? suggestions.snapshots()
        : suggestions.where('authorId', isEqualTo: _userId).snapshots();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProjectSuggestionsPage(
          project: _project,
          suggestions: suggestions,
          suggestionStream: stream,
          canReview: canReview,
          userId: _userId,
        ),
      ),
    );
  }

  Future<void> _submitSuggestion(List<_ProjectFile> files) async {
    final folderPaths = <String>{};
    for (final file in files) {
      final parts = file.path.split('/');
      if (parts.length < 2) continue;
      parts.removeLast();
      var path = '';
      for (final part in parts) {
        path = path.isEmpty ? part : '$path/$part';
        folderPaths.add(path);
      }
    }
    final draft = await showDialog<_ProjectSuggestionDraft>(
      context: context,
      builder: (_) => _ProjectSuggestionDialog(
        projectTitle: _project.title,
        filePaths: files.map((file) => file.path).toList()..sort(),
        folderPaths: folderPaths.toList()..sort(),
      ),
    );
    if (!mounted || draft == null) return;
    final user = FirebaseAuth.instance.currentUser!;
    final displayName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'Community member';
    final suggestions = FirebaseFirestore.instance
        .collection('projects')
        .doc(_project.id)
        .collection('suggestions');
    try {
      await suggestions.add({
        'authorId': _userId,
        'authorName': displayName.length > 80
            ? displayName.substring(0, 80)
            : displayName,
        'scope': draft.scope.name,
        'targetPath': draft.targetPath,
        'message': draft.message,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'projectId': _project.id,
        'projectTitle': _project.title,
        'projectOwnerId': _project.ownerId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your suggestion was sent to the owner.')),
      );
    } on FirebaseException catch (error) {
      _showWorkspaceMessage('Could not send suggestion (${error.code}).');
    } catch (_) {
      _showWorkspaceMessage('Could not send suggestion. Try again.');
    }
  }

  void _showWorkspaceMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  _FileTreeNode _makeTree(List<_ProjectFile> files) {
    final root = _FileTreeNode('');
    for (final file in files) {
      var node = root;
      final parts = file.path.split('/');
      for (final part in parts) {
        node = node.children.putIfAbsent(part, () => _FileTreeNode(part));
      }
      node.file = file;
    }
    return root;
  }

  List<Widget> _treeRows(
    _FileTreeNode parent, {
    required int depth,
    required String parentPath,
    required bool canEditFiles,
    required bool canProposeFiles,
    bool expandAll = false,
  }) {
    final children = parent.children.values.toList()
      ..sort((a, b) {
        final aIsFolder = a.children.isNotEmpty;
        final bIsFolder = b.children.isNotEmpty;
        if (aIsFolder != bIsFolder) return aIsFolder ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final rows = <Widget>[];
    for (final node in children) {
      final path = parentPath.isEmpty ? node.name : '$parentPath/${node.name}';
      final isFolder = node.children.isNotEmpty;
      if (isFolder) {
        final isCollapsed = !expandAll && _collapsedFolders.contains(path);
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 17.0),
            child: ListTile(
              dense: true,
              leading: Icon(
                isCollapsed ? Icons.folder_outlined : Icons.folder_open_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(node.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEditFiles)
                    PopupMenuButton<String>(
                      tooltip: 'Folder actions',
                      onSelected: (action) {
                        _runAfterMenuCloses(() {
                          if (action == 'new_file') {
                            _addFile(initialPath: '$path/new_file.dart');
                          } else if (action == 'rename') {
                            _renameFolder(path);
                          } else if (action == 'delete') {
                            _deleteFolder(path);
                          }
                        });
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'new_file',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.note_add_outlined),
                            title: Text('New file here'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.drive_file_rename_outline),
                            title: Text('Rename folder'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete folder'),
                          ),
                        ),
                      ],
                    ),
                  Icon(
                    isCollapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more,
                  ),
                ],
              ),
              onTap: () => setState(() {
                if (isCollapsed) {
                  _collapsedFolders.remove(path);
                } else {
                  _collapsedFolders.add(path);
                }
              }),
            ),
          ),
        );
        if (!isCollapsed) {
          rows.addAll(
            _treeRows(
              node,
              depth: depth + 1,
              parentPath: path,
              canEditFiles: canEditFiles,
              canProposeFiles: canProposeFiles,
              expandAll: expandAll,
            ),
          );
        }
      }
      final file = node.file;
      if (file != null) {
        rows.add(
          _fileRow(
            file,
            depth + (isFolder ? 1 : 0),
            canEditFiles,
            canProposeFiles,
          ),
        );
      }
    }
    return rows;
  }

  Widget _fileRow(
    _ProjectFile file,
    int depth,
    bool canEditFiles,
    bool canProposeFiles,
  ) => Padding(
    padding: EdgeInsets.only(left: depth * 17.0),
    child: ListTile(
      dense: true,
      leading: Icon(_fileIcon(file.name), color: mutedText(context)),
      title: Text(file.name),
      subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _openFile(
        file,
        canEditFiles: canEditFiles,
        canProposeFiles: canProposeFiles,
      ),
      trailing: canEditFiles
          ? PopupMenuButton<String>(
              tooltip: 'File actions',
              onSelected: (action) {
                _runAfterMenuCloses(() {
                  if (action == 'rename') {
                    _renameFile(file);
                  } else if (action == 'delete') {
                    _deleteFile(file);
                  }
                });
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.drive_file_rename_outline),
                    title: Text('Rename'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete'),
                  ),
                ),
              ],
            )
          : null,
    ),
  );

  // PopupMenuButton reports its selection as its route begins closing. Let
  // that route and its inherited widgets finish disposing before opening a
  // dialog or another overlay from the selected action.
  void _runAfterMenuCloses(VoidCallback action) {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) action();
    });
  }

  Future<void> _renameFile(_ProjectFile file) async {
    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePathDialog(
        title: 'Rename file',
        initialPath: file.path,
        fieldLabel: 'File path and name',
        hintText: 'lib/main.dart',
        helperText: 'Keep the folder path if you only want to rename it.',
      ),
    );
    if (!mounted || newPath == null) return;

    final path = newPath.trim();
    final parts = path.split('/');
    if (path.isEmpty ||
        path.length > 255 ||
        path.startsWith('/') ||
        path.contains('\\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      _showFileMessage('Enter a relative path like lib/main.dart.');
      return;
    }
    if (path == file.path) return;

    try {
      final existing = await _files
          .where('path', isEqualTo: path)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        _showFileMessage('A file with this path already exists.');
        return;
      }
      final oldRef = _files.doc(file.id);
      final oldSnapshot = await oldRef.get();
      final oldData = oldSnapshot.data();
      if (oldData == null) {
        _showFileMessage('This file no longer exists. Refresh the project.');
        return;
      }
      await oldRef.update({
        'path': path,
        'updatedBy': _userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      _showFileMessage('Could not rename this file (${error.code}).');
    } catch (_) {
      _showFileMessage('Could not rename this file. Try again.');
    }
  }

  Future<void> _deleteFile(_ProjectFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('“${file.path}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _files.doc(file.id).delete();
    } on FirebaseException catch (error) {
      _showFileMessage('Could not delete this file (${error.code}).');
    } catch (_) {
      _showFileMessage('Could not delete this file. Try again.');
    }
  }

  Future<void> _renameFolder(String folderPath) async {
    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePathDialog(
        title: 'Rename folder',
        initialPath: folderPath,
        fieldLabel: 'Folder path',
        hintText: 'lib',
        helperText: 'All files inside this folder will move with it.',
      ),
    );
    if (!mounted || newPath == null) return;

    final target = newPath.trim();
    final parts = target.split('/');
    if (target.isEmpty ||
        target.length > 255 ||
        target.startsWith('/') ||
        target.contains('\\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      _showFileMessage('Enter a valid relative folder path.');
      return;
    }
    if (target == folderPath) return;
    if (target.startsWith('$folderPath/') ||
        folderPath.startsWith('$target/')) {
      _showFileMessage('A folder cannot be moved inside itself or a parent.');
      return;
    }

    try {
      final allFiles = await _files.get();
      final movingFiles = allFiles.docs
          .where(
            (doc) => (doc.data()['path'] as String? ?? '').startsWith(
              '$folderPath/',
            ),
          )
          .toList();
      if (movingFiles.isEmpty) {
        _showFileMessage('This folder is empty.');
        return;
      }
      final movingIds = movingFiles.map((doc) => doc.id).toSet();
      final destinationPaths = movingFiles.map((doc) {
        final oldFilePath = doc.data()['path'] as String;
        return '$target${oldFilePath.substring(folderPath.length)}';
      }).toSet();
      final conflict = allFiles.docs.any((doc) {
        if (movingIds.contains(doc.id)) return false;
        final existingPath = doc.data()['path'] as String? ?? '';
        return existingPath == target ||
            existingPath.startsWith('$target/') ||
            destinationPaths.contains(existingPath) ||
            destinationPaths.any((path) => path.startsWith('$existingPath/'));
      });
      if (conflict) {
        _showFileMessage(
          'The new folder path conflicts with an existing file or folder.',
        );
        return;
      }

      for (var start = 0; start < movingFiles.length; start += 450) {
        final batch = FirebaseFirestore.instance.batch();
        final end = (start + 450).clamp(0, movingFiles.length);
        for (final doc in movingFiles.sublist(start, end)) {
          final oldFilePath = doc.data()['path'] as String;
          batch.update(doc.reference, {
            'path': '$target${oldFilePath.substring(folderPath.length)}',
            'updatedBy': _userId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      if (mounted) {
        setState(() {
          _collapsedFolders.remove(folderPath);
          _collapsedFolders.removeWhere(
            (path) => path.startsWith('$folderPath/'),
          );
        });
      }
    } on FirebaseException catch (error) {
      _showFileMessage('Could not rename this folder (${error.code}).');
    } catch (_) {
      _showFileMessage('Could not rename this folder. Try again.');
    }
  }

  Future<void> _deleteFolder(String folderPath) async {
    try {
      final files = await _files.get();
      final insideFolder = files.docs
          .where(
            (doc) => (doc.data()['path'] as String? ?? '').startsWith(
              '$folderPath/',
            ),
          )
          .toList();
      if (insideFolder.isEmpty) {
        _showFileMessage('This folder is empty.');
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete folder?'),
          content: Text(
            '“$folderPath” and all ${insideFolder.length} '
            '${insideFolder.length == 1 ? 'file' : 'files'} inside it will be permanently removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete folder'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      for (var start = 0; start < insideFolder.length; start += 450) {
        final batch = FirebaseFirestore.instance.batch();
        final end = (start + 450).clamp(0, insideFolder.length);
        for (final doc in insideFolder.sublist(start, end)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      if (mounted) {
        setState(() {
          _collapsedFolders.remove(folderPath);
          _collapsedFolders.removeWhere(
            (path) => path.startsWith('$folderPath/'),
          );
        });
      }
    } on FirebaseException catch (error) {
      _showFileMessage('Could not delete this folder (${error.code}).');
    } catch (_) {
      _showFileMessage('Could not delete this folder. Try again.');
    }
  }

  void _showFileMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _fileIcon(String name) {
    if (name.toLowerCase() == 'readme.md') return Icons.menu_book_outlined;
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'java' ||
      'kt' ||
      'swift' ||
      'c' ||
      'cpp' ||
      'h' ||
      'go' ||
      'rs' => Icons.code_rounded,
      'md' || 'txt' => Icons.description_outlined,
      'json' || 'yaml' || 'yml' || 'xml' => Icons.data_object_rounded,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  Future<void> _addFile({
    String initialPath = 'lib/main.dart',
    bool asProposal = false,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _CreateProjectFilePage(
          projectId: _project.id,
          userId: _userId,
          files: _files,
          initialPath: initialPath,
          asProposal: asProposal,
        ),
      ),
    );
  }

  void _openFile(
    _ProjectFile file, {
    required bool canEditFiles,
    required bool canProposeFiles,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProjectTextFilePage(
          projectId: _project.id,
          file: file,
          canEdit: canEditFiles,
          canPropose: canProposeFiles,
          userId: _userId,
        ),
      ),
    );
  }

  Future<void> _editProjectDetails() async {
    final details = await showDialog<_NewProjectDetails>(
      context: context,
      builder: (_) => _CreateProjectDialog(initialProject: _project),
    );
    if (!mounted || details == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('projects')
          .doc(_project.id)
          .update({
            ...details.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      setState(() {
        _project = _ProjectData(
          id: _project.id,
          ownerId: _project.ownerId,
          title: details.title,
          description: details.description,
          tags: details.tags,
          status: _project.status,
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project details updated.')));
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update project (${error.code}).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update project details.')),
      );
    }
  }
}

class _ContributionStatusMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ContributionStatusMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: colors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectSuggestionDialog extends StatefulWidget {
  final String projectTitle;
  final List<String> filePaths;
  final List<String> folderPaths;

  const _ProjectSuggestionDialog({
    required this.projectTitle,
    required this.filePaths,
    required this.folderPaths,
  });

  @override
  State<_ProjectSuggestionDialog> createState() =>
      _ProjectSuggestionDialogState();
}

class _ProjectSuggestionDialogState extends State<_ProjectSuggestionDialog> {
  final _messageController = TextEditingController();
  _SuggestionScope _scope = _SuggestionScope.project;
  String? _targetPath;
  String? _error;

  List<String> get _targetOptions => switch (_scope) {
    _SuggestionScope.project => const [],
    _SuggestionScope.file => widget.filePaths,
    _SuggestionScope.folder => widget.folderPaths,
  };

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a short suggestion first.');
      return;
    }
    if (_scope != _SuggestionScope.project && _targetPath == null) {
      setState(() => _error = 'Choose a file or folder.');
      return;
    }
    Navigator.pop(
      context,
      _ProjectSuggestionDraft(
        scope: _scope,
        targetPath: _targetPath ?? '',
        message: message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Suggest an improvement'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share feedback about “${widget.projectTitle}”.'),
          const SizedBox(height: 14),
          DropdownButtonFormField<_SuggestionScope>(
            initialValue: _scope,
            decoration: const InputDecoration(
              labelText: 'Suggestion is about',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: _SuggestionScope.project,
                child: Text('Whole project'),
              ),
              if (widget.filePaths.isNotEmpty)
                const DropdownMenuItem(
                  value: _SuggestionScope.file,
                  child: Text('A specific file'),
                ),
              if (widget.folderPaths.isNotEmpty)
                const DropdownMenuItem(
                  value: _SuggestionScope.folder,
                  child: Text('A specific folder'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _scope = value;
                _targetPath = null;
                _error = null;
              });
            },
          ),
          if (_scope != _SuggestionScope.project) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _targetOptions.contains(_targetPath)
                  ? _targetPath
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _scope == _SuggestionScope.file
                    ? 'Choose file'
                    : 'Choose folder',
                border: const OutlineInputBorder(),
              ),
              items: _targetOptions
                  .map(
                    (path) => DropdownMenuItem(
                      value: path,
                      child: Text(path, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _targetPath = value),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            maxLength: 1000,
            maxLines: 5,
            minLines: 3,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: const InputDecoration(
              labelText: 'Your suggestion',
              hintText: 'Describe the bug or improvement idea.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Send suggestion')),
    ],
  );
}

class _ProjectSuggestionsPage extends StatefulWidget {
  final _ProjectData project;
  final CollectionReference<Map<String, dynamic>> suggestions;
  final Stream<QuerySnapshot<Map<String, dynamic>>> suggestionStream;
  final bool canReview;
  final String userId;
  final String? focusDocumentId;

  const _ProjectSuggestionsPage({
    required this.project,
    required this.suggestions,
    required this.suggestionStream,
    required this.canReview,
    required this.userId,
    this.focusDocumentId,
  });

  @override
  State<_ProjectSuggestionsPage> createState() =>
      _ProjectSuggestionsPageState();
}

class _ProjectSuggestionsPageState extends State<_ProjectSuggestionsPage> {
  final Set<String> _updatingIds = {};

  Future<void> _setStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> suggestion,
    String status,
  ) async {
    setState(() => _updatingIds.add(suggestion.id));
    try {
      await suggestion.reference.update({
        'status': status,
        'reviewedBy': widget.userId,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update suggestion (${error.code}).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update suggestion. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingIds.remove(suggestion.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Project suggestions')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.suggestionStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load suggestions. Check your Firestore rules.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final suggestions = snapshot.data!.docs.toList()
          ..sort((a, b) {
            if (a.id == widget.focusDocumentId) return -1;
            if (b.id == widget.focusDocumentId) return 1;
            return _createdAt(b).compareTo(_createdAt(a));
          });
        if (suggestions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.canReview
                        ? 'No suggestions yet'
                        : 'You have not sent suggestions yet',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Suggestions for ${widget.project.title} will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedText(context)),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _suggestionCard(suggestions[index]),
        );
      },
    ),
  );

  DateTime _createdAt(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final value = doc.data()['createdAt'];
    return value is Timestamp ? value.toDate() : DateTime(0);
  }

  Widget _suggestionCard(
    QueryDocumentSnapshot<Map<String, dynamic>> suggestion,
  ) {
    final data = suggestion.data();
    final scope = data['scope'] as String? ?? 'project';
    final targetPath = data['targetPath'] as String? ?? '';
    final status = data['status'] as String? ?? 'open';
    final authorName = data['authorName'] as String? ?? 'Community member';
    final isUpdating = _updatingIds.contains(suggestion.id);
    final colors = Theme.of(context).colorScheme;
    final targetLabel = switch (scope) {
      'file' => 'File · $targetPath',
      'folder' => 'Folder · $targetPath',
      _ => 'Whole project',
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
                  targetLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              _SuggestionStatusPill(status: status),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            data['message'] as String? ?? '',
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            widget.canReview ? 'Suggested by $authorName' : 'Your suggestion',
            style: TextStyle(color: mutedText(context), fontSize: 12),
          ),
          if (widget.canReview) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: isUpdating
                    ? null
                    : () => _setStatus(
                        suggestion,
                        status == 'addressed' ? 'open' : 'addressed',
                      ),
                child: isUpdating
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(status == 'addressed' ? 'Reopen' : 'Mark addressed'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionStatusPill extends StatelessWidget {
  final String status;

  const _SuggestionStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'addressed'
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status == 'addressed' ? 'Addressed' : 'Open',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestContributionDialog extends StatefulWidget {
  final String projectTitle;

  const _RequestContributionDialog({required this.projectTitle});

  @override
  State<_RequestContributionDialog> createState() =>
      _RequestContributionDialogState();
}

class _RequestContributionDialogState
    extends State<_RequestContributionDialog> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Request to contribute'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ask the owner of “${widget.projectTitle}” to join the project.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _messageController,
            maxLength: 300,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Message (optional)',
              hintText: 'Tell the owner how you would like to help.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          Text(
            'If accepted, you can submit new files and edits for the owner to review before they are applied.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
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
        onPressed: () => Navigator.pop(context, _messageController.text.trim()),
        child: const Text('Send request'),
      ),
    ],
  );
}

class _ContributionRequestsPage extends StatefulWidget {
  final _ProjectData project;
  final CollectionReference<Map<String, dynamic>> requests;
  final Stream<QuerySnapshot<Map<String, dynamic>>> requestStream;
  final String ownerId;
  final String? focusDocumentId;

  const _ContributionRequestsPage({
    required this.project,
    required this.requests,
    required this.requestStream,
    required this.ownerId,
    this.focusDocumentId,
  });

  @override
  State<_ContributionRequestsPage> createState() =>
      _ContributionRequestsPageState();
}

class _ContributionRequestsPageState extends State<_ContributionRequestsPage> {
  final Set<String> _updatingRequestIds = {};

  Future<void> _setRequestStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> request,
    String status,
  ) async {
    setState(() => _updatingRequestIds.add(request.id));
    try {
      await request.reference.update({
        'status': status,
        'reviewedBy': widget.ownerId,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request (${error.code}).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update request. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _updatingRequestIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contribution requests')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.requestStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load requests. Check your Firestore rules.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!.docs.toList()
          ..sort((a, b) {
            if (a.id == widget.focusDocumentId) return -1;
            if (b.id == widget.focusDocumentId) return 1;
            final aTime = a.data()['requestedAt'];
            final bTime = b.data()['requestedAt'];
            final aDate = aTime is Timestamp ? aTime.toDate() : DateTime(0);
            final bDate = bTime is Timestamp ? bTime.toDate() : DateTime(0);
            return bDate.compareTo(aDate);
          });
        if (requests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.group_add_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No contribution requests yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Requests for ${widget.project.title} will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedText(context)),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _requestCard(requests[index]),
        );
      },
    ),
  );

  Widget _requestCard(QueryDocumentSnapshot<Map<String, dynamic>> request) {
    final data = request.data();
    final status = data['status'] as String? ?? 'pending';
    final isUpdating = _updatingRequestIds.contains(request.id);
    final name = data['requesterName'] as String? ?? 'Community member';
    final message = data['message'] as String? ?? '';
    final colors = Theme.of(context).colorScheme;
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
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _RequestStatusPill(status: status),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: mutedText(context), height: 1.4),
            ),
          ],
          if (status == 'pending' || status == 'accepted') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == 'pending')
                  TextButton(
                    onPressed: isUpdating
                        ? null
                        : () => _setRequestStatus(request, 'declined'),
                    child: const Text('Decline'),
                  ),
                const SizedBox(width: 6),
                FilledButton.tonal(
                  onPressed: isUpdating
                      ? null
                      : () => _setRequestStatus(
                          request,
                          status == 'accepted' ? 'declined' : 'accepted',
                        ),
                  child: isUpdating
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(status == 'accepted' ? 'Remove access' : 'Accept'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestStatusPill extends StatelessWidget {
  final String status;

  const _RequestStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (status) {
      'accepted' => 'Accepted',
      'declined' => 'Declined',
      _ => 'Pending',
    };
    final color = status == 'accepted'
        ? colors.primary
        : status == 'declined'
        ? colors.error
        : colors.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CreateProjectFilePage extends StatefulWidget {
  final String projectId;
  final String userId;
  final CollectionReference<Map<String, dynamic>> files;
  final String initialPath;
  final bool asProposal;

  const _CreateProjectFilePage({
    required this.projectId,
    required this.userId,
    required this.files,
    required this.initialPath,
    required this.asProposal,
  });

  @override
  State<_CreateProjectFilePage> createState() => _CreateProjectFilePageState();
}

class _CreateProjectFilePageState extends State<_CreateProjectFilePage> {
  late final TextEditingController _pathController;
  final _contentController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath);
  }

  @override
  void dispose() {
    _pathController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final path = _pathController.text.trim();
    final parts = path.split('/');
    if (path.isEmpty ||
        path.length > 255 ||
        path.startsWith('/') ||
        path.contains('\\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      setState(() => _error = 'Enter a relative path like lib/main.dart.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = await widget.files
          .where('path', isEqualTo: path)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = 'A file with this path already exists.';
        });
        return;
      }
      if (widget.asProposal) {
        await submitProjectFileProposal(
          projectId: widget.projectId,
          fileId: '',
          operation: 'create',
          path: path,
          content: _contentController.text,
          baseContent: '',
        );
      } else {
        await widget.files.add({
          'path': path,
          'content': _contentController.text,
          'createdBy': widget.userId,
          'updatedBy': widget.userId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.asProposal
            ? 'Could not submit this proposal (${error.code}).'
            : 'Could not save this file (${error.code}).';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.asProposal
            ? 'Could not submit this proposal. Try again.'
            : 'Could not save this file. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.asProposal ? 'Propose a new file' : 'Add text file'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? (widget.asProposal ? 'Submitting…' : 'Saving…')
                : (widget.asProposal ? 'Submit for review' : 'Save'),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'File path and name',
                hintText: 'lib/main.dart',
                prefixIcon: Icon(Icons.insert_drive_file_outlined),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                maxLength: 100000,
                textAlignVertical: TextAlignVertical.top,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Text or code',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ProjectTextFilePage extends StatefulWidget {
  final String projectId;
  final _ProjectFile file;
  final bool canEdit;
  final bool canPropose;
  final String userId;

  const _ProjectTextFilePage({
    required this.projectId,
    required this.file,
    required this.canEdit,
    required this.canPropose,
    required this.userId,
  });

  @override
  State<_ProjectTextFilePage> createState() => _ProjectTextFilePageState();
}

class _CodeTextEditingController extends TextEditingController {
  final bool highlightCode;

  _CodeTextEditingController({
    required super.text,
    required this.highlightCode,
  });

  static const _keywords = {
    'abstract',
    'as',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'def',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'final',
    'finally',
    'for',
    'from',
    'func',
    'function',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'lambda',
    'let',
    'mixin',
    'new',
    'of',
    'package',
    'pass',
    'private',
    'public',
    'return',
    'static',
    'struct',
    'super',
    'switch',
    'this',
    'throw',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  };
  static final _tokens = RegExp(
    r'''//[^\n]*|\#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[^`]*`|\b\d+(?:\.\d+)?\b|[A-Za-z_$][A-Za-z0-9_$]*''',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!highlightCode || text.isEmpty) {
      return TextSpan(style: style, text: text);
    }
    if (withComposing && value.composing.isValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final colors = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var previousEnd = 0;
    for (final match in _tokens.allMatches(text)) {
      if (match.start > previousEnd) {
        spans.add(TextSpan(text: text.substring(previousEnd, match.start)));
      }
      final token = match.group(0)!;
      TextStyle? tokenStyle;
      if (token.startsWith('//') || token.startsWith('#')) {
        tokenStyle = TextStyle(
          color: colors.onSurfaceVariant.withValues(alpha: 0.85),
          fontStyle: FontStyle.italic,
        );
      } else if (token.startsWith('"') ||
          token.startsWith("'") ||
          token.startsWith('`')) {
        tokenStyle = TextStyle(color: colors.tertiary);
      } else if (RegExp(r'^\d').hasMatch(token)) {
        tokenStyle = TextStyle(color: colors.secondary);
      } else if (_keywords.contains(token) ||
          const {
            'true',
            'false',
            'null',
            'None',
            'True',
            'False',
          }.contains(token)) {
        tokenStyle = TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w600,
        );
      } else if (token.isNotEmpty && token[0].toUpperCase() == token[0]) {
        tokenStyle = TextStyle(color: colors.tertiary);
      }
      spans.add(TextSpan(text: token, style: tokenStyle));
      previousEnd = match.end;
    }
    if (previousEnd < text.length) {
      spans.add(TextSpan(text: text.substring(previousEnd)));
    }
    return TextSpan(style: style, children: spans);
  }
}

class _ProjectTextFilePageState extends State<_ProjectTextFilePage> {
  late final TextEditingController _controller;
  late final ScrollController _horizontalScrollController;
  late String _savedContent;
  static const TextStyle _codeStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.5,
  );
  bool _saving = false;
  bool _discardingChanges = false;
  bool _isPreview = false;

  bool get _hasUnsavedChanges => _controller.text != _savedContent;

  DocumentReference<Map<String, dynamic>> get _fileRef => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('files')
      .doc(widget.file.id);

  @override
  void initState() {
    super.initState();
    final extension = widget.file.name.contains('.')
        ? widget.file.name.split('.').last.toLowerCase()
        : '';
    _controller = _CodeTextEditingController(
      text: widget.file.content,
      highlightCode: const {
        'dart',
        'py',
        'js',
        'ts',
        'java',
        'kt',
        'swift',
        'c',
        'cpp',
        'h',
        'go',
        'rs',
        'json',
        'yaml',
        'yml',
        'xml',
      }.contains(extension),
    );
    _savedContent = widget.file.content;
    _horizontalScrollController = ScrollController();
    _isPreview = widget.file.name.toLowerCase() == 'readme.md';
  }

  @override
  void dispose() {
    _controller.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final contentToSave = _controller.text;
    setState(() => _saving = true);
    try {
      if (widget.canPropose) {
        await submitProjectFileProposal(
          projectId: widget.projectId,
          fileId: widget.file.id,
          operation: 'update',
          path: widget.file.path,
          content: contentToSave,
          baseContent: widget.file.content,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent to the owner for review.')),
        );
        Navigator.of(context).pop();
        return;
      }
      await _fileRef.update({
        'content': contentToSave,
        'updatedBy': widget.userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _savedContent = contentToSave;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File saved.')));
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save changes (${error.code}).')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save changes. Try again.')),
      );
    }
  }

  Future<void> _confirmDiscardChanges() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your edits will be lost if you leave this file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    setState(() => _discardingChanges = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Widget _readmePreview(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _controller.text.split('\n');
    final blocks = <Widget>[];
    final codeLines = <String>[];
    var inCodeBlock = false;

    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        if (inCodeBlock) {
          blocks.add(_readmeCodeBlock(codeLines.join('\n'), context));
          codeLines.clear();
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
        }
        continue;
      }
      if (inCodeBlock) {
        codeLines.add(line);
        continue;
      }

      if (trimmed.isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final headingStyle = switch (level) {
          1 => theme.textTheme.headlineMedium,
          2 => theme.textTheme.headlineSmall,
          3 => theme.textTheme.titleLarge,
          4 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: SelectableText.rich(
              TextSpan(
                style: headingStyle?.copyWith(fontWeight: FontWeight.w700),
                children: _readmeInlineSpans(heading.group(2)!, context),
              ),
            ),
          ),
        );
        continue;
      }

      final quote = RegExp(r'^>\s?(.*)$').firstMatch(trimmed);
      if (quote != null) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText.rich(
                    TextSpan(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: mutedText(context),
                        height: 1.5,
                      ),
                      children: _readmeInlineSpans(quote.group(1)!, context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      final ordered = RegExp(r'^(\d+)[.)]\s+(.+)$').firstMatch(trimmed);
      final unordered = RegExp(r'^[-*+]\s+(.+)$').firstMatch(trimmed);
      if (ordered != null || unordered != null) {
        final marker = ordered?.group(1) ?? '•';
        final content = ordered?.group(2) ?? unordered!.group(1)!;
        final indent = line.length - trimmed.length;
        blocks.add(
          Padding(
            padding: EdgeInsets.only(left: indent * 8.0, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 25,
                  child: Text(
                    ordered == null ? '•' : '$marker.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      height: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText.rich(
                    TextSpan(
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                      children: _readmeInlineSpans(content, context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: outlineColor(context)),
          ),
        );
        continue;
      }

      blocks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              children: _readmeInlineSpans(trimmed, context),
            ),
          ),
        ),
      );
    }

    if (inCodeBlock) {
      blocks.add(_readmeCodeBlock(codeLines.join('\n'), context));
    }
    if (blocks.isEmpty) {
      blocks.add(
        Text('README is empty.', style: TextStyle(color: mutedText(context))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: outlineColor(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: blocks,
        ),
      ),
    );
  }

  Widget _readmeCodeBlock(String source, BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border.all(color: outlineColor(context)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText(
        source,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );

  List<InlineSpan> _readmeInlineSpans(String text, BuildContext context) {
    final pattern = RegExp(
      r'(`[^`]+`|\*\*.+?\*\*|__.+?__|\*[^*]+\*|_[^_]+_|~~.+?~~|\[[^\]]+\]\([^)]+\))',
    );
    final spans = <InlineSpan>[];
    var previousEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > previousEnd) {
        spans.add(TextSpan(text: text.substring(previousEnd, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
          ),
        );
      } else if (token.startsWith('**') || token.startsWith('__')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('~~')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (token.startsWith('*') || token.startsWith('_')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token)!;
        spans.add(
          TextSpan(
            text: link.group(1),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      }
      previousEnd = match.end;
    }
    if (previousEnd < text.length) {
      spans.add(TextSpan(text: text.substring(previousEnd)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: (!_hasUnsavedChanges && !_saving) || _discardingChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_saving && _hasUnsavedChanges) {
        _confirmDiscardChanges();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          if ((widget.canEdit || widget.canPropose) &&
              widget.file.name.toLowerCase() == 'readme.md')
            TextButton.icon(
              onPressed: () => setState(() => _isPreview = !_isPreview),
              icon: Icon(
                _isPreview ? Icons.edit_outlined : Icons.visibility_outlined,
              ),
              label: Text(_isPreview ? 'Edit' : 'Preview'),
            ),
          if (widget.canEdit || widget.canPropose)
            TextButton(
              onPressed: _saving || !_hasUnsavedChanges ? null : _save,
              child: Text(
                _saving
                    ? (widget.canPropose ? 'Submitting…' : 'Saving…')
                    : (widget.canPropose ? 'Submit for review' : 'Save'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.file.path,
                      style: TextStyle(color: mutedText(context)),
                    ),
                  ),
                  if (widget.canEdit || widget.canPropose) ...[
                    const SizedBox(width: 8),
                    Icon(
                      _hasUnsavedChanges
                          ? Icons.circle
                          : Icons.check_circle_outline,
                      size: 12,
                      color: _hasUnsavedChanges
                          ? Theme.of(context).colorScheme.tertiary
                          : mutedText(context),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _hasUnsavedChanges ? 'Unsaved' : 'Saved',
                      style: TextStyle(
                        fontSize: 12,
                        color: _hasUnsavedChanges
                            ? Theme.of(context).colorScheme.tertiary
                            : mutedText(context),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child:
                    _isPreview && widget.file.name.toLowerCase() == 'readme.md'
                    ? _readmePreview(context)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final lineCount =
                              '\n'.allMatches(_controller.text).length + 1;
                          final textPainter = TextPainter(
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            text: TextSpan(text: '', style: _codeStyle),
                          );
                          var longestLineWidth = constraints.maxWidth;
                          for (final line in _controller.text.split('\n')) {
                            textPainter.text = TextSpan(
                              text: line,
                              style: _codeStyle,
                            );
                            textPainter.layout();
                            if (textPainter.width + 28 > longestLineWidth) {
                              longestLineWidth = textPainter.width + 28;
                            }
                          }
                          final lineNumberWidth =
                              (lineCount.toString().length * 9.0) + 20;

                          return Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: outlineColor(context)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: lineNumberWidth,
                                    padding: const EdgeInsets.only(
                                      top: 10,
                                      bottom: 10,
                                    ),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.45),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: List.generate(
                                        lineCount,
                                        (index) => SizedBox(
                                          height:
                                              _codeStyle.fontSize! *
                                              _codeStyle.height!,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: Text(
                                              '${index + 1}',
                                              style: _codeStyle.copyWith(
                                                color: mutedText(context)
                                                    .withValues(alpha: 0.75),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Scrollbar(
                                      controller: _horizontalScrollController,
                                      thumbVisibility: true,
                                      interactive: true,
                                      thickness: 10,
                                      radius: const Radius.circular(12),
                                      scrollbarOrientation:
                                          ScrollbarOrientation.bottom,
                                      child: SingleChildScrollView(
                                        controller: _horizontalScrollController,
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        child: SizedBox(
                                          width: longestLineWidth,
                                          child: TextField(
                                            controller: _controller,
                                            readOnly:
                                                !widget.canEdit &&
                                                !widget.canPropose,
                                            minLines: 1,
                                            maxLines: null,
                                            maxLength: 100000,
                                            textAlignVertical:
                                                TextAlignVertical.top,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            style: _codeStyle,
                                            onChanged: (_) => setState(() {}),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              contentPadding:
                                                  EdgeInsets.fromLTRB(
                                                    12,
                                                    10,
                                                    16,
                                                    22,
                                                  ),
                                              counterText: '',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProjectTile extends StatelessWidget {
  final _ProjectData project;
  final List<String> matchedTags;
  final bool isSaved;
  final VoidCallback onToggleSaved;
  final VoidCallback onOpen;
  const _ProjectTile({
    required this.project,
    required this.matchedTags,
    required this.isSaved,
    required this.onToggleSaved,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isOwner = project.ownerId == FirebaseAuth.instance.currentUser?.uid;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlineColor(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 8, 13),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.code_rounded,
                        color: colors.onPrimaryContainer,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isOwner ? 'Created by you' : 'Community project',
                            style: TextStyle(
                              fontSize: 12,
                              color: mutedText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isSaved
                          ? 'Remove from saved projects'
                          : 'Save project',
                      onPressed: onToggleSaved,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: isSaved ? colors.primary : mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (matchedTags.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: .62),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: .18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 13,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Matches your profile',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                  ],
                  Text(
                    project.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedText(context),
                      height: 1.45,
                      fontSize: 13,
                    ),
                  ),
                  if (project.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: project.tags
                          .take(5)
                          .map(
                            (tag) => _ProjectTag(
                              label: tag,
                              highlighted: matchedTags.any(
                                (matched) =>
                                    matched.toLowerCase() == tag.toLowerCase(),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: outlineColor(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
              child: Row(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 16,
                    color: mutedText(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      project.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Open'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTag extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _ProjectTag({required this.label, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primaryContainer.withValues(alpha: .68)
            : softSurface(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
