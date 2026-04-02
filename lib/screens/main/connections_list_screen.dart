import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_profile_screen.dart';
import '../../widgets/user_avatar.dart';
import '../../theme/app_theme.dart';
import 'package:skillze/screens/main/conversation_screen.dart';

class ConnectionsListScreen extends StatefulWidget {
  const ConnectionsListScreen({super.key});

  @override
  State<ConnectionsListScreen> createState() => _ConnectionsListScreenState();
}

class _ConnectionsListScreenState extends State<ConnectionsListScreen> {
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _friends = [];
  
  List<Map<String, dynamic>> _filteredFollowers = [];
  List<Map<String, dynamic>> _filteredFollowing = [];
  List<Map<String, dynamic>> _filteredFriends = [];

  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String _currentUsername = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _filterLists();
    });
  }

  void _filterLists() {
    if (_searchQuery.isEmpty) {
      _filteredFollowers = _followers;
      _filteredFollowing = _following;
      _filteredFriends = _friends;
    } else {
      _filteredFollowers = _followers.where((u) => 
        (u['name']?.toString().toLowerCase().contains(_searchQuery) ?? false) ||
        (u['username']?.toString().toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
      _filteredFollowing = _following.where((u) => 
        (u['name']?.toString().toLowerCase().contains(_searchQuery) ?? false) ||
        (u['username']?.toString().toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
      _filteredFriends = _friends.where((u) => 
        (u['name']?.toString().toLowerCase().contains(_searchQuery) ?? false) ||
        (u['username']?.toString().toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
    }
  }

  Future<void> _fetchData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      _currentUsername = userData['username'] ?? userData['name'] ?? 'Me';

      // 1. Fetch Following
      List followingUids = List<String>.from(userData['followingList'] ?? []);
      List<Map<String, dynamic>> following = [];
      for (String uid in followingUids) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          following.add({'uid': uid, ...doc.data()!});
        }
      }

      // 2. Fetch Followers (users who follow me)
      final followersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('followingList', arrayContains: user.uid)
          .get();
      
      List<Map<String, dynamic>> followers = [];
      for (var doc in followersSnapshot.docs) {
        followers.add({'uid': doc.id, ...doc.data()});
      }

      // 3. Compute Friends (Mutuals)
      final followingSet = followingUids.toSet();
      List<Map<String, dynamic>> friends = followers.where((f) => followingSet.contains(f['uid'])).toList();

      if (mounted) {
        setState(() {
          _followers = followers;
          _following = following;
          _friends = friends;
          _filterLists();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _toggleFollow(String targetUid, String targetName, bool isCurrentlyFollowing) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (isCurrentlyFollowing) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surfaceColor,
          title: Text('Unfollow', style: TextStyle(color: context.textHigh)),
          content: Text('Are you sure you want to unfollow $targetName?', style: TextStyle(color: context.textMed)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: context.textLow)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unfollow', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      if (isCurrentlyFollowing) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'followingList': FieldValue.arrayRemove([targetUid]),
        });
      } else {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'followingList': FieldValue.arrayUnion([targetUid]),
        });
      }
      _fetchData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _messageUser(Map<String, dynamic> targetUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final otherUserId = targetUser['uid'];
    final otherUserName = targetUser['name'] ?? 'User';
    final otherAvatar = targetUser['profileImageUrl'] ?? '';

    setState(() => _isLoading = true);

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      final currentUserName = userDoc.data()?['name'] ?? 'User';
      final currentUserAvatar = userDoc.data()?['profileImageUrl'] ?? '';

      final chatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .get();

      String? chatId;
      for (var doc in chatQuery.docs) {
        final participants = List<String>.from(doc['participants']);
        if (participants.contains(otherUserId)) {
          chatId = doc.id;
          break;
        }
      }

      if (chatId == null) {
        final newChat = await FirebaseFirestore.instance.collection('chats').add({
          'participants': [currentUser.uid, otherUserId],
          'participantNames': {
            currentUser.uid: currentUserName,
            otherUserId: otherUserName,
          },
          'participantProfileImages': {
            currentUser.uid: currentUserAvatar,
            otherUserId: otherAvatar,
          },
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount_${currentUser.uid}': 0,
          'unreadCount_$otherUserId': 0,
        });
        chatId = newChat.id;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              chatId: chatId!,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting chat: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: context.bg, // Pure black background
        appBar: AppBar(
          backgroundColor: context.bg,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.textHigh, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _currentUsername,
            style: TextStyle(
              color: context.textHigh,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.person_add_outlined, color: context.textHigh, size: 28),
              onPressed: () {},
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: context.dividerColor,
            indicatorColor: context.textHigh,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 1.5,
            labelColor: context.textHigh,
            unselectedLabelColor: context.textMed,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            tabs: [
              Tab(text: '${_followers.length} Followers'),
              Tab(text: '${_friends.length} Friends'),
              Tab(text: '${_following.length} Following'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: context.textHigh))
                  : TabBarView(
                      children: [
                        _buildUserList(_filteredFollowers, 'Followers'),
                        _buildUserList(_filteredFriends, 'Friends'),
                        _buildUserList(_filteredFollowing, 'Following'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF262626) : const Color(0xFFEFEFEF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(color: context.textHigh, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search',
            hintStyle: TextStyle(color: context.textMed),
            prefixIcon: Icon(Icons.search, color: context.textMed, size: 22),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> users, String type) {
    if (users.isEmpty && !_isLoading) {
      return Center(
        child: Text(
          'No ${type.toLowerCase()} found',
          style: TextStyle(color: context.textMed),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: users.length + (type == 'Friends' ? 1 : 0),
      itemBuilder: (context, index) {
        if (type == 'Friends' && index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Followers you follow back',
                style: TextStyle(
                  color: context.textMed,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          );
        }
        
        final user = users[type == 'Friends' ? index - 1 : index];
        return _buildUserTile(user, type, index);
      },
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user, String type, int index) {
    final name = user['name'] ?? 'Unknown';
    final username = user['username'] ?? name.toLowerCase().replaceAll(' ', '_');
    final uid = user['uid'];
    final isFollowing = _following.any((f) => f['uid'] == uid);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UserProfileScreen(userId: uid)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with Gradient Border
            UserAvatar(
              imageUrl: user['profileImageUrl'],
              name: name,
              radius: 26,
            ),
            const SizedBox(width: 14),
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                  Text(
                    username,
                    style: TextStyle(
                      color: context.textHigh,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (user['isVerified'] == true) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified, color: context.primary, size: 13),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                name,
                style: TextStyle(
                  color: context.textMed,
                  fontSize: 12,
                ),
              ),
                  if (type == 'Friends' && index == 1) // Mocking "1 new post" for replica feel
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Text(
                            '1 new post',
                            style: TextStyle(color: context.textMed, fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Action Button
            GestureDetector(
              onTap: () {
                if (type == 'Following' || isFollowing) {
                  if (type == 'Friends' || type == 'Followers') {
                     _messageUser(user);
                  } else {
                     _toggleFollow(uid, name, true);
                  }
                } else {
                  _toggleFollow(uid, name, false);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF262626) : const Color(0xFFEFEFEF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  type == 'Following' ? 'Unfollow' : (isFollowing ? 'Message' : 'Follow'),
                  style: TextStyle(
                    color: context.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // More Icon
            IconButton(
              icon: Icon(Icons.more_vert, color: context.textHigh, size: 22),
              onPressed: () => _showUserOptions(user),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserOptions(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceLightColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.isDark ? Colors.white10 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.share_outlined, color: context.textHigh),
            title: Text('Share this profile', style: TextStyle(color: context.textHigh)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: context.textHigh),
            title: Text('Unfollow', style: TextStyle(color: context.textHigh)),
            onTap: () {
              Navigator.pop(context);
              _toggleFollow(user['uid'], user['name'] ?? 'User', true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.report_problem_outlined, color: Colors.redAccent),
            title: const Text('Report', style: TextStyle(color: Colors.redAccent)),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

}


