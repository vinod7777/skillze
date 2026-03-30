import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin;
import 'notifications_screen.dart';
import 'create_story_screen.dart';
import 'story_viewer_screen.dart';
import 'user_profile_screen.dart';
import 'main_navigation.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

import '../../theme/app_theme.dart';

import '../../models/story_model.dart';
import 'dart:async';
import '../../widgets/post_card.dart';
import '../../widgets/skeleton_replacement.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/interests_bottom_sheet.dart';
import '../../widgets/clean_text_field.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
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

  List<Map<String, dynamic>> _nearbyUsers = [];
  bool _isLoadingNearby = false;

  // Personalized Feed State
  List<String> _selectedInterestSkills = [];
  bool _showInterestsPrompt = false;

  // Story Avatar Cache: userId -> resolved profileImageUrl
  final Map<String, String?> _storyAvatarCache = {};

  Future<void> _resolveStoryAvatar(String userId, String savedAvatar) async {
    if (_storyAvatarCache.containsKey(userId)) return; // Already resolved
    if (savedAvatar.isNotEmpty) {
      _storyAvatarCache[userId] = savedAvatar;
      return;
    }
    // savedAvatar is empty — fetch fresh from Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data();
        final url = data?['profileImageUrl'] ??
            data?['photoURL'] ??
            data?['photoUrl'] ??
            data?['avatar'];
        setState(() => _storyAvatarCache[userId] = url);
      } else {
        _storyAvatarCache[userId] = null;
      }
    } catch (_) {
      _storyAvatarCache[userId] = null;
    }
  }

  @override
  void dispose() {
    _followingSubscription?.cancel();
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
  
  StreamSubscription? _followingSubscription;

  List<String> _followingList = [];
  Map<String, dynamic>? _currentUserData;

  @override
  void initState() {
    super.initState();
    _setupFollowingListener();
    _fetchCurrentUserProfile();
    _fetchNearbyUsers();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
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
        query = query.where(
          'authorId',
          whereIn: _followingList.take(30).toList(),
        );
      } else if (viewMode == 'all' && _selectedInterestSkills.isNotEmpty) {
        // PERSONALIZED FEED: Filter by user interests
        query = query.where('skills', arrayContainsAny: _selectedInterestSkills);
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
          
          // If filtering by skills returned no results, and it's our first load
          if (isFirstLoad && _posts.isEmpty && viewMode == 'all' && _selectedInterestSkills.isNotEmpty) {
            _hasMore = false;
            _isInitialLoading = false;
            _isLoadingMore = false;
            return;
          }

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
        // Show a more user-friendly error if possible, or at least a notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load posts. ${e.toString().contains('index') ? 'A specialized index is required in Firestore.' : 'Please check your connection.'}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }


  Future<void> _fetchNearbyUsers() async {
    if (_isLoadingNearby) return;
    setState(() => _isLoadingNearby = true);

    try {
      // Get current location
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // Fetch users who have registered a location
      // Using isGreaterThan: -91 is more robust than isNotEqualTo: 0 for finding numeric fields
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('latitude', isGreaterThan: -91)
          .limit(50)
          .get();

      final currentUser = FirebaseAuth.instance.currentUser;
      final List<Map<String, dynamic>> users = [];

      for (var doc in snapshot.docs) {
        if (currentUser != null && doc.id == currentUser.uid) continue;
        final data = doc.data();
        if (data['latitude'] != null && data['longitude'] != null) {
          final userLat = (data['latitude'] as num).toDouble();
          final userLng = (data['longitude'] as num).toDouble();

          double distanceKm = _calculateDistance(
            position.latitude,
            position.longitude,
            userLat,
            userLng,
          );

          users.add({
            'uid': doc.id,
            'name': data['name'] ?? 'Unknown',
            'username': data['username'] ?? '',
            'profileImageUrl': data['profileImageUrl'],
            'distanceKm': distanceKm,
            'role': data['role'] ?? data['status'] ?? 'Community Member',
          });
        }
      }

      // Sort by distance
      users.sort((a, b) => (a['distanceKm'] as double).compareTo(b['distanceKm'] as double));

      if (mounted) {
        setState(() {
          _nearbyUsers = users.take(10).toList();
          _isLoadingNearby = false;
        });
        _fetchNearbyPostsList(); // Also fetch nearby posts for the empty state
      }
    } catch (e) {
      debugPrint('Error fetching nearby users: $e');
      if (mounted) setState(() => _isLoadingNearby = false);
    }
  }

  List<DocumentSnapshot> _nearbyPosts = [];
  bool _isLoadingNearbyPosts = false;

  Future<void> _fetchNearbyPostsList() async {
    if (_isLoadingNearbyPosts) return;
    setState(() => _isLoadingNearbyPosts = true);

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('latitude', isGreaterThan: -91)
          .limit(100)
          .get();

      final List<Map<String, dynamic>> postsWithDistance = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['latitude'] == null || data['longitude'] == null) continue;

        double distanceKm = _calculateDistance(
          position.latitude,
          position.longitude,
          (data['latitude'] as num).toDouble(),
          (data['longitude'] as num).toDouble(),
        );

        if (distanceKm < 50) { // Show posts within 50km
          postsWithDistance.add({
            'doc': doc,
            'distanceKm': distanceKm,
          });
        }
      }

      postsWithDistance.sort((a, b) => (a['distanceKm'] as double).compareTo(b['distanceKm'] as double));

      if (mounted) {
        setState(() {
          _nearbyPosts = postsWithDistance.take(10).map((p) => p['doc'] as DocumentSnapshot).toList();
          _isLoadingNearbyPosts = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching nearby posts: $e');
      if (mounted) setState(() => _isLoadingNearbyPosts = false);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
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

  void _setupFollowingListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _followingSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
          final data = doc.data();
          if (data != null) {
            final newList = List<String>.from(data['followingList'] ?? []);
            final newInterests = List<String>.from(data['interested_skills'] ?? []);
            
            // If the list actually changed, and we are in connections mode, refresh posts
            bool followingChanged = newList.length != _followingList.length || 
                           !newList.every((id) => _followingList.contains(id));
            
            bool interestsChanged = newInterests.length != _selectedInterestSkills.length ||
                           !newInterests.every((s) => _selectedInterestSkills.contains(s));

            setState(() {
              _followingList = newList;
              _selectedInterestSkills = newInterests;
              _currentUserData = data;
              _showInterestsPrompt = newInterests.isEmpty;
            });

            if ((followingChanged && viewMode == 'connections') || (interestsChanged && viewMode == 'all')) {
              _fetchPosts(isFirstLoad: true);
            } else if (_posts.isEmpty && isInitialLoadingFirstTime) {
               // First time fetch
               _fetchPosts(isFirstLoad: true);
               isInitialLoadingFirstTime = false;
            }
          }
      }
    });
  }

  bool isInitialLoadingFirstTime = true;

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
              child: Builder(
                builder: (context) {
                  if (viewMode == 'skills') return _buildSkillsList();
                  return _buildPostsList();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 16, left: 12, right: 12, bottom: 8),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _buildSettingsButton(),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Skill',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: context.textHigh,
                        letterSpacing: -1,
                      ),
                    ),
                    TextSpan(
                      text: 'ze',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: context.primary,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _buildNotificationButton(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // For You / Following toggle (LinkedIn style pill)
              Expanded(
                child: _buildToggleSlider(),
              ),
              const SizedBox(width: 12),
              // Filter Button
              GestureDetector(
                onTap: _showFilterOptions,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _selectedInterestSkills.isNotEmpty ? context.primary : context.surfaceLightColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.border.withOpacity(0.3)),
                    boxShadow: _selectedInterestSkills.isNotEmpty ? [
                      BoxShadow(
                        color: context.primary.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ] : null,
                  ),
                  child: Icon(
                    _selectedInterestSkills.isNotEmpty ? Icons.tune_rounded : Icons.filter_list_rounded,
                    color: _selectedInterestSkills.isNotEmpty ? Colors.white : context.textMed,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return IconButton(
      icon: Icon(
        Icons.settings_outlined,
        color: context.textHigh,
        size: 22, // Size adjusted up slightly since no container now
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SettingsScreen(),
          ),
        );
      },
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildNotificationButton() {
    return IconButton(
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
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildToggleSlider() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.surfaceLightColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
            alignment: viewMode == 'connections' ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: context.primary,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: context.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (viewMode != 'all') {
                      setState(() {
                        viewMode = 'all';
                        _fetchPosts(isFirstLoad: true);
                      });
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: viewMode == 'all' ? (context.isDark ? Colors.black : Colors.white) : context.textMed,
                        fontWeight: viewMode == 'all' ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      child: const Text('For You'),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (viewMode != 'connections') {
                      setState(() {
                        viewMode = 'connections';
                        _fetchPosts(isFirstLoad: true);
                      });
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: viewMode == 'connections' ? (context.isDark ? Colors.black : Colors.white) : context.textMed,
                        fontWeight: viewMode == 'connections' ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      child: const Text('Following'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoriesBar() {
    final DateTime twentyFourHoursAgo = DateTime.now().subtract(
      const Duration(hours: 24),
    );

    return Container(
      height: 105,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where(
              'timestamp',
              isGreaterThan: Timestamp.fromDate(twentyFourHoursAgo),
            )
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return  Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.primary,
              ),
            );
          }

          final storiesDocs = snapshot.data?.docs ?? [];
          final Map<String, List<Story>> groupedStories = {};

          final currentUser = FirebaseAuth.instance.currentUser;
          final followingList = List<String>.from(
            _currentUserData?['followingList'] ?? [],
          );

          for (var doc in storiesDocs) {
            final story = Story.fromDoc(doc);

            // Privacy Filtering: Only show stories from people you follow, or your own
            if (story.userId == currentUser?.uid ||
                followingList.contains(story.userId)) {
              if (!groupedStories.containsKey(story.userId)) {
                groupedStories[story.userId] = [];
              }
              groupedStories[story.userId]!.add(story);
            }
          }

          final myStories = groupedStories[currentUser?.uid] ?? [];
          final otherUserIds = groupedStories.keys
              .where((id) => id != currentUser?.uid)
              .toList();

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
                      currentUser?.photoURL ??
                      '',
                  isMine: true,
                  stories: myStories,
                );
              }

              final userId = otherUserIds[index - 1];
              final userStories = groupedStories[userId]!;
              final savedAvatar = userStories.first.userAvatar;
              // Resolve avatar asynchronously for old stories
              _resolveStoryAvatar(userId, savedAvatar);
              final resolvedAvatar = _storyAvatarCache[userId] ?? savedAvatar;
              return _buildStoryItem(
                userStories.first.userName,
                resolvedAvatar,
                stories: userStories,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStoryItem(
    String name,
    String imageUrl, {
    bool isMine = false,
    List<Story> stories = const [],
  }) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final bool hasUnseen = stories.isNotEmpty && 
        !stories.every((s) => s.seenBy.contains(currentUserId));

    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (isMine) {
                if (stories.isEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateStoryScreen(),
                    ),
                  );
                } else {
                  _showMyStoryOptions(stories);
                }
              } else if (stories.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StoryViewerScreen(stories: stories),
                  ),
                );
              }
            },
            child: Stack(
              children: [
                UserAvatar(
                  imageUrl: imageUrl,
                  name: name,
                  radius: 28,
                  hasStory: stories.isNotEmpty,
                  isStorySeen: stories.isNotEmpty && !hasUnseen,
                ),
                if (isMine && stories.isEmpty)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: context.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 12,
                        color: context.isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 70,
            child: Text(
              isMine ? 'Your Story' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: (hasUnseen) ? FontWeight.bold : FontWeight.w500,
                color: hasUnseen ? context.textHigh : context.textMed,
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
              leading: Icon(
                Icons.remove_red_eye_outlined,
                color: context.primary,
              ),
              title: const Text(
                'View your story',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StoryViewerScreen(stories: stories),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.add_circle_outline_rounded,
                color: context.primary,
              ),
              title: const Text(
                'Add another story',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateStoryScreen(),
                  ),
                );
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
          child: CleanTextField(
            controller: _talentSearchController,
            hintText: 'Search for skills, roles, or anything...',
            prefixIcon: Icons.search_rounded,
            onChanged: (val) => setState(() => activeFilter = val.trim().toLowerCase()),
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
                    padding: EdgeInsets.zero,
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      return PostCard(
                        doc: filteredList[index],
                        onDeleted: () {
                          setState(() {
                            final docId = filteredList[index].id;
                            _posts.removeWhere((p) => p.id == docId);
                          });
                        },
                      );
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
      return _buildEmptyFollowingView();
    }

    if (_isInitialLoading) {
      return SkeletonListView(itemCount: 6);
    }

    if (_posts.isEmpty) {
      if (viewMode == 'connections') {
        return _buildEmptyFollowingView();
      }

      if (viewMode == 'all' && _selectedInterestSkills.isNotEmpty) {
        return _buildEmptyInterestsView();
      }

      final showStories = viewMode == 'all';
      return RefreshIndicator(
        onRefresh: () async {
          await _fetchPosts(isFirstLoad: true);
        },
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (showStories) _buildStoriesBar(),
            SizedBox(
              height: MediaQuery.of(context).size.height * (showStories ? 0.5 : 0.7),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    'No posts yet.\nBe the first to share something!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF71717A)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final showStories = viewMode == 'all';

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchPosts(isFirstLoad: true);
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 0, top: 4),
        itemCount: _posts.length + (showStories ? 2 : 1) + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          int currentIndex = 0;

          // 1. Stories Bar
          if (showStories) {
            if (index == currentIndex) return _buildStoriesBar();
            currentIndex++;
          }

          // 2. Interest Prompt (For new users or those with no skills)
          if (viewMode == 'all' && _showInterestsPrompt) {
            if (index == currentIndex) return _buildInterestsPrompt();
            currentIndex++;
          }

          // 3. Posts
          final postIndex = index - currentIndex;
          if (postIndex >= 0 && postIndex < _posts.length) {
            return PostCard(
              doc: _posts[postIndex],
              onDeleted: () {
                setState(() {
                  _posts.removeAt(postIndex);
                });
              },
            );
          }

          // 4. Loading More
          if (_hasMore && postIndex == _posts.length) {
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

          return const SizedBox.shrink();
        },
        physics: const BouncingScrollPhysics(),
      ),
    );
  }

  void _showFilterOptions() {
    InterestsBottomSheet.show(
      context,
      initialSkills: _selectedInterestSkills,
      onSave: (skills) {
        setState(() {
          _selectedInterestSkills = skills;
          _showInterestsPrompt = skills.isEmpty;
        });
        _fetchPosts(isFirstLoad: true);
      },
    );
  }

  Widget _buildInterestsPrompt() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.black : context.primary,
        borderRadius: BorderRadius.circular(24),
        border: context.isDark ? Border.all(color: Colors.white24, width: 1) : null,
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black26 : context.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Personalize your feed',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tell us which skills you want to explore! We will curate a custom feed just for you.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showFilterOptions,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.isDark ? Colors.white : Colors.white,
                foregroundColor: context.isDark ? Colors.black : context.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Select Interests', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  final Map<String, bool> _privacyCache = {};

  Future<List<DocumentSnapshot>> _filterPrivatePosts(
    List<DocumentSnapshot> docs,
    String? currentUserId,
  ) async {
    if (currentUserId == null) return docs;

    // Get current user's hidden and not interested lists
    final List<String> hiddenPosts = List<String>.from(
      _currentUserData?['hiddenPosts'] ?? [],
    );
    final List<String> notInterestedPosts = List<String>.from(
      _currentUserData?['notInterestedPosts'] ?? [],
    );
    final Set<String> excludedPostIds = {...hiddenPosts, ...notInterestedPosts};

    final List<DocumentSnapshot> result = [];
    for (final doc in docs) {
      if (excludedPostIds.contains(doc.id)) continue;

      final data = doc.data() as Map<String, dynamic>;
      final authorId = data['authorId'] as String?;

      // If it's my own post, or I follow the author, or the author is not private, show it
      if (authorId == null ||
          authorId == currentUserId ||
          viewMode == 'connections' ||
          _followingList.contains(authorId)) {
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
  Widget _buildEmptyFollowingView() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchPosts(isFirstLoad: true);
        await _fetchNearbyUsers();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Discover Card
            Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: context.surfaceLightColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: context.border.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.explore_rounded, size: 32, color: context.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Discover Talent',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textHigh,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Follow people to build your customized feed of skills and updates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textMed, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final navState = context.findAncestorStateOfType<MainNavigationState>();
                      if (navState != null) {
                        SearchScreen.searchKey.currentState?.switchToListView();
                        navState.setIndex(1); // Go to SearchScreen (Discover)
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primary,
                      foregroundColor: context.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('Discover People', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            
            if (_isLoadingNearby)
              const Padding(
                padding: EdgeInsets.all(60),
                child: CircularProgressIndicator(),
              )
            else if (_nearbyUsers.isNotEmpty) ...[
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      'Members near you',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textHigh,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.surfaceLightColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _nearbyUsers.length,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemBuilder: (context, index) {
                  return _buildNearbyUserItem(_nearbyUsers[index]);
                },
              ),
              
              if (_nearbyPosts.isNotEmpty) ...[
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Posts near you',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.textHigh,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _nearbyPosts.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, index) {
                    return PostCard(doc: _nearbyPosts[index], isClickable: true);
                  },
                ),
              ],
              const SizedBox(height: 24),
              // Explore Button
              TextButton.icon(
                onPressed: () {
                  final navState = context.findAncestorStateOfType<MainNavigationState>();
                  if (navState != null) {
                    SearchScreen.searchKey.currentState?.switchToListView();
                    navState.setIndex(1); // Go to Discover
                  }
                },
                icon: const Icon(Icons.search_rounded, size: 20),
                label: const Text('Explore Skills', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: TextButton.styleFrom(
                  foregroundColor: context.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: context.primary.withOpacity(0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyUserItem(Map<String, dynamic> user) {
    final bool isFollowing = _followingList.contains(user['uid']);
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: user['uid']),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            UserAvatar(
              imageUrl: user['profileImageUrl'],
              name: user['name'],
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.textHigh,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    user['role'],
                    style: TextStyle(color: context.textMed, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _toggleFollowUser(user['uid']),
              icon: Icon(
                isFollowing ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                color: isFollowing ? Colors.green : context.primary,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyInterestsView() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchPosts(isFirstLoad: true);
      },
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildStoriesBar(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.surfaceLightColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.psychology_outlined,
                    size: 48,
                    color: context.primary.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No posts matching your skills',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textHigh,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'There are currently no posts available for your selected skills: ${_selectedInterestSkills.join(", ")}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.textMed,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _showFilterOptions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Select Another Skill',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedInterestSkills = [];
                      _showInterestsPrompt = true;
                    });
                    _fetchPosts(isFirstLoad: true);
                  },
                  child: Text(
                    'Show All Feed',
                    style: TextStyle(
                      color: context.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFollowUser(String targetId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final isFollowing = _followingList.contains(targetId);
    
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final targetUserRef = FirebaseFirestore.instance.collection('users').doc(targetId);
    
    try {
      if (!isFollowing) {
        await currentUserRef.update({
          'followingList': FieldValue.arrayUnion([targetId]),
        });
        await targetUserRef.update({
          'followersList': FieldValue.arrayUnion([user.uid]),
        });
      } else {
        await currentUserRef.update({
          'followingList': FieldValue.arrayRemove([targetId]),
        });
        await targetUserRef.update({
          'followersList': FieldValue.arrayRemove([user.uid]),
        });
      }
    } catch (e) {
      debugPrint('Error toggling follow: $e');
    }
  }
}
