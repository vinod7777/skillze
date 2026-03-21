import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notifications_screen.dart';
import 'create_story_screen.dart';
import 'story_viewer_screen.dart';

import '../../theme/app_theme.dart';


import '../../models/story_model.dart';
import '../../widgets/post_card.dart';
import '../../widgets/skeleton_replacement.dart';
import '../../widgets/user_avatar.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _talentSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Pagination State
  final List<DocumentSnapshot> _posts = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _talentSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Helper to build the filter toggle buttons for skills/roles

  // Helper to get the Firestore stream for the selected skill/role
  Stream<QuerySnapshot> _getTalentStream() {
    return FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  String viewMode = 'all'; // 'all', 'connections', 'skills'
  String filterType = 'skills'; // 'skills', 'roles'
  String searchQuery = '';
  String activeFilter = '';

  final List<String> availableSkills = [
    'Flutter',
    'React Native',
    'Node.js',
    'Python',
    'UI/UX',
  ];
  final List<String> availableRoles = [
    'Frontend Dev',
    'Backend Dev',
    'Full Stack',
    'Designer',
  ];

  List<String> _followingList = [];
  Map<String, dynamic>? _currentUserData;

  @override
  void initState() {
    super.initState();
    _fetchFollowingList().then((_) => _fetchPosts(isFirstLoad: true));
    _fetchCurrentUserProfile();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchPosts();
    }
  }

  Future<void> _fetchPosts({bool isFirstLoad = false}) async {
    if (isFirstLoad) {
      setState(() {
        _isInitialLoading = true;
        _posts.clear();
        _lastDocument = null;
        _hasMore = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      Query query = FirebaseFirestore.instance.collection('posts');

      if (viewMode == 'connections') {
        if (_followingList.isEmpty) {
          setState(() {
            _isInitialLoading = false;
            _isLoadingMore = false;
            _hasMore = false;
          });
          return;
        }
        query = query.where('authorId', whereIn: _followingList.take(10).toList());
      }

      query = query.orderBy('timestamp', descending: true).limit(_pageSize);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final querySnapshot = await query.get();
      final List<DocumentSnapshot> newDocs = querySnapshot.docs;

      // Filter private posts
      final filteredDocs = await _filterPrivatePosts(newDocs, currentUserId);

      if (mounted) {
        setState(() {
          _posts.addAll(filteredDocs);
          if (newDocs.length < _pageSize) {
            _hasMore = false;
          } else {
            _lastDocument = newDocs.last;
          }
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching posts: $e');
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _fetchCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          setState(() {
            _currentUserData = doc.data();
          });
        }
      });
    }
  }

  Future<void> _fetchFollowingList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('followingList')) {
          if (mounted) {
            setState(() {
              _followingList = List<String>.from(data['followingList']);
            });
          }
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Column(
                children: [
                  if (viewMode != 'skills') _buildStoriesBar(),
                  Expanded(
                    child: Builder(builder: (context) {
                      if (viewMode == 'skills') return _buildSkillsList();
                      return _buildPostsList();
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // For You / Following toggle (Figma style pill)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.surfaceLightColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _buildModeTab('For You', 'all'),
                      _buildModeTab('Following', 'connections'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.border),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.notifications_outlined,
                    color: context.textHigh,
                    size: 22,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, String mode) {
    final isActive = viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (viewMode != mode) {
            setState(() {
              viewMode = mode;
              _fetchPosts(isFirstLoad: true);
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? context.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? Colors.white : context.textMed,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoriesBar() {
    final DateTime twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where('timestamp', isGreaterThan: Timestamp.fromDate(twentyFourHoursAgo))
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F2F6A)));
          }

          final storiesDocs = snapshot.data?.docs ?? [];
          final Map<String, List<Story>> groupedStories = {};
          
          final currentUser = FirebaseAuth.instance.currentUser;
          final followingList = List<String>.from(_currentUserData?['followingList'] ?? []);

          for (var doc in storiesDocs) {
            final story = Story.fromDoc(doc);
            
            // Privacy Filtering: Only show stories from people you follow, or your own
            if (story.userId == currentUser?.uid || followingList.contains(story.userId)) {
              if (!groupedStories.containsKey(story.userId)) {
                groupedStories[story.userId] = [];
              }
              groupedStories[story.userId]!.add(story);
            }
          }

          final myStories = groupedStories[currentUser?.uid] ?? [];
          final otherUserIds = groupedStories.keys.where((id) => id != currentUser?.uid).toList();

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: otherUserIds.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildStoryItem(
                  'Your Story',
                  _currentUserData?['profileImageUrl'] ?? 
                  _currentUserData?['authorProfileImageUrl'] ?? 
                  _currentUserData?['photoUrl'] ?? 
                  _currentUserData?['authorAvatar'] ?? 
                  currentUser?.photoURL ?? '',
                  isMine: true,
                  stories: myStories,
                );
              }
              
              final userId = otherUserIds[index - 1];
              final userStories = groupedStories[userId]!;
              return _buildStoryItem(
                userStories.first.userName,
                userStories.first.userAvatar,
                stories: userStories,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStoryItem(String name, String imageUrl, {bool isMine = false, List<Story> stories = const []}) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (isMine) {
                if (stories.isEmpty) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateStoryScreen()));
                } else {
                  // Show option to view or add another
                  _showMyStoryOptions(stories);
                }
              } else if (stories.isNotEmpty) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => StoryViewerScreen(stories: stories)));
              }
            },
            child: Stack(
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: (stories.isNotEmpty && !stories.every((s) => s.seenBy.contains(FirebaseAuth.instance.currentUser?.uid))) 
                      ? const LinearGradient(
                        colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ) : null,
                    color: (stories.isEmpty || stories.every((s) => s.seenBy.contains(FirebaseAuth.instance.currentUser?.uid))) 
                      ? Colors.grey.shade300 
                      : null,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: UserAvatar(
                      imageUrl: imageUrl,
                      name: name,
                      radius: 31,
                    ),
                  ),
                ),
                if (isMine && stories.isEmpty)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: context.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.isDark ? context.surfaceColor : Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 72,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: (isMine || stories.isNotEmpty) ? FontWeight.w600 : FontWeight.w500,
                color: context.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMyStoryOptions(List<Story> stories) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your Story',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Icon(Icons.remove_red_eye_outlined, color: context.primary),
              title: const Text('View your story', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => StoryViewerScreen(stories: stories)));
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded, color: context.primary),
              title: const Text('Add another story', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateStoryScreen()));
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: context.surfaceLightColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: context.textMed,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _talentSearchController,
                    onChanged: (val) =>
                        setState(() => activeFilter = val.trim().toLowerCase()),
                    style: TextStyle(color: context.textHigh),
                    decoration: InputDecoration(
                      hintText: 'Search for skills, roles, or anything...',
                      hintStyle: TextStyle(color: context.textLow),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (activeFilter.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _talentSearchController.clear();
                      setState(() => activeFilter = '');
                    },
                    color: const Color(0xFF71717A),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _getTalentStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(color: context.textHigh),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text(
                    'No posts found matching exactly this skill/role.\nBe the first to post!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textMed),
                  ),
                );
              }

              var docs = snapshot.data!.docs;

              // Local filtering for "search anything"
              if (activeFilter.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final content = (data['content'] ?? '')
                      .toString()
                      .toLowerCase();
                  final skills = List<String>.from(
                    data['skills'] ?? [],
                  ).map((s) => s.toString().toLowerCase()).toList();
                  final roles = List<String>.from(
                    data['roles'] ?? [],
                  ).map((r) => r.toString().toLowerCase()).toList();
                  final authorName = (data['authorName'] ?? '')
                      .toString()
                      .toLowerCase();

                  return content.contains(activeFilter) ||
                      skills.any((s) => s.contains(activeFilter)) ||
                      roles.any((r) => r.contains(activeFilter)) ||
                      authorName.contains(activeFilter);
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      activeFilter.isEmpty
                          ? 'No posts yet.'
                          : 'No results found for "$activeFilter".\nTry searching for skills like Flutter or React.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textMed),
                    ),
                  ),
                );
              }

              // Result sorting (already sorted by timestamp from stream, but keeping it safe)
              var list = List<DocumentSnapshot>.from(docs);

              list.sort((a, b) {
                final aTime =
                    (a.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                final bTime =
                    (b.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                if (aTime == null || bTime == null) return 0;
                return bTime.compareTo(aTime);
              });

              return FutureBuilder<List<DocumentSnapshot>>(
                future: _filterPrivatePosts(
                  list,
                  FirebaseAuth.instance.currentUser?.uid,
                ),
                builder: (context, filteredSnap) {
                  final filteredList = filteredSnap.data ?? list;
                  if (filteredList.isEmpty) {
                    return Center(
                      child: Text(
                        'No posts found.',
                        style: const TextStyle(color: Color(0xFF71717A)),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      return PostCard(doc: filteredList[index]);
                    },
                    physics: const BouncingScrollPhysics(),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPostsList() {
    if (viewMode == 'connections' && _followingList.isEmpty) {
      return Center(
        child: Text(
          'You are not following anyone yet.\nDiscover people in the Talent tab!',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
      );
    }

    if (_isInitialLoading) {
      return SkeletonListView(itemCount: 6);
    }

    if (_posts.isEmpty) {
      return Center(
        child: Text(
          'No posts yet.\nBe the first to share something!',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 120, top: 4),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.primary,
              ),
            ),
          );
        }
        return PostCard(doc: _posts[index]);
      },
      physics: const BouncingScrollPhysics(),
    );
  }

  final Map<String, bool> _privacyCache = {};

  Future<List<DocumentSnapshot>> _filterPrivatePosts(
    List<DocumentSnapshot> docs,
    String? currentUserId,
  ) async {
    if (currentUserId == null) return docs;

    // Get current user's hidden and not interested lists
    final List<String> hiddenPosts = List<String>.from(_currentUserData?['hiddenPosts'] ?? []);
    final List<String> notInterestedPosts = List<String>.from(_currentUserData?['notInterestedPosts'] ?? []);
    final Set<String> excludedPostIds = {...hiddenPosts, ...notInterestedPosts};

    final List<DocumentSnapshot> result = [];
    for (final doc in docs) {
      if (excludedPostIds.contains(doc.id)) continue;

      final data = doc.data() as Map<String, dynamic>;
      final authorId = data['authorId'] as String?;
      
      // If it's my own post, or I follow the author, or the author is not private, show it
      if (authorId == null || authorId == currentUserId || viewMode == 'connections' || _followingList.contains(authorId)) {
        result.add(doc);
        continue;
      }

      if (!_privacyCache.containsKey(authorId)) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authorId)
            .get();
        _privacyCache[authorId] = userDoc.data()?['isPrivate'] == true;
      }
      
      if (!_privacyCache[authorId]!) {
        result.add(doc);
      }
    }
    return result;
  }
}
