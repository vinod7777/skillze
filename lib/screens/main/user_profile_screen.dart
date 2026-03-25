import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'conversation_screen.dart';
import 'skills_screen.dart';
import '../../services/notification_service.dart';
import '../../widgets/post_card.dart';
import '../../widgets/skeleton_replacement.dart';
import '../../theme/app_theme.dart';
import 'user_list_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;
  int _postsCount = 0;
  bool _isBlocked = false;
  late Stream<QuerySnapshot> _postsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
    _fetchUserData();
  }

  void _initStream() {
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .where('authorId', isEqualTo: widget.userId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> _fetchUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (doc.exists) {
        _userData = doc.data();

        List followersList = _userData?['followersList'] ?? [];
        List followingList = _userData?['followingList'] ?? [];

        _followersCount = followersList.length;
        _followingCount = followingList.length;

        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          _isFollowing = followersList.contains(currentUser.uid);

          final currentUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          final blockedUsers = List<String>.from(
            currentUserDoc.data()?['blockedUsers'] ?? [],
          );
          _isBlocked = blockedUsers.contains(widget.userId);
        }
      }

      final postsSnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('authorId', isEqualTo: widget.userId)
          .get();
      _postsCount = postsSnapshot.docs.length;
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid == widget.userId) return;

    setState(() {
      _isFollowing = !_isFollowing;
      _followersCount += _isFollowing ? 1 : -1;
    });

    try {
      final targetUserRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId);
      final currentUserRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      if (_isFollowing) {
        await targetUserRef.update({
          'followersList': FieldValue.arrayUnion([user.uid]),
        });
        await currentUserRef.update({
          'followingList': FieldValue.arrayUnion([widget.userId]),
        });

        // Send Notification
        NotificationService.sendNotification(
          targetUserId: widget.userId,
          type: 'follow',
          message: 'started following you',
        );
      } else {
        await targetUserRef.update({
          'followersList': FieldValue.arrayRemove([user.uid]),
        });
        await currentUserRef.update({
          'followingList': FieldValue.arrayRemove([widget.userId]),
        });
      }
    } catch (e) {
      // Revert optimism
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
          _followersCount += _isFollowing ? 1 : -1;
        });
      }
    }
  }

  Future<void> _toggleBlock() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid);

    try {
      if (_isBlocked) {
        await userRef.update({
          'blockedUsers': FieldValue.arrayRemove([widget.userId]),
        });
      } else {
        await userRef.update({
          'blockedUsers': FieldValue.arrayUnion([widget.userId]),
        });
      }

      if (mounted) {
        setState(() {
          _isBlocked = !_isBlocked;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isBlocked ? 'User blocked.' : 'User unblocked.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update block status.')),
        );
      }
    }
  }

  void _shareProfile() {
    final name = _userData?['name'] ?? 'User';
    final bio = _userData?['bio'] ?? '';
    final profileText = 'Check out $name\'s profile on FeedNative!\n$bio';
    Clipboard.setData(ClipboardData(text: profileText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile link copied to clipboard!')),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(Icons.share_rounded, color: context.textHigh),
            title: Text(
              'Share Profile',
              style: TextStyle(color: context.textHigh),
            ),
            onTap: () {
              Navigator.pop(context);
              _shareProfile();
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.report_gmailerrorred_rounded,
              color: Colors.redAccent,
            ),
            title: const Text(
              'Report User',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('User reported')));
            },
          ),
          ListTile(
            leading: Icon(
              _isBlocked ? Icons.security_rounded : Icons.block_rounded,
              color: _isBlocked ? context.textHigh : Colors.redAccent,
            ),
            title: Text(
              _isBlocked ? 'Unblock User' : 'Block User',
              style: TextStyle(
                color: _isBlocked ? context.textHigh : Colors.redAccent,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleBlock();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        body: SkeletonListView(
          itemCount: 1,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonAvatar(
                      style: SkeletonAvatarStyle(
                        shape: BoxShape.circle,
                        width: 90,
                        height: 90,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          3,
                          (i) => SkeletonLine(
                            style: SkeletonLineStyle(height: 18, width: 40),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SkeletonLine(style: SkeletonLineStyle(height: 20, width: 120)),
                const SizedBox(height: 8),
                SkeletonLine(style: SkeletonLineStyle(height: 14, width: 200)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SkeletonLine(
                        style: SkeletonLineStyle(height: 40, width: 100),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SkeletonLine(
                        style: SkeletonLineStyle(height: 40, width: 100),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SkeletonAvatar(
                      style: SkeletonAvatarStyle(width: 40, height: 40),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SkeletonLine(style: SkeletonLineStyle(height: 32, width: 200)),
                const SizedBox(height: 16),
                SkeletonLine(style: SkeletonLineStyle(height: 16, width: 230)),
                const SizedBox(height: 8),
                SkeletonLine(style: SkeletonLineStyle(height: 16, width: 180)),
                const SizedBox(height: 32),
                SkeletonLine(style: SkeletonLineStyle(height: 40, width: 200)),
              ],
            ),
          ),
        ),
      );
    }

    if (_userData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Text('User not found', style: TextStyle(color: context.textHigh)),
        ),
      );
    }

    final authorName = _userData!['name'] ?? 'Unknown User';
    final bio = _userData!['bio'] ?? '';
    final username = _userData?['username'] ?? '';
    final profileImageUrl = _userData?['profileImageUrl'] ?? 
                             _userData?['authorProfileImageUrl'] ?? 
                             _userData?['photoUrl'] ?? 
                             _userData?['authorAvatar'];

    return Scaffold(
      backgroundColor: context.bg,
      body: DefaultTabController(
        length: 2,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                backgroundColor: context.bg,
                pinned: true,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  username.isNotEmpty ? username : authorName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.textHigh,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: context.textHigh,
                    ),
                    onPressed: _showMoreOptions,
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          UserAvatar(
                            imageUrl: profileImageUrl?.toString(),
                            name: authorName,
                            radius: 45,
                            border: Border.all(
                              color: context.primary,
                              width: 2,
                            ),
                            fontSize: 36,
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStatColumn('$_postsCount', 'posts', null),
                                _buildStatColumn(
                                  '$_followersCount',
                                  'followers',
                                  () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserListScreen(
                                          userId: widget.userId,
                                          title: 'Followers',
                                          type: UserListType.followers,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _buildStatColumn(
                                  '$_followingCount',
                                  'following',
                                  () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserListScreen(
                                          userId: widget.userId,
                                          title: 'Following',
                                          type: UserListType.following,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 18),
                      Text(
                        authorName,
                        style: TextStyle(
                          color: context.textHigh,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (bio.isNotEmpty) ...[
                        SizedBox(height: 6),
                        Text(
                          bio,
                          style: TextStyle(
                            color: context.textMed,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                      SizedBox(height: 20),
                      if (widget.userId !=
                          FirebaseAuth.instance.currentUser?.uid)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _toggleFollow,
                                icon: Icon(
                                  _isFollowing
                                      ? Icons.person_remove_rounded
                                      : Icons.person_add_rounded,
                                ),
                                label: Text(
                                  _isFollowing ? 'Unfollow' : 'Follow',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing
                                      ? Colors.red.withValues(alpha: 0.1)
                                      : context.primary,
                                  foregroundColor: _isFollowing
                                      ? Colors.red
                                      : context.onPrimary,
                                  elevation: 0,
                                  side: _isFollowing 
                                      ? const BorderSide(color: Colors.red, width: 1.5) 
                                      : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final currentUserId =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (currentUserId == null) return;

                                  // Check if chat already exists
                                  final chatQuery = await FirebaseFirestore
                                      .instance
                                      .collection('chats')
                                      .where(
                                        'participants',
                                        arrayContains: currentUserId,
                                      )
                                      .get();

                                  String? existingChatId;
                                  for (var doc in chatQuery.docs) {
                                    final participants = List<String>.from(
                                      doc['participants'],
                                    );
                                    if (participants.contains(widget.userId)) {
                                      existingChatId = doc.id;
                                      break;
                                    }
                                  }

                                  String chatId;
                                  if (existingChatId != null) {
                                    chatId = existingChatId;
                                  } else {
                                    // Fetch my name first
                                    final myDoc = await FirebaseFirestore
                                        .instance
                                        .collection('users')
                                        .doc(currentUserId)
                                        .get();
                                    final myName =
                                        myDoc.data()?['name'] ?? 'User';

                                    // Create new chat
                                    final newChatRef = await FirebaseFirestore
                                        .instance
                                        .collection('chats')
                                        .add({
                                          'participants': [
                                            currentUserId,
                                            widget.userId,
                                          ],
                                          'participantNames': {
                                            currentUserId: myName,
                                            widget.userId: authorName,
                                          },
                                          'lastMessage': '',
                                          'lastMessageTime':
                                              FieldValue.serverTimestamp(),
                                          'unreadCount_$currentUserId': 0,
                                          'unreadCount_${widget.userId}': 0,
                                        });
                                    chatId = newChatRef.id;
                                  }

                                   if (!context.mounted) return;
                                  // ignore: use_build_context_synchronously
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ConversationScreen(
                                        chatId: chatId,
                                        otherUserId: widget.userId,
                                        otherUserName: username.isNotEmpty
                                            ? username
                                            : authorName,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.chat_bubble_rounded),
                                label: const Text('Message'),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  TabBar(
                    indicatorColor: context.primary,
                    indicatorWeight: 1.5,
                    labelColor: context.primary,
                    unselectedLabelColor: context.textMed,
                    tabs: [
                      Tab(icon: Icon(Icons.grid_on_rounded, size: 24)),
                      Tab(icon: Icon(Icons.psychology_outlined, size: 26)),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(children: [_buildPostsGrid(), _buildSkillsTab()]),
        ),
      ),
    );
  }

  Widget _buildPostsGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.primary),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 60,
                  color: context.textLow,
                ),
                const SizedBox(height: 16),
                Text(
                  'No posts yet',
                  style: TextStyle(
                    color: context.textHigh,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        final posts = snapshot.data!.docs;
        return GridView.builder(
          padding: const EdgeInsets.only(top: 2, bottom: 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 1,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final data = posts[index].data() as Map<String, dynamic>;
            final mediaUrl = data['mediaUrl'] as String?;
            final List<String> mediaUrls = data['mediaUrls'] != null
                ? List<String>.from(data['mediaUrls'])
                : (mediaUrl != null && mediaUrl.isNotEmpty ? [mediaUrl] : []);
            final content = data['content'] ?? '';

            return GestureDetector(
              onTap: () => _openPostDetail(posts[index]),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mediaUrls.isNotEmpty)
                    Image.network(
                      mediaUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: context.surfaceLightColor,
                        child: Icon(
                          Icons.image_not_supported,
                          color: context.textMed,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: context.surfaceLightColor,
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: Text(
                          content,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  // Multiple images indicator
                  if (mediaUrls.length > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.collections_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSkillsTab() {
    final skills = List<String>.from(_userData?['skills'] ?? []);
    final role = _userData?['role'] ?? 'No role set';

    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.surfaceLightColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.work_rounded,
                      color: context.primary,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Current Status',
                      style: TextStyle(
                        color: context.textMed,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  role,
                  style: TextStyle(
                    color: context.textHigh,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFEC4899),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Core Expertise',
                style: TextStyle(
                  color: context.textHigh,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          if (skills.isEmpty)
            Center(
              child: Container(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      color: context.textLow,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No skills defined yet',
                      style: TextStyle(color: context.textMed, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: (() {
                final List<dynamic> skillsData = _userData?['skills_with_levels'] ?? [];
                if (skillsData.isNotEmpty) {
                  return skillsData.map((s) {
                    final skill = s as Map<String, dynamic>;
                    final name = skill['name'] ?? 'Skill';
                    final level = skill['level'] ?? 'Intermediate';
                    return _buildSkillItemFigma(name, level);
                  }).toList();
                } else {
                  return (_userData?['skills'] as List<dynamic>? ?? []).map((s) {
                    return _buildSkillItemFigma(s.toString(), 'Intermediate');
                  }).toList();
                }
              }()),
            ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _openPostDetail(DocumentSnapshot postDoc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  margin: EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: PostCard(
                      doc: postDoc,
                      onDeleted: () {
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatColumn(String count, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textHigh,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: context.textMed, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSkillItemFigma(String name, String level) {
    final isMe = widget.userId == FirebaseAuth.instance.currentUser?.uid;

    return GestureDetector(
      onTap: isMe
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SkillsScreen()),
              );
            }
          : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: context.surfaceLightColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: context.primary,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: context.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  level,
                  style: TextStyle(
                    color: context.textMed,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: context.bg, child: tabBar);
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}
