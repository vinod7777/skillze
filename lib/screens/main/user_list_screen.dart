import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import 'user_profile_screen.dart';
import '../../widgets/user_avatar.dart';

enum UserListType { followers, following }

class UserListScreen extends StatefulWidget {
  final String userId;
  final String title;
  final UserListType type;

  const UserListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.type,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (!userDoc.exists) return;

      final userData = userDoc.data() ?? {};
      List uids = [];

      if (widget.type == UserListType.followers) {
        uids = userData['followersList'] ?? [];
      } else {
        uids = userData['followingList'] ?? [];
      }

      List<Map<String, dynamic>> users = [];
      for (String uid in uids) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          users.add({'uid': uid, ...doc.data()!});
        }
      }

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user list: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: context.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: context.textHigh),
            )
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.type == UserListType.followers
                        ? Icons.people_outline_rounded
                        : Icons.person_add_outlined,
                    size: 64,
                    color: context.textMed,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No ${widget.type == UserListType.followers ? 'followers' : 'following'} yet',
                    style: TextStyle(
                      color: context.textMed,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return _buildUserTile(user);
              },
            ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final uid = user['uid'];

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
            UserAvatar(
              imageUrl: user['profileImageUrl'],
              name: user['name'] ?? '?',
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
                      Flexible(
                        child: Text(
                          user['username'] ?? 'User',
                          style: TextStyle(
                            color: context.textHigh,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
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
                    user['name'] ?? '',
                    style: TextStyle(
                      color: context.textMed,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Action Button
            _buildActionButton(user),
            const SizedBox(width: 8),
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

  Widget _buildActionButton(Map<String, dynamic> user) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || user['uid'] == currentUser.uid) return const SizedBox.shrink();

    // If it's MY following list, show "Unfollow"
    if (widget.userId == currentUser.uid && widget.type == UserListType.following) {
      return GestureDetector(
        onTap: () => _toggleFollow(user['uid'], user['name'] ?? 'User', true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF262626) : const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Unfollow',
            style: TextStyle(
              color: context.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Default to "View" or "Follow" for others
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: user['uid'] ?? ''),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF262626) : const Color(0xFFEFEFEF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'View',
          style: TextStyle(
            color: context.textHigh,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow(String targetUid, String targetName, bool isCurrentlyFollowing) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (isCurrentlyFollowing) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surfaceLightColor,
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
      final batch = FirebaseFirestore.instance.batch();
      final currentUserRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final targetUserRef = FirebaseFirestore.instance.collection('users').doc(targetUid);

      if (isCurrentlyFollowing) {
        batch.update(currentUserRef, {
          'followingList': FieldValue.arrayRemove([targetUid]),
        });
        batch.update(targetUserRef, {
          'followersList': FieldValue.arrayRemove([user.uid]),
        });
      } else {
        batch.update(currentUserRef, {
          'followingList': FieldValue.arrayUnion([targetUid]),
        });
        batch.update(targetUserRef, {
          'followersList': FieldValue.arrayUnion([user.uid]),
        });
      }
      
      await batch.commit();
      _fetchUsers(); // Refresh list
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
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
