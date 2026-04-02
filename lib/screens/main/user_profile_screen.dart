import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/image_viewer_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:skillze/screens/main/conversation_screen.dart';
import '../../services/notification_service.dart';
import '../../widgets/post_card.dart';
import '../../widgets/skeleton_replacement.dart';
import '../../theme/app_theme.dart';
import 'user_list_screen.dart';
import '../../widgets/linkified_text.dart';
import '../../utils/avatar_helper.dart';

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

  Widget _buildStatItem(String count, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.textHigh,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.textHigh,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, {required VoidCallback onTap, bool isPrimary = false, Color? color}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary 
            ? (color ?? context.primary) 
            : (context.isDark ? context.surfaceLightColor : Colors.grey[200]),
          foregroundColor: isPrimary ? Colors.white : context.textHigh,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
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
      debugPrint('Error fetching user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not load profile details.'),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Retry', textColor: Colors.black, onPressed: _fetchUserData),
          ),
        );
      }
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
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to update block status.'),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
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
      SnackBar(
        content: const Text('Profile link copied to clipboard!'),
        backgroundColor: Colors.white,
        action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
      ),
    );
  }

  Future<void> _navigateToUserByUsername(String username) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty && mounted) {
        if (query.docs.first.id == widget.userId) return; // Already on this profile
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: query.docs.first.id),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error lookup username: $e');
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
              ).showSnackBar(SnackBar(
                content: const Text('User reported'),
                backgroundColor: Colors.white,
                action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
              ));
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
    final profileImageUrl = AvatarHelper.getAvatarUrl(_userData);

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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      // Avatar and Stats Row
                      Row(
                        children: [
                          // Avatar
                          GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Pinch or hold to view profile', 
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                                    backgroundColor: Colors.white,
                                    elevation: 8,
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.all(16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: Colors.grey.withOpacity(0.05)),
                                    ),
                                  ),
                              );
                            },
                            onLongPress: () => ImageViewerDialog.show(
                              context,
                              profileImageUrl?.toString(),
                              authorName,
                            ),
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: context.primary.withOpacity(0.2),
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: UserAvatar(
                                  imageUrl: profileImageUrl?.toString(),
                                  name: authorName,
                                  radius: 42,
                                  fontSize: 32,
                                ),
                              ),
                            ),
                          ),
                          // Stats
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStatItem('$_postsCount', 'Posts'),
                                _buildStatItem('$_followersCount', 'Followers', onTap: () {
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
                                }),
                                _buildStatItem('$_followingCount', 'Following', onTap: () {
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
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // User Info
                      Text(
                        authorName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.textHigh,
                        ),
                      ),
                      if (_userData?['status'] != null && _userData!['status'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _userData!['status'],
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textMed.withOpacity(0.8),
                            ),
                          ),
                        ),
                      if (bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: LinkifiedText(
                            text: bio,
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textHigh,
                              height: 1.3,
                            ),
                            onMentionTap: _navigateToUserByUsername,
                          ),
                        ),
                      
                      const SizedBox(height: 20),
                      
                      // Follow/Message Buttons Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              _isFollowing ? 'Following' : 'Follow',
                              isPrimary: !_isFollowing,
                              onTap: _toggleFollow,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton(
                              'Message',
                              onTap: () async {
                                final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                                if (currentUserId == null) return;

                                // Check if chat already exists
                                final chatQuery = await FirebaseFirestore.instance
                                    .collection('chats')
                                    .where('participants', arrayContains: currentUserId)
                                    .get();

                                String? existingChatId;
                                for (var doc in chatQuery.docs) {
                                  final participants = List<String>.from(doc['participants']);
                                  if (participants.contains(widget.userId)) {
                                    existingChatId = doc.id;
                                    break;
                                  }
                                }

                                String chatId;
                                if (existingChatId != null) {
                                  chatId = existingChatId;
                                } else {
                                  final myDoc = await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(currentUserId)
                                      .get();
                                  final myName = myDoc.data()?['name'] ?? 'User';
                                  final myAvatar = myDoc.data()?['profileImageUrl'] ?? myDoc.data()?['photoUrl'] ?? '';
                                  final authorAvatar = _userData?['profileImageUrl'] ?? _userData?['photoUrl'] ?? '';

                                  final newChatRef = await FirebaseFirestore.instance.collection('chats').add({
                                    'participants': [currentUserId, widget.userId],
                                    'participantNames': {
                                      currentUserId: myName,
                                      widget.userId: authorName,
                                    },
                                    'participants_data': {
                                      currentUserId: {'name': myName, 'profileImageUrl': myAvatar, 'uid': currentUserId},
                                      widget.userId: {'name': authorName, 'profileImageUrl': authorAvatar, 'uid': widget.userId},
                                    },
                                    'lastMessage': '',
                                    'lastMessageTime': FieldValue.serverTimestamp(),
                                    'unreadCount_$currentUserId': 0,
                                    'unreadCount_${widget.userId}': 0,
                                  });
                                  chatId = newChatRef.id;
                                }

                                if (!context.mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ConversationScreen(
                                      chatId: chatId,
                                      otherUserId: widget.userId,
                                      otherUserName: username.isNotEmpty ? username : authorName,
                                    ),
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
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  TabBar(
                    indicatorColor: context.primary,
                    indicatorWeight: 1.5,
                    labelColor: context.primary,
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on_sharp, size: 22)),
                      Tab(icon: Icon(Icons.psychology_alt_outlined, size: 24)),
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
          return Center(child: CircularProgressIndicator(color: context.primary));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_outlined, size: 60, color: context.textLow),
                const SizedBox(height: 16),
                Text(
                  'No posts yet',
                  style: TextStyle(color: context.textHigh, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        final posts = snapshot.data!.docs;
        return GridView.builder(
          padding: const EdgeInsets.all(1),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            childAspectRatio: 1.0,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final doc = posts[index];
            final data = doc.data() as Map<String, dynamic>;
            final mediaUrl = data['mediaUrl'] as String?;
            final List<String> mediaUrls = data['mediaUrls'] != null
                ? List<String>.from(data['mediaUrls'])
                : (mediaUrl != null && mediaUrl.isNotEmpty ? [mediaUrl] : []);
            final content = data['content'] ?? '';

            return GestureDetector(
              onTap: () => _openPostDetail(doc),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mediaUrls.isNotEmpty && mediaUrls.first.isNotEmpty)
                    Image.network(
                      mediaUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: context.surfaceLightColor,
                        child: Icon(Icons.image_not_supported, color: context.textLow),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            context.surfaceLightColor,
                            context.surfaceLightColor.withOpacity(0.8),
                            context.primary.withOpacity(0.15),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: Text(
                          content,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  if (mediaUrls.length > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.collections_rounded, color: Colors.white, size: 14),
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

  void _openPostDetail(DocumentSnapshot postDoc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
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
                    isClickable: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkillsTab() {
    final List<dynamic> skillsData = _userData?['skills_with_levels'] ?? [];
    List<Map<String, dynamic>> skillsList = [];

    if (skillsData.isNotEmpty) {
      skillsList = List<Map<String, dynamic>>.from(skillsData);
    } else {
      final List<dynamic> legacySkills = _userData?['skills'] ?? [];
      skillsList = legacySkills.map((s) => {'name': s.toString(), 'level': 'Intermediate'}).toList();
    }

    if (skillsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology_alt_outlined, size: 64, color: context.textLow),
            const SizedBox(height: 16),
            Text(
              'No skills added yet',
              style: TextStyle(color: context.textMed, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: skillsList.length,
      itemBuilder: (context, index) {
        final skill = skillsList[index];
        final String name = skill['name'] ?? 'Unknown';
        final String level = skill['level'] ?? 'Intermediate';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceLightColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.border.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bolt_rounded, color: context.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      level,
                      style: TextStyle(color: context.primary, fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.bg,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
